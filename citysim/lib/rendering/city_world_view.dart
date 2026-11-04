import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../content/city_content.dart';
import '../domain/city_state.dart';

const cityWorldWidth = 1280.0;
const cityWorldHeight = 720.0;
const _tileWidth = 64.0;
const _tileHeight = 32.0;
const _originX = cityWorldWidth / 2;
const _originY = 54.0;

class CityWorldHit {
  const CityWorldHit({this.lotId, this.buildingId});

  final String? lotId;
  final String? buildingId;
}

class CityWorldView extends StatefulWidget {
  const CityWorldView({
    required this.state,
    required this.onMapTap,
    this.selectedCatalogueId,
    this.selectedLotId,
    this.selectedBuildingId,
    super.key,
  });

  final CityState state;
  final String? selectedCatalogueId;
  final String? selectedLotId;
  final String? selectedBuildingId;
  final ValueChanged<CityWorldHit> onMapTap;

  @override
  State<CityWorldView> createState() => _CityWorldViewState();
}

class _CityWorldViewState extends State<CityWorldView> {
  late final Future<Map<String, ui.Image>> _images = _loadImages();

  @override
  void dispose() {
    _images.then((images) {
      for (final image in images.values) {
        image.dispose();
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, ui.Image>>(
    future: _images,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(child: Text('Could not load the city artwork.'));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final images = snapshot.requireData;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          widget.onMapTap(
            _hitTest(details.localPosition, widget.state, images),
          );
        },
        child: CustomPaint(
          size: const Size(cityWorldWidth, cityWorldHeight),
          painter: _CityWorldPainter(
            images: images,
            state: widget.state,
            selectedCatalogueId: widget.selectedCatalogueId,
            selectedLotId: widget.selectedLotId,
            selectedBuildingId: widget.selectedBuildingId,
          ),
        ),
      );
    },
  );

  Future<Map<String, ui.Image>> _loadImages() async {
    final paths = <String>{
      cityArtPath('Roads and Grounds/tile_ground_grass.png'),
      for (final road in cityRoads)
        cityArtPath('Roads and Grounds/${road.assetName}'),
      for (final scenery in cityScenery)
        cityArtPath('Props/${scenery.assetName}'),
      for (final item in cityCatalogue) cityCatalogueAsset(item.id),
    };
    final loaded = <String, ui.Image>{};
    for (final path in paths) {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      loaded[path] = frame.image;
      codec.dispose();
    }
    return loaded;
  }
}

CityWorldHit _hitTest(
  Offset position,
  CityState state,
  Map<String, ui.Image> images,
) {
  final renderedBuildings = state.buildings.toList()
    ..sort((a, b) {
      final aCell = cityLotById[a.lotId]!.cell;
      final bCell = cityLotById[b.lotId]!.cell;
      return (aCell.column + aCell.row).compareTo(bCell.column + bCell.row);
    });
  for (final building in renderedBuildings.reversed) {
    final lot = cityLotById[building.lotId]!;
    final image = images[cityCatalogueAsset(building.catalogueId)];
    if (image == null) continue;
    if (_assetRect(
      image,
      _cellCenter(lot.cell),
      definition: citySpriteManifest[building.catalogueId]!,
    ).inflate(3).contains(position)) {
      return CityWorldHit(lotId: lot.id, buildingId: building.id);
    }
  }

  final nearestCell = _nearestCell(position);
  final center = _cellCenter(nearestCell);
  final diamondDistance =
      (center.dx - position.dx).abs() / (_tileWidth / 2) +
      (center.dy - position.dy).abs() / (_tileHeight / 2);
  if (diamondDistance > 1.05) return const CityWorldHit();
  for (final lot in cityLots) {
    if (lot.cell == nearestCell) return CityWorldHit(lotId: lot.id);
  }
  return const CityWorldHit();
}

CityCell _nearestCell(Offset position) {
  final x = (position.dx - _originX) / (_tileWidth / 2);
  final y = (position.dy - _originY) / (_tileHeight / 2);
  final column = ((x + y) / 2).round();
  final row = ((y - x) / 2).round();
  CityCell closest = CityCell(column, row);
  var closestDistance = double.infinity;
  for (var c = column - 1; c <= column + 1; c++) {
    for (var r = row - 1; r <= row + 1; r++) {
      final center = _cellCenter(CityCell(c, r));
      final distance =
          math.pow((center.dx - position.dx) / _tileWidth, 2) +
          math.pow((center.dy - position.dy) / _tileHeight, 2);
      if (distance < closestDistance) {
        closest = CityCell(c, r);
        closestDistance = distance.toDouble();
      }
    }
  }
  return closest;
}

Offset _cellCenter(CityCell cell) => Offset(
  _originX + (cell.column - cell.row) * (_tileWidth / 2),
  _originY + (cell.column + cell.row) * (_tileHeight / 2),
);

Rect _assetRect(
  ui.Image image,
  Offset center, {
  CitySpriteDefinition? definition,
}) {
  final scale = definition?.renderScale ?? 0.5;
  final width = image.width * scale;
  final height = image.height * scale;
  final anchorX = definition?.groundAnchorX ?? 0.5;
  final anchorY = definition?.groundAnchorY ?? 1.0;
  final groundY = center.dy + _tileHeight / 2;
  return Rect.fromLTWH(
    center.dx - width * anchorX,
    groundY - height * anchorY,
    width,
    height,
  );
}

class _CityWorldPainter extends CustomPainter {
  const _CityWorldPainter({
    required this.images,
    required this.state,
    required this.selectedCatalogueId,
    required this.selectedLotId,
    required this.selectedBuildingId,
  });

