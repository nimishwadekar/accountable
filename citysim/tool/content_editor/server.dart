/// Content editor dashboard server.
///
/// Serves the editor dashboard (a Flutter web build in build/editor/) and a
/// localhost-only REST API that reads, validates, backs up, and writes the
/// JSON content layer. Run from the `citysim/` folder:
///
///   dart run tool/content_editor/server.dart
///
/// The server listens on port 9200 and never touches ports 9000 (the
/// Accountable app) or 9101 (the game preview).
library;

import 'dart:convert';
import 'dart:io';

import 'package:citysim/content/content_bundle.dart';

import 'file_content_source.dart';

const editorPort = 9200;
const categoryFiles = [
  'manifest.json',
  'catalogue.json',
  'sprites.json',
  'economy.json',
  'ambience.json',
];

Future<void> main(List<String> args) async {
  final rootArg = _rootArgument(args);
  final root = rootArg != null ? Directory(rootArg) : _findPackageRoot();
  final port = _portArgument(args) ?? editorPort;
  final contentDir = Directory('${root.path}/assets/content');
  final assetsDir = Directory('${root.path}/assets');
  final dashboardDir = Directory('${root.path}/build/editor');
  final backupDir = Directory('${root.path}/tool/content_editor/backups')
    ..createSync(recursive: true);

  if (!contentDir.existsSync()) {
    stderr.writeln('No assets/content under ${root.path}');
    exitCode = 1;
    return;
  }
  if (dashboardDir.existsSync() == false) {
    stderr.writeln(
      'Dashboard build not found at build/editor. Build it with:\n'
      '  flutter build web -t lib/editor/main.dart -o build/editor',
    );
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Content editor listening on http://localhost:$port');
  stdout.writeln('Content: ${contentDir.path}');
  stdout.writeln('Backups: ${backupDir.path}');

  await for (final request in server) {
    try {
      await _handle(
        request,
        contentDir: contentDir,
        assetsDir: assetsDir,
        dashboardDir: dashboardDir,
        backupDir: backupDir,
      );
    } catch (error) {
      _respondJson(request, 500, {'error': '$error'});
    } finally {
      await request.response.flush();
      await request.response.close();
    }
  }
}

String? _rootArgument(List<String> args) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--root') return args[i + 1];
  }
  return null;
}

/// Overrides the listen port (tests use an ephemeral one so a developer's
/// running editor server on the default port never interferes).
int? _portArgument(List<String> args) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--port') return int.tryParse(args[i + 1]);
  }
  return null;
}

Directory _findPackageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 3; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/assets/content').existsSync()) {
      return dir;
    }
    final parentPath = dir.parent.path;
    if (parentPath == dir.path) break;
    dir = Directory(parentPath);
  }
  return Directory.current;
}

Future<void> _handle(
  HttpRequest request, {
  required Directory contentDir,
  required Directory assetsDir,
  required Directory dashboardDir,
  required Directory backupDir,
}) async {
  final path = request.uri.path;
  switch (request.method) {
    case 'GET':
      if (path == '/api/content') {
        await _getContent(request, contentDir);
      } else if (path == '/api/backups') {
        _listBackups(request, backupDir);
      } else if (path.startsWith('/api/asset/')) {
        _servePackFile(
          request,
          path.substring('/api/asset/'.length),
          assetsDir,
        );
      } else {
        await _serveDashboard(request, path, dashboardDir);
      }
    case 'POST':
      if (path == '/api/content/validate') {
        await _validateContent(request, assetsDir);
      } else if (path == '/api/content') {
        await _saveContent(
          request,
          contentDir: contentDir,
          assetsDir: assetsDir,
          backupDir: backupDir,
        );
      } else if (path.startsWith('/api/backups/restore/')) {
        await _restoreBackup(
          request,
          backupDir,
          path.substring('/api/backups/restore/'.length),
          contentDir,
        );
      } else {
        _respondJson(request, 404, {'error': 'Unknown endpoint'});
      }
    default:
      _respondJson(request, 405, {'error': 'Method not allowed'});
  }
}

Future<void> _getContent(HttpRequest request, Directory contentDir) async {
  final result = <String, Object?>{};
  for (final name in categoryFiles) {
    final file = File('${contentDir.path}/$name');
    if (!file.existsSync()) {
      _respondJson(request, 500, {'error': 'Missing content file: $name'});
      return;
    }
    result[name] = readJsonFile(file);
  }
  _respondJson(request, 200, result);
}

Future<void> _validateContent(HttpRequest request, Directory assetsDir) async {
  final body = await _readJsonBody(request);
  if (body == null) return;
  final result = _validateBundleMaps(body, assetsDir);
  _respondJson(request, 200, result);
}

Future<void> _saveContent(
  HttpRequest request, {
  required Directory contentDir,
  required Directory assetsDir,
  required Directory backupDir,
}) async {
  final body = await _readJsonBody(request);
  if (body == null) return;
  final validation = _validateBundleMaps(body, assetsDir);
  if (validation['ok'] != true) {
    _respondJson(request, 422, validation);
    return;
  }

  // Back up the current files before writing, then write changed
  // categories atomically. Content history is tracked by git; no revision
  // counter is maintained.
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  for (final name in categoryFiles) {
    final file = File('${contentDir.path}/$name');
    final incoming = body[name];
    if (incoming is! Map<String, Object?>) continue;
    final encodedNew = const JsonEncoder.withIndent('  ')
        .convert(_sortedJson(incoming));
    if (file.existsSync()) {
      final current = file.readAsStringSync();
      if (current == encodedNew) continue;
      file.copySync('${backupDir.path}/$timestamp-$name');
    }
    await writeJsonFileAtomic(
      file,
      _sortedJson(incoming) as Map<String, Object?>,
    );
  }

  _respondJson(request, 200, {'ok': true});
}

