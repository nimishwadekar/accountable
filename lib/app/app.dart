import 'package:flutter/material.dart';

import '../config/accountable_config.dart';
import '../config/data_source_config.dart';
import '../data/data.dart';
import 'app_shell.dart';
import 'google_sheets_gate.dart';
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

  @override
  Widget build(BuildContext context) {
    if (widget.dataRepository != null) {
      return MaterialApp(
        title: 'Accountable',
        theme: AppTheme.light(),
        home: AppShell(dataRepository: widget.dataRepository!),
      );
    }

    return FutureBuilder<AccountableConfig>(
      future: _configFuture,
      builder: (context, snapshot) {
        return MaterialApp(
          title: 'Accountable',
          theme: AppTheme.light(),
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
          config: const AppDataConfig(
            dataSourceMode: DataSourceMode.localAssets,
          ),
        ),
      );
    }
    return GoogleSheetsGate(config: config);
  }
}
