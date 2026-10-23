import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/accountable_config.dart';
import '../data/data.dart';
import 'app_shell.dart';
import 'google_sheets_gate.dart';
import 'session_ui_preferences.dart';
import 'theme/app_theme.dart';

class AccountableApp extends StatefulWidget {
  const AccountableApp({super.key, this.dataRepository, this.configLoader});

  final AppDataRepository? dataRepository;
  final Future<AccountableConfig> Function()? configLoader;

  @override
  State<AccountableApp> createState() => _AccountableAppState();
}

class _AccountableAppState extends State<AccountableApp> {
  late final Future<AccountableConfig>? _configFuture =
      widget.dataRepository == null
      ? (widget.configLoader ?? () => AccountableConfig.load())()
      : null;
  double _textScale = 1;

  @override
  void initState() {
    super.initState();
    _restoreTextScale();
    unawaited(SessionUiPreferences.instance.startSession());
  }

  Future<void> _restoreTextScale() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _textScale = preferences.getDouble('text_scale')?.clamp(0.75, 1.0) ?? 1;
    });
  }

  Future<void> _setTextScale(double value) async {
    final scale = value.clamp(0.75, 1.0).toDouble();
    setState(() => _textScale = scale);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('text_scale', scale);
  }

  Widget _withTextScale(BuildContext context, Widget? child) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: TextScaler.linear(_textScale)),
      child: child ?? const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dataRepository != null) {
      return MaterialApp(
        title: 'Accountable',
        theme: AppTheme.light(),
        builder: (context, child) => _withTextScale(context, child),
        home: AppShell(
          dataRepository: widget.dataRepository!,
          textScale: _textScale,
          onTextScaleChanged: _setTextScale,
        ),
      );
    }

    return FutureBuilder<AccountableConfig>(
      future: _configFuture,
      builder: (context, snapshot) {
        return MaterialApp(
          title: 'Accountable',
          theme: AppTheme.light(),
          builder: (context, child) => _withTextScale(context, child),
          home: _buildHome(snapshot),
        );
      },
    );
  }

  Widget _buildHome(AsyncSnapshot<AccountableConfig> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              snapshot.error?.toString() ??
                  'Unable to load assets/config.json.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final config = snapshot.data!;
    if (config.isCsvDataSource) {
      return AppShell(
        dataRepository: createAppDataRepository(
          config: AccountableConfig(
            dataSource: AccountableDataSource.csv,
            migrationAssistance: config.migrationAssistance,
          ),
        ),
        migrationAssistance: config.migrationAssistance,
        textScale: _textScale,
        onTextScaleChanged: _setTextScale,
      );
    }
    return GoogleSheetsGate(
      config: config,
      textScale: _textScale,
      onTextScaleChanged: _setTextScale,
    );
  }
}
