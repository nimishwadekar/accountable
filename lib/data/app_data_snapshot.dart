import 'models/models.dart';

class AppDataSnapshot {
  AppDataSnapshot({
    required List<Account> accounts,
    required List<Category> categories,
    required List<CurrencyDefinition> currencies,
    required List<Tag> tags,
    required List<Transaction> transactions,
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
       dailyAccountBalancesById = _indexById(
         dailyAccountBalances,
         (balance) => balance.id,
       ),
       dailyNetWorthById = _indexById(dailyNetWorth, (netWorth) => netWorth.id),
       dailyManualValuationsById = _indexById(
         dailyManualValuations,
         (valuation) => valuation.id,
       ),
       displayPreferences = List.unmodifiable(displayPreferences),
       displayPreferencesByKey = {
         for (final preference in displayPreferences)
           _preferenceKey(preference.entityType, preference.entityId):
               preference,
       },
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
  final Map<String, DailyNetWorth> dailyNetWorthById;
  final Map<String, DailyManualValuation> dailyManualValuationsById;
  final Map<String, DisplayPreference> displayPreferencesByKey;
  final Map<String, TransactionTemplate> transactionTemplatesById;
  final Map<String, IncomeAllocation> incomeAllocationsById;

  DisplayPreference? displayPreferenceFor(String entityType, String entityId) =>
      displayPreferencesByKey[_preferenceKey(entityType, entityId)];

  List<Account> get orderedAccounts =>
      _ordered(accounts, entityType: 'account', idOf: (account) => account.id);

  List<Category> get orderedCategories => _ordered(
    categories,
    entityType: 'category',
    idOf: (category) => category.id,
  );

  List<Tag> get orderedTags =>
      _ordered(tags, entityType: 'tag', idOf: (tag) => tag.id);

  List<Account> get visibleAccounts => orderedAccounts
      .where(
        (account) =>
            displayPreferenceFor('account', account.id)?.showInApp ?? true,
      )
      .toList();

  List<Category> get visibleCategories => orderedCategories
      .where(
        (category) =>
            displayPreferenceFor('category', category.id)?.showInApp ?? true,
      )
      .toList();

  List<Tag> get visibleTags => orderedTags
      .where((tag) => displayPreferenceFor('tag', tag.id)?.showInApp ?? true)
      .toList();

  List<Account> get entryFormAccounts => orderedAccounts
      .where(
        (account) =>
            displayPreferenceFor('account', account.id)?.showInEntryForms ??
            true,
      )
      .toList();

  List<Category> get entryFormCategories => orderedCategories
      .where(
        (category) =>
            displayPreferenceFor('category', category.id)?.showInEntryForms ??
            true,
      )
      .toList();

  List<Tag> get entryFormTags => orderedTags
      .where(
        (tag) => displayPreferenceFor('tag', tag.id)?.showInEntryForms ?? true,
      )
      .toList();

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

  static String _preferenceKey(String entityType, String entityId) =>
      '$entityType:$entityId';

  static Map<String, T> _indexById<T>(
    Iterable<T> values,
    String Function(T) idOf,
  ) {
    return Map.unmodifiable({for (final value in values) idOf(value): value});
  }
}
