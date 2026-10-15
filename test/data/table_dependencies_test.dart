import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('current table dependency graph is acyclic', () {
    expect(hasCircularTableDependency(tableDependencies), isFalse);
  });

  test('cycle detection catches future circular dependencies', () {
    expect(
      hasCircularTableDependency({
        'A': ['B'],
        'B': ['C'],
        'C': ['A'],
      }),
      isTrue,
    );
  });
}
