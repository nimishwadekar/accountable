import 'package:web/web.dart' as web;

class NavigationHistory {
  String get currentPath =>
      '${web.window.location.pathname}${web.window.location.search}';

  Stream<String> get changes => web.window.onPopState.map((_) => currentPath);

  bool isAuthenticatedPath(String path) =>
      Uri.parse(path).queryParameters['app'] == '1';

  String authenticatedPath(String path) {
    final uri = Uri.parse(path);
    return uri.replace(
      queryParameters: {...uri.queryParameters, 'app': '1'},
    ).toString();
  }

  void push(String path) {
    web.window.history.pushState(null, '', path);
  }

  void replace(String path) {
    web.window.history.replaceState(null, '', path);
  }

  void dispose() {}
}
