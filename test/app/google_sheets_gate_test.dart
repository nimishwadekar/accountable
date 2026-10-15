import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/google_sheets_gate.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/config/accountable_config.dart';

void main() {
  testWidgets('shows configuration guidance before OAuth is configured', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: GoogleSheetsGate(
          config: const AccountableConfig(
            dataSource: AccountableDataSource.sheets,
            googleClientId: 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
            spreadsheetId: 'YOUR_SPREADSHEET_ID',
            allowedEmail: 'YOUR_EMAIL@example.com',
            oauthOrigin: 'http://localhost:9000',
            sheetsScope: 'https://www.googleapis.com/auth/spreadsheets',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Connect Accountable'), findsOneWidget);
    expect(
      find.textContaining('Add the Google OAuth client ID'),
      findsOneWidget,
    );
  });
}
