import 'models/models.dart';

class AppDataSnapshot {
  AppDataSnapshot({
    required List<Account> accounts,
    required List<Category> categories,
    required List<CurrencyDefinition> currencies,
    required List<Tag> tags,
    required List<Transaction> transactions,
    List<Transaction> transactionsToMigrate = const [],
    required List<ExchangeRate> exchangeRates,
    required List<DailyAccountBalance> dailyAccountBalances,
    required List<DailyNetWorth> dailyNetWorth,
    required List<DailyManualValuation> dailyManualValuations,
    List<DisplayPreference> displayPreferences = const [],
    List<TransactionTemplate> transactionTemplates = const [],
    List<IncomeAllocation> incomeAllocations = const [],
  }) : accounts = List.unmodifiable(accounts),
       categories = List.unmodifiable(categories),
       currencies = List.unmodifiable(currencies),
       tags = List.unmodifiable(tags),
       transactions = List.unmodifiable(transactions),
       transactionsByDisplayOrder = _sortTransactions(transactions),
       transactionsByDate = _indexTransactions(
         transactions,
         (date) => DateTime.utc(date.year, date.month, date.day),
       ),
       transactionsByMonth = _indexTransactions(
         transactions,
         (date) => DateTime.utc(date.year, date.month),
       ),
       earliestTransactionDate = _earliestTransactionDate(transactions),
       transactionsToMigrate = List.unmodifiable(transactionsToMigrate),
       exchangeRates = List.unmodifiable(exchangeRates),
       dailyAccountBalances = List.unmodifiable(dailyAccountBalances),
       dailyNetWorth = List.unmodifiable(dailyNetWorth),
       dailyManualValuations = List.unmodifiable(dailyManualValuations),
       accountsById = _indexById(accounts, (account) => account.id),
       categoriesById = _indexById(categories, (category) => category.id),
       currenciesById = _indexById(currencies, (currency) => currency.id),
       tagsById = _indexById(tags, (tag) => tag.id),
       transactionsById = _indexById(
         transactions,
         (transaction) => transaction.id,
       ),
       exchangeRatesById = _indexById(exchangeRates, (rate) => rate.id),
       dailyNetWorthById = _indexById(dailyNetWorth, (netWorth) => netWorth.id),
       dailyNetWorthByDate = _indexByDate(
         dailyNetWorth,
         (netWorth) => netWorth.date,
       ),
       dailyAccountBalancesById = _indexById(
         dailyAccountBalances,
         (balance) => balance.id,
       ),
       dailyBalancesByAccountId = _groupAndSort(
         dailyAccountBalances,
         (balance) => balance.accountId,
         (balance) => balance.date,
       ),
       dailyManualValuationsById = _indexById(
         dailyManualValuations,
         (valuation) => valuation.id,
       ),
       manualValuationsByAccountId = _groupAndSort(
         dailyManualValuations,
         (valuation) => valuation.accountId,
         (valuation) => valuation.date,
       ),
       exchangeRatesByCurrencyId = _groupAndSort(
         exchangeRates,
         (rate) => rate.currencyId,
         (rate) => rate.date,
       ),
       ledgerBalances = _calculateLedgerBalances(accounts, transactions),
       displayPreferences = List.unmodifiable(displayPreferences),
       displayPreferencesByKey = Map.unmodifiable({
         for (final preference in displayPreferences)
           _preferenceKey(preference.entityType, preference.entityId):
               preference,
       }),
       transactionTemplates = List.unmodifiable(transactionTemplates),
       transactionTemplatesById = _indexById(
         transactionTemplates,
         (template) => template.id,
       ),
       incomeAllocations = List.unmodifiable(incomeAllocations),
       incomeAllocationsById = _indexById(
         incomeAllocations,
         (allocation) => allocation.id,
       );

