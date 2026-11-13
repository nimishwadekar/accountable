/// The building foundation: every structure's footprint carries a
/// concrete slab, poured the moment the project is planned and kept
/// after completion. Roads and bridges keep their dirt grading —
/// that is a renderer pass, not ground state.
library;

import 'package:citysim/content/asset_content_source.dart';
import 'package:citysim/content/content_bundle.dart';
import 'package:citysim/storage/sheet_tables.dart';
import 'package:citysim/storage/world_sheet_codec.dart';
import 'package:citysim/world/coordinates.dart';
import 'package:citysim/world/terrain_provider.dart';
import 'package:citysim/world/world_queries.dart';
import 'package:citysim/world/world_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentTerrainProvider terrain;
  late ContentBundle content;

  setUpAll(() async {
    content = await loadContentBundle(const AssetContentSource());
    terrain = ContentTerrainProvider(content.terrain);
  });

  /// The codec test's handwritten town — a cottage, a half-funded
  /// café under construction, roads, and a bridge over the east
  /// water parcel.
  ParcelWorldState town() => sheetTablesToWorld(
    SheetTables(
      userData: const {
        'seed': '7',
        'coins': '50',
        'coins_earned': '50',
        'coins_spent': '0',
        'simulated_date': '2026-11-02',
        'high_water_date': '2026-11-02',
        'last_checkin_date': '2026-11-02',
        'checkin_count': '1',
        'construction_day': '5',
      },
      ownedParcels: const [
        ['0', '0'],
        ['1', '0'],
        ['2', '0'],
      ],
      tiles: [
        const ['4', '4', 'road', 'complete', 'dirt', '', '', ''],
        const ['5', '4', 'road', 'complete', 'asphalt', '', '', ''],
        const ['6', '4', 'road', 'complete', 'asphalt', '', '', ''],
        const ['7', '4', 'road', 'complete', 'asphalt', '', '', ''],
        const [
          '3',
          '4',
          'structure',
          'complete',
          'small-home',
          'home-small-yellow',
          'east',
          '',
        ],
        const ['6', '5', 'structure', 'planned', 'cafe', 'cafe', 'east', ''],
      ],
      projects: const [
        ['2', 'structure', 'cafe', '6:5', '1'],
      ],
    ),
    content: content,
    terrainProvider: terrain,
  );

  test(
    'buildings sit on a concrete slab from planning, kept after completion',
    () {
      final queries = WorldQueries(town(), terrain);

      // Completed structures: every footprint cell carries the slab.
      final structures = queries.state.structures;
      expect(structures, isNotEmpty);
      for (final structure in structures) {
        for (final cell in structure.footprint) {
          expect(
            queries.terrainAt(cell).groundStyle,
            GroundStyle.concrete,
            reason: 'completed building at ${cell.column},${cell.row}',
          );
          expect(
            queries.terrainAt(cell).kind,
            TerrainKind.grass,
            reason: 'the slab is ground style only — the kind stays land',
          );
        }
      }

      // Planned structures: the foundation is poured at planning, funded
      // or not.
      final planned = queries.state.constructions
          .where((job) => job.kind == WorldConstructionKind.structure)
          .toList();
      expect(planned, isNotEmpty);
      for (final job in planned) {
        expect(
          job.coinsFunded,
          greaterThan(0),
          reason: 'the café is half-funded',
        );
        for (final cell in job.footprint) {
          expect(
            queries.terrainAt(cell).groundStyle,
            GroundStyle.concrete,
            reason: 'planned building at ${cell.column},${cell.row}',
          );
        }
      }

      // Everything else keeps its ground: plain grass stays grass, and
      // road cells keep theirs — their dirt grading is a renderer pass,
      // not ground state.
      expect(
        queries.terrainAt(const CellCoord(2, 2)).groundStyle,
        GroundStyle.grass,
      );
      expect(
        queries.terrainAt(const CellCoord(4, 4)).groundStyle,
        GroundStyle.grass,
        reason: 'road cells do not carry the slab',
      );
    },
  );
}
