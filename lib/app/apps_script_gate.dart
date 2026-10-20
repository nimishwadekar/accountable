import 'dart:async';

import 'package:flutter/material.dart';

import '../config/accountable_config.dart';
import '../data/data.dart';
import 'app_shell.dart';
import 'google_sign_in_button.dart';
import 'theme/design_tokens.dart';

class AppsScriptGate extends StatefulWidget {
  const AppsScriptGate({
    super.key,
    required this.config,
    this.textScale = 1,
    this.onTextScaleChanged,
  });

  final AccountableConfig config;
  final double textScale;
  final ValueChanged<double>? onTextScaleChanged;

  @override
  State<AppsScriptGate> createState() => _AppsScriptGateState();
}

class _AppsScriptGateState extends State<AppsScriptGate> {
  late final GoogleAuthService _authService;
  StreamSubscription<AccountableGoogleAccount>? _eventsSubscription;
  Completer<AccountableGoogleAccount?>? _silentSignIn;
  AccountableGoogleAccount? _account;
  AppDataRepository? _repository;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _authService = GoogleAuthService(config: widget.config);
    _eventsSubscription = _authService.authenticationEvents.listen((event) {
      final completer = _silentSignIn;
      if (completer != null && !completer.isCompleted) {
        completer.complete(event);
      } else {
        unawaited(_connect(event));
      }
    });
    unawaited(_restoreSignIn());
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_repository != null) {
      return AppShell(
        dataRepository: _repository!,
        textScale: widget.textScale,
        onTextScaleChanged: widget.onTextScaleChanged,
      );
    }
    return Scaffold(
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_outlined, size: 48),
                const SizedBox(height: AppSpacing.md),
                const Text('Connect Accountable'),
                const SizedBox(height: AppSpacing.sm),
                Text(_message, textAlign: TextAlign.center),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (_loading)
                  const CircularProgressIndicator()
                else
                  buildGoogleSignInButton(onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _message {
    if (_loading) return 'Restoring your Google session…';
    if (_account != null) return 'Loading your financial data…';
    return 'Sign in with your Google account to continue.';
  }

  Future<void> _restoreSignIn() async {
    if (!widget.config.hasConfiguredAppsScript) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Configure appsScriptUrl before using Apps Script mode.';
        });
      }
      return;
    }
    final completer = Completer<AccountableGoogleAccount?>();
    _silentSignIn = completer;
    try {
      final attempt = await _authService.attemptSilentAuthentication();
      final account = attempt == null
          ? await completer.future.timeout(
              const Duration(seconds: 5),
              onTimeout: () => null,
            )
          : await attempt.timeout(
              const Duration(seconds: 5),
              onTimeout: () => null,
            );
      if (!mounted) return;
      setState(() => _loading = false);
      if (account != null) await _connect(account);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    } finally {
      if (identical(_silentSignIn, completer)) _silentSignIn = null;
    }
  }

  Future<void> _connect(AccountableGoogleAccount account) async {
    if (_repository != null) return;
    try {
      _authService.validateAllowedAccount(account);
      if (mounted) {
        setState(() {
          _account = account;
          _loading = true;
          _error = null;
        });
      }
      final client = AppsScriptTableClient(
        endpoint: widget.config.appsScriptUrl,
        idTokenProvider: () => _authService.idToken(account),
      );
      final repository = GoogleSheetsAppDataRepository(client);
      await repository.load();
      if (!mounted) return;
      setState(() {
        _repository = repository;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }
}
