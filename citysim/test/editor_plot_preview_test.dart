import 'package:citysim/editor/edit_fields.dart';
import 'package:citysim/editor/preview_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('footprintForRole resolves the using model, defaulting to 1×1', () {
    final categories = {
      'catalogue.json': {
        'models': [
          {
            'id': 'city-office',
            'assetRoles': ['office-medium-white', 'office-medium-blue'],
            'footprint': {'columns': 2, 'rows': 2},
          },
          {
            'id': 'small-home',
            'assetRoles': ['house-small-red'],
            'footprint': {'columns': 1, 'rows': 1},
          },
        ],
      },
    };
    expect(footprintForRole(categories, 'office-medium-blue'), (2, 2));
    expect(footprintForRole(categories, 'house-small-red'), (1, 1));
    expect(footprintForRole(categories, 'not-a-role'), (1, 1));
    expect(footprintForRole(const {}, 'office-medium-white'), (1, 1));
  });

  testWidgets('SpritePlotPreview renders its plot without loaded art', (
    tester,
  ) async {
    final categories = {
      'catalogue.json': {
        'models': [
          {
            'id': 'city-office',
            'assetRoles': ['office-medium-white'],
            'footprint': {'columns': 2, 'rows': 2},
          },
        ],
      },
      'sprites.json': {
        'sprites': {
          'office-medium-white': {
            'path': 'sprites/buildings/offices/missing-in-test.png',
            'renderScale': 0.5,
            'groundAnchor': [0.5, 1.0],
            'category': 'buildings',
            'subcategory': 'offices',
          },
          'road.straight.se': {
            'path': 'sprites/roads/straight/also-missing.png',
          },
        },
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpritePlotPreview(
            categories: categories,
            role: 'office-medium-white',
          ),
        ),
      ),
    );
    // The network images cannot load under test; the preview must still
    // paint the plot outline and stay exception-free.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('2×2 plot'), findsOneWidget);
  });

  testWidgets('SpritePlotPreview labels tile-category sprites tile-fit', (
    tester,
  ) async {
    final categories = {
      'sprites.json': {
        'sprites': {
          'tile_ground_grass': {
            'path': 'sprites/ground/grass/missing.png',
            'renderScale': 0.5,
            'groundAnchor': [0.5, 1.0],
            'category': 'ground',
            'subcategory': 'grass',
          },
        },
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpritePlotPreview(
            categories: categories,
            role: 'tile_ground_grass',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('1×1 plot · drawn tile-fit'), findsOneWidget);
  });

  testWidgets('facings sprites get a road-side picker that applies the pull', (
    tester,
  ) async {
    final categories = {
      'catalogue.json': {
        'models': [
          {
            'id': 'city-office',
            'assetRoles': ['office-medium-white'],
            'footprint': {'columns': 2, 'rows': 2},
          },
        ],
      },
      'sprites.json': {
        'sprites': {
          'office-medium-white': {
            'facings': {
              'left': 'sprites/buildings/offices/missing-left.png',
              'right': 'sprites/buildings/offices/missing-right.png',
            },
            'renderScale': 0.5,
            'groundAnchor': [0.5, 1.0],
            'facingOffset': 0.25,
            'category': 'buildings',
            'subcategory': 'offices',
          },
          'road.straight.se': {'path': 'sprites/roads/straight/se-missing.png'},
          'road.straight.sw': {'path': 'sprites/roads/straight/sw-missing.png'},
        },
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpritePlotPreview(
            categories: categories,
            role: 'office-medium-white',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Four road-side chips — north, east, south, west — with south
    // selected by default.
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(4));
    expect(
      tester.widget<ChoiceChip>(chips.at(2)).selected,
      isTrue,
      reason: 'south is the default road side',
    );

    // Switching sides swaps to that half's art variant and re-renders
    // the pulled plot without errors.
    await tester.tap(chips.at(1)); // east
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<ChoiceChip>(chips.at(1)).selected, isTrue);
    expect(find.text('2×2 plot'), findsOneWidget);
  });

  testWidgets('single-facing building sprites keep the plain plot preview', (
    tester,
  ) async {
    final categories = {
      'sprites.json': {
        'sprites': {
          'warehouse-blue': {
            'path': 'sprites/buildings/industrial/missing.png',
            'renderScale': 0.5,
            'groundAnchor': [0.5, 1.0],
            'category': 'buildings',
            'subcategory': 'industrial',
          },
        },
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpritePlotPreview(
            categories: categories,
            role: 'warehouse-blue',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('1×1 plot'), findsOneWidget);
  });

  testWidgets('prop sprites preview on the subtile lattice', (tester) async {
    final categories = {
      'sprites.json': {
        'sprites': {
          'park-bench': {
            'path': 'sprites/props/benches/missing.png',
            'renderScale': 0.5,
            'groundAnchor': [0.5, 1.0],
            'category': 'props',
            'subcategory': 'benches',
          },
        },
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpritePlotPreview(categories: categories, role: 'park-bench'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Three slot chips — back, centre, front — with centre selected
    // by default; the caption names the lattice and the slot.
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(3));
    expect(
      tester.widget<ChoiceChip>(chips.at(1)).selected,
      isTrue,
      reason: 'centre is the default slot',
    );
    expect(find.text('8×8 lattice · subtile (3,3)'), findsOneWidget);

    // Switching slots re-renders the lattice preview without errors.
    await tester.tap(chips.at(2)); // front
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<ChoiceChip>(chips.at(2)).selected, isTrue);
    expect(find.text('8×8 lattice · subtile (7,7)'), findsOneWidget);
  });
}
