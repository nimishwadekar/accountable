import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';

import '../../config/accountable_config.dart';
import 'accountable_google_account.dart';
import 'sheets_authorization.dart';

class GoogleAuthService {
  GoogleAuthService({required this.config});

  final AccountableConfig config;
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  static Future<void>? _initialization;
  late final SheetsAuthorizationDelegate _sheetsAuthorization =
      SheetsAuthorizationDelegate(config: config);
  String? _sheetsAccessToken;
  AccountableGoogleAccount? _sheetsAccount;

  Stream<AccountableGoogleAccount> get authenticationEvents async* {
    await for (final event in _signIn.authenticationEvents) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        yield _accountFromNative(event.user);
      }
    }
  }

  Future<void> initialize() => _initialization ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    await _signIn.initialize(clientId: config.googleClientId);
  }

  Future<Future<AccountableGoogleAccount?>?>
  attemptSilentAuthentication() async {
    await initialize();
    final attempt = _signIn.attemptLightweightAuthentication();
    if (attempt == null) return null;
    final account = await attempt;
    final result = account == null
        ? Future<AccountableGoogleAccount?>.value(null)
        : Future<AccountableGoogleAccount?>.value(_accountFromNative(account));
    return Future<Future<AccountableGoogleAccount?>?>.value(result);
  }

  Future<AccountableGoogleAccount> authenticate() async {
    await initialize();
    final account = await _signIn.authenticate();
    return _accountFromNative(account);
  }

  Future<String> authorizeSheets(
    AccountableGoogleAccount account, {
    bool forceRefresh = false,
  }) async {
    final native = account.nativeAccount!;
    if (_sheetsAccount?.email != account.email) {
      _sheetsAccessToken = null;
      _sheetsAccount = account;
    }
    if (!forceRefresh && _sheetsAccessToken != null) return _sheetsAccessToken!;
    if (forceRefresh && _sheetsAccessToken != null) {
      await _sheetsAuthorization.clear(native, _sheetsAccessToken!);
      _sheetsAccessToken = null;
    }
    _sheetsAccessToken = await _sheetsAuthorization.authorize(
      native,
      interactive: false,
      forceRefresh: forceRefresh,
    );
    return _sheetsAccessToken!;
  }

  Future<String> authorizeSheetsInteractively(
    AccountableGoogleAccount account,
  ) async {
    _sheetsAccessToken = await _sheetsAuthorization.authorize(
      account.nativeAccount!,
      interactive: true,
      forceRefresh: true,
    );
    _sheetsAccount = account;
    return _sheetsAccessToken!;
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
    await _signIn.signOut();
  }

  AccountableGoogleAccount _accountFromNative(GoogleSignInAccount account) {
    final token = account.authentication.idToken;
    if (token == null || token.isEmpty) {
      throw const GoogleAuthException('Google did not return an ID token.');
    }
    return AccountableGoogleAccount(
      email: account.email,
      idToken: token,
      nativeAccount: account,
    );
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
