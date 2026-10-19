import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../config/accountable_config.dart';
import 'gis_logging.dart';
import 'sheets_authorization.dart';

class GoogleAuthService {
  GoogleAuthService({required this.config});

  final AccountableConfig config;
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  static Future<void>? _initialization;
  late final SheetsAuthorizationDelegate _sheetsAuthorization =
      SheetsAuthorizationDelegate(config: config);
  String? _sheetsAccessToken;
  GoogleSignInAccount? _sheetsAccount;

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
    suppressGisDebugLogs();
  }

  Future<Future<GoogleSignInAccount?>?> attemptSilentAuthentication() async {
    await initialize();
    return _signIn.attemptLightweightAuthentication();
  }

  Future<GoogleSignInAccount> authenticate() async {
    await initialize();
    return _signIn.authenticate();
  }

  Future<String> idToken(GoogleSignInAccount account) async {
    await initialize();
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw const GoogleAuthException('Google did not return an ID token.');
    }
    return token;
  }

  Future<String> authorizeSheets(
    GoogleSignInAccount account, {
    bool forceRefresh = false,
  }) async {
    if (_sheetsAccount?.email != account.email) {
      _sheetsAccessToken = null;
      _sheetsAccount = account;
    }
    if (!forceRefresh && _sheetsAccessToken != null) {
      return _sheetsAccessToken!;
    }
    try {
      _sheetsAccessToken = await _sheetsAuthorization.authorize(
        account,
        interactive: false,
        forceRefresh: forceRefresh,
      );
      return _sheetsAccessToken!;
    } on SheetsAuthorizationInteractionRequiredException {
      throw const SheetsAuthorizationRequiredException();
    }
  }

  Future<String> authorizeSheetsInteractively(
    GoogleSignInAccount account,
  ) async {
    try {
      _sheetsAccessToken = await _sheetsAuthorization.authorize(
        account,
        interactive: true,
        forceRefresh: true,
      );
      _sheetsAccount = account;
      return _sheetsAccessToken!;
    } on SheetsAuthorizationInteractionRequiredException {
      throw const SheetsAuthorizationRequiredException();
    }
  }

  void validateAllowedAccount(GoogleSignInAccount account) {
    if (account.email.toLowerCase() != config.allowedEmail.toLowerCase()) {
      throw UnauthorizedGoogleAccountException(account.email);
    }
  }

  Future<void> signOut() async {
    _sheetsAccessToken = null;
    _sheetsAccount = null;
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
