const transactionsHeaders = <String>[
  'transaction_id',
  'date',
  'description',
  'category',
  'transaction_type',
  'source_amount',
  'source_account_id',
  'dest_amount',
  'dest_account_id',
  'tag',
  'created_at',
];

class RuntimeTableSchema {
  const RuntimeTableSchema({
    required this.name,
    required this.headers,
    required this.range,
    this.numericColumns = const {},
    this.booleanColumns = const {},
  });

  final String name;
  final List<String> headers;
  final String range;
  final Set<int> numericColumns;
  final Set<int> booleanColumns;

  String get assetPath => 'test_sheets/$name.csv';
  int get columnCount => headers.length;
}

abstract final class RuntimeTableSchemas {
  static const currencies = RuntimeTableSchema(
    name: 'Currencies',
    headers: ['currency_id', 'currency_symbol', 'decimal_places'],
    range: 'Currencies!A:C',
    numericColumns: {2},
  );
  static const accounts = RuntimeTableSchema(
    name: 'Accounts',
    headers: [
      'account_id',
      'name',
      'account_type',
      'currency',
      'opening_balance',
      'opening_date',
      'closing_date',
      'uses_manual_valuations',
    ],
    range: 'Accounts!A:H',
    numericColumns: {4},
  );
  static const categories = RuntimeTableSchema(
    name: 'Categories',
    headers: ['category_id', 'category_name', 'allowed_transaction_types'],
    range: 'Categories!A:C',
  );
  static const tags = RuntimeTableSchema(
    name: 'Tags',
    headers: ['tag_id', 'tag_name'],
    range: 'Tags!A:B',
  );
  static const transactions = RuntimeTableSchema(
    name: 'Transactions',
    headers: transactionsHeaders,
    range: 'Transactions!A:K',
    numericColumns: {5, 7},
  );
  static const dailyExchangeRates = RuntimeTableSchema(
    name: 'DailyExchangeRates',
    headers: [
      'rate_id',
      'rate_date',
      'currency',
      'rate_to_usd',
      'source_rate_date',
      'retrieved_at',
    ],
    range: 'DailyExchangeRates!A:F',
    numericColumns: {3},
  );
  static const dailyAccountBalances = RuntimeTableSchema(
    name: 'DailyAccountBalances',
    headers: [
      'balance_id',
      'balance_date',
      'account_id',
      'balance',
      'balance_usd',
      'retrieved_at',
    ],
    range: 'DailyAccountBalances!A:F',
    numericColumns: {3, 4},
  );
  static const dailyNetWorth = RuntimeTableSchema(
    name: 'DailyNetWorth',
    headers: ['net_worth_id', 'net_worth_date', 'amount', 'retrieved_at'],
    range: 'DailyNetWorth!A:D',
    numericColumns: {2},
  );
  static const dailyManualValuations = RuntimeTableSchema(
    name: 'DailyManualValuations',
    headers: ['valuation_id', 'date', 'account_id', 'value'],
    range: 'DailyManualValuations!A:D',
    numericColumns: {3},
  );
  static const displayPreferences = RuntimeTableSchema(
    name: 'DisplayPreferences',
    headers: [
      'entity_type',
      'entity_id',
      'display_order',
      'show_in_app',
      'show_in_entry_forms',
    ],
    range: 'DisplayPreferences!A:E',
    numericColumns: {2},
    booleanColumns: {3, 4},
  );
  static const transactionTemplates = RuntimeTableSchema(
    name: 'TransactionTemplates',
    headers: [
      'template_id',
      'name',
      'transaction_type',
      'date',
      'description',
      'category',
      'tag',
      'source_account_id',
      'source_amount',
      'dest_account_id',
      'dest_amount',
      'created_at',
      'updated_at',
    ],
    range: 'TransactionTemplates!A:M',
    numericColumns: {8, 10},
  );
  static const transactionsToMigrate = RuntimeTableSchema(
    name: 'TransactionsToMigrate',
    headers: transactionsHeaders,
    range: 'TransactionsToMigrate!A:K',
    numericColumns: {5, 7},
  );
  static const incomeAllocations = RuntimeTableSchema(
    name: 'IncomeAllocations',
    headers: [
      'allocation_id',
      'name',
      'income_category_id',
      'income_account_id',
      'transfer_category_id',
      'expected_amount_per_income',
      'start_date',
      'end_date',
      'created_at',
      'updated_at',
    ],
    range: 'IncomeAllocations!A:J',
    numericColumns: {6},
  );

  static const all = [
    currencies,
    accounts,
    categories,
    tags,
    transactions,
    dailyExchangeRates,
    dailyAccountBalances,
    dailyNetWorth,
    dailyManualValuations,
    transactionsToMigrate,
    displayPreferences,
    transactionTemplates,
    incomeAllocations,
  ];

  static RuntimeTableSchema byName(String name) => all.firstWhere(
    (schema) => schema.name == name,
    orElse: () => throw ArgumentError('Unknown runtime table: $name.'),
  );

  static RuntimeTableSchema byRange(String range) => all.firstWhere(
    (schema) => schema.range == range,
    orElse: () => throw ArgumentError('Unknown runtime range: $range.'),
  );
}
