import 'dart:async';

import 'package:google_identity_services_web/oauth2.dart' as oauth2;
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/accountable_config.dart';

class SheetsAuthorizationDelegate {
  SheetsAuthorizationDelegate({required this.config});

  final AccountableConfig config;
  oauth2.TokenClient? _tokenClient;
  String? _accountEmail;
  Completer<String>? _pending;

  Future<String> authorize(
    GoogleSignInAccount account, {
    required bool interactive,
    required bool forceRefresh,
  }) async {
    if (_accountEmail != account.email) {
      _accountEmail = account.email;
      _tokenClient = null;
    }
    final pending = Completer<String>();
    _pending = pending;
    _tokenClient ??= oauth2.oauth2.initTokenClient(
      oauth2.TokenClientConfig(
        client_id: config.googleClientId,
        scope: [config.sheetsScope],
        prompt: '',
        login_hint: account.email,
        callback: _handleToken,
        error_callback: _handleError,
      ),
    );
    _tokenClient!.requestAccessToken(
      oauth2.OverridableTokenClientConfig(
        scope: [config.sheetsScope],
        prompt: interactive ? 'consent' : '',
        login_hint: account.email,
      ),
    );
    try {
      return await pending.future;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  void _handleToken(oauth2.TokenResponse response) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    final token = response.access_token;
    if (response.error != null || token == null || token.isEmpty) {
      pending.completeError(SheetsAuthorizationInteractionRequiredException());
      return;
    }
    pending.complete(token);
  }

  void _handleError(oauth2.GoogleIdentityServicesError? error) {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    pending.completeError(SheetsAuthorizationInteractionRequiredException());
  }

  Future<void> clear(GoogleSignInAccount account, String accessToken) async {}
}

class SheetsAuthorizationInteractionRequiredException implements Exception {
  const SheetsAuthorizationInteractionRequiredException();

  @override
  String toString() => 'Sheets authorization requires user interaction.';
}
