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
}
