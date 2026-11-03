import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../world/coordinates.dart';
import '../world/road_sprite_resolver.dart';
import '../world/terrain_provider.dart';
import '../world/world_content.dart';
import '../world/world_queries.dart';
import '../world/world_state.dart';

const _logicalTileWidth = 64.0;
const _logicalTileHeight = 32.0;

class ParcelWorldView extends StatefulWidget {
  const ParcelWorldView({
    required this.state,
    required this.terrainProvider,
    required this.onCellTap,
    this.selectedCell,
    this.selectedParcel,
    this.selectedCatalogueId,
    this.bridgeStartCell,
    this.roadPlanCells = const [],
    this.fundableRoadCells = const {},
    this.cameraResetToken = 0,
    super.key,
  });

  final ParcelWorldState state;
  final TerrainProvider terrainProvider;
  final void Function(CellCoord cell, String? structureId) onCellTap;
  final CellCoord? selectedCell;
  final ParcelCoord? selectedParcel;
  final String? selectedCatalogueId;
  final CellCoord? bridgeStartCell;
  final List<CellCoord> roadPlanCells;
  final Set<CellCoord> fundableRoadCells;
  final int cameraResetToken;

  @override
  State<ParcelWorldView> createState() => _ParcelWorldViewState();
}

class _ParcelWorldViewState extends State<ParcelWorldView> {
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image>> _imageRequests = {};
  late WorldQueries _queries = WorldQueries(
    widget.state,
    widget.terrainProvider,
  );
  late Future<void> _loading;
  final Map<int, Offset> _pointerDown = {};
  double _scale = 1.0;
  double _scaleAtGestureStart = 1.0;
  Offset _offset = Offset.zero;
  Offset _worldAnchorAtGestureStart = Offset.zero;
  double _panZoomStartScale = 1.0;
  Offset _panZoomStartOffset = Offset.zero;
  Offset _panZoomStartPosition = Offset.zero;
  bool _cameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _loading = _loadMissingImages();
  }

  @override
  void didUpdateWidget(covariant ParcelWorldView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.terrainProvider != widget.terrainProvider) {
      _queries = WorldQueries(widget.state, widget.terrainProvider);
      _loading = _loadMissingImages();
    }
    if (oldWidget.selectedCatalogueId != widget.selectedCatalogueId) {
      _loading = _loadMissingImages();
    }
    if (widget.cameraResetToken != oldWidget.cameraResetToken) {
      _cameraInitialized = false;
    }
  }

  @override
  void dispose() {
    for (final image in _images.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      _initializeCamera(size);
      return FutureBuilder<void>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.hasError && _images.isEmpty) {
            return const Center(
              child: Text(
                'Could not load the world artwork. Retry after checking the asset pack.',
              ),
            );
          }
          if (_images.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final world = Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              _pointerDown[event.pointer] = event.localPosition;
            },
            onPointerUp: (event) {
              final down = _pointerDown.remove(event.pointer);
              if (down == null ||
                  (event.localPosition - down).distance > 8 ||
                  _pointerDown.isNotEmpty) {
                return;
              }
              _dispatchTap(event.localPosition, size);
            },
            onPointerCancel: (event) => _pointerDown.remove(event.pointer),
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent) return;
              _zoomAt(
                event.localPosition,
                size,
                math.exp(-event.scrollDelta.dy * 0.0015),
              );
            },
            onPointerPanZoomStart: (event) {
              _panZoomStartScale = _scale;
              _panZoomStartOffset = _offset;
              _panZoomStartPosition = event.position;
            },
            onPointerPanZoomUpdate: (event) {
              final anchor = _screenToWorld(
                _panZoomStartPosition,
                size,
                _panZoomStartScale,
                _panZoomStartOffset,
              );
              final nextScale = (_panZoomStartScale * event.scale).clamp(
                0.42,
                3.2,
              );
              final focal = _panZoomStartPosition + event.pan;
              setState(() {
                _scale = nextScale;
                _offset = focal - size.center(Offset.zero) - anchor * nextScale;
              });
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                _scaleAtGestureStart = _scale;
                _worldAnchorAtGestureStart = _screenToWorld(
                  details.localFocalPoint,
                  size,
                  _scale,
                  _offset,
                );
              },
              onScaleUpdate: (details) {
                final nextScale = (_scaleAtGestureStart * details.scale).clamp(
                  0.42,
                  3.2,
                );
                setState(() {
                  _scale = nextScale;
                  _offset =
                      details.localFocalPoint -
                      size.center(Offset.zero) -
                      _worldAnchorAtGestureStart * nextScale;
                });
              },
              child: CustomPaint(
                size: size,
                painter: _ParcelWorldPainter(
                  state: widget.state,
                  images: _images,
                  scale: _scale,
                  offset: _offset,
                  queries: _queries,
                  selectedCell: widget.selectedCell,
                  selectedParcel: widget.selectedParcel,
                  selectedCatalogueId: widget.selectedCatalogueId,
                  bridgeStartCell: widget.bridgeStartCell,
                  roadPlanCells: widget.roadPlanCells,
                  fundableRoadCells: widget.fundableRoadCells,
                ),
              ),
            ),
          );
          if (!snapshot.hasError &&
              snapshot.connectionState == ConnectionState.done) {
            return world;
          }
          return Stack(
            children: [
              Positioned.fill(child: world),
              Positioned(
                right: 8,
                top: 8,
                child: snapshot.hasError
                    ? IconButton.filledTonal(
                        tooltip: 'Retry loading world art',
                        onPressed: () => setState(() {
                          _loading = _loadMissingImages(retryFailed: true);
                        }),
                        icon: const Icon(Icons.refresh_rounded),
                      )
                    : const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            ],
          );
        },
      );
    },
  );

  void _initializeCamera(Size size) {
    if (_cameraInitialized || size.isEmpty) return;
    _cameraInitialized = true;
    _scale = 1.0;
    final start = CellCoord(
      widget.state.parcelSize ~/ 2,
      widget.state.parcelSize ~/ 2,
    );
    final world = _cellWorldCenter(start);
    _offset = Offset(-world.dx * _scale, -world.dy * _scale);
  }

  void _dispatchTap(Offset position, Size size) {
    final hit = _hitTest(position, size, _scale, _offset, _queries, _images);
    widget.onCellTap(hit.cell, hit.structureId);
  }

  /// Zooms by [factor] while keeping the world point under [focalPoint]
  /// anchored to that screen position.
  void _zoomAt(Offset focalPoint, Size size, double factor) {
    if (factor == 1.0) return;
    final anchor = _screenToWorld(focalPoint, size, _scale, _offset);
    final nextScale = (_scale * factor).clamp(0.42, 3.2);
    setState(() {
      _scale = nextScale;
      _offset = focalPoint - size.center(Offset.zero) - anchor * nextScale;
    });
  }

  Future<void> _loadMissingImages({bool retryFailed = false}) async {
    final paths = <String>{
      'terrain.grass',
      'terrain.grass.puddle',
      'terrain.dirt',
      'terrain.asphalt',
      'terrain.concrete',
      'terrain.water',
      for (final style in ['grass', 'dirt'])
        for (final edge in ['n', 'e', 's', 'w']) ...[
          'shore.$style.edge.$edge',
          'shore.$style.corner.$edge',
        ],
      for (final style in ['grass', 'dirt'])
        for (final dir in ['ne', 'se', 'sw', 'nw']) 'shore.$style.quarter.$dir',
      for (final road in widget.state.roads)
        if (road.style == RoadStyle.asphalt)
          for (var mask = 0; mask < 16; mask++) roadSpriteRole(mask),
      for (final structure in widget.state.structures)
        structureById[structure.catalogueId]!.assetRole,
      for (final job in widget.state.constructions)
        if (job.kind == WorldConstructionKind.structure)
          structureById[job.catalogueId]!.assetRole,
      if (widget.selectedCatalogueId != null)
        structureById[widget.selectedCatalogueId]!.assetRole,
      if (widget.state.bridges.isNotEmpty)
        for (final role in [
          'bridge.body.se',
          'bridge.body.sw',
          'bridge.ramp.ne',
          'bridge.ramp.nw',
          'bridge.ramp.se',
          'bridge.ramp.sw',
        ])
          role,
    }.map(citysimAssetPath).toSet();

    if (retryFailed) {
      _imageRequests.removeWhere((path, _) => !_images.containsKey(path));
    }
    final pending = <Future<ui.Image>>[];
    for (final path in paths) {
      if (_images.containsKey(path)) continue;
      final request = _imageRequests.putIfAbsent(path, () {
        final future = _loadImage(path);
        unawaited(
          future.then<void>((image) {
            if (mounted) {
              setState(() => _images[path] = image);
            } else {
              image.dispose();
            }
          }, onError: (Object _) => _imageRequests.remove(path)),
        );
        return future;
      });
      pending.add(request);
    }
    await Future.wait(pending);
  }

  Future<ui.Image> _loadImage(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      final frame = await codec.getNextFrame();
      final role = _spriteRoleForPath(path);
      if (role != null && role.startsWith('shore.')) {
        final overlay = await _maskShoreOverlay(role, frame.image);
        if (overlay != null) {
          frame.image.dispose();
          return overlay;
        }
      }
      return frame.image;
    } finally {
      codec.dispose();
    }
  }
}

