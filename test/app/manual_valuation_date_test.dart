import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/assets_liabilities_page.dart';
import 'package:accountable/data/data.dart';

void main() {
  final account = Account(
    id: 'loan',
    name: 'Loan',
    accountType: 'liability',
    currencyId: 'USD',
    openingBalance: Money.zero(
      const CurrencyDefinition(id: 'USD', symbol: r'$', decimalPlaces: 2),
    ),
    openingDate: DateTime.utc(2026, 1, 10),
    closingDate: DateTime.utc(2026, 1, 20),
  );

  test('default daily valuation date is after the latest entry', () {
    final usd = const CurrencyDefinition(
      id: 'USD',
      symbol: r'$',
      decimalPlaces: 2,
    );
    final data = AppDataSnapshot(
      accounts: [account],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: const [],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: [
        DailyManualValuation(
          id: 'v',
          date: DateTime.utc(2026, 1, 15),
          accountId: account.id,
          value: Money.zero(usd),
        ),
      ],
    );

    expect(defaultManualValuationDate(data), DateTime.utc(2026, 1, 16));
  });

  test('manual valuation IDs use date and account ID', () {
    expect(
      manualValuationId(DateTime.utc(2026, 1, 15), 'brokerage'),
      '2026-01-15-brokerage',
    );
  });

  test('daily form excludes accounts already valued on the selected date', () {
    final usd = const CurrencyDefinition(
      id: 'USD',
      symbol: r'$',
      decimalPlaces: 2,
    );
    final second = Account(
      id: 'brokerage',
      name: 'Brokerage',
      accountType: 'asset',
      currencyId: 'USD',
      openingBalance: Money.zero(usd),
      openingDate: DateTime.utc(2026, 1, 1),
      closingDate: null,
    );
    final data = AppDataSnapshot(
      accounts: [account, second],
      categories: const [],
      currencies: [usd],
      tags: const [],
      transactions: const [],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: [
        DailyManualValuation(
          id: 'v',
          date: DateTime.utc(2026, 1, 15),
          accountId: account.id,
          value: Money.zero(usd),
        ),
      ],
    );

    expect(eligibleManualValuationAccounts(data, DateTime.utc(2026, 1, 15)), [
      second,
    ]);
  });

  test('allows opening and closing dates inclusively', () {
    expect(
      isManualValuationDateAllowed(
        date: DateTime.utc(2026, 1, 10),
        account: account,
        existing: const [],
      ),
      isTrue,
    );
    expect(
      isManualValuationDateAllowed(
        date: DateTime.utc(2026, 1, 20),
        account: account,
        existing: const [],
      ),
      isTrue,
    );
  });

  test('rejects dates outside account lifetime and duplicates', () {
    final existing = [
      DailyManualValuation(
        id: 'v1',
        date: DateTime.utc(2026, 1, 15),
        accountId: account.id,
        value: Money.fromMajorUnits(
          value: '100',
          currency: const CurrencyDefinition(
            id: 'USD',
            symbol: r'$',
            decimalPlaces: 2,
          ),
        ),
      ),
    ];

    expect(
      isManualValuationDateAllowed(
        date: DateTime.utc(2026, 1, 9),
        account: account,
        existing: existing,
      ),
      isFalse,
    );
    expect(
      isManualValuationDateAllowed(
        date: DateTime.utc(2026, 1, 21),
        account: account,
        existing: existing,
      ),
      isFalse,
    );
    expect(
      isManualValuationDateAllowed(
        date: DateTime.utc(2026, 1, 15),
        account: account,
        existing: existing,
      ),
      isFalse,
    );
  });
}
