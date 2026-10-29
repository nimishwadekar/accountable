import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transactions_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'balance toggle defaults hidden and scroll button returns to top',
    (tester) async {
      final source = await AssetAppDataRepository().load();
      final transactions = [
        for (var index = 0; index < 40; index++)
          _withId(
            source.transactions[index % source.transactions.length],
            'scroll-$index',
            index,
          ),
      ];
      final data = AppDataSnapshot(
        accounts: source.accounts,
        categories: source.categories,
        currencies: source.currencies,
        tags: source.tags,
        transactions: transactions,
        exchangeRates: source.exchangeRates,
        dailyAccountBalances: source.dailyAccountBalances,
        dailyNetWorth: source.dailyNetWorth,
        dailyManualValuations: source.dailyManualValuations,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: TransactionsPage(
            data: data,
            onTransactionAdded: (_) async {},
            onTransactionsAdded: (_) async {},
            onTemplateAdded: (_) async {},
            onTemplateUpdated: (_) async {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Show balances'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.textContaining('Balance:'), findsNothing);

      await tester.tap(find.text('Show balances'));
      await tester.pump();

      expect(find.text('Hide balances'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.textContaining('Balance:'), findsWidgets);

      await tester.drag(
        find.byKey(const PageStorageKey<String>('transactions-list')),
        const Offset(0, -1200),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to top'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to top'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back to top'), findsNothing);
    },
  );
}

Transaction _withId(Transaction transaction, String id, int offset) =>
    Transaction(
      id: id,
      createdAt: transaction.createdAt.add(Duration(seconds: offset)),
      date: transaction.date,
      type: transaction.type,
      sourceAmount: transaction.sourceAmount,
      sourceAccountId: transaction.sourceAccountId,
      destinationAmount: transaction.destinationAmount,
      destinationAccountId: transaction.destinationAccountId,
      categoryId: transaction.categoryId,
      tagId: transaction.tagId,
      description: transaction.description,
    );
