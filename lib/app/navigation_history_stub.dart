class NavigationHistory {
  String get currentPath => '/';
  Stream<String> get changes => const Stream.empty();
  bool isAuthenticatedPath(String path) => true;
  String authenticatedPath(String path) => path;
  void push(String path) {}
  void replace(String path) {}
  void dispose() {}
}
