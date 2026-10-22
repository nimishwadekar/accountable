import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../repositories/display_preference_manager.dart';
import '../table_schema.dart';

/// The tables needed to render and validate a transaction form.
const formSnapshotTableNames = <String>{
  'Accounts',
  'Categories',
  'Currencies',
  'Tags',
  'TransactionTemplates',
  'DisplayPreferences',
};

class FormSnapshot {
  FormSnapshot({
    required this.schemaVersion,
    required this.savedAt,
    required this.dataSource,
    required Map<String, String> tables,
  }) : tables = Map.unmodifiable(tables);

  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime savedAt;
  final String dataSource;
  final Map<String, String> tables;

  factory FormSnapshot.fromData(
    AppDataSnapshot data, {
    required String dataSource,
    DateTime? savedAt,
  }) {
    final currencies = data.currenciesById;
    final accounts = data.accountsById;
    String amount(Money value, String accountId) {
      final account = accounts[accountId];
      if (account == null) throw StateError('Unknown account: $accountId.');
      final currency = currencies[account.currencyId];
      if (currency == null) {
        throw StateError('Unknown currency: ${account.currencyId}.');
      }
      return value.toMajorUnitsString(currency);
    }
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

    final tables = <String, String>{
      RuntimeTableSchemas.currencies.name: csv.encode([
        RuntimeTableSchemas.currencies.headers,
        for (final currency in data.currencies)
          [currency.id, currency.symbol, currency.decimalPlaces],
      ]),
      RuntimeTableSchemas.accounts.name: csv.encode([
        RuntimeTableSchemas.accounts.headers,
        for (final account in data.accounts)
          [
            account.id,
            account.name,
            account.accountType,
            account.currencyId,
            account.openingBalance.toMajorUnitsString(
              currencies[account.currencyId]!,
            ),
            date(account.openingDate),
            account.closingDate == null ? '' : date(account.closingDate!),
            account.usesManualValuations.toString().toUpperCase(),
          ],
      ]),
      RuntimeTableSchemas.categories.name: csv.encode([
        RuntimeTableSchemas.categories.headers,
        for (final category in data.categories)
          [
            category.id,
            category.name,
            category.allowedTransactionTypes.map((type) => type.wireValue).join(','),
          ],
      ]),
      RuntimeTableSchemas.tags.name: csv.encode([
        RuntimeTableSchemas.tags.headers,
        for (final tag in data.tags) [tag.id, tag.name],
      ]),
      RuntimeTableSchemas.displayPreferences.name: csv.encode([
        RuntimeTableSchemas.displayPreferences.headers,
        for (final preference in data.displayPreferences)
          [
            preference.entityType,
            preference.entityId,
            preference.displayOrder,
            preference.showInApp.toString().toUpperCase(),
            preference.showInEntryForms.toString().toUpperCase(),
          ],
      ]),
      RuntimeTableSchemas.transactionTemplates.name: csv.encode([
        RuntimeTableSchemas.transactionTemplates.headers,
        for (final template in data.transactionTemplates)
          [
            template.id,
            template.name,
            template.type.wireValue,
            template.date == null ? '' : date(template.date!),
            template.description ?? '',
            template.categoryId ?? '',
            template.tagId ?? '',
            template.sourceAccountId ?? '',
            template.sourceAmount == null
                ? ''
                : amount(template.sourceAmount!, template.sourceAccountId!),
            template.destinationAccountId ?? '',
            template.destinationAmount == null
                ? ''
                : amount(
                    template.destinationAmount!,
                    template.destinationAccountId!,
                  ),
            template.createdAt.toUtc().toIso8601String(),
            template.updatedAt.toUtc().toIso8601String(),
          ],
      ]),
    };
    return FormSnapshot(
      schemaVersion: currentSchemaVersion,
      savedAt: (savedAt ?? DateTime.now()).toUtc(),
      dataSource: dataSource,
      tables: tables,
    );
  }

