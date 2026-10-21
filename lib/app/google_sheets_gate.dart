import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/accountable_config.dart';
import '../data/data.dart';
import 'app_shell.dart';
import 'pages/app_pages.dart';
import 'google_sign_in_button.dart';
import 'theme/design_tokens.dart';

class GoogleSheetsGate extends StatefulWidget {
  const GoogleSheetsGate({
    super.key,
    required this.config,
    this.textScale = 1,
    this.onTextScaleChanged,
  });

  final AccountableConfig config;
  final double textScale;
  final ValueChanged<double>? onTextScaleChanged;

  @override
  State<GoogleSheetsGate> createState() => _GoogleSheetsGateState();
}

enum _GateState {
  configurationRequired,
  restoringSignIn,
  signedOut,
  signingIn,
  authorizingSheets,
  awaitingSheetsConsent,
  loadingData,
  error,
  ready,
}

class _GoogleSheetsGateState extends State<GoogleSheetsGate> {
  late final GoogleAuthService _authService;
  StreamSubscription<AccountableGoogleAccount>? _eventsSubscription;
  Completer<AccountableGoogleAccount?>? _silentSignInCompleter;
  String? _error;
  DataValidationFailure? _dataFailure;
  _GateState _state = _GateState.restoringSignIn;
  AccountableGoogleAccount? _account;
  AppDataRepository? _repository;
  Future<void> Function()? _rebuildDailyTables;
  bool _connectionInProgress = false;
  final Stopwatch _startupStopwatch = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _logTiming('gate initialized');
    _authService = GoogleAuthService(config: widget.config);
    _eventsSubscription = _authService.authenticationEvents.listen(
      (event) {
        final completer = _silentSignInCompleter;
        _logTiming('Google sign-in event received');
        if (completer != null && !completer.isCompleted) {
          completer.complete(event);
          return;
        }
        unawaited(_finishSignIn(event));
      },
      onError: (Object error) {
        final completer = _silentSignInCompleter;
        if (completer != null && !completer.isCompleted) {
          if (_isBenignAuthenticationError(error)) {
            completer.complete(null);
          } else {
            completer.completeError(error);
          }
          return;
        }
        if (_isBenignAuthenticationError(error)) return;
        if (mounted) {
          setState(() {
            _state = _GateState.error;
            _error = error.toString();
          });
        }
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
        migrationAssistance: widget.config.migrationAssistance,
        onRebuildDailyTables: _rebuildDailyTables,
        textScale: widget.textScale,
        onTextScaleChanged: widget.onTextScaleChanged,
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
                    else
                      _buildAction(context),
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

  Widget _buildAction(BuildContext context) {
    return switch (_state) {
      _GateState.restoringSignIn ||
      _GateState.signingIn ||
      _GateState.authorizingSheets ||
      _GateState.loadingData => Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(_message, textAlign: TextAlign.center),
        ],
      ),
      _GateState.awaitingSheetsConsent => FilledButton.icon(
        onPressed: _grantSheetsAccess,
        icon: const Icon(Icons.lock_open_outlined),
        label: const Text('Grant Sheets access'),
      ),
      _GateState.configurationRequired ||
      _GateState.signedOut ||
      _GateState.error ||
      _GateState.ready => buildGoogleSignInButton(onPressed: _signIn),
    };
  }

  void _logTiming(String message) {
    if (!kDebugMode) return;
    debugPrint(
      '[Accountable startup] ${_startupStopwatch.elapsedMilliseconds}ms — $message',
    );
  }

  String get _message {
    if (!widget.config.hasConfiguredGoogleSheets) {
      return 'Add the Google OAuth client ID, spreadsheet ID, and allowed email in assets/config.json.';
    }
    return switch (_state) {
      _GateState.restoringSignIn => 'Restoring your Google session…',
      _GateState.signingIn => 'Signing in to Google…',
      _GateState.authorizingSheets => 'Checking Sheets access…',
      _GateState.loadingData => 'Loading your financial data…',
      _GateState.awaitingSheetsConsent =>
        'Authorize Sheets access for your account to continue.',
      _GateState.signedOut || _GateState.error || _GateState.ready =>
        'Sign in with your authorized Google account to continue.',
      _GateState.configurationRequired => 'Add the Google OAuth client ID, spreadsheet ID, and allowed email in assets/config.json.',
    };
  }

