import 'package:citysim/content/city_content.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all catalogue, map, and scenery art references are bundled', () async {
    expect(citySpriteManifest.keys.toSet(), cityCatalogueById.keys.toSet());
    final paths = <String>{
      cityArtPath('Roads and Grounds/tile_ground_grass.png'),
      ...cityRoads.map(
        (road) => cityArtPath('Roads and Grounds/${road.assetName}'),
      ),
      ...cityScenery.map(
        (scenery) => cityArtPath('Props/${scenery.assetName}'),
      ),
      ...citySpriteManifest.values.map(
        (sprite) => cityArtPath(sprite.assetPath),
      ),
    };

    for (final path in paths) {
      final data = await rootBundle.load(path);
      expect(data.lengthInBytes, greaterThan(0), reason: path);
    }
  });

  test('authored lots are unique and stay off the fixed road grid', () {
    final lotCells = cityLots.map((lot) => lot.cell.key).toList();
    final roadCells = cityRoads.map((road) => road.cell.key).toSet();

    expect(lotCells.toSet(), hasLength(lotCells.length));
    expect(lotCells.toSet().intersection(roadCells), isEmpty);
    for (final item in cityCatalogue) {
      final sprite = citySpriteManifest[item.id]!;
      expect(sprite.footprintColumns, greaterThan(0));
      expect(sprite.footprintRows, greaterThan(0));
      expect(sprite.groundAnchorX, inInclusiveRange(0, 1));
      expect(sprite.groundAnchorY, inInclusiveRange(0, 1));
      expect(
        cityLots
            .where((lot) => lot.districtId == 'village')
            .every(
              (lot) =>
                  sprite.footprintColumns <= lot.footprintColumns &&
                  sprite.footprintRows <= lot.footprintRows,
            ),
        isTrue,
      );
    }
    expect(
      cityStartingBuildings.map((building) => building.lotId).toSet(),
      hasLength(cityStartingBuildings.length),
    );
  });
}
