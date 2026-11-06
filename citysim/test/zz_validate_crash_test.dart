import 'dart:convert';
import 'dart:io';

import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_usage.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replay server validation on the fetched body', () {
    final body =
        (jsonDecode(
          File(
            '/private/var/folders/cq/8w4pbwbj0vd6pjrchp9xh6280000gn/T/opencode/content.json',
          ).readAsStringSync(),
        ) as Map).cast<String, Object?>();

    // _asMap equivalents.
    Map<String, Object?> asMap(String name) =>
        (body[name] as Map).cast<String, Object?>();

    final bundle = parseContentBundle(
      manifest: asMap('manifest.json'),
      catalogue: asMap('catalogue.json'),
      sprites: asMap('sprites.json'),
      economy: asMap('economy.json'),
      ambience: asMap('ambience.json'),
      terrain: asMap('terrain.json'),
    );
    print('parseContentBundle ok');

    final issues = <String>[
      ...checkSpriteFilesLocal(bundle.sprites),
      ...terrainOccupationLocal(body, asMap('terrain.json'), bundle),
    ];
    print('validation issues: $issues');
  });
}

List<String> checkSpriteFilesLocal(
  Map<String, SpriteDefinition> sprites,
) {
  final issues = <String>[];
  for (final entry in sprites.entries) {
    for (final relative in entry.value.allPaths) {
      if (!File('assets/$relative').existsSync()) {
        issues.add('Sprite "${entry.key}" missing file: $relative');
      }
    }
  }
  return issues;
}

List<String> terrainOccupationLocal(
  Map<String, Object?> body,
  Map<String, Object?> incomingTerrain,
  ContentBundle bundle,
) {
  final currentFile = File('assets/content/terrain.json');
  final currentParcels =
      (jsonDecode(currentFile.readAsStringSync()) as Map)['parcels']
          as Map?;
  final incomingParcels = incomingTerrain['parcels'] as Map?;
  if (currentParcels == null || incomingParcels == null) return const [];

  String doc(String name) =>
      File('assets/test_sheets/$name.csv').readAsStringSync();
  final tables = decodeSheetTables(
    userData: doc('UserData'),
    tiles: doc('Tiles'),
    ownedParcels: doc('OwnedParcels'),
    projects: doc('Projects'),
  );
  if (tables.isEmpty) return const [];
  final usage = computeWorldUsage(tables, bundle);

  final issues = <String>[];
  for (final entry in currentParcels.entries) {
    if (incomingParcels[entry.key] == entry.value) continue;
    final parts = (entry.key as String).split(',');
    if (parts.length != 2) continue;
    final x = int.tryParse(parts[0]);
    final y = int.tryParse(parts[1]);
    if (x == null || y == null) continue;
    final parcel = ParcelCoord(x, y);
    if (parcel.cells(8).any(usage.occupiedCells.contains)) {
      issues.add('[error] Parcel ${entry.key} has occupied cells.');
    }
  }
  return issues;
}