  AppDataSnapshot toDataSnapshot() {
    final currencyList = ModelParsers.parseCurrencies(tables['Currencies']!);
    final currencies = {for (final item in currencyList) item.id: item};
    final accountList = ModelParsers.parseAccounts(
      tables['Accounts']!,
      currencies,
    );
    final accounts = {for (final item in accountList) item.id: item};
    final categoryList = ModelParsers.parseCategories(tables['Categories']!);
    final tagList = ModelParsers.parseTags(tables['Tags']!);
    final preferenceList = ModelParsers.parseDisplayPreferences(
      tables['DisplayPreferences']!,
    );
    final templateList = ModelParsers.parseTransactionTemplates(
      tables['TransactionTemplates']!,
      accounts: accounts,
      currencies: currencies,
    );
    final synchronizedPreferences = synchronizeDisplayPreferences(
      existing: preferenceList,
      accountIds: accounts.keys.toSet(),
      categoryIds: categoryList.map((item) => item.id).toSet(),
      tagIds: tagList.map((item) => item.id).toSet(),
    );
    return AppDataSnapshot(
      accounts: accountList,
      categories: categoryList,
      currencies: currencyList,
      tags: tagList,
      transactions: const [],
      exchangeRates: const [],
      dailyAccountBalances: const [],
      dailyNetWorth: const [],
      dailyManualValuations: const [],
      displayPreferences: synchronizedPreferences.preferences,
      transactionTemplates: templateList,
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'data_source': dataSource,
    'tables': tables,
  };

  factory FormSnapshot.fromJson(Map<String, dynamic> json) {
    final rawTables = json['tables'];
    if (rawTables is! Map) {
      throw const FormatException('The form snapshot tables are not an object.');
    }
    final schemaVersion = json['schema_version'];
    final savedAt = json['saved_at'];
    final dataSource = json['data_source'];
    if (schemaVersion is! int || savedAt is! String || dataSource is! String) {
      throw const FormatException('The form snapshot metadata is invalid.');
    }
    final tables = <String, String>{};
    for (final entry in rawTables.entries) {
      if (!formSnapshotTableNames.contains(entry.key.toString()) ||
          entry.value is! String) {
        throw const FormatException('The form snapshot contains invalid tables.');
      }
      tables[entry.key.toString()] = entry.value as String;
    }
    if (!formSnapshotTableNames.every(tables.containsKey)) {
      throw const FormatException('The form snapshot is missing required tables.');
    }
    return FormSnapshot(
      schemaVersion: schemaVersion,
      savedAt: DateTime.parse(savedAt).toUtc(),
      dataSource: dataSource,
      tables: Map.unmodifiable(tables),
    );
  }
}

abstract interface class FormSnapshotStore {
  Future<FormSnapshot?> read();

  Future<void> write(FormSnapshot snapshot);

  Future<void> clear();
}

class SharedPreferencesFormSnapshotStore implements FormSnapshotStore {
  SharedPreferencesFormSnapshotStore({this.preferences});

  static const storageKey = 'accountable.form_snapshot.v1';
  final SharedPreferencesAsync? preferences;

  SharedPreferencesAsync get _preferences => preferences ?? SharedPreferencesAsync();

  @override
  Future<FormSnapshot?> read() async {
    try {
      final encoded = await _preferences.getString(storageKey);
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('The form snapshot is not an object.');
      }
      return FormSnapshot.fromJson(decoded.cast<String, dynamic>());
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> write(FormSnapshot snapshot) async {
    try {
      await _preferences.setString(storageKey, jsonEncode(snapshot.toJson()));
    } on StateError {
      // Browser storage is unavailable in Flutter's non-browser test VM.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _preferences.remove(storageKey);
    } on StateError {
      // Browser storage is unavailable in Flutter's non-browser test VM.
    }
  }
}

class MemoryFormSnapshotStore implements FormSnapshotStore {
  FormSnapshot? _snapshot;

  MemoryFormSnapshotStore([FormSnapshot? initialSnapshot])
    : _snapshot = initialSnapshot;

  @override
  Future<FormSnapshot?> read() async => _snapshot;

  @override
  Future<void> write(FormSnapshot snapshot) async => _snapshot = snapshot;

  @override
  Future<void> clear() async => _snapshot = null;
}
