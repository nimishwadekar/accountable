// Local profile-mode UI harness. It uses generated data only and never reads
// assets/config.json, signs in, or connects to Google Sheets.
//
// Run from the repository root:
// flutter run --profile -d web-server --target=tool/performance_profile_app.dart --web-port=9000
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import 'package:accountable/app/pages/transactions_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';
import 'package:accountable/features/analysis/analysis_page.dart';

void main() => runApp(_ProfileHarness(data: _syntheticSnapshot()));

class _ProfileHarness extends StatelessWidget {
  const _ProfileHarness({required this.data});

  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Accountable Profile Harness',
    theme: AppTheme.light(),
    home: DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Synthetic profile harness · 650 transactions'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Transactions'),
              Tab(text: 'Analysis'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TransactionsPage(
              data: data,
              onTransactionAdded: (_) async {},
              onTransactionsAdded: (_) async {},
              onTemplateAdded: (_) async {},
              onTemplateUpdated: (_) async {},
            ),
            AnalysisPage(data: data),
          ],
        ),
      ),
    ),
  );
}

AppDataSnapshot _syntheticSnapshot() {
  const usd = CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2);
  const expenseCategory = Category(
    id: 'synthetic-expense',
    name: 'Synthetic expense',
    allowedTransactionTypes: {
      TransactionType.expense,
      TransactionType.transfer,
    },
  );
  const incomeCategory = Category(
    id: 'synthetic-income',
    name: 'Synthetic income',
    allowedTransactionTypes: {TransactionType.income},
  );
  const tag = Tag(id: 'synthetic-tag', name: 'Synthetic');
  final end = DateTime.utc(2026, 10, 28);
  final start = end.subtract(const Duration(days: 364));
  final checking = _cashAccount('checking', 'Checking', usd, start);
  final savings = _cashAccount('savings', 'Savings', usd, start);
  final accounts = [checking, savings];
  final transactions = <Transaction>[];
  for (var index = 0; index < 650; index++) {
    final date = start.add(Duration(days: index * 365 ~/ 650));
    final account = index.isEven ? checking : savings;
    final otherAccount = identical(account, checking) ? savings : checking;
    final amount = Money(minorUnits: 500 + (index % 15000), currencyId: 'USD');
    final createdAt = date.add(Duration(seconds: index));
    switch (index % 10) {
      case 0:
        transactions.add(
          Transaction(
            id: 'SYN${index.toString().padLeft(6, '0')}',
            createdAt: createdAt,
            date: date,
            type: TransactionType.transfer,
            sourceAmount: amount,
            sourceAccountId: account.id,
            destinationAmount: amount,
            destinationAccountId: otherAccount.id,
            categoryId: expenseCategory.id,
            tagId: tag.id,
            description: 'Synthetic transfer $index',
          ),
        );
      case 1:
      case 2:
        transactions.add(
          Transaction(
            id: 'SYN${index.toString().padLeft(6, '0')}',
            createdAt: createdAt,
            date: date,
            type: TransactionType.income,
            sourceAmount: null,
            sourceAccountId: null,
            destinationAmount: amount,
            destinationAccountId: account.id,
            categoryId: incomeCategory.id,
            tagId: tag.id,
            description: 'Synthetic income $index',
          ),
        );
      default:
        transactions.add(
          Transaction(
            id: 'SYN${index.toString().padLeft(6, '0')}',
            createdAt: createdAt,
            date: date,
            type: TransactionType.expense,
            sourceAmount: amount,
            sourceAccountId: account.id,
            destinationAmount: null,
            destinationAccountId: null,
            categoryId: expenseCategory.id,
            tagId: tag.id,
            description: 'Synthetic expense $index',
          ),
        );
    }
  }

  final dailyBalances = <DailyAccountBalance>[];
  final dailyNetWorth = <DailyNetWorth>[];
  final exchangeRates = <ExchangeRate>[];
  var checkingBalance = checking.openingBalance.minorUnits;
  var savingsBalance = savings.openingBalance.minorUnits;
  final byDate = <DateTime, List<Transaction>>{};
  for (final transaction in transactions) {
    byDate.putIfAbsent(transaction.date, () => []).add(transaction);
  }
  for (var day = 0; day < 365; day++) {
    final date = start.add(Duration(days: day));
    for (final transaction in byDate[date] ?? const <Transaction>[]) {
      if (transaction.sourceAccountId == checking.id) {
        checkingBalance -= transaction.sourceAmount!.minorUnits;
      } else if (transaction.sourceAccountId == savings.id) {
        savingsBalance -= transaction.sourceAmount!.minorUnits;
      }
      if (transaction.destinationAccountId == checking.id) {
        checkingBalance += transaction.destinationAmount!.minorUnits;
      } else if (transaction.destinationAccountId == savings.id) {
        savingsBalance += transaction.destinationAmount!.minorUnits;
      }
    }
    final checkingMoney = Money(
      minorUnits: checkingBalance,
      currencyId: usd.id,
    );
    final savingsMoney = Money(minorUnits: savingsBalance, currencyId: usd.id);
    dailyBalances
      ..add(
        DailyAccountBalance(
          id: '${_dateKey(date)}-${checking.id}',
          date: date,
          accountId: checking.id,
          balance: checkingMoney,
          balanceUsd: checkingMoney,
          retrievedAt: end,
        ),
      )
      ..add(
        DailyAccountBalance(
          id: '${_dateKey(date)}-${savings.id}',
          date: date,
          accountId: savings.id,
          balance: savingsMoney,
          balanceUsd: savingsMoney,
          retrievedAt: end,
        ),
      );
    dailyNetWorth.add(
      DailyNetWorth(
        id: '${_dateKey(date)}-net',
        date: date,
        amount: Money(
          minorUnits: checkingBalance + savingsBalance,
          currencyId: usd.id,
        ),
        retrievedAt: end,
      ),
    );
    exchangeRates.add(
      ExchangeRate(
        id: '${_dateKey(date)}-USD',
        date: date,
        currencyId: usd.id,
        rateToUsd: Decimal.one,
        sourceRateDate: date,
        retrievedAt: end,
      ),
    );
  }

  return AppDataSnapshot(
    accounts: accounts,
    categories: const [expenseCategory, incomeCategory],
    currencies: const [usd],
    tags: const [tag],
    transactions: transactions,
    exchangeRates: exchangeRates,
    dailyAccountBalances: dailyBalances,
    dailyNetWorth: dailyNetWorth,
    dailyManualValuations: const [],
  );
}

Account _cashAccount(
  String id,
  String name,
  CurrencyDefinition currency,
  DateTime openingDate,
) => Account(
  id: id,
  name: name,
  accountType: 'cash',
  currencyId: currency.id,
  openingBalance: Money.fromMajorUnits(value: '10000', currency: currency),
  openingDate: openingDate,
  closingDate: null,
  usesManualValuations: false,
);

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
