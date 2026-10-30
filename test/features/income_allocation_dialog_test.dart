import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/income_allocation_dialog.dart';
import 'package:accountable/app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders income allocation fields', (tester) async {
    const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
    final checking = Account(
      id: 'checking',
      name: 'Checking',
      accountType: 'cash',
      currencyId: 'USD',
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
      usesManualValuations: false,
    );
    final data = AppDataSnapshot(
      accounts: [checking],
      categories: const [
        Category(
          id: 'salary',
          name: 'Salary',
          allowedTransactionTypes: {TransactionType.income},
        ),
      ],
      currencies: const [usd],
      tags: const [],
      transactions: const [],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: IncomeAllocationDialog(data: data),
      ),
    );
    await tester.pump();

    expect(find.text('Add Income Allocation'), findsOneWidget);
    expect(find.text('Income Category'), findsOneWidget);
    expect(find.text('Expected Amount per Income'), findsOneWidget);
    expect(find.text('Transfer Category'), findsOneWidget);
  });

  testWidgets(
    'validates and returns an allocation in the income account currency',
    (tester) async {
      const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
      final checking = Account(
        id: 'checking',
        name: 'Checking',
        accountType: 'cash',
        currencyId: 'USD',
        openingBalance: Money.zero(usd),
        openingDate: DateTime.utc(2026, 1, 1),
        closingDate: null,
        usesManualValuations: false,
      );
      final data = AppDataSnapshot(
        accounts: [checking],
        categories: const [
          Category(
            id: 'salary',
            name: 'Salary',
            allowedTransactionTypes: {TransactionType.income},
          ),
          Category(
            id: 'transfer',
            name: 'Transfer',
            allowedTransactionTypes: {TransactionType.transfer},
          ),
        ],
        currencies: const [usd],
        tags: const [],
        transactions: const [],
        exchangeRates: const [],
        dailyAccountBalances: const [],
        dailyNetWorth: const [],
        dailyManualValuations: const [],
      );
      IncomeAllocation? saved;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showDialog<IncomeAllocation>(
                    context: context,
                    builder: (_) => IncomeAllocationDialog(data: data),
                  );
                },
                child: const Text('Open allocation'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open allocation'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(1), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Required.'), findsOneWidget);
      expect(find.text('Select a value.'), findsNWidgets(3));
      expect(find.text('Enter a positive amount.'), findsOneWidget);
      expect(saved, isNull);

      await tester.enterText(find.byType(TextFormField).first, '  Bonus  ');
      final dropdowns = find.byType(DropdownButtonFormField<String>);
      await tester.tap(dropdowns.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salary').last);
      await tester.pumpAndSettle();
      await tester.tap(dropdowns.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checking').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(1), '1,234.56');
      await tester.ensureVisible(dropdowns.at(2));
      await tester.pumpAndSettle();
      await tester.tap(dropdowns.at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer').last);
      await tester.pumpAndSettle();

      final priorDay = DateTime.now().subtract(const Duration(days: 1));
      final expectedPickedDate = DateTime(
        priorDay.year,
        priorDay.month,
        priorDay.day,
      );
      Future<void> chooseDate(Finder button) async {
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final current = DateTime.now();
        final monthDifference =
            (priorDay.year - current.year) * 12 +
            priorDay.month -
            current.month;
        if (monthDifference < 0) {
          for (var month = 0; month < -monthDifference; month++) {
            await tester.tap(find.byTooltip('Previous month'));
            await tester.pumpAndSettle();
          }
        } else {
          for (var month = 0; month < monthDifference; month++) {
            await tester.tap(find.byTooltip('Next month'));
            await tester.pumpAndSettle();
          }
        }
        await tester.tap(find.text(priorDay.day.toString()).last);
        await tester.tap(find.text('OK').last);
        await tester.pumpAndSettle();
      }

      await chooseDate(find.textContaining('End Date'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('End date must be after start date.'), findsOneWidget);
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      await chooseDate(find.textContaining('Start Date'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.name, 'Bonus');
      expect(saved!.incomeCategoryId, 'salary');
      expect(saved!.incomeAccountId, 'checking');
      expect(saved!.transferCategoryId, 'transfer');
      expect(saved!.expectedAmountPerIncome.minorUnits, 123456);
      expect(saved!.expectedAmountPerIncome.currencyId, 'USD');
      expect(saved!.startDate, expectedPickedDate);
      expect(saved!.endDate, expectedPickedDate);

      saved = null;
      await tester.tap(find.text('Open allocation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
    },
  );
}
