import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/accountable_config.dart';

class GoogleAuthService {
  GoogleAuthService({required this.config});

  final AccountableConfig config;
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  bool _initialized = false;

  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents =>
      _signIn.authenticationEvents;

  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      final currentOrigin = Uri.base.origin;
      if (currentOrigin != config.oauthOrigin) {
        throw GoogleAuthException(
          'Current web origin $currentOrigin does not match the configured '
          'OAuth origin ${config.oauthOrigin}.',
        );
      }
    }
    await _signIn.initialize(clientId: config.googleClientId);
    _initialized = true;
  }

  Future<GoogleSignInAccount?> attemptSilentAuthentication() async {
    await initialize();
    final future = _signIn.attemptLightweightAuthentication();
    return future ?? Future<GoogleSignInAccount?>.value();
  }

  Future<GoogleSignInAccount> authenticate() async {
    await initialize();
    return _signIn.authenticate();
  }

  Future<String> authorizeSheets(GoogleSignInAccount account) async {
    final authorization = await account.authorizationClient.authorizationForScopes(
      [config.sheetsScope],
    );
    if (authorization == null) {
      throw const GoogleAuthException(
        'Sheets permission requires an interactive authorization action.',
      );
    }
    return authorization.accessToken;
  }

  Future<String> authorizeSheetsInteractively(
    GoogleSignInAccount account,
  ) async {
    final authorization = await account.authorizationClient.authorizeScopes([
      config.sheetsScope,
    ]);
    return authorization.accessToken;
  }

  void validateAllowedAccount(GoogleSignInAccount account) {
    if (account.email.toLowerCase() != config.allowedEmail.toLowerCase()) {
      throw UnauthorizedGoogleAccountException(account.email);
    }
  }

  Future<void> signOut() => _signIn.signOut();
}

class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UnauthorizedGoogleAccountException implements Exception {
  const UnauthorizedGoogleAccountException(this.email);

  final String email;

  @override
  String toString() => 'Google account $email is not authorized.';
}
