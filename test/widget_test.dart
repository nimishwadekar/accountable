import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';
import 'package:accountable/main.dart';

void main() {
  testWidgets('loads the overview shell', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(dataRepository: AssetAppDataRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Net Worth'), findsOneWidget);
    expect(find.text('Current Account Balances'), findsOneWidget);
    expect(
      find.text('Current ledger balance through the latest transaction.'),
      findsOneWidget,
    );
    expect(find.text(r'$ 1,560.00'), findsOneWidget);
    expect(find.text('As of 2026-10-12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
