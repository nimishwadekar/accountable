import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config/accountable_config.dart';
import '../data/data.dart';
import 'app_shell.dart';
import 'pages/app_pages.dart';
import 'google_sign_in_button.dart';
import 'theme/design_tokens.dart';

class GoogleSheetsGate extends StatefulWidget {
  const GoogleSheetsGate({super.key, required this.config});

  final AccountableConfig config;

  @override
  State<GoogleSheetsGate> createState() => _GoogleSheetsGateState();
}

class _GoogleSheetsGateState extends State<GoogleSheetsGate> {
  late final GoogleAuthService _authService;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _eventsSubscription;
  String? _error;
  DataValidationFailure? _dataFailure;
  bool _loading = true;
  bool _authorizing = false;
  bool _needsConsent = false;
  bool _loadingData = false;
  GoogleSignInAccount? _account;
  AppDataRepository? _repository;
  Future<void> Function()? _rebuildDailyTables;

  @override
  void initState() {
    super.initState();
    _authService = GoogleAuthService(config: widget.config);
    _eventsSubscription = _authService.authenticationEvents.listen(
      (event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _finishSignIn(event.user);
        }
      },
      onError: (Object error) {
        if (_isBenignAuthenticationError(error)) return;
        if (mounted) setState(() => _error = error.toString());
      },
    );
    _initialize();
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dataFailure != null) {
      return DataValidationPage(failure: _dataFailure!, onReload: _retry);
    }
    if (_repository != null) {
      return AppShell(
        dataRepository: _repository!,
        onRebuildDailyTables: _rebuildDailyTables,
      );
    }

    final configured = widget.config.hasConfiguredGoogleSheets;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.account_balance_outlined,
                      size: 48,
                      color: AppColors.navy,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Connect Accountable',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(_message, textAlign: TextAlign.center),
                    if (!configured) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Update assets/config.json with your Google client ID, spreadsheet ID, allowed email, OAuth origin, and Sheets scope.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    if (!configured)
                      const SizedBox.shrink()
                    else if (_loading || _authorizing || _loadingData)
                      Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: AppSpacing.md),
                          Text(_message, textAlign: TextAlign.center),
                        ],
                      )
                    else if (_needsConsent)
                      FilledButton.icon(
                        onPressed: _grantSheetsAccess,
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('Grant Sheets access'),
                      )
                    else
                      buildGoogleSignInButton(onPressed: _signIn),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(onPressed: _retry, child: const Text('Retry')),
                    ],
                    if (_account != null && _repository == null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: _switchAccount,
                        child: const Text('Use a different Google account'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _message {
    if (!widget.config.hasConfiguredGoogleSheets) {
      return 'Add the Google OAuth client ID, spreadsheet ID, and allowed email in assets/config.json.';
    }
    if (_loading) return 'Restoring your Google session…';
    if (_authorizing) return 'Signing in to Google…';
    if (_loadingData) return 'Loading your financial data…';
    if (_needsConsent) {
      return 'Authorize Sheets access for your account to continue.';
    }
    return 'Sign in with your authorized Google account to continue.';
  }

  Future<void> _initialize() async {
    if (!widget.config.hasConfiguredGoogleSheets) {
      setState(() => _loading = false);
      return;
    }
    try {
      final attempt = await _authService.attemptSilentAuthentication();
      GoogleSignInAccount? account;
      if (attempt != null) {
        account = await attempt.timeout(
          const Duration(seconds: 3),
          onTimeout: () => null,
        );
      } else {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      if (!mounted || _account != null) return;
      setState(() {
        _loading = false;
        _error = null;
      });
      if (account != null) await _finishSignIn(account);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _isBenignAuthenticationError(error) ? null : error.toString();
      });
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _authorizing = true;
      _error = null;
    });
    try {
      final account = await _authService.authenticate();
      await _finishSignIn(account, interactiveConsent: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authorizing = false;
        _error = _isBenignAuthenticationError(error) ? null : error.toString();
      });
    }
  }

  Future<void> _grantSheetsAccess() async {
    final account = _account;
    if (account == null) return;
    setState(() {
      _authorizing = true;
      _error = null;
    });
    await _finishSignIn(account, interactiveConsent: true);
  }

  Future<void> _finishSignIn(
    GoogleSignInAccount account, {
    bool interactiveConsent = false,
  }) async {
    if (!mounted || _repository != null) return;
    setState(() {
      _account = account;
      _authorizing = true;
      _needsConsent = false;
      _error = null;
    });
    try {
      _authService.validateAllowedAccount(account);
      if (mounted) {
        setState(() {
          _authorizing = false;
          _loadingData = true;
        });
      }
      final accessToken = interactiveConsent
          ? await _authService.authorizeSheetsInteractively(account)
          : await _authService.authorizeSheets(account);
      final api = GoogleSheetsApi(
        spreadsheetId: widget.config.spreadsheetId,
        accessToken: accessToken,
      );
      final repository = GoogleSheetsAppDataRepository(api);
      final initialData = await repository.load();
      final maintenance = DailyMaintenanceService(
        client: api,
        data: initialData,
      );
      final today = DateTime.now();
      await maintenance.catchUp(
        yesterday: today.subtract(const Duration(days: 1)),
      );
      await repository.reload();
      _rebuildDailyTables = () async {
        await maintenance.rebuild();
        await repository.reload();
      };
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _authorizing = false;
        _loadingData = false;
      });
    } on GoogleAuthException {
      if (!mounted) return;
      setState(() {
        _authorizing = false;
        _loadingData = false;
        _needsConsent = true;
      });
    } on DataValidationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _authorizing = false;
        _loadingData = false;
        _dataFailure = failure;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _authorizing = false;
        _loadingData = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _switchAccount() async {
    await _authService.signOut();
    if (!mounted) return;
    setState(() {
      _account = null;
      _repository = null;
      _needsConsent = false;
      _loading = false;
      _authorizing = false;
      _loadingData = false;
      _error = null;
    });
  }

  bool _isBenignAuthenticationError(Object error) {
    if (error is! GoogleSignInException) return false;
    return error.code == GoogleSignInExceptionCode.canceled ||
        error.code == GoogleSignInExceptionCode.interrupted ||
        error.code == GoogleSignInExceptionCode.uiUnavailable;
  }

  void _retry() {
    setState(() {
      _error = null;
      _dataFailure = null;
      _loading = _account == null;
    });
    final account = _account;
    if (account != null) {
      _finishSignIn(account);
    } else {
      _initialize();
    }
  }
}
