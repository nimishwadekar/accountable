import 'package:flutter/material.dart';

import '../config/accountable_config.dart';
import '../data/data.dart';
import 'app_shell.dart';
import 'pages/app_pages.dart';

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
  late Future<AppDataSnapshot> _snapshotFuture;
  AppDataRepository? _repository;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDataSnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return AppErrorPage(
            error:
                snapshot.error ?? StateError('Apps Script returned no data.'),
            onReload: _reload,
          );
        }
        return AppShell(
          dataRepository: _repository!,
          textScale: widget.textScale,
          onTextScaleChanged: widget.onTextScaleChanged,
        );
      },
    );
  }

  Future<AppDataSnapshot> _load() async {
    if (!widget.config.hasConfiguredAppsScript) {
      throw const FormatException(
        'Configure appsScriptUrl before selecting the apps_script data source.',
      );
    }
    final client = AppsScriptTableClient(endpoint: widget.config.appsScriptUrl);
    final repository = GoogleSheetsAppDataRepository(client);
    _repository = repository;
    return repository.load();
  }

  void _reload() {
    setState(() {
      _snapshotFuture = _load();
    });
  }
}
