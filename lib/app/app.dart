import 'package:flutter/material.dart';

import '../data/data.dart';
import 'app_shell.dart';
import 'theme/app_theme.dart';

class AccountableApp extends StatelessWidget {
  const AccountableApp({super.key, this.dataRepository});

  final AppDataRepository? dataRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accountable',
      theme: AppTheme.light(),
      home: AppShell(
        dataRepository: dataRepository ?? createAppDataRepository(),
      ),
    );
  }
}