/// Reverse lookup from a bundled asset path back to its sprite-manifest role.
String? _spriteRoleForPath(String path) {
  for (final entry in spriteManifest.entries) {
    if (citysimAssetPath(entry.key) == path) return entry.key;
  }
  return null;
}

// Reference colours sampled from the pack's plain ground tiles. Shore
// sprites are full grass/dirt tiles carrying a water band; masking them
// against these references turns them into water-only overlays that layer
// over the base ground tile without painting grass over another piece's
// water.
const _shoreWaterRgb = (105, 156, 188);
const _shoreGrassRgb = (155, 162, 81);
const _shoreDirtRgb = (171, 158, 127);

Future<ui.Image?> _maskShoreOverlay(String role, ui.Image image) async {
  final base = role.startsWith('shore.dirt') ? _shoreDirtRgb : _shoreGrassRgb;
  try {
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (bytes == null) return null;
    final pixels = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    for (var i = 0; i < pixels.length; i += 4) {
      final alpha = pixels[i + 3];
      if (alpha == 0) continue;
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      final dWater =
          (r - _shoreWaterRgb.$1) * (r - _shoreWaterRgb.$1) +
          (g - _shoreWaterRgb.$2) * (g - _shoreWaterRgb.$2) +
          (b - _shoreWaterRgb.$3) * (b - _shoreWaterRgb.$3);
      final dBase =
          (r - base.$1) * (r - base.$1) +
          (g - base.$2) * (g - base.$2) +
          (b - base.$3) * (b - base.$3);
      final waterShare = dWater / math.max(1.0, dWater + dBase);
      final keep = (1.0 - waterShare).clamp(0.0, 1.0);
      pixels[i + 3] = (alpha * keep).round();
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final overlayCodec = await descriptor.instantiateCodec();
    try {
      final overlayFrame = await overlayCodec.getNextFrame();
      return overlayFrame.image;
    } finally {
      overlayCodec.dispose();
      descriptor.dispose();
    }
  } catch (_) {
    return null;
  }
}

class _WorldHit {
  const _WorldHit(this.cell, this.structureId);

  final CellCoord cell;
  final String? structureId;
}

_WorldHit _hitTest(
  Offset position,
  Size size,
  double scale,
  Offset offset,
  WorldQueries queries,
  Map<String, ui.Image> images,
) {
  final world = _screenToWorld(position, size, scale, offset);
  final cell = _nearestCell(world);
  final structures =
      queries.structuresInBounds(
        left: cell.column - 5,
        right: cell.column + 5,
        top: cell.row - 5,
        bottom: cell.row + 5,
      )..sort((a, b) {
        final aDepth = a.footprint
            .map((entry) => entry.column + entry.row)
            .reduce(math.max);
        final bDepth = b.footprint
            .map((entry) => entry.column + entry.row)
            .reduce(math.max);
        return aDepth.compareTo(bDepth);
      });
  for (final structure in structures.reversed) {
    final definition = structureById[structure.catalogueId]!;
    final image = images[citysimAssetPath(definition.assetRole)];
    if (image == null) continue;
    final rect = _structureRect(image, definition, structure);
    final screenRect = _worldRectToScreen(rect, size, scale, offset);
    if (screenRect.inflate(3).contains(position)) {
      return _WorldHit(structure.origin, structure.id);
    }
  }
  return _WorldHit(cell, null);
}

class _ParcelWorldPainter extends CustomPainter {
  const _ParcelWorldPainter({
    required this.state,
    required this.queries,
    required this.images,
    required this.scale,
    required this.offset,
    required this.selectedCell,
    required this.selectedParcel,
    required this.selectedCatalogueId,
    required this.bridgeStartCell,
    required this.roadPlanCells,
    required this.fundableRoadCells,
  });

  final ParcelWorldState state;
  final WorldQueries queries;
  final Map<String, ui.Image> images;
  final double scale;
  final Offset offset;
  final CellCoord? selectedCell;
  final ParcelCoord? selectedParcel;
  final String? selectedCatalogueId;
  final CellCoord? bridgeStartCell;
  final List<CellCoord> roadPlanCells;
  final Set<CellCoord> fundableRoadCells;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFB5DCCF),
    );
    final bounds = _visibleCellBounds(size, scale, offset);
    final visibleCellCount =
        (bounds.right - bounds.left + 1) * (bounds.bottom - bounds.top + 1);
    var terrainStride = 1;
    while (visibleCellCount ~/ (terrainStride * terrainStride) > 24000) {
      terrainStride *= 2;
    }
    final terrainTop = floorDivide(bounds.top, terrainStride) * terrainStride;
    final terrainLeft = floorDivide(bounds.left, terrainStride) * terrainStride;
    for (var row = terrainTop; row <= bounds.bottom; row += terrainStride) {
      for (
        var column = terrainLeft;
        column <= bounds.right;
        column += terrainStride
      ) {
        final cell = CellCoord(column, row);
        final terrain = queries.terrainAt(cell);
        var anyWater = !terrain.isLand;
        var allOwned = queries.ownsCell(cell);
        if (terrainStride > 1) {
          for (var dy = 0; dy < terrainStride; dy++) {
            for (var dx = 0; dx < terrainStride; dx++) {
              if (dx == 0 && dy == 0) continue;
              final subCell = cell.offset(dx, dy);
              anyWater = anyWater || !queries.terrainAt(subCell).isLand;
              allOwned = allOwned && queries.ownsCell(subCell);
            }
          }
        }
        final roles = anyWater
            ? const ['terrain.water']
            : _terrainSpriteRoles(cell, terrain, queries);
        final blockCenter = _blockWorldCenter(cell, terrainStride);
        for (final role in roles) {
          final image = images[citysimAssetPath(role)];
          if (image == null) continue;
          _drawImageAtWorld(
            canvas,
            image,
            blockCenter,
            size,
            scale,
            offset,
            tileSpan: terrainStride,
          );
        }
        if (!allOwned) {
          _drawCellWash(
            canvas,
            blockCenter,
            terrainStride,
            size,
            scale,
            offset,
          );
        }
      }
    }

    _drawOwnedParcels(canvas, size, bounds);
    _drawRoads(canvas, size, queries, bounds);
    _drawBridges(canvas, size, bounds);
    _drawStructures(canvas, size, bounds);
    _drawPendingConstructions(canvas, size);
    _drawRoadPlan(canvas, size);
    _drawSelection(canvas, size, queries);
  }

  _CellBounds _visibleCellBounds(Size size, double cameraScale, Offset pan) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((point) => _screenToWorld(point, size, cameraScale, pan));
    final cells = corners.map(_nearestCell).toList();
    return _CellBounds(
      cells.map((cell) => cell.column).reduce(math.min) - 2,
      cells.map((cell) => cell.column).reduce(math.max) + 2,
      cells.map((cell) => cell.row).reduce(math.min) - 2,
      cells.map((cell) => cell.row).reduce(math.max) + 2,
    );
  }

  List<String> _terrainSpriteRoles(
    CellCoord cell,
    TerrainCell terrain,
    WorldQueries queries,
  ) {
    if (!terrain.isLand) return const ['terrain.water'];
    final style = terrain.groundStyle == GroundStyle.dirt ? 'dirt' : 'grass';
    bool water(int dx, int dy) =>
        !queries.terrainAt(cell.offset(dx, dy)).isLand;
    final waterNorth = water(0, -1);
    final waterEast = water(1, 0);
    final waterSouth = water(0, 1);
    final waterWest = water(-1, 0);
    final roles = <String>[
      switch (terrain.groundStyle) {
        GroundStyle.grass => 'terrain.grass',
        GroundStyle.grassPuddle => 'terrain.grass.puddle',
        GroundStyle.dirt => 'terrain.dirt',
        GroundStyle.asphalt => 'terrain.asphalt',
        GroundStyle.concrete => 'terrain.concrete',
      },
    ];

    // Cardinal water neighbours each need a water band along the shared
    // edge (quarter pieces). Two adjacent water neighbours share a vertex,
    // where the pack provides a pre-composed half-tile edge piece instead.
    // The pack's sprite families, verified from their pixels:
    // - quarter (water_NE/SE/SW/NW): water along one edge plus the two
    //   adjacent vertex wedges, for a single cardinal water neighbour;
    // - edge (wateredge_N/E/S/W): water across a full half tile, for two
    //   adjacent cardinal water neighbours;
    // - corner (watercorner_N/E/S/W): a small notch at one vertex, for
    //   water touching the tile only diagonally.
    var north = waterNorth;
    var east = waterEast;
    var south = waterSouth;
    var west = waterWest;
    if (north && east && south && west) {
      // A one-cell island keeps its grass centre visible.
      roles.addAll([
        'shore.$style.quarter.ne',
        'shore.$style.quarter.se',
        'shore.$style.quarter.sw',
        'shore.$style.quarter.nw',
      ]);
    } else {
      if (north && east) {
        roles.add('shore.$style.edge.e');
        north = false;
        east = false;
      } else if (east && south) {
        roles.add('shore.$style.edge.s');
        east = false;
        south = false;
      } else if (south && west) {
        roles.add('shore.$style.edge.w');
        south = false;
        west = false;
      } else if (west && north) {
        roles.add('shore.$style.edge.n');
        west = false;
        north = false;
      }
      if (north) roles.add('shore.$style.quarter.ne');
      if (east) roles.add('shore.$style.quarter.se');
      if (south) roles.add('shore.$style.quarter.sw');
      if (west) roles.add('shore.$style.quarter.nw');
    }

    // Water touching only a diagonal corner fills the shared vertex with a
    // notch, unless a cardinal quarter piece already covers that vertex.
    if (!waterNorth && !waterWest && water(-1, -1)) {
      roles.add('shore.$style.corner.n');
    }
    if (!waterNorth && !waterEast && water(1, -1)) {
      roles.add('shore.$style.corner.e');
    }
    if (!waterEast && !waterSouth && water(1, 1)) {
      roles.add('shore.$style.corner.s');
    }
    if (!waterSouth && !waterWest && water(-1, 1)) {
      roles.add('shore.$style.corner.w');
    }
    return roles;
  }

  void _drawOwnedParcels(Canvas canvas, Size size, _CellBounds bounds) {
    for (final parcel in queries.parcelsInBounds(
      left: bounds.left - state.parcelSize,
      right: bounds.right + state.parcelSize,
      top: bounds.top - state.parcelSize,
      bottom: bounds.bottom + state.parcelSize,
    )) {
      final origin = parcel.coord.origin(state.parcelSize);
      final last = origin.offset(state.parcelSize, state.parcelSize);
      final vertices = [
        origin,
        origin.offset(state.parcelSize, 0),
        last,
        origin.offset(0, state.parcelSize),
      ];
      final path = Path();
      for (var i = 0; i < vertices.length; i++) {
        final point = _worldToScreen(
          _cellWorldCorner(vertices[i]),
          size,
          scale,
          offset,
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x66537662)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawRoads(
    Canvas canvas,
    Size size,
    WorldQueries queries,
    _CellBounds bounds,
  ) {
    final nearbyRoads = queries.roadsInBounds(
      left: bounds.left - 8,
      right: bounds.right + 8,
      top: bounds.top - 8,
      bottom: bounds.bottom + 8,
    );
    final nearbyBridges = queries.bridgesInBounds(
      left: bounds.left - 8,
      right: bounds.right + 8,
      top: bounds.top - 8,
      bottom: bounds.bottom + 8,
    );
    final roadCells = <CellCoord>{
      ...nearbyRoads.map((road) => road.cell),
      for (final bridge in nearbyBridges) ...bridge.waterCells,
    };
    final entries =
        nearbyRoads.where((road) => _containsCell(bounds, road.cell)).toList()
          ..sort((a, b) => _depthCompare(a.cell, b.cell));
    for (final road in entries) {
      final image = road.style == RoadStyle.dirt
          ? images[citysimAssetPath('terrain.dirt')]
          : images[citysimAssetPath(
              roadSpriteRole(roadNeighborMask(road.cell, roadCells)),
            )];
      if (image != null) {
        _drawImageAtCell(canvas, image, road.cell, size, scale, offset);
      }
    }
  }

  void _drawBridges(Canvas canvas, Size size, _CellBounds bounds) {
    for (final bridge in queries.bridgesInBounds(
      left: bounds.left - 5,
      right: bounds.right + 5,
      top: bounds.top - 5,
      bottom: bounds.bottom + 5,
    )) {
      final bodyRole = bridgeBodyRole(bridge.nearBank, bridge.farBank);
      for (final cell in bridge.waterCells) {
        _drawTileRole(canvas, bodyRole, cell, size, scale, offset);
      }
      _drawTileRole(
        canvas,
        bridgeRampRole(bridge.nearBank, bridge.waterCells.first),
        bridge.nearBank,
        size,
        scale,
        offset,
      );
      _drawTileRole(
        canvas,
        bridgeRampRole(bridge.farBank, bridge.waterCells.last),
        bridge.farBank,
        size,
        scale,
        offset,
      );
    }
  }

  /// Draws a tile sprite at its natural aspect ratio with the sprite's
  /// ground diamond aligned to the cell's diamond. Standard 128×64 ground
  /// tiles land exactly where the old fixed 64×32 rect put them; taller
  /// sprites such as bridge decks and ramps keep their height instead of
  /// being squashed, with [SpriteDefinition.baseOffsetY] letting content
  /// such as support posts hang below the cell.
  void _drawTileRole(
    Canvas canvas,
    String role,
    CellCoord cell,
    Size size,
    double scale,
    Offset offset,
  ) {
    final image = images[citysimAssetPath(role)];
    if (image == null) return;
    final sprite = spriteManifest[role]!;
    final center = _worldToScreen(_cellWorldCenter(cell), size, scale, offset);
    final unit = (_logicalTileWidth * scale) / image.width;
    final width = image.width * unit;
    final height = image.height * unit;
    final southVertexY =
        center.dy +
        (_logicalTileHeight / 2) * scale +
        sprite.baseOffsetY * unit;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        center.dx - width / 2,
        southVertexY - height,
        width,
        height,
      ),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = const Color(0xFFFFFFFF),
    );
  }

  void _drawStructures(Canvas canvas, Size size, _CellBounds bounds) {
    final structures =
        queries.structuresInBounds(
          left: bounds.left - 5,
          right: bounds.right + 5,
          top: bounds.top - 5,
          bottom: bounds.bottom + 5,
        )..sort((a, b) {
          final aDepth = a.footprint
              .map((cell) => cell.column + cell.row)
              .reduce(math.max);
          final bDepth = b.footprint
              .map((cell) => cell.column + cell.row)
              .reduce(math.max);
          return aDepth.compareTo(bDepth);
        });
    for (final structure in structures) {
      final definition = structureById[structure.catalogueId]!;
      final image = images[citysimAssetPath(definition.assetRole)];
      if (image == null) continue;
      final rect = _worldRectToScreen(
        _structureRect(image, definition, structure),
        size,
        scale,
        offset,
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
  }

  void _drawPendingConstructions(Canvas canvas, Size size) {
    for (final job in state.constructions) {
      final cells = switch (job.kind) {
        WorldConstructionKind.structure => job.footprint,
        WorldConstructionKind.road => job.roadCells,
        WorldConstructionKind.bridge => [
          ...job.waterCells,
          job.nearBank!,
          job.farBank!,
        ],
      };
      for (final cell in cells) {
        if (job.kind == WorldConstructionKind.road &&
            state.roadsByCell.containsKey(cell)) {
          continue;
        }
        _drawCellOutline(
          canvas,
          _worldToScreen(_cellWorldCenter(cell), size, scale, offset),
          job.kind == WorldConstructionKind.road
              ? const Color(0xC1836D30)
              : const Color(0xB3765B31),
          scale,
          fill: job.kind == WorldConstructionKind.road
              ? const Color(0x30836D30)
              : const Color(0x28765B31),
        );
      }
      if (cells.isEmpty) continue;
      final cell = cells.first;
      final center = _worldToScreen(
        _cellWorldCenter(cell),
        size,
        scale,
        offset,
      );
      final progress = job.progress;
      final barWidth = 34 * scale;
      final bar = Rect.fromLTWH(
        center.dx - barWidth / 2,
        center.dy - 22 * scale,
        barWidth,
        4 * scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, Radius.circular(3 * scale)),
        Paint()..color = const Color(0xFFECE9DB),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, bar.top, bar.width * progress, bar.height),
          Radius.circular(3 * scale),
        ),
        Paint()..color = const Color(0xFF1D8065),
      );
    }
  }

  void _drawRoadPlan(Canvas canvas, Size size) {
    final hasRoadProject = state.constructions.any(
      (job) => job.kind == WorldConstructionKind.road,
    );
    if (!hasRoadProject) {
      for (final cell in roadPlanCells) {
        final center = _worldToScreen(
          _cellWorldCenter(cell),
          size,
          scale,
          offset,
        );
        _drawCellOutline(
          canvas,
          center,
          const Color(0xFF8B682A),
          scale,
          fill: const Color(0x447BBE92),
        );
      }
    }
    for (final cell in fundableRoadCells) {
      final center = _worldToScreen(
        _cellWorldCenter(cell),
        size,
        scale,
        offset,
      );
      _drawCellOutline(
        canvas,
        center,
        const Color(0xFF178064),
        scale,
        fill: const Color(0x3389DDB6),
      );
    }
  }

  void _drawSelection(Canvas canvas, Size size, WorldQueries queries) {
    if (selectedCell case final cell?) {
      final center = _worldToScreen(
        _cellWorldCenter(cell),
        size,
        scale,
        offset,
      );
      _drawCellOutline(
        canvas,
        center,
        const Color(0xFF1E6552),
        scale,
        fill: const Color(0x334BC69B),
      );
    }
    if (bridgeStartCell case final start?) {
      final center = _worldToScreen(
        _cellWorldCenter(start),
        size,
        scale,
        offset,
      );
      _drawCellOutline(canvas, center, const Color(0xFF8C512D), scale);
    }
    if (selectedParcel case final parcel?) {
      final owned = queries.ownsParcel(parcel);
      if (!owned) _drawParcelPreview(canvas, size, parcel);
    }
    if (selectedCatalogueId != null && selectedCell != null) {
      final definition = structureById[selectedCatalogueId];
      if (definition != null) {
        for (final cell in structureFootprint(definition, selectedCell!)) {
          final center = _worldToScreen(
            _cellWorldCenter(cell),
            size,
            scale,
            offset,
          );
          _drawCellOutline(
            canvas,
            center,
            const Color(0xFF367D63),
            scale,
            fill: const Color(0x334BC69B),
          );
        }
      }
    }
  }

  void _drawParcelPreview(Canvas canvas, Size size, ParcelCoord parcel) {
    final origin = parcel.origin(state.parcelSize);
    final vertices = [
      origin,
      origin.offset(state.parcelSize, 0),
      origin.offset(state.parcelSize, state.parcelSize),
      origin.offset(0, state.parcelSize),
    ];
    final path = Path();
    for (var i = 0; i < vertices.length; i++) {
      final point = _worldToScreen(
        _cellWorldCorner(vertices[i]),
        size,
        scale,
        offset,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF25745C)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ParcelWorldPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.scale != scale ||
      oldDelegate.offset != offset ||
      oldDelegate.selectedCell != selectedCell ||
      oldDelegate.selectedParcel != selectedParcel ||
      oldDelegate.selectedCatalogueId != selectedCatalogueId ||
      oldDelegate.bridgeStartCell != bridgeStartCell ||
      !listEquals(oldDelegate.roadPlanCells, roadPlanCells) ||
      !setEquals(oldDelegate.fundableRoadCells, fundableRoadCells);
}

class _CellBounds {
  const _CellBounds(this.left, this.right, this.top, this.bottom);

  final int left;
  final int right;
  final int top;
  final int bottom;
}

Rect _structureRect(
  ui.Image image,
  StructureDefinition definition,
  PlacedStructure structure,
) {
  final cells = structure.footprint;
  final centers = cells.map(_cellWorldCenter).toList();
  final anchorX =
      centers.map((point) => point.dx).reduce((a, b) => a + b) / centers.length;
  final bottomY =
      centers.map((point) => point.dy).reduce(math.max) +
      _logicalTileHeight / 2;
  final sprite = spriteManifest[definition.assetRole]!;
  final width = image.width * sprite.renderScale;
  final height = image.height * sprite.renderScale;
  return Rect.fromLTWH(
    anchorX - width * sprite.groundAnchorX,
    bottomY - height * sprite.groundAnchorY,
    width,
    height,
  );
}

void _drawImageAtCell(
  Canvas canvas,
  ui.Image image,
  CellCoord cell,
  Size size,
  double scale,
  Offset offset,
) {
  _drawImageAtWorld(canvas, image, _cellWorldCenter(cell), size, scale, offset);
}

void _drawImageAtWorld(
  Canvas canvas,
  ui.Image image,
  Offset worldCenter,
  Size size,
  double scale,
  Offset offset, {
  int tileSpan = 1,
}) {
  final center = _worldToScreen(worldCenter, size, scale, offset);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromCenter(
      center: center,
      width: _logicalTileWidth * tileSpan * scale,
      height: _logicalTileHeight * tileSpan * scale,
    ),
    Paint()..filterQuality = FilterQuality.medium,
  );
}

