import 'dart:async';
import 'dart:convert';

import 'package:google_identity_services_web/id.dart' as gis;
import 'package:google_identity_services_web/oauth2.dart' as oauth2;

import '../../config/accountable_config.dart';
import 'accountable_google_account.dart';
import 'gis_logging.dart';

class GoogleAuthService {
  GoogleAuthService({required this.config});

  final AccountableConfig config;
  static Future<void>? _initialization;
  final StreamController<AccountableGoogleAccount> _events =
      StreamController.broadcast();
  oauth2.TokenClient? _tokenClient;
  AccountableGoogleAccount? _sheetsAccount;
  String? _sheetsAccessToken;
  Completer<AccountableGoogleAccount?>? _pendingAuthentication;
  Completer<String>? _pendingToken;

  Stream<AccountableGoogleAccount> get authenticationEvents => _events.stream;

  Future<void> initialize() {
    return _initialization ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    final currentOrigin = Uri.base.origin;
    if (!config.oauthOrigins.contains(currentOrigin)) {
      throw GoogleAuthException(
        'OAuth origin $currentOrigin is not configured. Expected one of: '
        '${config.oauthOrigins.join(', ')}.',
      );
    }
    gis.id.initialize(
      gis.IdConfiguration(
        client_id: config.googleClientId,
        auto_select: true,
        use_fedcm_for_prompt: true,
        callback: _handleCredential,
      ),
    );
    suppressGisDebugLogs();
  }

  Future<Future<AccountableGoogleAccount?>?>
  attemptSilentAuthentication() async {
    await initialize();
    final pending = Completer<AccountableGoogleAccount?>();
    _pendingAuthentication = pending;
    gis.id.prompt();
    return Future.value(pending.future);
  }

  Future<AccountableGoogleAccount> authenticate() async {
    await initialize();
    final pending = Completer<AccountableGoogleAccount?>();
    _pendingAuthentication = pending;
    gis.id.prompt();
    final account = await pending.future;
    if (account == null) {
      throw const GoogleAuthException('Google sign-in was canceled.');
    }
    return account;
  }

  void _handleCredential(gis.CredentialResponse response) {
    final credential = response.credential;
    if (credential == null || credential.isEmpty) return;
    try {
      final account = _accountFromIdToken(credential);
      final pending = _pendingAuthentication;
      if (pending != null && !pending.isCompleted) {
        pending.complete(account);
      }
      _events.add(account);
    } catch (error) {
      final pending = _pendingAuthentication;
      if (pending != null && !pending.isCompleted) pending.completeError(error);
    }
  }

  AccountableGoogleAccount _accountFromIdToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw const GoogleAuthException('Invalid Google ID token.');
    }
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final email = payload['email']?.toString();
    if (email == null || email.isEmpty) {
      throw const GoogleAuthException('Google ID token has no email.');
    }
    return AccountableGoogleAccount(email: email, idToken: token);
  }

  Future<String> authorizeSheets(
    AccountableGoogleAccount account, {
    bool forceRefresh = false,
  }) async {
    if (_sheetsAccount?.email != account.email) {
      _sheetsAccount = account;
      _sheetsAccessToken = null;
    }
    if (!forceRefresh && _sheetsAccessToken != null) return _sheetsAccessToken!;
    _sheetsAccessToken = await _requestSheetsToken(account, interactive: false);
    return _sheetsAccessToken!;
  }

  Future<String> authorizeSheetsInteractively(
    AccountableGoogleAccount account,
  ) async {
    _sheetsAccessToken = await _requestSheetsToken(account, interactive: true);
    _sheetsAccount = account;
    return _sheetsAccessToken!;
  }

  Future<String> _requestSheetsToken(
    AccountableGoogleAccount account, {
    required bool interactive,
  }) async {
    final pending = Completer<String>();
    _pendingToken = pending;
    _tokenClient ??= oauth2.oauth2.initTokenClient(
      oauth2.TokenClientConfig(
        client_id: config.googleClientId,
        scope: [config.sheetsScope],
        prompt: '',
        login_hint: account.email,
        callback: _handleToken,
        error_callback: _handleTokenError,
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
      if (identical(_pendingToken, pending)) _pendingToken = null;
    }
  }

  void _handleToken(oauth2.TokenResponse response) {
    final pending = _pendingToken;
    if (pending == null || pending.isCompleted) return;
    final token = response.access_token;
    if (response.error != null || token == null || token.isEmpty) {
      pending.completeError(const SheetsAuthorizationRequiredException());
    } else {
      pending.complete(token);
    }
  }

  void _handleTokenError(oauth2.GoogleIdentityServicesError? error) {
    final pending = _pendingToken;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const SheetsAuthorizationRequiredException());
    }
  }

  void validateAllowedAccount(AccountableGoogleAccount account) {
    if (account.email.toLowerCase() != config.allowedEmail.toLowerCase()) {
      throw UnauthorizedGoogleAccountException(account.email);
    }
  }

  Future<String> idToken(AccountableGoogleAccount account) async =>
      account.idToken;

  Future<void> signOut() async {
    _sheetsAccessToken = null;
    _sheetsAccount = null;
    _pendingAuthentication = null;
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
