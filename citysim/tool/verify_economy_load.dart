// Verification-only: loads the live content and the live save sheets
// through the game's own parse+codec+validate path, then prints the
// town's next-report projection and vitality. Not part of the app or
// tests; run with `dart run tool/verify_economy_load.dart`.
import 'dart:io';

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_rules.dart';

Future<Map<String, Object?>> readCategory(String name) async =>
    decodeJsonObject(File('assets/content/$name').readAsStringSync());

Future<void> main() async {
  final content = parseContentBundle(
    manifest: await readCategory('manifest.json'),
    catalogue: await readCategory('catalogue.json'),
    sprites: await readCategory('sprites.json'),
    economy: await readCategory('economy.json'),
    ambience: await readCategory('ambience.json'),
    terrain: await readCategory('terrain.json'),
    progression: await readCategory('progression.json'),
  );
  stdout.writeln(
    'content parses; treasury start '
    '${content.economy.startingTreasuryCoins}, parcel '
    '${content.economy.parcelBaseCoins}',
  );

  String sheets(String name) =>
      File('assets/test_sheets/$name.csv').readAsStringSync();
  final tables = decodeSheetTables(
    userData: sheets('UserData'),
    tiles: sheets('Tiles'),
    props: sheets('Props'),
    ownedParcels: sheets('OwnedParcels'),
    projects: sheets('Projects'),
  );
  final terrain = ContentTerrainProvider(content.terrain);
  final world = sheetTablesToWorld(
    tables,
    content: content,
    terrainProvider: terrain,
  );
  validateParcelWorldState(world, content, terrain);
  stdout.writeln(
    'live save loads and validates: ${world.coins} coins, '
    '${world.structures.length} structures, ${world.roads.length} roads, '
    '${world.bridges.length} bridges, ${world.constructions.length} '
    'projects',
  );
  final ledger = townLedger(world, content);
  stdout.writeln(
    'next report projection: taxes ${ledger.taxes} '
    '(gross ${ledger.grossTaxes.toStringAsFixed(1)} x '
    '${ledger.contentment}%), upkeep ${ledger.upkeep}, '
    'net ${ledger.net}',
  );
  stdout.writeln(
    'vitality: population ${world.population}, employed '
    '${world.employedPopulation}, waiting ${world.waitingHouseholds}, '
    'unemployed ${ledger.employmentDemand}, vacant homes '
    '${ledger.residentialVacancy}, open jobs ${ledger.jobVacancy}',
  );
  for (final entry in ledger.coverage.entries) {
    stdout.writeln(
      '  ${entry.key} coverage '
      '${(entry.value * 100).toStringAsFixed(1)}%',
    );
  }
  stdout.writeln(
    'next parcel price: '
    '${content.economy.parcelBaseCoins + content.economy.parcelPerPopulationCoins * world.population} '
    'coins at population ${world.population}',
  );
  final limitsKm2 = world.ownedTileCount * tileAreaSquareMetres / 1e6;
  final builtKm2 = world.builtTileCount * tileAreaSquareMetres / 1e6;
  stdout.writeln(
    'footprint: city limits ${limitsKm2.toStringAsFixed(3)} '
    'km2 (${world.ownedTileCount} tiles), built '
    '${builtKm2.toStringAsFixed(3)} km2 (${world.builtTileCount} tiles), '
    'density ${limitsKm2 > 0 ? (world.population / limitsKm2).round() : 0}'
    '/km2',
  );

  // Round-trip: the save must survive a save→load cycle unchanged.
  final saved = worldToSheetTables(world);
  final reloaded = sheetTablesToWorld(
    saved,
    content: content,
    terrainProvider: terrain,
  );
  validateParcelWorldState(reloaded, content, terrain);
  stdout.writeln(
    'round-trip ok: ${reloaded.coins} coins, '
    '${reloaded.structures.length} structures, '
    '${reloaded.roads.length} roads, ${reloaded.bridges.length} bridges, '
    'population ${reloaded.population}',
  );
}