/// Unowned land is faded toward the map background. The wash is applied once
/// over the cell's fully composed layers, so a cell with layered shore
/// pieces fades exactly like plain ground instead of compounding
/// per-sprite transparency (which made shorelines look darker than the
/// surrounding grass).
void _drawCellWash(
  Canvas canvas,
  Offset worldCenter,
  int tileSpan,
  Size size,
  double scale,
  Offset offset,
) {
  final center = _worldToScreen(worldCenter, size, scale, offset);
  final halfWidth = _logicalTileWidth / 2 * tileSpan * scale;
  final halfHeight = _logicalTileHeight / 2 * tileSpan * scale;
  final path = Path()
    ..moveTo(center.dx, center.dy - halfHeight)
    ..lineTo(center.dx + halfWidth, center.dy)
    ..lineTo(center.dx, center.dy + halfHeight)
    ..lineTo(center.dx - halfWidth, center.dy)
    ..close();
  canvas.drawPath(path, Paint()..color = const Color(0x4FB5DCCF));
}

void _drawCellOutline(
  Canvas canvas,
  Offset center,
  Color stroke,
  double scale, {
  Color? fill,
}) {
  final width = _logicalTileWidth * scale;
  final height = _logicalTileHeight * scale;
  final path = Path()
    ..moveTo(center.dx, center.dy - height / 2)
    ..lineTo(center.dx + width / 2, center.dy)
    ..lineTo(center.dx, center.dy + height / 2)
    ..lineTo(center.dx - width / 2, center.dy)
    ..close();
  if (fill != null) {
    canvas.drawPath(path, Paint()..color = fill);
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = stroke
      ..strokeWidth = 1.5 * scale.clamp(0.7, 1.6)
      ..style = PaintingStyle.stroke,
  );
}

