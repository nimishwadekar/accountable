import '../app_data_snapshot.dart';
import '../models/models.dart';

abstract interface class CurrencyRepository {
  Future<List<CurrencyDefinition>> load();
}

abstract interface class AccountRepository {
  Future<List<Account>> load({
    required Map<String, CurrencyDefinition> currencies,
  });
}

abstract interface class CategoryRepository {
  Future<List<Category>> load();
}

abstract interface class TagRepository {
  Future<List<Tag>> load();
}

abstract interface class TransactionRepository {
  Future<List<Transaction>> load({
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  });
}

abstract interface class ExchangeRateRepository {
  Future<List<ExchangeRate>> load();
}

abstract interface class DailyAccountBalanceRepository {
  Future<List<DailyAccountBalance>> load({
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  });
}

abstract interface class DailyNetWorthRepository {
  Future<List<DailyNetWorth>> load({
    required Map<String, CurrencyDefinition> currencies,
  });
}

abstract interface class AppDataRepository {
  Future<AppDataSnapshot> load();

  Future<AppDataSnapshot> reload();

  Future<AppDataSnapshot> addTransaction(Transaction transaction);
}