  final List<Account> accounts;
  final List<Category> categories;
  final List<CurrencyDefinition> currencies;
  final List<Tag> tags;
  final List<Transaction> transactions;
  final List<Transaction> transactionsByDisplayOrder;
  final Map<DateTime, List<Transaction>> transactionsByDate;
  final Map<DateTime, List<Transaction>> transactionsByMonth;
  final DateTime? earliestTransactionDate;
  final List<Transaction> transactionsToMigrate;
  final List<ExchangeRate> exchangeRates;
  final List<DailyAccountBalance> dailyAccountBalances;
  final List<DailyNetWorth> dailyNetWorth;
  final List<DailyManualValuation> dailyManualValuations;
  final List<DisplayPreference> displayPreferences;
  final List<TransactionTemplate> transactionTemplates;
  final List<IncomeAllocation> incomeAllocations;

  final Map<String, Account> accountsById;
  final Map<String, Category> categoriesById;
  final Map<String, CurrencyDefinition> currenciesById;
  final Map<String, Tag> tagsById;
  final Map<String, Transaction> transactionsById;
  final Map<String, ExchangeRate> exchangeRatesById;
  final Map<String, DailyAccountBalance> dailyAccountBalancesById;
  final Map<DateTime, DailyNetWorth> dailyNetWorthByDate;
  final Map<String, DailyNetWorth> dailyNetWorthById;
  final Map<String, List<DailyAccountBalance>> dailyBalancesByAccountId;
  final Map<String, DailyManualValuation> dailyManualValuationsById;
  final Map<String, List<DailyManualValuation>> manualValuationsByAccountId;
  final Map<String, List<ExchangeRate>> exchangeRatesByCurrencyId;
  final Map<String, Money> ledgerBalances;
  final Map<String, DisplayPreference> displayPreferencesByKey;
  final Map<String, TransactionTemplate> transactionTemplatesById;
  final Map<String, IncomeAllocation> incomeAllocationsById;

  DisplayPreference? displayPreferenceFor(String entityType, String entityId) =>
      displayPreferencesByKey[_preferenceKey(entityType, entityId)];

  late final List<Account> _orderedAccounts = _ordered(
    accounts,
    entityType: 'account',
    idOf: (account) => account.id,
  );
  late final List<Category> _orderedCategories = _ordered(
    categories,
    entityType: 'category',
    idOf: (category) => category.id,
  );
  late final List<Tag> _orderedTags = _ordered(
    tags,
    entityType: 'tag',
    idOf: (tag) => tag.id,
  );

  List<Account> get orderedAccounts => _orderedAccounts;

  List<Category> get orderedCategories => _orderedCategories;

  List<Tag> get orderedTags => _orderedTags;

  late final List<Account> _visibleAccounts = orderedAccounts
      .where(
        (account) =>
            displayPreferenceFor('account', account.id)?.showInApp ?? true,
      )
      .toList(growable: false);
  late final List<Category> _visibleCategories = orderedCategories
      .where(
        (category) =>
            displayPreferenceFor('category', category.id)?.showInApp ?? true,
      )
      .toList(growable: false);
  late final List<Tag> _visibleTags = orderedTags
      .where((tag) => displayPreferenceFor('tag', tag.id)?.showInApp ?? true)
      .toList(growable: false);

  List<Account> get visibleAccounts => _visibleAccounts;

  List<Category> get visibleCategories => _visibleCategories;

  List<Tag> get visibleTags => _visibleTags;

  late final List<Account> _entryFormAccounts = orderedAccounts
      .where(
        (account) =>
            displayPreferenceFor('account', account.id)?.showInEntryForms ??
            true,
      )
      .toList(growable: false);
  late final List<Category> _entryFormCategories = orderedCategories
      .where(
        (category) =>
            displayPreferenceFor('category', category.id)?.showInEntryForms ??
            true,
      )
      .toList(growable: false);
  late final List<Tag> _entryFormTags = orderedTags
      .where(
        (tag) => displayPreferenceFor('tag', tag.id)?.showInEntryForms ?? true,
      )
      .toList(growable: false);

  List<Account> get entryFormAccounts => _entryFormAccounts;

  List<Category> get entryFormCategories => _entryFormCategories;

