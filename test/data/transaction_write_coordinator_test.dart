import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('serializes concurrent same-origin write operations', () async {
    const coordinator = TransactionWriteCoordinator();
    final releaseFirst = Completer<void>();
    final order = <String>[];

    final first = coordinator.run(() async {
      order.add('first-start');
      await releaseFirst.future;
      order.add('first-end');
    });
    final second = coordinator.run(() async {
      order.add('second-start');
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, ['first-start']);
    releaseFirst.complete();
    await Future.wait([first, second]);

    expect(order, ['first-start', 'first-end', 'second-start']);
  });

  test('preserves the original write failure', () async {
    const coordinator = TransactionWriteCoordinator();
    final failure = StateError('write failed after append');

    await expectLater(
      coordinator.run<void>(() async => throw failure),
      throwsA(same(failure)),
    );
  });
}