  Future<void> _initialize() async {
    _logTiming('starting authentication initialization');
    if (!widget.config.hasConfiguredGoogleSheets) {
      if (mounted) {
        setState(() => _state = _GateState.configurationRequired);
      }
      return;
    }
    final completer = Completer<AccountableGoogleAccount?>();
    _silentSignInCompleter = completer;
    if (mounted) {
      setState(() {
        _state = _GateState.restoringSignIn;
        _error = null;
      });
    }
    try {
      final attempt = await _authService.attemptSilentAuthentication();
      _logTiming(
        attempt == null
            ? 'silent authentication started asynchronously'
            : 'silent authentication future returned',
      );
      final account = attempt == null
          ? await completer.future.timeout(
              const Duration(seconds: 5),
              onTimeout: () => null,
            )
          : await attempt.timeout(
              const Duration(seconds: 5),
              onTimeout: () => null,
            );
      if (!mounted || _account != null) return;
      if (account == null) {
        _logTiming('silent authentication did not restore an account');
        setState(() => _state = _GateState.signedOut);
      } else {
        _logTiming('Google account restored');
        await _finishSignIn(account);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _GateState.error;
        _error = _isBenignAuthenticationError(error) ? null : error.toString();
      });
    } finally {
      if (identical(_silentSignInCompleter, completer)) {
        _silentSignInCompleter = null;
      }
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _state = _GateState.signingIn;
      _error = null;
    });
    try {
      final account = await _authService.authenticate();
      await _finishSignIn(account, interactiveConsent: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _GateState.error;
        _error = _isBenignAuthenticationError(error) ? null : error.toString();
      });
    }
  }

  Future<void> _grantSheetsAccess() async {
    final account = _account;
    if (account == null) return;
    setState(() {
      _state = _GateState.authorizingSheets;
      _error = null;
    });
    await _finishSignIn(account, interactiveConsent: true);
  }

  Future<void> _finishSignIn(
    AccountableGoogleAccount account, {
    bool interactiveConsent = false,
  }) async {
    if (!mounted || _repository != null || _connectionInProgress) return;
    _connectionInProgress = true;
    setState(() {
      _account = account;
      _state = _GateState.authorizingSheets;
      _error = null;
    });
    try {
      _authService.validateAllowedAccount(account);
      _logTiming(
        interactiveConsent
            ? 'starting interactive Sheets authorization'
            : 'starting silent Sheets authorization',
      );
      if (interactiveConsent) {
        await _authService.authorizeSheetsInteractively(account);
      } else {
        await _authService.authorizeSheets(account);
      }
      _logTiming('Sheets authorization completed');
      if (mounted) {
        setState(() => _state = _GateState.loadingData);
      }
      final api = GoogleSheetsApi(
        spreadsheetId: widget.config.spreadsheetId,
        accessTokenProvider: ({forceRefresh = false}) =>
            _authService.authorizeSheets(account, forceRefresh: forceRefresh),
      );
      final repository = GoogleSheetsAppDataRepository(
        api,
        migrationAssistance: widget.config.migrationAssistance,
      );
      _logTiming('loading initial Sheets snapshot');
      final initialData = await repository.load();
      _logTiming('initial Sheets snapshot loaded');
      final maintenance = DailyMaintenanceService(
        client: api,
        data: initialData,
      );
      final today = DateTime.now();
      _logTiming('starting daily catch-up');
      await maintenance.catchUp(
        yesterday: today.subtract(const Duration(days: 1)),
      );
      _logTiming('daily catch-up completed; reloading snapshot');
      await repository.reload();
      _logTiming('final Sheets snapshot loaded');
      _rebuildDailyTables = () async {
        final latestData = await repository.reload();
        final latestMaintenance = DailyMaintenanceService(
          client: api,
          data: latestData,
        );
        await latestMaintenance.rebuild();
        await repository.reload();
      };
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _state = _GateState.ready;
        _connectionInProgress = false;
      });
      _logTiming('app startup finished');
    } on SheetsAuthorizationRequiredException {
      _connectionInProgress = false;
      if (!mounted) return;
      setState(() => _state = _GateState.awaitingSheetsConsent);
    } on DataValidationFailure catch (failure) {
      _connectionInProgress = false;
      if (!mounted) return;
      setState(() {
        _dataFailure = failure;
        _state = _GateState.error;
      });
    } catch (error) {
      _connectionInProgress = false;
      if (!mounted) return;
      setState(() {
        _state = _GateState.error;
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
      _state = _GateState.signedOut;
      _error = null;
    });
  }

  bool _isBenignAuthenticationError(Object error) =>
      error is GoogleAuthException &&
      error.message == 'Google sign-in was canceled.';

  void _retry() {
    setState(() {
      _error = null;
      _dataFailure = null;
      _state = _account == null
          ? _GateState.restoringSignIn
          : _GateState.authorizingSheets;
    });
    final account = _account;
    if (account != null) {
      unawaited(_finishSignIn(account));
    } else {
      unawaited(_initialize());
    }
  }
}
