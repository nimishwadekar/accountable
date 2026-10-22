import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/transaction.dart';
import '../models/money.dart';

/// The lifecycle state of a locally persisted transaction batch.
enum TransactionOutboxStatus {
  pending,
  uploading,
  uncertain,
  failed,

  ;

  String get wireValue => name;

  static TransactionOutboxStatus parse(String value) => values.firstWhere(
    (status) => status.wireValue == value,
    orElse: () => throw FormatException('Unknown outbox status: $value.'),
  );
}

class PendingTransaction {
  const PendingTransaction({
    required this.transaction,
    required this.batchId,
    required this.createdAt,
    this.status = TransactionOutboxStatus.pending,
    this.lastError,
  });

  final Transaction transaction;
  final String batchId;
  final DateTime createdAt;
  final TransactionOutboxStatus status;
  final String? lastError;

  PendingTransaction copyWith({
    Transaction? transaction,
    String? batchId,
    DateTime? createdAt,
    TransactionOutboxStatus? status,
    String? lastError,
    bool clearLastError = false,
  }) => PendingTransaction(
    transaction: transaction ?? this.transaction,
    batchId: batchId ?? this.batchId,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
    lastError: clearLastError ? null : (lastError ?? this.lastError),
  );

  Map<String, dynamic> toJson() => {
    'transaction': _transactionToJson(transaction),
    'batch_id': batchId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'status': status.wireValue,
    'last_error': lastError,
  };

  factory PendingTransaction.fromJson(Map<String, dynamic> json) {
    final transaction = json['transaction'];
    if (transaction is! Map ||
        json['batch_id'] is! String ||
        json['created_at'] is! String ||
        json['status'] is! String ||
        (json['last_error'] != null && json['last_error'] is! String)) {
      throw const FormatException('The pending transaction is invalid.');
    }
    return PendingTransaction(
      transaction: _transactionFromJson(transaction.cast<String, dynamic>()),
      batchId: json['batch_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      status: TransactionOutboxStatus.parse(json['status'] as String),
      lastError: json['last_error'] as String?,
    );
  }
}

abstract interface class TransactionOutboxStore {
  Future<List<PendingTransaction>> read();

  Future<void> enqueueBatch({required String batchId, required List<Transaction> transactions});

  Future<void> updateBatch(
    String batchId,
    TransactionOutboxStatus status, {
    String? lastError,
  });

  Future<void> removeBatch(String batchId);
}

class SharedPreferencesTransactionOutboxStore implements TransactionOutboxStore {
  SharedPreferencesTransactionOutboxStore({this.preferences});

  static const storageKey = 'accountable.transaction_outbox.v1';
  final SharedPreferencesAsync? preferences;

  SharedPreferencesAsync get _preferences => preferences ?? SharedPreferencesAsync();

  @override
  Future<List<PendingTransaction>> read() async {
    try {
      final encoded = await _preferences.getString(storageKey);
      if (encoded == null) return const [];
      final decoded = jsonDecode(encoded);
      if (decoded is! List) {
        throw const FormatException('The transaction outbox is not an array.');
      }
      return [
        for (final item in decoded)
          PendingTransaction.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } on StateError {
      return const [];
    }
  }

  @override
  Future<void> enqueueBatch({required String batchId, required List<Transaction> transactions}) async {
    if (batchId.trim().isEmpty) throw ArgumentError.value(batchId, 'batchId');
    if (transactions.isEmpty) throw ArgumentError('A batch cannot be empty.');
    final current = await read();
    if (current.any((item) => item.batchId == batchId)) {
      throw StateError('Outbox batch $batchId already exists.');
    }
    await _write([
      ...current,
      for (final transaction in transactions)
        PendingTransaction(
          transaction: transaction,
          batchId: batchId,
          createdAt: DateTime.now().toUtc(),
        ),
    ]);
  }

  @override
  Future<void> updateBatch(
    String batchId,
    TransactionOutboxStatus status, {
    String? lastError,
  }) async {
    final current = await read();
    if (!current.any((item) => item.batchId == batchId)) {
      throw StateError('Outbox batch $batchId does not exist.');
    }
    await _write([
      for (final item in current)
        item.batchId == batchId
            ? item.copyWith(
                status: status,
                lastError: lastError,
                clearLastError: lastError == null,
              )
            : item,
    ]);
  }

  @override
  Future<void> removeBatch(String batchId) async {
    final current = await read();
    await _write(current.where((item) => item.batchId != batchId).toList());
  }

  Future<void> _write(List<PendingTransaction> entries) async {
    try {
      await _preferences.setString(
        storageKey,
        jsonEncode([for (final entry in entries) entry.toJson()]),
      );
    } on StateError {
      // Browser storage is unavailable in Flutter's non-browser test VM.
    }
  }
}

class MemoryTransactionOutboxStore implements TransactionOutboxStore {
  final List<PendingTransaction> _entries = [];

