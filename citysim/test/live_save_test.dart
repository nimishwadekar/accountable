import 'dart:io';

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bundled save sheets are live data the player mutates by
/// playing — and content edits (like a footprint growing from 1×1 to
/// 2×1) can invalidate older placements. This file loads the shipped
/// sheets through the real codec and validator, so a content/save
/// clash fails here — with a message — instead of at game startup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentBundle content;
  late ContentTerrainProvider terrain;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  test('the bundled save sheets load and validate against the content', () {
    const dir = 'assets/test_sheets';
    String read(String name) => File('$dir/$name').readAsStringSync();
    final world = sheetTablesToWorld(
      decodeSheetTables(
        userData: read('UserData.csv'),
        tiles: read('Tiles.csv'),
        props: read('Props.csv'),
        ownedParcels: read('OwnedParcels.csv'),
        projects: read('Projects.csv'),
      ),
      content: content,
      terrainProvider: terrain,
    );
    expect(world.structures, isNotEmpty, reason: 'the save has buildings');
    validateParcelWorldState(world, content, terrain);
  });
}
