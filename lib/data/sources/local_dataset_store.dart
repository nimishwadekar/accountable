import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LocalDatasetStore {
  Future<Map<String, String>?> read();

  Future<void> write(Map<String, String> tables);
}

class SharedPreferencesLocalDatasetStore implements LocalDatasetStore {
  SharedPreferencesLocalDatasetStore({this._preferences});

  static const _storageKey = 'accountable.local_dataset';
  final SharedPreferencesAsync? _preferences;

  @override
  Future<Map<String, String>?> read() async {
    try {
      final preferences = _preferences ?? SharedPreferencesAsync();
      final encoded = await preferences.getString(_storageKey);
      if (encoded == null) return null;

      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException(
          'The stored local dataset is not an object.',
        );
      }

      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } on StateError {
      // The Flutter test VM has no browser storage platform. Use assets there.
      return null;
    }
  }

  @override
  Future<void> write(Map<String, String> tables) async {
    try {
      final preferences = _preferences ?? SharedPreferencesAsync();
      await preferences.setString(_storageKey, jsonEncode(tables));
    } on StateError {
      // Persistence is available in Chrome; tests without a storage platform
      // remain an in-memory asset-backed data source.
    }
  }
}

class MemoryLocalDatasetStore implements LocalDatasetStore {
  MemoryLocalDatasetStore([Map<String, String>? initialTables])
    : _tables = initialTables == null ? null : Map.of(initialTables);

  Map<String, String>? _tables;

  @override
  Future<Map<String, String>?> read() async {
    final tables = _tables;
    return tables == null ? null : Map.unmodifiable(tables);
  }

  @override
  Future<void> write(Map<String, String> tables) async {
    _tables = Map.of(tables);
  }
}
