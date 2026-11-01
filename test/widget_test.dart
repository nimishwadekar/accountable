import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/app.dart';
import 'package:accountable/config/accountable_config.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/main.dart';

void main() {
  testWidgets('loads the transaction shell', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(dataRepository: AssetAppDataRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Transactions'), findsWidgets);
    expect(find.text('Add transaction'), findsOneWidget);
    expect(find.text('Show balances'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loads the local repository from CSV configuration', (
    tester,
  ) async {
    await tester.pumpWidget(
      AccountableApp(
        configLoader: () async =>
            const AccountableConfig(dataSource: AccountableDataSource.csv),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Transactions'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });
}
