import '../models/models.dart';

const displayPreferenceBases = <String, int>{
  'account': 1001,
  'category': 2000,
  'tag': 3000,
};

class DisplayPreferenceSyncResult {
  const DisplayPreferenceSyncResult({
    required this.preferences,
    required this.missing,
  });

  final List<DisplayPreference> preferences;
  final List<DisplayPreference> missing;
}

DisplayPreferenceSyncResult synchronizeDisplayPreferences({
  required List<DisplayPreference> existing,
  required Set<String> accountIds,
  required Set<String> categoryIds,
  required Set<String> tagIds,
}) {
  final knownIds = <String, Set<String>>{
    'account': accountIds,
    'category': categoryIds,
    'tag': tagIds,
  };
  final keys = <String>{};
  final ordersByType = <String, Set<int>>{};
  for (final preference in existing) {
    final key = '${preference.entityType}:${preference.entityId}';
    if (!keys.add(key)) {
      throw FormatException('Duplicate DisplayPreferences row for $key.');
    }
    final ids = knownIds[preference.entityType];
    if (ids == null) {
      throw FormatException(
        'Unsupported entity_type: ${preference.entityType}.',
      );
    }
    if (!ids.contains(preference.entityId)) {
      throw FormatException(
        'DisplayPreferences references unknown ${preference.entityType}: '
        '${preference.entityId}.',
      );
    }
    if (!preference.showInApp && preference.showInEntryForms) {
      throw FormatException(
        'show_in_entry_forms cannot be TRUE when show_in_app is FALSE for $key.',
      );
    }
    final minimumOrder = displayPreferenceBases[preference.entityType]!;
    if (preference.displayOrder < minimumOrder) {
      throw FormatException(
        'display_order ${preference.displayOrder} is outside the '
        '${preference.entityType} range.',
      );
    }
    final orders = ordersByType.putIfAbsent(
      preference.entityType,
      () => <int>{},
    );
    if (!orders.add(preference.displayOrder)) {
      throw FormatException(
        'Duplicate display_order ${preference.displayOrder} for '
        '${preference.entityType}.',
      );
    }
  }

  final normalized = [...existing];
  final missing = <DisplayPreference>[];
  for (final entry in knownIds.entries) {
    var nextOrder = displayPreferenceBases[entry.key]!;
    final orders = ordersByType[entry.key] ?? const <int>{};
    if (orders.isNotEmpty) {
      nextOrder = (orders.reduce((a, b) => a > b ? a : b) + 1)
          .clamp(nextOrder, 1 << 30)
          .toInt();
    }
    for (final id in entry.value) {
      final key = '${entry.key}:$id';
      if (keys.contains(key)) continue;
      final preference = DisplayPreference(
        entityType: entry.key,
        entityId: id,
        displayOrder: nextOrder++,
        showInApp: true,
        showInEntryForms: true,
      );
      keys.add(key);
      missing.add(preference);
      normalized.add(preference);
    }
  }
  return DisplayPreferenceSyncResult(preferences: normalized, missing: missing);
}
