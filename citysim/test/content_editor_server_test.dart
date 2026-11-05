import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

HttpClient? _testClient;

/// Port of the spawned editor server. An ephemeral port keeps the tests
/// isolated from any developer editor server already listening on the
/// default 9200.
late int testPort;

/// Reserves a free loopback port by binding port 0 and releasing it.
Future<int> _freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // This is a real-socket integration test: undo the test binding's fake
  // HttpClient override so requests actually reach the spawned server.
  HttpOverrides.global = null;

  late HttpServer server;
  late Directory tempRoot;

  setUpAll(() async {
    // Build a throwaway package layout: seed content copied from the real
    // bundle, stubbed sprite files, and no dashboard build.
    tempRoot = await Directory.systemTemp.createTemp('editor_test');
    final contentDir = Directory('${tempRoot.path}/assets/content')
      ..createSync(recursive: true);
    final source = Directory('assets/content');
    for (final file in source.listSync().whereType<File>()) {
      file.copySync('${contentDir.path}/${file.uri.pathSegments.last}');
    }
    // Stub every referenced sprite file so the server's file-existence
    // validation passes without copying the whole art pack. Sprite paths
    // are assets-root-relative (e.g. sprites/buildings/houses/x.png) and
    // facings sprites carry one path per door side.
    final sprites =
        (jsonDecode(File('${contentDir.path}/sprites.json').readAsStringSync())
                as Map)['sprites']
            as Map;
    for (final sprite in sprites.values.cast<Map>()) {
      final paths = <String>[
        if (sprite['path'] != null) sprite['path'] as String,
        for (final value in ((sprite['facings'] as Map?)?.values ?? const []))
          value as String,
      ];
      for (final relative in paths) {
        final stub = File('${tempRoot.path}/assets/$relative');
        stub.parent.createSync(recursive: true);
        stub.writeAsBytesSync(const []);
      }
    }
    testPort = await _freePort();
    server = await _startServer(tempRoot, testPort);
  });

  tearDownAll(() async {
    _testClient?.close();
    await server.close(force: true);
    await tempRoot.delete(recursive: true);
  });

  test('GET /api/content returns every category', () async {
    final response = await _get('/api/content');
    expect(response.statusCode, 200);
    final body = await _decode(response);
    expect(
      body.keys,
      containsAll([
        'manifest.json',
        'catalogue.json',
        'sprites.json',
        'economy.json',
        'ambience.json',
      ]),
    );
    expect(((body['catalogue.json'] as Map)['models'] as List), isNotEmpty);
  });

  test('validating the seed content passes', () async {
    final content = await _decode(await _get('/api/content'));
    final response = await _post('/api/content/validate', content);
    expect(response.statusCode, 200);
    final body = await _decode(response);
    expect(body['ok'], isTrue);
    expect(body['issues'], isEmpty);
  });

  test('saving invalid content is rejected without writing files', () async {
    final content = await _decode(await _get('/api/content'));
    (content['catalogue.json'] as Map)['models'] = const [];
    final response = await _post('/api/content', content);
    expect(response.statusCode, 422);
    final body = await _decode(response);
    expect(body['ok'], isFalse);

    // The files on disk are untouched.
    final fresh = await _decode(await _get('/api/content'));
    expect((fresh['catalogue.json'] as Map)['models'], isNotEmpty);
  });

  test('saving a valid change writes the file and backs up', () async {
    final content = await _decode(await _get('/api/content'));
    final models = (content['catalogue.json'] as Map)['models'] as List;
    (models.first as Map)['costCoins'] = 99;
    final response = await _post('/api/content', content);
    expect(response.statusCode, 200);
    final body = await _decode(response);
    expect(body['ok'], isTrue);

    final fresh = await _decode(await _get('/api/content'));
    final freshModels = (fresh['catalogue.json'] as Map)['models'] as List;
    expect((freshModels.first as Map)['costCoins'], 99);

    final backups = await _decode(await _get('/api/backups'));
    expect((backups['backups'] as List), isNotEmpty);
  });

  test('world documents round-trip through the server', () async {
    final response = await _put('/api/world', {
      'UserData': 'key,value\nseed,7\n',
      'Tiles': 'x,y,kind,status,detail,variant,facing,project\n',
      'OwnedParcels': 'x,y\n',
      'Projects': 'id,kind,detail,target,funded\n',
    });
    expect(response.statusCode, 200);
    final documents = await _decode(await _get('/api/world'));
    expect(documents['UserData'] as String, contains('seed,7'));
  });

  test('world summary expands footprints and bridge spans', () async {
    await _put('/api/world', {
      'UserData': 'key,value\nseed,7\n',
      'Tiles':
          'x,y,kind,status,detail,variant,facing,project\n'
          '3,4,structure,complete,apartments,,,\n'
          '5,6,road,complete,dirt,,,\n',
      'OwnedParcels': 'x,y\n0,0\n',
      'Projects':
          'id,kind,detail,target,funded\n'
          '1,bridge,,7:4:16:4,0\n',
    });
    final summary = await _decode(await _get('/api/world/summary'));
    final occupied = {
      for (final pair in summary['occupiedCells'] as List)
        '${(pair as List)[0]},${pair[1]}',
    };
    // The 2×2 apartments footprint at (3,4).
    expect(occupied, containsAll(['3,4', '4,4', '3,5', '4,5']));
    // The road tile.
    expect(occupied, contains('5,6'));
    // The bridge span between banks (7,4) and (16,4).
    expect(occupied, containsAll(['8,4', '12,4', '15,4']));
    expect(summary['ownedParcels'], [
      [0, 0],
    ]);
  });

  test('terrain edits under occupied cells are rejected', () async {
    await _put('/api/world', {
      'UserData': 'key,value\nseed,7\n',
      'Tiles':
          'x,y,kind,status,detail,variant,facing,project\n'
          '10,4,road,complete,dirt,,,\n',
      'OwnedParcels': 'x,y\n0,0\n',
      'Projects': 'id,kind,detail,target,funded\n',
    });
    final content = await _decode(await _get('/api/content'));
    // Re-type the occupied east water parcel (the road at (10,4) sits
    // in parcel (1,0)).
    (content['terrain.json'] as Map)['parcels']['1,0'] = 'grass';
    final rejected = await _post('/api/content', content);
    expect(rejected.statusCode, 422);
    final body = await _decode(rejected);
    expect((body['issues'] as List).join('\n'), contains('occupied cells'));

    // The files on disk are untouched.
    final fresh = await _decode(await _get('/api/content'));
    expect((fresh['terrain.json'] as Map)['parcels'], isNotEmpty);
  });

  test('pack endpoint rejects traversal', () async {
    // Plain ../ gets normalized away by the HTTP client; the encoded form
    // reaches the server, which must reject it.
    final response = await _get('/api/asset/%2e%2e%2fpubspec.yaml');
    expect(response.statusCode, anyOf(400, 404));
  });
}

