import 'package:flutter/material.dart';

import 'editor_app.dart';

/// Entry point for the content editor dashboard.
///
/// Run the editor server first (from the `citysim/` folder):
///
///   dart run tool/content_editor/server.dart
///
/// Then develop the dashboard with:
///
///   flutter run -d web-server --web-port=9201 -t lib/editor/main.dart
///
/// or build it for the server to serve:
///
///   flutter build web -t lib/editor/main.dart -o build/editor
void main() {
  runApp(const ContentEditorApp());
}
