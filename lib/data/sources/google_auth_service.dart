import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/accountable_config.dart';

class GoogleAuthService {
  GoogleAuthService({required this.config});

  final AccountableConfig config;
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  static Future<void>? _initialization;
  String? _sheetsAccessToken;
  String? _authorizedEmail;

  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents =>
      _signIn.authenticationEvents;

  Future<void> initialize() {
    return _initialization ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    if (kIsWeb) {
      final currentOrigin = Uri.base.origin;
      if (!config.oauthOrigins.contains(currentOrigin)) {
        throw GoogleAuthException(
          'OAuth origin $currentOrigin is not configured. Expected one of: '
          '${config.oauthOrigins.join(', ')}.',
        );
      }
    }
    await _signIn.initialize(clientId: config.googleClientId);
  }

  Future<Future<GoogleSignInAccount?>?> attemptSilentAuthentication() async {
    await initialize();
    return _signIn.attemptLightweightAuthentication();
  }

  Future<GoogleSignInAccount> authenticate() async {
    await initialize();
    return _signIn.authenticate();
  }

  Future<String> authorizeSheets(
    GoogleSignInAccount account, {
    bool forceRefresh = false,
  }) async {
    final authorizationClient = account.authorizationClient;
    if (_authorizedEmail != account.email) {
      _sheetsAccessToken = null;
      _authorizedEmail = account.email;
    }
    if (!forceRefresh && _sheetsAccessToken != null) {
      return _sheetsAccessToken!;
    }
    if (forceRefresh && _sheetsAccessToken != null) {
      await authorizationClient.clearAuthorizationToken(
        accessToken: _sheetsAccessToken!,
      );
      _sheetsAccessToken = null;
    }
    final authorization = await authorizationClient.authorizationForScopes([
      config.sheetsScope,
    ]);
    if (authorization == null) {
      throw const SheetsAuthorizationRequiredException();
    }
    _sheetsAccessToken = authorization.accessToken;
    return _sheetsAccessToken!;
  }

  Future<String> authorizeSheetsInteractively(
    GoogleSignInAccount account,
  ) async {
    final authorization = await account.authorizationClient.authorizeScopes([
      config.sheetsScope,
    ]);
    _authorizedEmail = account.email;
    _sheetsAccessToken = authorization.accessToken;
    return _sheetsAccessToken!;
  }

  void validateAllowedAccount(GoogleSignInAccount account) {
    if (account.email.toLowerCase() != config.allowedEmail.toLowerCase()) {
      throw UnauthorizedGoogleAccountException(account.email);
    }
  }

  Future<void> signOut() async {
    _sheetsAccessToken = null;
    _authorizedEmail = null;
    await _signIn.signOut();
  }
}

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
