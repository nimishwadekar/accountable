import 'package:accountable/app/pages/transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction date ranges include both boundaries', () {
    final range = DateTimeRange(
      start: DateTime(2026, 10, 10),
      end: DateTime(2026, 10, 11),
    );

    expect(isTransactionDateInRange(DateTime.utc(2026, 10, 10), range), isTrue);
    expect(isTransactionDateInRange(DateTime.utc(2026, 10, 11), range), isTrue);
    expect(
      isTransactionDateInRange(DateTime.utc(2026, 10, 12), range),
      isFalse,
    );
  });
}
