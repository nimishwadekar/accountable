import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_form.dart';

void main() {
  test('generates a 12-character base62 ID', () {
    final id = generateTransactionId(const [], random: Random(1));

    expect(id, hasLength(12));
    expect(id, matches(RegExp(r'^[0-9A-Za-z]{12}$')));
  });

  test('regenerates when the candidate already exists', () {
    final random = _SequenceRandom([...List.filled(23, 0), 1]);
    final first = '0' * 12;
    final second = '0' * 11 + '1';

    final id = generateTransactionId([first], random: random);

    expect(id, second);
  });
}

class _SequenceRandom implements Random {
  _SequenceRandom(this.values);

  final List<int> values;
  var _index = 0;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(1000) / 1000;

  @override
  int nextInt(int max) => values[_index++ % values.length] % max;
}