Map<String, Object?> _validateBundleMaps(
  Map<String, Object?> body,
  Directory assetsDir,
) {
  try {
    final manifest = _asMap(body, 'manifest.json');
    final catalogue = _asMap(body, 'catalogue.json');
    final sprites = _asMap(body, 'sprites.json');
    final economy = _asMap(body, 'economy.json');
    final ambience = _asMap(body, 'ambience.json');
    final bundle = parseContentBundle(
      manifest: manifest,
      catalogue: catalogue,
      sprites: sprites,
      economy: economy,
      ambience: ambience,
    );
    final issues =
        validateContentData(
          catalogue: bundle.catalogue,
          sprites: bundle.sprites,
          economy: bundle.economy,
          ambience: bundle.ambience,
        ).map((issue) => issue.toString()).toList()..addAll(
          checkSpriteFiles(sprites: bundle.sprites, packDirectory: assetsDir),
        );
    return {
      'ok': issues.every((issue) => !issue.startsWith('[error]')),
      'issues': issues,
    };
  } on FormatException catch (error) {
    return {
      'ok': false,
      'issues': ['[error] ${error.message}'],
    };
  }
}

Map<String, Object?> _asMap(Map<String, Object?> body, String name) {
  final value = body[name];
  if (value is! Map) {
    throw FormatException('Request is missing the "$name" category.');
  }
  return value.cast<String, Object?>();
}

void _listBackups(HttpRequest request, Directory backupDir) {
  final entries =
      backupDir
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toList()
        ..sort();
  _respondJson(request, 200, {'backups': entries.reversed.toList()});
}

Future<void> _restoreBackup(
  HttpRequest request,
  Directory backupDir,
  String backupName,
  Directory contentDir,
) async {
  // The backup name is `<timestamp>-<category>`; only the category file it
  // came from is restored, keeping the blast radius of a restore small.
  final safeName = backupName.replaceAll('/', '').replaceAll('..', '');
  final backup = File('${backupDir.path}/$safeName');
  if (!backup.existsSync()) {
    _respondJson(request, 404, {'error': 'Unknown backup'});
    return;
  }
  final category = categoryFiles
      .where((name) => safeName.endsWith(name))
      .firstOrNull;
  if (category == null) {
    _respondJson(request, 400, {'error': 'Backup does not match a category'});
    return;
  }
  final target = File('${contentDir.path}/$category');
  target.copySync('${backupDir.path}/$safeName');
  _respondJson(request, 200, {'ok': true, 'restored': category});
}

void _servePackFile(HttpRequest request, String relative, Directory packDir) {
  // Paths are restricted to the pack directory; traversal is rejected.
  final normalized = Uri.decodeComponent(relative);
  if (normalized.contains('..') || normalized.startsWith('/')) {
    _respondJson(request, 400, {'error': 'Invalid path'});
    return;
  }
  final file = File('${packDir.path}/$normalized');
  if (!file.existsSync()) {
    _respondJson(request, 404, {'error': 'Not found'});
    return;
  }
  request.response.headers.contentType = _contentTypeFor(normalized);
  request.response.add(file.readAsBytesSync());
}

Future<void> _serveDashboard(
  HttpRequest request,
  String path,
  Directory dashboardDir,
) async {
  if (!dashboardDir.existsSync()) {
    _respondJson(request, 503, {
      'error':
          'Dashboard not built. Run: flutter build web '
          '-t lib/editor/main.dart -o build/editor',
    });
    return;
  }
  var relative = path == '/' ? 'index.html' : path.substring(1);
  var file = File('${dashboardDir.path}/$relative');
  if (!file.existsSync() && !relative.contains('.')) {
    // SPA fallback for client-side routes.
    file = File('${dashboardDir.path}/index.html');
  }
  if (!file.existsSync()) {
    _respondJson(request, 404, {'error': 'Not found'});
    return;
  }
  request.response.headers.contentType = _contentTypeFor(relative);
  request.response.add(file.readAsBytesSync());
}

ContentType _contentTypeFor(String path) {
  final extension = path.split('.').last.toLowerCase();
  return switch (extension) {
    'html' => ContentType.html,
    'js' => ContentType('text', 'javascript', charset: 'utf-8'),
    'json' => ContentType.json,
    'png' => ContentType('image', 'png'),
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'svg' => ContentType('image', 'svg+xml'),
    'wasm' => ContentType('application', 'wasm'),
    'css' => ContentType('text', 'css', charset: 'utf-8'),
    _ => ContentType.binary,
  };
}

Future<Map<String, Object?>?> _readJsonBody(HttpRequest request) async {
  final raw = await utf8.decoder.bind(request).join();
  if (raw.isEmpty) {
    _respondJson(request, 400, {'error': 'Empty body'});
    return null;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      _respondJson(request, 400, {'error': 'Body must be a JSON object'});
      return null;
    }
    return decoded.cast<String, Object?>();
  } on FormatException {
    _respondJson(request, 400, {'error': 'Invalid JSON'});
    return null;
  }
}

void _respondJson(HttpRequest request, int status, Object? body) {
  request.response.statusCode = status;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
}

/// Re-encodes decoded JSON with stable key ordering so file writes are
/// deterministic and diffs stay minimal.
Object? _sortedJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _sortedJson(value[key])};
  }
  if (value is List) {
    return [for (final item in value) _sortedJson(item)];
  }
  return value;
}
