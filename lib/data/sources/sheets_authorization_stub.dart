import 'package:google_sign_in/google_sign_in.dart';

import '../../config/accountable_config.dart';

class SheetsAuthorizationDelegate {
  SheetsAuthorizationDelegate({required this.config});

  final AccountableConfig config;

  Future<String> authorize(
    GoogleSignInAccount account, {
    required bool interactive,
    required bool forceRefresh,
  }) async {
    final client = account.authorizationClient;
    final authorization = interactive
        ? await client.authorizeScopes([config.sheetsScope])
        : await client.authorizationForScopes([config.sheetsScope]);
    if (authorization == null) {
      throw const SheetsAuthorizationInteractionRequiredException();
    }
    return authorization.accessToken;
  }

  Future<void> clear(GoogleSignInAccount account, String accessToken) {
    return account.authorizationClient.clearAuthorizationToken(
      accessToken: accessToken,
    );
  }
}

class SheetsAuthorizationInteractionRequiredException implements Exception {
  const SheetsAuthorizationInteractionRequiredException();

  @override
  String toString() => 'Sheets authorization requires user interaction.';
}
