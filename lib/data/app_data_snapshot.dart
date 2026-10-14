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
  })  : accounts = List.unmodifiable(accounts),
        categories = List.unmodifiable(categories),
        currencies = List.unmodifiable(currencies),
        tags = List.unmodifiable(tags),
        transactions = List.unmodifiable(transactions),
        exchangeRates = List.unmodifiable(exchangeRates),
        dailyAccountBalances = List.unmodifiable(dailyAccountBalances),
        dailyNetWorth = List.unmodifiable(dailyNetWorth),
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
        dailyNetWorthById = _indexById(
          dailyNetWorth,
          (netWorth) => netWorth.id,
        );

  final List<Account> accounts;
  final List<Category> categories;
  final List<CurrencyDefinition> currencies;
  final List<Tag> tags;
  final List<Transaction> transactions;
  final List<ExchangeRate> exchangeRates;
  final List<DailyAccountBalance> dailyAccountBalances;
  final List<DailyNetWorth> dailyNetWorth;

  final Map<String, Account> accountsById;
  final Map<String, Category> categoriesById;
  final Map<String, CurrencyDefinition> currenciesById;
  final Map<String, Tag> tagsById;
  final Map<String, Transaction> transactionsById;
  final Map<String, ExchangeRate> exchangeRatesById;
  final Map<String, DailyAccountBalance> dailyAccountBalancesById;
  final Map<String, DailyNetWorth> dailyNetWorthById;

  static Map<String, T> _indexById<T>(
    Iterable<T> values,
    String Function(T) idOf,
  ) {
    return Map.unmodifiable({for (final value in values) idOf(value): value});
  }
}