Future<HttpServer> _startServer(Directory packageRoot, int port) async {
  // Run the real server as a subprocess from the actual package (so its
  // imports resolve), pointing --root at the throwaway layout.
  final process = await Process.start('dart', [
    'run',
    'tool/content_editor/server.dart',
    '--root',
    packageRoot.path,
    '--port',
    '$port',
  ], workingDirectory: Directory.current.path);
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      final probe = await Socket.connect('127.0.0.1', port);
      probe.destroy();
      return _ProcessBackedServer(process);
    } on SocketException {
      final exited = await process.exitCode.timeout(
        const Duration(milliseconds: 1),
        onTimeout: () => -1,
      );
      if (exited != -1) {
        throw StateError(
          'Editor server exited early: ${await process.stderr.transform(utf8.decoder).join()}',
        );
      }
    }
  }
  process.kill();
  throw StateError('Editor server did not start');
}

class _ProcessBackedServer implements HttpServer {
  _ProcessBackedServer(this._process);

  final Process _process;

  @override
  Future close({bool force = false}) async {
    _process.kill();
    await _process.exitCode;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<HttpClientResponse> _get(String path) => (_testClient ??= HttpClient())
    .getUrl(Uri.parse('http://localhost:$testPort$path'))
    .then((request) => request.close());

Future<HttpClientResponse> _post(String path, Object body) async {
  final request = await (_testClient ??= HttpClient()).postUrl(
    Uri.parse('http://localhost:$testPort$path'),
  );
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  return request.close();
}

Future<HttpClientResponse> _put(String path, Object body) async {
  final request = await (_testClient ??= HttpClient()).putUrl(
    Uri.parse('http://localhost:$testPort$path'),
  );
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  return request.close();
}

Future<Map<String, Object?>> _decode(HttpClientResponse response) async {
  final raw = await response.transform(utf8.decoder).join();
  return (jsonDecode(raw) as Map).cast<String, Object?>();
}
