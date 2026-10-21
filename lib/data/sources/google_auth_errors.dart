class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SheetsAuthorizationRequiredException extends GoogleAuthException {
  const SheetsAuthorizationRequiredException()
    : super('Sheets authorization requires a one-time user action.');
}

class UnauthorizedGoogleAccountException implements Exception {
  const UnauthorizedGoogleAccountException(this.email);

  final String email;

  @override
  String toString() => 'Google account $email is not authorized.';
}
