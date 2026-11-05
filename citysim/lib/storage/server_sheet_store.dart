import 'dart:convert';

import 'package:http/http.dart' as http;

import '../content/content_bundle.dart';
import '../world/terrain_provider.dart';
import '../world/world_reducer.dart';
import '../world/world_rules.dart';
import '../world/world_save_store.dart';
import '../world/world_state.dart';
import 'sheet_tables.dart';
import 'world_sheet_codec.dart';

/// Reads and writes the four sheet documents over HTTP — the CSV-mode
/// transport to the local editor server, and the seam the Google Sheets
/// store later replaces.
abstract interface class WorldDocumentsApi {
  /// Returns the sheet documents keyed by sheet name, or null when no
  /// world exists yet.
  Future<Map<String, String>?> fetchDocuments();

  Future<void> putDocuments(Map<String, String> documents);
}

class HttpWorldDocumentsApi implements WorldDocumentsApi {
  const HttpWorldDocumentsApi(this.baseUrl);

  final String baseUrl;

  @override
  Future<Map<String, String>?> fetchDocuments() async {
    final response = await http.get(Uri.parse('$baseUrl/api/world'));
    if (response.statusCode != 200) {
      throw StateError(
        'The game server rejected loading the world '
        '(HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('The world response is not an object.');
    }
    final documents = <String, String>{};
    for (final entry in decoded.entries) {
      if (entry.value is String) documents['${entry.key}'] = entry.value;
    }
    return documents;
  }

  @override
  Future<void> putDocuments(Map<String, String> documents) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/world'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(documents),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'The game server rejected saving the world '
        '(HTTP ${response.statusCode}).',
      );
    }
  }
}

/// Stores the parcel world as the four sheet documents held by the game
/// server: the world lives in memory, every save writes the documents
/// through, and `assets/test_sheets/` on the server's disk is the save —
/// loading from an empty document set starts a fresh world.
class ServerSheetParcelWorldStore implements ParcelWorldStore {
  ServerSheetParcelWorldStore({
    required this.content,
    required this.terrainProvider,
    required this.api,
  });

  final ContentBundle content;
  final TerrainProvider terrainProvider;
  final WorldDocumentsApi api;

  @override
  Future<ParcelWorldState?> load() async {
    final Map<String, String>? documents;
    try {
      documents = await api.fetchDocuments();
    } catch (error) {
      throw StateError(
        'Could not reach the game server — start the preview with '
        '`dart run tool/run_game.dart` from the citysim folder. '
        '($error)',
      );
    }
    final tables = decodeSheetTables(
      userData: documents?[userDataSheetName] ?? '',
      tiles: documents?[tilesSheetName] ?? '',
      ownedParcels: documents?[ownedParcelsSheetName] ?? '',
      projects: documents?[projectsSheetName] ?? '',
    );
    if (tables.isEmpty) return null;
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

  @override
  Future<void> save(ParcelWorldState state) async {
    validateParcelWorldState(state, content, terrainProvider);
    await api.putDocuments(encodeSheetTables(worldToSheetTables(state)));
  }
}
