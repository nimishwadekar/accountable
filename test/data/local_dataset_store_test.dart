import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/data/data.dart';

void main() {
  test('memory dataset store copies values', () async {
    final store = MemoryLocalDatasetStore({'table': 'initial'});
    final first = await store.read();
    expect(first?['table'], 'initial');

    await store.write({'table': 'updated'});
    expect((await store.read())?['table'], 'updated');
  });
}
