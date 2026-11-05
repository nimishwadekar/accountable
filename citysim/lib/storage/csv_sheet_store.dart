import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../content/content_bundle.dart';
import '../world/terrain_provider.dart';
import '../world/world_reducer.dart';
import '../world/world_rules.dart';
import '../world/world_save_store.dart';
import '../world/world_state.dart';
import 'sheet_tables.dart';
import 'world_sheet_codec.dart';

/// Reads raw sheet documents by name (without extension). The bundled
/// test sheets implement this for the CSV data source and for seeding a
/// fresh install; the future Google Sheets store will implement it
/// against the spreadsheet API.
abstract interface class SheetSource {
  /// Returns the sheet's CSV document, or null when it does not exist.
  Future<String?> readSheet(String name);
}

/// Reads the sheets bundled at `assets/test_sheets/<name>.csv`.
class AssetSheetSource implements SheetSource {
  const AssetSheetSource();

  @override
  Future<String?> readSheet(String name) async {
    try {
      return await rootBundle.loadString('assets/test_sheets/$name.csv');
    } catch (_) {
      return null;
    }
  }
}

/// Stores the parcel world as the four CSV sheet documents, persisted in
/// local browser storage until the Google Sheets data source lands. The
/// document format is identical to the real spreadsheet's tabs, so the
/// codec and fixtures carry over unchanged.
class CsvSheetParcelWorldStore implements ParcelWorldStore {
  CsvSheetParcelWorldStore({
    required this.content,
    required this.terrainProvider,
    this.preferences,
    this.seedSource = const AssetSheetSource(),
  });

  static const _keyPrefix = 'citysim.sheets.';

  final ContentBundle content;
  final TerrainProvider terrainProvider;
  final SharedPreferences? preferences;

  /// Consulted when no local save exists yet: a non-empty bundled sheet
  /// set seeds the world (the developer can ship a starting state);
  /// an empty one means a brand-new game.
  final SheetSource seedSource;

  Future<SharedPreferences> get _store async =>
      preferences ?? SharedPreferences.getInstance();

  @override
  Future<ParcelWorldState?> load() async {
    final preferences = await _store;
    final local = await _readLocal(preferences);
    if (local == null) {
      final seeded = await _readSeed();
      if (seeded == null) return null;
      return _build(seeded);
    }
    return _build(local);
  }

  @override
  Future<void> save(ParcelWorldState state) async {
    validateParcelWorldState(state, content, terrainProvider);
    final documents = encodeSheetTables(worldToSheetTables(state));
    final preferences = await _store;
    for (final entry in documents.entries) {
      final saved = await preferences.setString(
        '$_keyPrefix${entry.key}',
        entry.value,
      );
      if (!saved) {
        throw StateError(
          'The browser did not confirm saving the ${entry.key} sheet.',
        );
      }
    }
  }

  Future<SheetTables?> _readLocal(SharedPreferences preferences) async {
    final hasAny = preferences.getKeys().any(
      (key) => key.startsWith(_keyPrefix),
    );
    if (!hasAny) return null;
    return decodeSheetTables(
      userData: preferences.getString('$_keyPrefix$userDataSheetName') ?? '',
      tiles: preferences.getString('$_keyPrefix$tilesSheetName') ?? '',
      ownedParcels:
          preferences.getString('$_keyPrefix$ownedParcelsSheetName') ?? '',
      projects: preferences.getString('$_keyPrefix$projectsSheetName') ?? '',
    );
  }

  Future<SheetTables?> _readSeed() async {
    final tables = decodeSheetTables(
      userData: await seedSource.readSheet(userDataSheetName) ?? '',
      tiles: await seedSource.readSheet(tilesSheetName) ?? '',
      ownedParcels: await seedSource.readSheet(ownedParcelsSheetName) ?? '',
      projects: await seedSource.readSheet(projectsSheetName) ?? '',
    );
    return tables.isEmpty ? null : tables;
  }

  ParcelWorldState _build(SheetTables tables) {
    final state = sheetTablesToWorld(
      tables,
      content: content,
      terrainProvider: terrainProvider,
    );
    // Progression derives from population on every load, so
    // reconciliation is a no-op for consistent tables — it stays as a
    // safety net for hand-edited ones.
    final reconciled = reconcileWorldProgression(state, content);
    validateParcelWorldState(reconciled, content, terrainProvider);
    return reconciled;
  }
}