  final Map<String, ui.Image> images;
  final CityState state;
  final String? selectedCatalogueId;
  final String? selectedLotId;
  final String? selectedBuildingId;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFB5DCCF),
    );
    final grass =
        images[cityArtPath('Roads and Grounds/tile_ground_grass.png')];
    if (grass == null) return;

    for (
      var diagonal = 0;
      diagonal < cityMapColumns + cityMapRows - 1;
      diagonal++
    ) {
      for (var column = 0; column < cityMapColumns; column++) {
        final row = diagonal - column;
        if (row < 0 || row >= cityMapRows) continue;
        final center = _cellCenter(CityCell(column, row));
        _drawGround(canvas, grass, center);
      }
    }

    for (final road in cityRoads) {
      final image = images[cityArtPath('Roads and Grounds/${road.assetName}')];
      if (image != null) _drawGround(canvas, image, _cellCenter(road.cell));
    }

    _drawOpenLots(canvas);
    _drawContents(canvas);
    _drawConstructionIndicators(canvas);
  }

  void _drawGround(Canvas canvas, ui.Image image, Offset center) {
    final destination = Rect.fromCenter(
      center: center,
      width: _tileWidth,
      height: _tileHeight,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      destination,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _drawOpenLots(Canvas canvas) {
    final available = _eligibleLots.toSet();
    final activeLots = state.constructions
        .where((job) => job.lotId != null)
        .map((job) => job.lotId!)
        .toSet();
    for (final lot in cityLots) {
      if (!state.unlockedDistrictIds.contains(lot.districtId)) continue;
      final occupied =
          state.buildings.any((building) => building.lotId == lot.id) ||
          activeLots.contains(lot.id);
      if (occupied) continue;
      final center = _cellCenter(lot.cell);
      final selected = lot.id == selectedLotId;
      final isEligible = available.contains(lot.id);
      final path = Path()
        ..moveTo(center.dx, center.dy - _tileHeight / 2)
        ..lineTo(center.dx + _tileWidth / 2, center.dy)
        ..lineTo(center.dx, center.dy + _tileHeight / 2)
        ..lineTo(center.dx - _tileWidth / 2, center.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = selected
              ? const Color(0x6663D6B1)
              : isEligible
              ? const Color(0x18FFFFFF)
              : const Color(0x18000000)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = selected
              ? const Color(0xFF256957)
              : isEligible
              ? const Color(0x6671A78F)
              : const Color(0x557A8E82)
          ..strokeWidth = selected ? 2 : 1
          ..style = PaintingStyle.stroke,
      );
    }
  }

  Iterable<String> get _eligibleLots sync* {
    if (selectedCatalogueId == null) return;
    final item = cityCatalogueById[selectedCatalogueId];
    if (item == null) return;
    final sprite = citySpriteManifest[selectedCatalogueId]!;
    final busyLots = {
      ...state.buildings.map((building) => building.lotId),
      ...state.constructions
          .where((job) => job.lotId != null)
          .map((job) => job.lotId!),
    };
    for (final lot in cityLots) {
      if (!state.unlockedDistrictIds.contains(lot.districtId) ||
          busyLots.contains(lot.id) ||
          sprite.footprintColumns > lot.footprintColumns ||
          sprite.footprintRows > lot.footprintRows ||
          item.minimumDistrictRank > cityDistrictRank(lot.districtId)) {
        continue;
      }
      yield lot.id;
    }
  }

  void _drawContents(Canvas canvas) {
    final contents =
        <
          ({
            CityCell cell,
            String path,
            String? buildingId,
            CitySpriteDefinition? definition,
          })
        >[];
    for (final scenery in cityScenery) {
      contents.add((
        cell: scenery.cell,
        path: cityArtPath('Props/${scenery.assetName}'),
        buildingId: null,
        definition: null,
      ));
    }
    for (final building in state.buildings) {
      final lot = cityLotById[building.lotId]!;
      contents.add((
        cell: lot.cell,
        path: cityCatalogueAsset(building.catalogueId),
        buildingId: building.id,
        definition: citySpriteManifest[building.catalogueId]!,
      ));
    }
    contents.sort((a, b) {
      final depth = (a.cell.column + a.cell.row).compareTo(
        b.cell.column + b.cell.row,
      );
      return depth != 0 ? depth : a.cell.column.compareTo(b.cell.column);
    });
    for (final content in contents) {
      final image = images[content.path];
      if (image == null) continue;
      final rect = _assetRect(
        image,
        _cellCenter(content.cell),
        definition: content.definition,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = content.buildingId == selectedBuildingId
              ? Colors.white
              : const Color(0xFFFFFFFF),
      );
    }
  }

  void _drawConstructionIndicators(Canvas canvas) {
    for (final job in state.constructions) {
      final center = job.lotId == null
          ? const Offset(cityWorldWidth / 2, 36)
          : _cellCenter(cityLotById[job.lotId!]!.cell);
      if (job.lotId != null) _drawConstructionLot(canvas, center);

      final progress =
          ((state.simulationSeconds - job.startSeconds) / job.durationSeconds)
              .clamp(0.0, 1.0);
      final bar = Rect.fromLTWH(center.dx - 21, center.dy - 28, 42, 5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(3)),
        Paint()..color = const Color(0xFFE8F1EC),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, bar.top, bar.width * progress, bar.height),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF1D8065),
      );
    }
  }

  void _drawConstructionLot(Canvas canvas, Offset center) {
    final path = Path()
      ..moveTo(center.dx, center.dy - _tileHeight / 2)
      ..lineTo(center.dx + _tileWidth / 2, center.dy)
      ..lineTo(center.dx, center.dy + _tileHeight / 2)
      ..lineTo(center.dx - _tileWidth / 2, center.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x335C846F)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF56816A)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CityWorldPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.selectedCatalogueId != selectedCatalogueId ||
      oldDelegate.selectedLotId != selectedLotId ||
      oldDelegate.selectedBuildingId != selectedBuildingId;
}
