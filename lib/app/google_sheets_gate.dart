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
  String? _outboxError;
  DataValidationFailure? _dataFailure;
  _GateState _state = _GateState.restoringSignIn;
  AccountableGoogleAccount? _account;
  AppDataRepository? _repository;
  AppDataRepository? _pendingOnlineRepository;
  StartupDataRepository? _startupRepository;
  final FormSnapshotStore _formSnapshotStore =
      SharedPreferencesFormSnapshotStore();
  final TransactionOutboxStore _outboxStore =
      SharedPreferencesTransactionOutboxStore();
  Future<void> Function()? _rebuildDailyTables;
  Future<void> Function(DateTime startDate)? _rebuildNetWorth;
  Future<void> Function()? _reconcileDailyTables;
  final TransactionWriteCoordinator _writeCoordinator =
      const TransactionWriteCoordinator();
  late final TransactionOutboxSynchronizer _outboxSynchronizer =
      TransactionOutboxSynchronizer(
        outbox: _outboxStore,
        writeCoordinator: _writeCoordinator,
      );
  bool _connectionInProgress = false;
  bool _onlineTransitionRequested = false;
  bool _transactionFormActive = false;
  int _connectionGeneration = 0;
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
    unawaited(_loadCachedStartupData());
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
        onReconcileDailyTables: _reconcileDailyTables,
        onRebuildNetWorth: _rebuildNetWorth,
        textScale: widget.textScale,
        onTextScaleChanged: widget.onTextScaleChanged,
      );
    }
    if (_startupRepository != null) {
      final backgroundSignIn = switch (_state) {
        _GateState.restoringSignIn ||
        _GateState.signingIn ||
        _GateState.authorizingSheets ||
        _GateState.loadingData => true,
        _ => false,
      };
      return AppShell(
        dataRepository: _startupRepository!,
        restrictedStartup: true,
        onStartupSignIn: _transactionFormActive || backgroundSignIn
            ? null
            : _signIn,
        startupError: backgroundSignIn ? null : _outboxError,
        onRetryOutbox: !backgroundSignIn && _pendingOnlineRepository != null
            ? _retryOutbox
            : null,
        onTransactionFormActiveChanged: _handleTransactionFormActiveChanged,
        migrationAssistance: widget.config.migrationAssistance,
        onRebuildDailyTables: _rebuildDailyTables,
        onReconcileDailyTables: _reconcileDailyTables,
        onRebuildNetWorth: _rebuildNetWorth,
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

  bool _isCurrentConnection(int generation) =>
      mounted && generation == _connectionGeneration;

  Future<void> _loadCachedStartupData() async {
    final generation = _connectionGeneration;
    try {
      final cached = await _formSnapshotStore.read();
      if (cached == null || !mounted) return;
      final pending = await _outboxStore.read();
      final cachedData = cached.toDataSnapshot();
      final pendingTransactions = [
        for (final item in pending) item.transaction,
      ];
      final startupData = withAdditionalTransactions(
        cachedData,
        pendingTransactions,
      );
      if (!_isCurrentConnection(generation) || _repository != null) return;
      setState(() {
        _startupRepository = StartupDataRepository(
          snapshot: startupData,
          outbox: _outboxStore,
        );
      });
    } catch (error) {
      if (kDebugMode) debugPrint('[Accountable startup cache] $error');
    }
  }

  Future<void> _initialize() async {
    _logTiming('starting authentication initialization');
    final scenario = widget.config.debugStartupScenario;
    if (scenario == StartupScenario.delayAutoSignIn ||
        scenario == StartupScenario.delayAndAutoSignInFailure) {
      await Future<void>.delayed(const Duration(seconds: 10));
    }
    if (scenario == StartupScenario.autoSignInFailure ||
        scenario == StartupScenario.delayAndAutoSignInFailure) {
      if (mounted) {
        setState(() {
          _state = _GateState.error;
          _error = 'Debug startup scenario: automatic sign-in failed.';
        });
      }
      return;
    }
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
    final generation = _connectionGeneration;
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
      if (!interactiveConsent &&
          widget.config.debugStartupScenario ==
              StartupScenario.sheetsAuthorizationFailure) {
        throw const GoogleAuthException(
          'Debug startup scenario: Sheets authorization failed.',
        );
      }
      if (interactiveConsent) {
        await _authService.authorizeSheetsInteractively(account);
      } else {
        await _authService.authorizeSheets(account);
      }
      if (!_isCurrentConnection(generation)) return;
      _logTiming('Sheets authorization completed');
      setState(() => _state = _GateState.loadingData);
      final api = GoogleSheetsApi(
        spreadsheetId: widget.config.spreadsheetId,
        accessTokenProvider: ({forceRefresh = false}) =>
            _authService.authorizeSheets(account, forceRefresh: forceRefresh),
      );
      final repository = GoogleSheetsAppDataRepository(
        api,
        migrationAssistance: widget.config.migrationAssistance,
      );
      _reconcileDailyTables = () => _writeCoordinator.run(() async {
        final latestData = await repository.reload();
        await DailyMaintenanceService(
          client: api,
          data: latestData,
        ).reconcile();
        await repository.reload();
      });
      _logTiming('loading initial Sheets snapshot');
      final initialData = await repository.load();
      if (!_isCurrentConnection(generation)) return;
      _logTiming('initial Sheets snapshot loaded');
      if (widget.config.debugStartupScenario ==
          StartupScenario.dataLoadFailure) {
        throw const DataLoadException(
          tableName: 'Debug startup',
          message: 'Debug startup scenario: data loading failed.',
        );
      }
      final maintenance = DailyMaintenanceService(
        client: api,
        data: initialData,
      );
      final today = DateTime.now();
      _logTiming('starting daily-table reconciliation');
      await _writeCoordinator.run(
        () => maintenance.reconcile(
          yesterday: today.subtract(const Duration(days: 1)),
        ),
      );
      if (!_isCurrentConnection(generation)) return;
      _logTiming('daily-table reconciliation completed; reloading snapshot');
      await repository.reload();
      if (!_isCurrentConnection(generation)) return;
      _logTiming('final Sheets snapshot loaded');
      _pendingOnlineRepository = repository;
      _rebuildDailyTables = () => _writeCoordinator.run(() async {
        final latestData = await repository.reload();
        await DailyMaintenanceService(client: api, data: latestData).rebuild();
        await repository.reload();
      });
      _rebuildNetWorth = (startDate) => _writeCoordinator.run(() async {
        final latestData = await repository.reload();
        await DailyMaintenanceService(
          client: api,
          data: latestData,
        ).rebuildNetWorth(startDate: startDate);
        await repository.reload();
      });
      var transitionedOnline = false;
      if (!_transactionFormActive) {
        transitionedOnline = await _synchronizeOutboxAndTransition(
          repository,
          generation: generation,
        );
      }
      if (!_isCurrentConnection(generation)) return;
      if (!transitionedOnline) setState(() => _state = _GateState.ready);
      _logTiming('app startup finished');
    } on SheetsAuthorizationRequiredException {
      if (!_isCurrentConnection(generation)) return;
      setState(() => _state = _GateState.awaitingSheetsConsent);
    } on DataValidationFailure catch (failure) {
      if (!_isCurrentConnection(generation)) return;
      setState(() {
        _dataFailure = failure;
        _state = _GateState.error;
      });
    } catch (error) {
      if (!_isCurrentConnection(generation)) return;
      if (_pendingOnlineRepository != null) {
        _outboxError = error.toString();
      }
      setState(() {
        _state = _GateState.error;
        _error = error.toString();
      });
    } finally {
      if (generation == _connectionGeneration) {
        _connectionInProgress = false;
        _resumeRequestedOnlineTransition();
      }
    }
  }

  Future<void> _flushPendingTransactions(
    AppDataRepository repository, {
    bool allowUncertainRetry = false,
  }) => _outboxSynchronizer.flush(
    repository,
    allowUncertainRetry: allowUncertainRetry,
  );

  void _handleTransactionFormActiveChanged(bool active) {
    if (!mounted) return;
    setState(() => _transactionFormActive = active);
    if (!active && _pendingOnlineRepository != null && _repository == null) {
      if (_connectionInProgress) {
        _onlineTransitionRequested = true;
        return;
      }
      unawaited(_completeOnlineTransition());
    }
  }

  void _resumeRequestedOnlineTransition() {
    if (!_onlineTransitionRequested) return;
    _onlineTransitionRequested = false;
    if (_pendingOnlineRepository != null &&
        _repository == null &&
        !_transactionFormActive) {
      unawaited(_completeOnlineTransition());
    }
  }

  Future<bool> _synchronizeOutboxAndTransition(
    AppDataRepository repository, {
    required int generation,
    bool allowUncertainRetry = false,
  }) async {
    while (_isCurrentConnection(generation) && !_transactionFormActive) {
      await _flushPendingTransactions(
        repository,
        allowUncertainRetry: allowUncertainRetry,
      );
      if (!_isCurrentConnection(generation) || _transactionFormActive) {
        return false;
      }
      await _reconcileDailyTables?.call();
      if (!_isCurrentConnection(generation) || _transactionFormActive) {
        return false;
      }
      final data = await repository.reload();
      if (!_isCurrentConnection(generation) || _transactionFormActive) {
        return false;
      }
      await _formSnapshotStore.write(
        FormSnapshot.fromData(data, dataSource: 'sheets'),
      );
      if (!_isCurrentConnection(generation) || _transactionFormActive) {
        return false;
      }
      final transitioned = await _writeCoordinator.run(() async {
        if (!_isCurrentConnection(generation) || _transactionFormActive) {
          return false;
        }
        final pending = await _outboxStore.read();
        if (pending.isNotEmpty || _transactionFormActive) return false;
        setState(() {
          _repository = repository;
          _pendingOnlineRepository = null;
          _startupRepository = null;
          _outboxError = null;
          _state = _GateState.ready;
        });
        return true;
      });
      if (transitioned || _transactionFormActive) return transitioned;
      // A transaction was queued while synchronization was in flight.
      // Re-read and upload it before switching the shell to online data.
    }
    return false;
  }

  Future<void> _completeOnlineTransition() async {
    final repository = _pendingOnlineRepository;
    if (repository == null || _repository != null || _connectionInProgress) {
      return;
    }
    final generation = _connectionGeneration;
    _connectionInProgress = true;
    try {
      await _synchronizeOutboxAndTransition(repository, generation: generation);
    } catch (error) {
      if (!_isCurrentConnection(generation)) return;
      setState(() => _outboxError = error.toString());
    } finally {
      if (generation == _connectionGeneration) {
        _connectionInProgress = false;
        _resumeRequestedOnlineTransition();
      }
    }
  }

  Future<void> _retryOutbox() async {
    final repository = _pendingOnlineRepository;
    if (repository == null || _connectionInProgress || _transactionFormActive) {
      return;
    }
    final generation = _connectionGeneration;
    setState(() => _outboxError = null);
    try {
      _connectionInProgress = true;
      await _synchronizeOutboxAndTransition(
        repository,
        generation: generation,
        allowUncertainRetry: true,
      );
    } catch (error) {
      if (!_isCurrentConnection(generation)) return;
      setState(() => _outboxError = error.toString());
    } finally {
      if (generation == _connectionGeneration) {
        _connectionInProgress = false;
        _resumeRequestedOnlineTransition();
      }
    }
  }

  Future<void> _switchAccount() async {
    _connectionGeneration++;
    _connectionInProgress = false;
    _pendingOnlineRepository = null;
    _rebuildDailyTables = null;
    _rebuildNetWorth = null;
    _reconcileDailyTables = null;
    await _authService.signOut();
    if (!mounted) return;
    setState(() {
      _account = null;
      _repository = null;
      _startupRepository = null;
      _outboxError = null;
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