  List<Tag> get entryFormTags => _entryFormTags;

  List<T> _ordered<T>(
    List<T> values, {
    required String entityType,
    required String Function(T) idOf,
  }) {
    final indexed = values.asMap().entries.toList();
    indexed.sort((a, b) {
      final aPreference = displayPreferenceFor(entityType, idOf(a.value));
      final bPreference = displayPreferenceFor(entityType, idOf(b.value));
      final aOrder = aPreference?.displayOrder ?? 1 << 30;
      final bOrder = bPreference?.displayOrder ?? 1 << 30;
      return aOrder == bOrder
          ? a.key.compareTo(b.key)
          : aOrder.compareTo(bOrder);
    });
    return [for (final entry in indexed) entry.value];
  }

  static Map<String, Money> _calculateLedgerBalances(
    Iterable<Account> accounts,
    Iterable<Transaction> transactions,
  ) {
    final balances = <String, Money>{
      for (final account in accounts) account.id: account.openingBalance,
    };
    for (final transaction in transactions) {
      if (transaction.sourceAccountId != null &&
          transaction.sourceAmount != null) {
        final accountId = transaction.sourceAccountId!;
        balances[accountId] = balances[accountId]! - transaction.sourceAmount!;
      }
      if (transaction.destinationAccountId != null &&
          transaction.destinationAmount != null) {
        final accountId = transaction.destinationAccountId!;
        balances[accountId] =
            balances[accountId]! + transaction.destinationAmount!;
      }
    }
    return Map.unmodifiable(balances);
  }

  static List<Transaction> _sortTransactions(Iterable<Transaction> values) {
    final sorted = [...values]
      ..sort((a, b) {
        final dateComparison = b.date.compareTo(a.date);
        return dateComparison == 0
            ? b.createdAt.compareTo(a.createdAt)
            : dateComparison;
      });
    return List<Transaction>.unmodifiable(sorted);
  }

  static Map<DateTime, List<Transaction>> _indexTransactions(
    Iterable<Transaction> values,
    DateTime Function(DateTime) keyOf,
  ) {
    final grouped = <DateTime, List<Transaction>>{};
    for (final transaction in values) {
      grouped.putIfAbsent(keyOf(transaction.date), () => []).add(transaction);
    }
    return Map<DateTime, List<Transaction>>.unmodifiable({
      for (final entry in grouped.entries)
        entry.key: List<Transaction>.unmodifiable(entry.value),
    });
  }

  static DateTime? _earliestTransactionDate(Iterable<Transaction> values) {
    DateTime? earliest;
    for (final transaction in values) {
      final date = DateTime.utc(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      if (earliest == null || date.isBefore(earliest)) earliest = date;
    }
    return earliest;
  }

  static String _preferenceKey(String entityType, String entityId) =>
      '$entityType:$entityId';

  static Map<DateTime, T> _indexByDate<T>(
    Iterable<T> values,
    DateTime Function(T) dateOf,
  ) {
    return Map.unmodifiable({
      for (final value in values)
        DateTime.utc(
          dateOf(value).year,
          dateOf(value).month,
          dateOf(value).day,
        ): value,
    });
  }

  static Map<String, List<T>> _groupAndSort<T>(
    Iterable<T> values,
    String Function(T) keyOf,
    DateTime Function(T) dateOf,
  ) {
    final grouped = <String, List<T>>{};
    for (final value in values) {
      grouped.putIfAbsent(keyOf(value), () => []).add(value);
    }
    for (final valuesForKey in grouped.values) {
      valuesForKey.sort((a, b) => dateOf(a).compareTo(dateOf(b)));
    }
    return Map.unmodifiable({
      for (final entry in grouped.entries)
        entry.key: List<T>.unmodifiable(entry.value),
    });
  }

  static Map<String, T> _indexById<T>(
    Iterable<T> values,
    String Function(T) idOf,
  ) {
    return Map.unmodifiable({for (final value in values) idOf(value): value});
  }
}
