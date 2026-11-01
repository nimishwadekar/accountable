import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/formatters.dart';
import 'package:accountable/app/pages/account_balance_row.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  late final AppDataSnapshot data;

  setUpAll(() async {
    data = await AssetAppDataRepository().load();
  });

  testWidgets('row layout follows its allocated width and text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = data.visibleAccounts.first;
    final balance = Money(
      minorUnits: 123456789,
      currencyId: account.currencyId,
    );
    final expectedAmount = formatMoney(balance, data.currenciesById);

    Future<void> pumpRow({
      required double rowWidth,
      TextScaler textScaler = TextScaler.noScaling,
      Key? key,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          key: key,
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(800, 700))
                .copyWith(textScaler: textScaler),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: rowWidth,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Card(
                        child: AccountBalanceRow(
                          account: account,
                          amount: balance,
                          currencies: data.currenciesById,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpRow(rowWidth: 320, key: const ValueKey('narrow-card-wide-view'));
    expect(find.byType(ListTile), findsNothing);
    expect(find.text(expectedAmount), findsOneWidget);
    final narrowCard = tester.getRect(find.byType(Card));
    final narrowAmount = tester.getRect(find.text(expectedAmount));
    expect(
      narrowCard.height,
      lessThanOrEqualTo(90),
      reason: 'Keep the compact account row without excess padding.',
    );
    expect(narrowAmount.right, closeTo(narrowCard.right - 16, 1));
    expect(find.text(account.name), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final width in [360.0, 390.0, 430.0]) {
      await pumpRow(rowWidth: width, key: ValueKey('phone-$width'));
      final card = tester.getRect(find.byType(Card));
      final amount = tester.getRect(find.text(expectedAmount));
      expect(amount.right, closeTo(card.right - 16, 1), reason: '$width px');
      expect(find.text(account.name), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$width px');
    }

    await pumpRow(rowWidth: 700, key: const ValueKey('wide-row'));
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text(expectedAmount), findsOneWidget);
    expect(
      tester.getRect(find.text(expectedAmount)).right,
      lessThanOrEqualTo(tester.getRect(find.byType(Card)).right - 16),
    );
    expect(tester.takeException(), isNull);

    await pumpRow(
      rowWidth: 700,
      textScaler: const TextScaler.linear(2),
      key: const ValueKey('enlarged-wide-row'),
    );
    expect(find.byType(ListTile), findsNothing);
    expect(find.text(expectedAmount), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpRow(
      rowWidth: 320,
      textScaler: const TextScaler.linear(2),
      key: const ValueKey('enlarged-phone-row'),
    );
    expect(find.text(expectedAmount), findsOneWidget);
    expect(
      tester.getRect(find.byType(SingleChildScrollView)).right,
      closeTo(tester.getRect(find.byType(Card)).right - 16, 1),
      reason: 'The complete enlarged value stays in a right-aligned viewport.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large INR liability remains complete and right-aligned', (
    tester,
  ) async {
    const size = Size(320, 740);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final account = data.accountsById['hdfc-credila-loan']!;
    final amount = Money(
      minorUnits: -286130100,
      currencyId: account.currencyId,
    );
    final expected = formatMoney(amount, data.currenciesById);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: Scaffold(
            body: ListView(
              shrinkWrap: true,
              children: [
                Card(
                  child: AccountBalanceRow(
                    account: account,
                    amount: amount,
                    currencies: data.currenciesById,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(account.name), findsOneWidget);
    expect(find.text(expected), findsOneWidget);
    final card = tester.getRect(find.byType(Card));
    final value = tester.getRect(find.text(expected));
    expect(value.right, closeTo(card.right - 16, 1));
    expect(tester.takeException(), isNull);
  });
}
