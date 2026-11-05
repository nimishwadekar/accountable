/// Combined dev launcher: starts the content editor server (unless one
/// is already running), runs the game preview with an interactive
/// terminal, and stops the server it started when the game session ends.
///
/// Run from the `citysim/` folder:
///
///   dart run tool/run_game.dart
///
/// The game's saves go through the editor server (`/api/world`), so this
/// is the normal way to launch the preview in CSV mode.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  // Reuse a running editor server, or start a fresh one.
  var serverRunning = false;
  try {
    final probe = await Socket.connect('127.0.0.1', 9200);
    probe.destroy();
    serverRunning = true;
  } catch (_) {
    serverRunning = false;
  }

  Process? server;
  if (serverRunning) {
    stdout.writeln('Editor server already running on 9200 — reusing it.');
  } else {
    server = await Process.start('dart', [
      'run',
      'tool/content_editor/server.dart',
    ]);
    server.stderr.transform(utf8.decoder).listen(stderr.writeln);
    server.stdout.transform(utf8.decoder).listen(stdout.writeln);
    stdout.writeln('Editor server starting on 9200.');
  }

  stdout.writeln('Launching the game preview on http://localhost:9101 …');
  final game = await Process.start('flutter', [
    'run',
    '-d',
    'web-server',
    '--web-port=9101',
  ]);
  // The game session owns the terminal: its output and keyboard input
  // (hot reload, quit) pass straight through.
  game.stdout.transform(utf8.decoder).listen(stdout.write);
  game.stderr.transform(utf8.decoder).listen(stderr.write);
  stdin.lineMode = false;
  stdin.echoMode = false;
  unawaited(stdin.pipe(game.stdin).catchError((Object _) {}));

  final code = await game.exitCode;
  if (server != null) {
    server.kill();
    await server.exitCode;
    stdout.writeln('Editor server stopped.');
  }
  exitCode = code;
}