Offset _cellWorldCenter(CellCoord cell) => Offset(
  (cell.column - cell.row) * (_logicalTileWidth / 2),
  (cell.column + cell.row) * (_logicalTileHeight / 2),
);

/// Maps a lattice corner (the point where four cells meet) to world space.
/// Cell diamonds are centred on integer lattice points, so a parcel's outer
/// tips sit half a tile above the world position of its corner coordinates;
/// without this correction parcel outlines draw half a tile too low.
Offset _cellWorldCorner(CellCoord gridCorner) => Offset(
  (gridCorner.column - gridCorner.row) * (_logicalTileWidth / 2),
  (gridCorner.column + gridCorner.row) * (_logicalTileHeight / 2) -
      _logicalTileHeight / 2,
);

/// Centre of the diamond covered by a span×span block of cells. Cell
/// diamonds are centred on integer lattice points, so the block covers the
/// continuous square [c-0.5, c+span-0.5] × [r-0.5, r+span-0.5], whose centre
/// is at lattice (c+(span-1)/2, r+(span-1)/2). For span 1 this is exactly
/// the cell's centre; terrain must keep using this value so the ground grid
/// stays aligned with cell-centred overlays.
Offset _blockWorldCenter(CellCoord firstCell, int span) {
  final halfOffset = (span - 1) / 2.0;
  return Offset(
    (firstCell.column + halfOffset - firstCell.row - halfOffset) *
        (_logicalTileWidth / 2),
    (firstCell.column + halfOffset + firstCell.row + halfOffset) *
        (_logicalTileHeight / 2),
  );
}

Offset _worldToScreen(Offset point, Size size, double scale, Offset offset) =>
    size.center(Offset.zero) + offset + point * scale;

Offset _screenToWorld(Offset point, Size size, double scale, Offset offset) =>
    (point - size.center(Offset.zero) - offset) / scale;

CellCoord _nearestCell(Offset world) {
  final x = world.dx / (_logicalTileWidth / 2);
  final y = world.dy / (_logicalTileHeight / 2);
  return CellCoord(((x + y) / 2).round(), ((y - x) / 2).round());
}

Rect _worldRectToScreen(Rect rect, Size size, double scale, Offset offset) =>
    Rect.fromLTRB(
      size.width / 2 + offset.dx + rect.left * scale,
      size.height / 2 + offset.dy + rect.top * scale,
      size.width / 2 + offset.dx + rect.right * scale,
      size.height / 2 + offset.dy + rect.bottom * scale,
    );

int _depthCompare(CellCoord a, CellCoord b) =>
    (a.column + a.row).compareTo(b.column + b.row);

bool _containsCell(_CellBounds bounds, CellCoord cell) =>
    cell.column >= bounds.left &&
    cell.column <= bounds.right &&
    cell.row >= bounds.top &&
    cell.row <= bounds.bottom;
