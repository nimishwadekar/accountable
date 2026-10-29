import 'dart:math';

import 'package:csv/csv.dart';

import '../app_data_snapshot.dart';
import '../csv/csv.dart';
import '../models/models.dart';
import '../net_worth_achievement_calculator.dart';
import '../sources/google_sheets_api.dart';
import '../table_schema.dart';
import 'data_load_exception.dart';
import 'display_preference_manager.dart';
import 'data_validation_failure.dart';
import 'transaction_write_validator.dart';
import 'manual_valuation_write_validator.dart';
import 'migration_transactions.dart';
import 'table_dependencies.dart';
import 'repositories.dart';

const _migrationIdAlphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

abstract final class GoogleSheetsRanges {
  static final accounts = RuntimeTableSchemas.accounts.range;
  static final categories = RuntimeTableSchemas.categories.range;
  static final currencies = RuntimeTableSchemas.currencies.range;
  static final dailyAccountBalances =
      RuntimeTableSchemas.dailyAccountBalances.range;
  static final dailyExchangeRates =
      RuntimeTableSchemas.dailyExchangeRates.range;
  static final dailyNetWorth = RuntimeTableSchemas.dailyNetWorth.range;
  static final dailyManualValuations =
      RuntimeTableSchemas.dailyManualValuations.range;
  static final displayPreferences =
      RuntimeTableSchemas.displayPreferences.range;
  static final tags = RuntimeTableSchemas.tags.range;
  static final transactions = RuntimeTableSchemas.transactions.range;
  static final transactionTemplates =
      RuntimeTableSchemas.transactionTemplates.range;
  static final incomeAllocations = RuntimeTableSchemas.incomeAllocations.range;
  static final achievements = RuntimeTableSchemas.achievements.range;
  static final achievementSettings =
      RuntimeTableSchemas.achievementSettings.range;
  static final transactionsToMigrate =
      RuntimeTableSchemas.transactionsToMigrate.range;
}

class GoogleSheetsAppDataRepository implements AppDataRepository {
  GoogleSheetsAppDataRepository(this.api, {this.migrationAssistance = false});

  final SheetsTableClient api;
  final bool migrationAssistance;
  AppDataSnapshot? _cachedSnapshot;

  @override
  Future<AppDataSnapshot> load() async {
    return _cachedSnapshot ??= await _loadFreshSnapshot();
  }

  @override
  Future<AppDataSnapshot> reload() async {
    final snapshot = await _loadFreshSnapshot();
    _cachedSnapshot = snapshot;
    return snapshot;
  }

  @override
  Future<AppDataSnapshot> addManualValuation(DailyManualValuation valuation) =>
      addManualValuations([valuation]);

