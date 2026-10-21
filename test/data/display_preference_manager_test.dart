import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('adds missing preferences at the end of each entity range', () {
    final result = synchronizeDisplayPreferences(
      existing: const [
        DisplayPreference(
          entityType: 'account',
          entityId: 'checking',
          displayOrder: 1001,
          showInApp: true,
          showInEntryForms: true,
        ),
      ],
      accountIds: {'checking', 'savings'},
      categoryIds: {'groceries'},
      tagIds: {'home'},
    );

    expect(result.missing.map((item) => item.entityId), [
      'savings',
      'groceries',
      'home',
    ]);
    expect(result.preferences.last.displayOrder, 3000);
    expect(result.missing.first.displayOrder, 1002);
  });

  test('rejects duplicate keys, unknown IDs, duplicate orders, and invalid visibility', () {
    DisplayPreference preference({
      String entityId = 'checking',
      int order = 1001,
      bool showInApp = true,
      bool showInEntryForms = true,
    }) => DisplayPreference(
      entityType: 'account',
      entityId: entityId,
      displayOrder: order,
      showInApp: showInApp,
      showInEntryForms: showInEntryForms,
    );

    expect(
      () => synchronizeDisplayPreferences(
        existing: [preference(), preference()],
        accountIds: {'checking'},
        categoryIds: {},
        tagIds: {},
      ),
      throwsFormatException,
    );
    expect(
      () => synchronizeDisplayPreferences(
        existing: [preference(entityId: 'missing')],
        accountIds: {'checking'},
        categoryIds: {},
        tagIds: {},
      ),
      throwsFormatException,
    );
    expect(
      () => synchronizeDisplayPreferences(
        existing: [
          preference(),
          preference(entityId: 'other'),
        ],
        accountIds: {'checking', 'other'},
        categoryIds: {},
        tagIds: {},
      ),
      throwsFormatException,
    );
    expect(
      () => synchronizeDisplayPreferences(
        existing: [preference(showInApp: false)],
        accountIds: {'checking'},
        categoryIds: {},
        tagIds: {},
      ),
      throwsFormatException,
    );
  });

  test('copies individual display preference fields', () {
    const preference = DisplayPreference(
      entityType: 'tag',
      entityId: 'home',
      displayOrder: 3000,
      showInApp: true,
      showInEntryForms: true,
    );
    final copy = preference.copyWith(
      displayOrder: 3001,
      showInApp: false,
    );

    expect(copy.entityType, 'tag');
    expect(copy.entityId, 'home');
    expect(copy.displayOrder, 3001);
    expect(copy.showInApp, isFalse);
    expect(copy.showInEntryForms, isTrue);
  });
}
