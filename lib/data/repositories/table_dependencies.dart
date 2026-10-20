const tableDependencies = <String, List<String>>{
  'Accounts': ['Currencies'],
  'Transactions': ['Accounts', 'Currencies'],
  'DailyAccountBalances': ['Accounts', 'Currencies'],
  'DailyNetWorth': ['Currencies'],
  'DailyManualValuations': ['Accounts', 'Currencies'],
  'DisplayPreferences': ['Accounts', 'Categories', 'Tags'],
  'TransactionTemplates': ['Accounts', 'Categories', 'Tags', 'Currencies'],
};

bool hasCircularTableDependency(Map<String, List<String>> graph) {
  final visiting = <String>{};
  final visited = <String>{};

  bool visit(String table) {
    if (visiting.contains(table)) return true;
    if (!visited.add(table)) return false;
    visiting.add(table);
    for (final dependency in graph[table] ?? const <String>[]) {
      if (visit(dependency)) return true;
    }
    visiting.remove(table);
    return false;
  }

  return graph.keys.any(visit);
}