  @override
  Future<AppDataSnapshot> addManualValuations(
    List<DailyManualValuation> valuations,
  ) async {
    final current = await load();
    final validationErrors = validateManualValuationsForWrite(
      valuations,
      current,
    );
    if (validationErrors.isNotEmpty) {
      throw StateError(validationErrors.join(' '));
    }
    await api.appendRows(GoogleSheetsRanges.dailyManualValuations, [
      for (final valuation in valuations)
        [
          valuation.id,
          _dateString(valuation.date),
          valuation.accountId,
          valuation.value.toMajorUnitsString(
            current.currenciesById[valuation.value.currencyId]!,
          ),
        ],
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> saveDisplayPreferences(
    List<DisplayPreference> preferences,
  ) async {
    final current = await load();
    final normalized = synchronizeDisplayPreferences(
      existing: preferences,
      accountIds: current.accounts.map((item) => item.id).toSet(),
      categoryIds: current.categories.map((item) => item.id).toSet(),
      tagIds: current.tags.map((item) => item.id).toSet(),
    );
    if (normalized.missing.isNotEmpty) {
      throw StateError('Display preferences must include every entity.');
    }
    await api.replaceRange(GoogleSheetsRanges.displayPreferences, [
      RuntimeTableSchemas.displayPreferences.headers,
      for (final preference in normalized.preferences)
        _displayPreferenceRow(preference),
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> addIncomeAllocation(
    IncomeAllocation allocation,
  ) async {
    final current = await load();
    final incomeAccount = current.accountsById[allocation.incomeAccountId];
    final incomeCategory = current.categoriesById[allocation.incomeCategoryId];
    final transferCategory =
        current.categoriesById[allocation.transferCategoryId];
    if (incomeAccount == null ||
        incomeCategory == null ||
        !incomeCategory.allowedTransactionTypes.contains(
          TransactionType.income,
        ) ||
        transferCategory == null ||
        !transferCategory.allowedTransactionTypes.contains(
          TransactionType.transfer,
        )) {
      throw StateError(
        'Income allocation references invalid categories or account.',
      );
    }
    if (current.incomeAllocations.any(
      (item) =>
          item.incomeCategoryId == allocation.incomeCategoryId &&
          item.incomeAccountId == allocation.incomeAccountId &&
          item.transferCategoryId == allocation.transferCategoryId,
    )) {
      throw StateError(
        'An allocation with this category and income account already exists.',
      );
    }
    await api.appendRow(
      GoogleSheetsRanges.incomeAllocations,
      _incomeAllocationRow(
        allocation,
        current.accountsById,
        current.currenciesById,
      ),
    );
    return reload();
  }

  @override
  Future<AppDataSnapshot> addTransactionTemplate(
    TransactionTemplate template,
  ) async {
    final current = await load();
    _validateTemplateName(template, current.transactionTemplates);
    await api.appendRow(
      GoogleSheetsRanges.transactionTemplates,
      _transactionTemplateRow(
        template,
        accounts: (await load()).accountsById,
        currencies: (await load()).currenciesById,
      ),
    );
    return reload();
  }

  @override
  Future<AppDataSnapshot> updateTransactionTemplate(
    TransactionTemplate template,
  ) async {
    final current = await load();
    if (!current.transactionTemplates.any((item) => item.id == template.id)) {
      throw StateError('Template ${template.id} does not exist.');
    }
    _validateTemplateName(template, current.transactionTemplates);
    final templates = [
      for (final item in current.transactionTemplates)
        item.id == template.id ? template : item,
    ];
    await api.replaceRange(GoogleSheetsRanges.transactionTemplates, [
      RuntimeTableSchemas.transactionTemplates.headers,
      for (final item in templates)
        _transactionTemplateRow(
          item,
          accounts: current.accountsById,
          currencies: current.currenciesById,
        ),
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> deleteTransactionTemplate(String templateId) async {
    final current = await load();
    if (!current.transactionTemplates.any((item) => item.id == templateId)) {
      throw StateError('Template $templateId does not exist.');
    }
    final templates = current.transactionTemplates
        .where((item) => item.id != templateId)
        .toList();
    await api.replaceRange(GoogleSheetsRanges.transactionTemplates, [
      RuntimeTableSchemas.transactionTemplates.headers,
      for (final item in templates)
        _transactionTemplateRow(
          item,
          accounts: current.accountsById,
          currencies: current.currenciesById,
        ),
    ]);
    return reload();
  }

  @override
  Future<AppDataSnapshot> updateAchievementEarned(
    String achievementId, {
    required bool earned,
  }) async {
    final current = await load();
    final achievement = current.achievementsById[achievementId];
    if (achievement == null) {
      throw StateError('Achievement $achievementId does not exist.');
    }
    if (achievement.earned == earned) return current;
    final updatedAchievements = [
      for (final item in current.achievements)
        item.id == achievementId ? item.copyWith(earned: earned) : item,
    ];
    await api.replaceRange(GoogleSheetsRanges.achievements, [
      RuntimeTableSchemas.achievements.headers,
      for (final item in updatedAchievements)
        _achievementRow(item, current.currenciesById['USD']!),
    ]);
    _cachedSnapshot = current.withAchievementEarned(achievementId, earned);
    return _cachedSnapshot!;
  }

  @override
  Future<AppDataSnapshot> addTransaction(Transaction transaction) =>
      addTransactions([transaction]);

  @override
  Future<AppDataSnapshot> addTransactions(
    List<Transaction> transactions,
  ) async {
    final current = await load();
    final validationErrors = validateTransactionsForWrite(
      transactions,
      current,
    );
    if (validationErrors.isNotEmpty) {
      throw StateError(validationErrors.join(' '));
    }
    final accountCurrencies = {
      for (final account in current.accounts) account.id: account.currencyId,
    };
    await api.appendRows(GoogleSheetsRanges.transactions, [
      for (final transaction in transactions)
        RuntimeTableSchemas.transactions.headers
            .map(
              (header) =>
                  transactionToRow(
                    transaction,
                    current.currenciesById,
                    accountCurrencies,
                  )[header] ??
                  '',
            )
            .toList(),
    ]);
    // The append succeeded; don't make that success depend on a second Sheets
    // read. AppShell reconciles derived history and reloads after the write.
    // Returning the updated snapshot also avoids reporting a false write
    // failure if the follow-up read fails after the transaction was persisted.
    final updated = current.withAdditionalTransactions(transactions);
    _cachedSnapshot = updated;
    return updated;
  }

  Future<MigrationBatchStatus> finalizeMigrationTransactions({
    DateTime? now,
    Random? random,
  }) async {
    _requireMigrationAssistance();
    final current = await reload();
    final migrations = current.transactionsToMigrate;
    if (migrations.isEmpty) {
      throw StateError('There are no transactions to finalize.');
    }
    if (migrations.length > maximumMigrationTransactionCount) {
      throw StateError(
        'Cannot finalize ${migrations.length} transactions. The maximum is '
        '$maximumMigrationTransactionCount.',
      );
    }

    final status = MigrationBatchStatus.fromSnapshot(current);
    if (status.isFinalized) return status;

    final generator = random ?? Random.secure();
    final existingIds = current.transactionsById.keys.toSet();
    String? token;
    for (var attempt = 0; attempt < 100; attempt++) {
      final candidate = List.generate(
        6,
        (_) =>
            _migrationIdAlphabet[generator.nextInt(
              _migrationIdAlphabet.length,
            )],
      ).join();
      final collides = List.generate(
        migrations.length,
        (index) => 'MIG$candidate${(index + 1).toString().padLeft(4, '0')}',
      ).any(existingIds.contains);
      if (!collides) {
        token = candidate;
        break;
      }
    }
    if (token == null) {
      throw StateError('Could not generate a unique migration ID batch.');
    }

    final firstCreatedAt = (now ?? DateTime.now()).toUtc();
    final firstSheetRow = 2;
    final lastSheetRow = migrations.length + 1;
    await api.updateRanges({
      '${GoogleSheetsRanges.transactionsToMigrate.split('!').first}!A$firstSheetRow:A$lastSheetRow':
          [
            for (var index = 0; index < migrations.length; index++)
              ['MIG$token${(index + 1).toString().padLeft(4, '0')}'],
          ],
      '${GoogleSheetsRanges.transactionsToMigrate.split('!').first}!K$firstSheetRow:K$lastSheetRow':
          [
            for (var index = 0; index < migrations.length; index++)
              [
                firstCreatedAt
                    .add(Duration(seconds: index * 10))
                    .toIso8601String(),
              ],
          ],
    });

    return MigrationBatchStatus.fromSnapshot(await reload());
  }

  Future<MigrationExecutionResult> migrateTransactionsToMain() async {
    _requireMigrationAssistance();
    final current = await reload();
    final migrations = current.transactionsToMigrate;
    final status = MigrationBatchStatus.fromSnapshot(current);
    if (migrations.isEmpty) {
      throw StateError('There are no transactions to migrate.');
    }
    if (!status.isFinalized) {
      throw StateError(
        'Finalize migration transactions before migrating them.',
      );
    }
    if (status.alreadyMigratedCount == migrations.length) {
      for (final migration in migrations) {
        final existing = current.transactionsById[migration.id]!;
        if (!_sameTransactionData(migration, existing, current)) {
          throw StateError(
            'Migration transaction ${migration.id} already exists in '
            'Transactions with different data.',
          );
        }
      }
      return MigrationExecutionResult(
        transactionCount: migrations.length,
        wasAlreadyMigrated: true,
      );
    }
    if (status.alreadyMigratedCount > 0) {
      throw StateError(
        'Some migration transaction IDs already exist in Transactions. '
        'No rows were added; review the sheet before retrying.',
      );
    }

    await api.insertRowsAndCopyValues(
      sourceSheetName: 'TransactionsToMigrate',
      destinationSheetName: 'Transactions',
      rowCount: migrations.length,
      columnCount: RuntimeTableSchemas.transactions.columnCount,
    );
    _cachedSnapshot = null;
    return MigrationExecutionResult(
      transactionCount: migrations.length,
      wasAlreadyMigrated: false,
    );
  }

  void _requireMigrationAssistance() {
    if (!migrationAssistance) {
      throw StateError('Migration assistance is not enabled.');
    }
  }

  bool _sameTransactionData(
    Transaction expected,
    Transaction actual,
    AppDataSnapshot data,
  ) {
    final accountCurrencies = {
      for (final account in data.accounts) account.id: account.currencyId,
    };
    final expectedRow = transactionToRow(
      expected,
      data.currenciesById,
      accountCurrencies,
    );
    final actualRow = transactionToRow(
      actual,
      data.currenciesById,
      accountCurrencies,
    );
    return expectedRow.keys.every((key) => expectedRow[key] == actualRow[key]);
  }

  static void _validateTemplateName(
    TransactionTemplate template,
    Iterable<TransactionTemplate> existing,
  ) {
    final normalizedName = template.name.trim().toLowerCase();
    if (normalizedName.isEmpty) {
      throw StateError('Template name cannot be empty.');
    }
    if (existing.any(
      (item) =>
          item.id != template.id &&
          item.name.trim().toLowerCase() == normalizedName,
    )) {
      throw StateError('A template with this name already exists.');
    }
  }

  Future<AppDataSnapshot> _loadFreshSnapshot() async {
    try {
      final tables = await _readRuntimeTables();
      final issues = <DataValidationIssue>[];
      final tableHasErrors = <String, bool>{};
      bool dependenciesAreValid(String table) {
        final dependencies = tableDependencies[table] ?? const <String>[];
        return dependencies.every(
          (dependency) => tableHasErrors[dependency] == false,
        );
      }

      void recordIssues(String table, List<DataValidationIssue> tableIssues) {
        tableHasErrors[table] = tableIssues.isNotEmpty;
        issues.addAll(tableIssues);
      }

      List<CurrencyDefinition> currencies = const [];
      List<Account> accounts = const [];
      List<Category> categories = const [];
      List<Tag> tags = const [];
      List<Transaction> transactions = const [];
      List<Transaction> transactionsToMigrate = const [];
      List<ExchangeRate> exchangeRates = const [];
      List<DailyAccountBalance> dailyAccountBalances = const [];
      List<DailyNetWorth> dailyNetWorth = const [];
      List<DailyManualValuation> dailyManualValuations = const [];
      List<DisplayPreference> displayPreferences = const [];
      List<TransactionTemplate> transactionTemplates = const [];
      List<IncomeAllocation> incomeAllocations = const [];
      List<NetWorthAchievement> achievements = const [];
      DateTime? achievementStartDate;

      try {
        final result = ModelParsers.parseCurrenciesWithIssues(
          _encode(tables[GoogleSheetsRanges.currencies]!),
        );
        currencies = result.values;
        recordIssues('Currencies', result.issues);
      } catch (error) {
        final issue = issueFromError('Currencies', error);
        recordIssues('Currencies', [issue]);
      }
      final currencyById = {
        for (final currency in currencies) currency.id: currency,
      };
      if (dependenciesAreValid('Accounts')) {
        try {
          final result = ModelParsers.parseAccountsWithIssues(
            _encode(tables[GoogleSheetsRanges.accounts]!),
            currencyById,
          );
          accounts = result.values;
          recordIssues('Accounts', result.issues);
        } catch (error) {
          recordIssues('Accounts', [issueFromError('Accounts', error)]);
        }
      }
      final accountById = {for (final account in accounts) account.id: account};
      try {
        final result = ModelParsers.parseCategoriesWithIssues(
          _encode(tables[GoogleSheetsRanges.categories]!),
        );
        categories = result.values;
        recordIssues('Categories', result.issues);
      } catch (error) {
        recordIssues('Categories', [issueFromError('Categories', error)]);
      }
      try {
        final result = ModelParsers.parseTagsWithIssues(
          _encode(tables[GoogleSheetsRanges.tags]!),
        );
        tags = result.values;
        recordIssues('Tags', result.issues);
      } catch (error) {
        recordIssues('Tags', [issueFromError('Tags', error)]);
      }
      if (dependenciesAreValid('DisplayPreferences')) {
        try {
          final result = ModelParsers.parseDisplayPreferencesWithIssues(
            _encode(tables[GoogleSheetsRanges.displayPreferences]!),
          );
          if (result.issues.isNotEmpty) {
            recordIssues('DisplayPreferences', result.issues);
          } else {
            final synchronized = synchronizeDisplayPreferences(
              existing: result.values,
              accountIds: accountById.keys.toSet(),
              categoryIds: categories.map((item) => item.id).toSet(),
              tagIds: tags.map((item) => item.id).toSet(),
            );
            displayPreferences = synchronized.preferences;
            if (synchronized.missing.isNotEmpty) {
              await api.appendRows(GoogleSheetsRanges.displayPreferences, [
                for (final preference in synchronized.missing)
                  _displayPreferenceRow(preference),
              ]);
            }
            recordIssues('DisplayPreferences', const []);
          }
        } catch (error) {
          recordIssues('DisplayPreferences', [
            issueFromError('DisplayPreferences', error),
          ]);
        }
      }
      if (dependenciesAreValid('IncomeAllocations')) {
        try {
          incomeAllocations = ModelParsers.parseIncomeAllocations(
            _encode(tables[GoogleSheetsRanges.incomeAllocations]!),
            accounts: accountById,
            currencies: currencyById,
            categories: {
              for (final category in categories) category.id: category,
            },
          );
          recordIssues('IncomeAllocations', const []);
        } catch (error) {
          recordIssues('IncomeAllocations', [
            issueFromError('IncomeAllocations', error),
          ]);
        }
      }
      if (dependenciesAreValid('TransactionTemplates')) {
        try {
          transactionTemplates = ModelParsers.parseTransactionTemplates(
            _encode(tables[GoogleSheetsRanges.transactionTemplates]!),
            accounts: accountById,
            currencies: currencyById,
          );
          recordIssues('TransactionTemplates', const []);
        } catch (error) {
          recordIssues('TransactionTemplates', [
            issueFromError('TransactionTemplates', error),
          ]);
        }
      }
      if (dependenciesAreValid('Transactions')) {
        try {
          final result = ModelParsers.parseTransactionsWithIssues(
            _encode(tables[GoogleSheetsRanges.transactions]!),
            accounts: accountById,
            currencies: currencyById,
            categories: {
              for (final category in categories) category.id: category,
            },
            tags: {for (final tag in tags) tag.id: tag},
          );
          transactions = result.values;
          recordIssues('Transactions', result.issues);
        } catch (error) {
          recordIssues('Transactions', [issueFromError('Transactions', error)]);
        }
      }
      if (migrationAssistance) {
        try {
          final result = ModelParsers.parseMigrationTransactionsWithIssues(
            _encode(tables[GoogleSheetsRanges.transactionsToMigrate]!),
            accounts: accountById,
            currencies: currencyById,
            categories: {
              for (final category in categories) category.id: category,
            },
            tags: {for (final tag in tags) tag.id: tag},
          );
          transactionsToMigrate = result.values;
          recordIssues('TransactionsToMigrate', result.issues);
        } catch (error) {
          recordIssues('TransactionsToMigrate', [
            issueFromError('TransactionsToMigrate', error),
          ]);
        }
      }
      try {
        final result = ModelParsers.parseExchangeRatesWithIssues(
          _encode(tables[GoogleSheetsRanges.dailyExchangeRates]!),
        );
        exchangeRates = result.values;
        recordIssues('DailyExchangeRates', result.issues);
      } catch (error) {
        recordIssues('DailyExchangeRates', [
          issueFromError('DailyExchangeRates', error),
        ]);
      }
      if (dependenciesAreValid('DailyAccountBalances')) {
        try {
          final result = ModelParsers.parseDailyAccountBalancesWithIssues(
            _encode(tables[GoogleSheetsRanges.dailyAccountBalances]!),
            accounts: accountById,
            currencies: currencyById,
          );
          dailyAccountBalances = result.values;
          recordIssues('DailyAccountBalances', result.issues);
        } catch (error) {
          recordIssues('DailyAccountBalances', [
            issueFromError('DailyAccountBalances', error),
          ]);
        }
      }
      if (dependenciesAreValid('DailyNetWorth')) {
        try {
          final result = ModelParsers.parseDailyNetWorthWithIssues(
            _encode(tables[GoogleSheetsRanges.dailyNetWorth]!),
            currencyById,
          );
          dailyNetWorth = result.values;
          recordIssues('DailyNetWorth', result.issues);
        } catch (error) {
          recordIssues('DailyNetWorth', [
            issueFromError('DailyNetWorth', error),
          ]);
        }
      }
      if (dependenciesAreValid('Achievements')) {
        try {
          final result = ModelParsers.parseAchievementsWithIssues(
            _encode(tables[GoogleSheetsRanges.achievements]!),
            currencies: currencyById,
          );
          achievements = result.values;
          recordIssues('Achievements', result.issues);
        } catch (error) {
          recordIssues('Achievements', [issueFromError('Achievements', error)]);
        }
      }
      try {
        achievementStartDate = ModelParsers.parseAchievementSettings(
          _encode(tables[GoogleSheetsRanges.achievementSettings]!),
        ).trackingStartDate;
        recordIssues('AchievementSettings', const []);
      } catch (error) {
        recordIssues('AchievementSettings', [
          issueFromError('AchievementSettings', error),
        ]);
      }
      if (dependenciesAreValid('DailyManualValuations')) {
        try {
          final result = ModelParsers.parseDailyManualValuationsWithIssues(
            _encode(tables[GoogleSheetsRanges.dailyManualValuations]!),
            accounts: accountById,
            currencies: currencyById,
          );
          dailyManualValuations = result.values;
          recordIssues('DailyManualValuations', result.issues);
        } catch (error) {
          recordIssues('DailyManualValuations', [
            issueFromError('DailyManualValuations', error),
          ]);
        }
      }
      if (issues.isNotEmpty) throw DataValidationFailure(issues);

      final snapshot = AppDataSnapshot(
        accounts: accounts,
        categories: categories,
        currencies: currencies,
        tags: tags,
        transactions: transactions,
        transactionsToMigrate: transactionsToMigrate,
        exchangeRates: exchangeRates,
        dailyAccountBalances: dailyAccountBalances,
        dailyNetWorth: dailyNetWorth,
        dailyManualValuations: dailyManualValuations,
        displayPreferences: displayPreferences,
        transactionTemplates: transactionTemplates,
        incomeAllocations: incomeAllocations,
        achievements: achievements,
        achievementStartDate: achievementStartDate,
      );
      final achievementEvaluation = NetWorthAchievementCalculator.evaluate(
        dailyNetWorth: dailyNetWorth,
        trackingStartDate: achievementStartDate!,
        achievements: achievements,
      );
      if (achievementEvaluation.validationErrors.isNotEmpty) {
        throw DataValidationFailure([
          for (final message in achievementEvaluation.validationErrors)
            DataValidationIssue(table: 'Achievements', message: message),
        ]);
      }
      if (achievementEvaluation.earnedFlagsToReset.isEmpty) return snapshot;

      final resetIds = achievementEvaluation.earnedFlagsToReset.toSet();
      final updatedAchievements = [
        for (final achievement in achievements)
          resetIds.contains(achievement.id)
              ? achievement.copyWith(earned: false)
              : achievement,
      ];
      await api.replaceRange(GoogleSheetsRanges.achievements, [
        RuntimeTableSchemas.achievements.headers,
        for (final achievement in updatedAchievements)
          _achievementRow(achievement, currencyById['USD']!),
      ]);
      return snapshot.withAchievements(updatedAchievements);
    } on DataValidationFailure {
      rethrow;
    } catch (error) {
      throw DataLoadException(
        tableName: 'Google Sheets',
        message: error.toString(),
        cause: error,
      );
    }
  }

  Future<Map<String, List<List<String>>>> _readRuntimeTables() async {
    final ranges = [
      GoogleSheetsRanges.accounts,
      GoogleSheetsRanges.categories,
      GoogleSheetsRanges.currencies,
      GoogleSheetsRanges.dailyAccountBalances,
      GoogleSheetsRanges.dailyExchangeRates,
      GoogleSheetsRanges.dailyNetWorth,
      GoogleSheetsRanges.dailyManualValuations,
      GoogleSheetsRanges.displayPreferences,
      GoogleSheetsRanges.transactionTemplates,
      GoogleSheetsRanges.incomeAllocations,
      GoogleSheetsRanges.achievements,
      GoogleSheetsRanges.achievementSettings,
      GoogleSheetsRanges.tags,
      GoogleSheetsRanges.transactions,
      if (migrationAssistance) GoogleSheetsRanges.transactionsToMigrate,
    ];
    final response = await api.batchReadRanges(ranges);
    return {
      for (final range in ranges)
        range: _padRows(
          response[range] ?? const [],
          RuntimeTableSchemas.byRange(range),
        ),
    };
  }

  static List<List<String>> _padRows(
    List<List<String>> rows,
    RuntimeTableSchema schema,
  ) {
    return [
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
        if (rowIndex == 0 && _matchesHeaderPrefix(rows[rowIndex], schema))
          schema.headers
        else
          [
            ...rows[rowIndex],
            for (
              var index = rows[rowIndex].length;
              index < schema.columnCount;
              index++
            )
              '',
          ],
    ];
  }

  static bool _matchesHeaderPrefix(
    List<String> row,
    RuntimeTableSchema schema,
  ) =>
      row.isNotEmpty &&
      row.length <= schema.columnCount &&
      row.asMap().entries.every(
        (entry) =>
            entry.value == schema.headers[entry.key] ||
            (entry.key == schema.columnCount - 1 && entry.value.isEmpty),
      );

  static String _encode(List<List<String>> rows) => csv.encode(rows);

  static List<String> _incomeAllocationRow(
    IncomeAllocation allocation,
    Map<String, Account> accounts,
    Map<String, CurrencyDefinition> currencies,
  ) => [
    allocation.id,
    allocation.name,
    allocation.incomeCategoryId,
    allocation.incomeAccountId,
    allocation.transferCategoryId,
    allocation.expectedAmountPerIncome.toMajorUnitsString(
      currencies[accounts[allocation.incomeAccountId]!.currencyId]!,
    ),
    _dateString(allocation.startDate),
    allocation.endDate == null ? '' : _dateString(allocation.endDate!),
    allocation.createdAt.toUtc().toIso8601String(),
    allocation.updatedAt.toUtc().toIso8601String(),
  ];

  static List<String> _transactionTemplateRow(
    TransactionTemplate template, {
    required Map<String, Account> accounts,
    required Map<String, CurrencyDefinition> currencies,
  }) {
    String amountFor(Money? amount, String? accountId) {
      if (amount == null || accountId == null) return '';
      final account = accounts[accountId];
      if (account == null) {
        throw StateError('Unknown template account: $accountId.');
      }
      return amount.toMajorUnitsString(currencies[account.currencyId]!);
    }

    return [
      template.id,
      template.name,
      template.type.wireValue,
      template.date == null ? '' : _dateString(template.date!),
      template.description ?? '',
      template.categoryId ?? '',
      template.tagId ?? '',
      template.sourceAccountId ?? '',
      amountFor(template.sourceAmount, template.sourceAccountId),
      template.destinationAccountId ?? '',
      amountFor(template.destinationAmount, template.destinationAccountId),
      template.createdAt.toUtc().toIso8601String(),
      template.updatedAt.toUtc().toIso8601String(),
      template.isFavorite.toString().toUpperCase(),
    ];
  }

  static List<String> _achievementRow(
    NetWorthAchievement achievement,
    CurrencyDefinition usd,
  ) => [
    achievement.id,
    achievement.name,
    achievement.target.toMajorUnitsString(usd),
    achievement.earned.toString().toUpperCase(),
  ];

  static List<String> _displayPreferenceRow(DisplayPreference preference) => [
    preference.entityType,
    preference.entityId,
    preference.displayOrder.toString(),
    preference.showInApp.toString().toUpperCase(),
    preference.showInEntryForms.toString().toUpperCase(),
  ];

  static String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
