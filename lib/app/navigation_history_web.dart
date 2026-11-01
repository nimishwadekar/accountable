import 'dart:async';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

class NavigationHistory {
  static String? _capturedInitialPath;

  static void captureInitialPath() {
    _capturedInitialPath =
        '${web.window.location.pathname}${web.window.location.search}';
  }

  NavigationHistory()
    : _initialPath =
          _capturedInitialPath ??
          '${web.window.location.pathname}${web.window.location.search}' {
    _capturedInitialPath = null;
    _knownPaths.add(_initialPath);
    _historyReady = _initializeHistory();
  }

  final String _initialPath;
  final Set<String> _knownPaths = {};
  late final Future<void> _historyReady;
  bool _readyForPop = false;

  String get currentPath => _readyForPop
      ? '${web.window.location.pathname}${web.window.location.search}'
      : _initialPath;

  Stream<String> get changes => web.window.onPopState
      .map((_) => currentPath)
      .where(
        (path) =>
            _readyForPop &&
            (_knownPaths.contains(path) || !isAuthenticatedPath(path)),
      );

  Future<void> _initializeHistory() async {
    // Navigator defaults to Flutter's single-entry browser history. The app
    // shell has stable sections rather than pushed routes, so use Flutter's
    // multi-entry history API for its existing section URLs. Restore the
    // initial deep link after switching modes, which tears down the temporary
    // single-entry wrapper.
    await SystemNavigator.selectMultiEntryHistory();
    await SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(_initialPath),
      replace: true,
    );
    _readyForPop = true;
  }

  bool isAuthenticatedPath(String path) =>
      Uri.parse(path).queryParameters['app'] == '1';

  String authenticatedPath(String path) {
    final uri = Uri.parse(path);
    final result = uri
        .replace(queryParameters: {...uri.queryParameters, 'app': '1'})
        .toString();
    _knownPaths.add(result);
    return result;
  }

  void push(String path) => unawaited(_update(path, replace: false));

  void replace(String path) => unawaited(_update(path, replace: true));

  Future<void> _update(String path, {required bool replace}) async {
    await _historyReady;
    _knownPaths.add(path);
    await SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(path),
      replace: replace,
    );
  }

  void dispose() {}
}