  @override
  Future<List<PendingTransaction>> read() async => List.unmodifiable(_entries);

  @override
  Future<void> enqueueBatch({
    required String batchId,
    required List<Transaction> transactions,
  }) async {
    if (batchId.trim().isEmpty) throw ArgumentError.value(batchId, 'batchId');
    if (transactions.isEmpty) throw ArgumentError('A batch cannot be empty.');
    if (_entries.any((item) => item.batchId == batchId)) {
      throw StateError('Outbox batch $batchId already exists.');
    }
    _entries.addAll([
      for (final transaction in transactions)
        PendingTransaction(
          transaction: transaction,
          batchId: batchId,
          createdAt: DateTime.now().toUtc(),
        ),
    ]);
  }

  @override
  Future<void> updateBatch(
    String batchId,
    TransactionOutboxStatus status, {
    String? lastError,
  }) async {
    var found = false;
    for (var index = 0; index < _entries.length; index++) {
      if (_entries[index].batchId == batchId) {
        found = true;
        _entries[index] = _entries[index].copyWith(
          status: status,
          lastError: lastError,
          clearLastError: lastError == null,
        );
      }
    }
    if (!found) {
      throw StateError('Outbox batch $batchId does not exist.');
    }
  }

  @override
  Future<void> removeBatch(String batchId) async =>
      _entries.removeWhere((item) => item.batchId == batchId);
}

Map<String, dynamic> _transactionToJson(Transaction transaction) => {
  'id': transaction.id,
  'created_at': transaction.createdAt.toUtc().toIso8601String(),
  'date': transaction.date.toUtc().toIso8601String(),
  'type': transaction.type.wireValue,
  'source_amount': _moneyToJson(transaction.sourceAmount),
  'source_account_id': transaction.sourceAccountId,
  'destination_amount': _moneyToJson(transaction.destinationAmount),
  'destination_account_id': transaction.destinationAccountId,
  'category_id': transaction.categoryId,
  'tag_id': transaction.tagId,
  'description': transaction.description,
};

Transaction _transactionFromJson(Map<String, dynamic> json) => Transaction(
  id: json['id'] as String,
  createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
  date: DateTime.parse(json['date'] as String).toUtc(),
  type: TransactionTypeWireValue.parse(json['type'] as String),
  sourceAmount: _moneyFromJson(json['source_amount']),
  sourceAccountId: json['source_account_id'] as String?,
  destinationAmount: _moneyFromJson(json['destination_amount']),
  destinationAccountId: json['destination_account_id'] as String?,
  categoryId: json['category_id'] as String?,
  tagId: json['tag_id'] as String?,
  description: json['description'] as String,
);

Map<String, dynamic>? _moneyToJson(Money? money) => money == null
    ? null
    : {'minor_units': money.minorUnits, 'currency_id': money.currencyId};

Money? _moneyFromJson(Object? value) {
  if (value == null) return null;
  if (value is! Map || value['minor_units'] is! int || value['currency_id'] is! String) {
    throw const FormatException('The money value is invalid.');
  }
  return Money(
    minorUnits: value['minor_units'] as int,
    currencyId: value['currency_id'] as String,
  );
}
