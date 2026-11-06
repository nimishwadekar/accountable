import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'package:citysim/rendering/parcel_world_tuning.dart';
import 'package:citysim/rendering/sprite_picking.dart';

import '../content/content_bundle.dart';
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
    required this.content,
    required this.terrainProvider,
    required this.onCellTap,
    this.selectedCell,
    this.selectedParcel,
    this.selectedCatalogueId,
    this.bridgeStartCell,
    this.roadPlanCells = const [],
    this.fundableRoadCells = const {},
    this.cameraResetToken = 0,
    this.facingOverride,
    super.key,
  });

  final ParcelWorldState state;
  final ContentBundle content;
  final TerrainProvider terrainProvider;
  final void Function(CellCoord cell, String? structureId) onCellTap;
  final CellCoord? selectedCell;
  final ParcelCoord? selectedParcel;
  final String? selectedCatalogueId;
  final CellCoord? bridgeStartCell;
  final List<CellCoord> roadPlanCells;
  final Set<CellCoord> fundableRoadCells;
  final int cameraResetToken;

  /// Player's pre-placement door-side choice for the footprint preview,
  /// toggled by the floating swap button while roads touch both halves.
  final String? facingOverride;

  @override
  State<ParcelWorldView> createState() => _ParcelWorldViewState();
}

class _ParcelWorldViewState extends State<ParcelWorldView>
    with SingleTickerProviderStateMixin {
  final Map<String, ui.Image> _images = {};
  final Map<String, Future<ui.Image>> _imageRequests = {};

  /// Per-pixel picking masks for the decoded sprites, keyed by asset
  /// path. Filled alongside [_images]; taps read them synchronously.
  final Map<String, SpriteMask> _masks = {};

  /// How many cells a sprite's art can reach above its footprint — the
  /// candidate window for picking. Starts wide enough for the pack's
  /// tallest building and grows if taller art loads.
  int _spriteReachCells = 8;
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

  /// Drives water shimmer, vegetation sway, and ambient pedestrians. The
  /// clock is muted when the platform requests reduced motion; the ambient
  /// time scale comes from content so the editor can tune it live.
  final _AmbientClock _ambient = _AmbientClock();
  late final Ticker _ambientTicker = createTicker(
    (elapsed) => _ambient.tick(
      elapsed,
      timeScale: widget.content.ambience.ambientTimeScale,
    ),
  );
  final _TerrainLayerCache _terrainCache = _TerrainLayerCache();
  final _PedestrianSim _pedestrians = _PedestrianSim();

  @override
  void initState() {
    super.initState();
    _loading = _loadMissingImages();
    _ambientTicker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ambientTicker.muted =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
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
    _ambientTicker.dispose();
    _ambient.dispose();
    _terrainCache.dispose();
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
                math.exp(-event.scrollDelta.dy * cameraWheelZoomSensitivity),
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
                cameraMinZoom,
                cameraMaxZoom,
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
                  cameraMinZoom,
                  cameraMaxZoom,
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
                  content: widget.content,
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
                  facingOverride: widget.facingOverride,
                  ambient: _ambient,
                  terrainCache: _terrainCache,
                  pedestrians: _pedestrians,
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
    final hit = _hitTest(
      position,
      size,
      _scale,
      _offset,
      _queries,
      _images,
      _masks,
      _spriteReachCells,
      widget.content,
    );
    widget.onCellTap(hit.cell, hit.structureId);
  }

  /// Zooms by [factor] while keeping the world point under [focalPoint]
  /// anchored to that screen position.
  void _zoomAt(Offset focalPoint, Size size, double factor) {
    if (factor == 1.0) return;
    final anchor = _screenToWorld(focalPoint, size, _scale, _offset);
    final nextScale = (_scale * factor).clamp(cameraMinZoom, cameraMaxZoom);
    setState(() {
      _scale = nextScale;
      _offset = focalPoint - size.center(Offset.zero) - anchor * nextScale;
    });
  }

  Future<void> _loadMissingImages({bool retryFailed = false}) async {
    final content = widget.content;
    final roles = <String>{
      ...requiredSpriteRoles,
      for (final road in widget.state.roads)
        if (road.style == RoadStyle.asphalt)
          for (var mask = 0; mask < 16; mask++) roadSpriteRole(mask),
      // Placed structures and jobs render their rolled variant at its
      // chosen door side; the selected catalogue model needs every
      // variant's facings since either side can be chosen at placement.
      for (final structure in widget.state.structures)
        structure.assetRole ??
            content.structure(structure.catalogueId)!.assetRoles.first,
      for (final job in widget.state.constructions)
        if (job.kind == WorldConstructionKind.structure)
          job.assetRole ??
              content.structure(job.catalogueId!)!.assetRoles.first,
      if (widget.selectedCatalogueId != null)
        ...content.structure(widget.selectedCatalogueId!)!.assetRoles,
    };
    // Ambient pedestrian walk cycles have no manifest roles; they are
    // render-only art, so their asset paths join the set directly.
    final paths = {
      for (final role in roles) ...content.allAssetPaths(role),
      for (final character in ['a', 'b', 'c'])
        for (final direction in ['NE', 'NW', 'SE', 'SW'])
          for (final frame in [1, 2, 3, 4])
            'assets/characters/'
                'char_${character}_walk_${direction}_f0$frame.png',
    };

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
              unawaited(_loadMask(path, image));
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

  /// Builds the per-pixel picking mask for a decoded sprite and widens
  /// the picking window to cover the tallest art seen. Masks only feed
  /// taps, so they fill without triggering repaints.
  Future<void> _loadMask(String path, ui.Image image) async {
    final mask = await extractSpriteMask(image);
    if (!mounted || mask == null) return;
    _masks[path] = mask;
    final role = _spriteRoleForPath(path, widget.content);
    final sprite = role == null ? null : widget.content.sprite(role);
    if (sprite == null) return;
    final cells =
        (mask.height * sprite.renderScale / (_logicalTileHeight / 2)).ceil() +
        1;
    if (cells > _spriteReachCells) _spriteReachCells = cells;
  }

  Future<ui.Image> _loadImage(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    try {
      final frame = await codec.getNextFrame();
      final role = _spriteRoleForPath(path, widget.content);
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
String? _spriteRoleForPath(String path, ContentBundle content) {
  for (final entry in content.sprites.entries) {
    if (content.allAssetPaths(entry.key).contains(path)) return entry.key;
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
  Map<String, SpriteMask> masks,
  int reachCells,
  ContentBundle content,
) {
  final world = _screenToWorld(position, size, scale, offset);
  final cell = _nearestCell(world);
  // Candidates are every structure whose art could reach the tap,
  // ordered exactly as the painter draws them (back to front) and
  // walked front to back. The first sprite with an opaque pixel under
  // the tap wins; the ground diamond below is the fallback.
  final structures = queries.structuresInBounds(
    left: cell.column - reachCells,
    right: cell.column + reachCells,
    top: cell.row - reachCells,
    bottom: cell.row + reachCells,
  )..sort(_compareStructureDepth);
  for (final structure in structures.reversed) {
    final definition = content.structure(structure.catalogueId)!;
    final role = structure.assetRole ?? definition.assetRoles.first;
    final path = content.tryAssetPathFor(role, structure.facing);
    final image = images[path];
    if (image == null) continue;
    final screenRect = _worldRectToScreen(
      _structureRect(image, definition, structure, content),
      size,
      scale,
      offset,
    );
    if (!screenRect.contains(position)) continue;
    final mask = masks[path];
    if (mask == null) {
      // Mask still decoding: fall back to the rect until it lands.
      return _WorldHit(structure.origin, structure.id);
    }
    if (spritePixelHit(mask, screenRect, position)) {
      return _WorldHit(structure.origin, structure.id);
    }
  }
  return _WorldHit(cell, null);
}

/// The painter's depth for a structure — the deepest footprint cell —
/// matching the back-to-front order [_ParcelWorldPainter] draws, so
/// picking tests sprites in exactly the order they were painted.
int _structureDepth(PlacedStructure structure) =>
    structure.footprint.map((cell) => cell.column + cell.row).reduce(math.max);

int _compareStructureDepth(PlacedStructure a, PlacedStructure b) =>
    _structureDepth(a).compareTo(_structureDepth(b));

class _ParcelWorldPainter extends CustomPainter {
  _ParcelWorldPainter({
    required this.state,
    required this.content,
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
    required this.facingOverride,
    required this.ambient,
    required this.terrainCache,
    required this.pedestrians,
  }) : super(repaint: ambient);

  final ParcelWorldState state;
  final ContentBundle content;
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
  final String? facingOverride;
  final _AmbientClock ambient;
  final _TerrainLayerCache terrainCache;
  final _PedestrianSim pedestrians;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFB5DCCF),
    );
    final bounds = _visibleCellBounds(size, scale, offset);

    // Flat content — ground, roads, parcel outlines — only changes with
    // the world or the camera, so it is recorded once and replayed
    // while the ambient animations tick. Everything standing or
    // elevated (bridges included) plus the animated layers (water
    // shimmer, swaying vegetation, pedestrians) draw on top every
    // frame, depth-sorted, so raised geometry occludes correctly.
    final cacheKey = (state, scale, offset, size, images.length);
    if (terrainCache.key != cacheKey) {
      _recordTerrainLayer(terrainCache, cacheKey, size, bounds);
    }
    canvas.drawPicture(terrainCache.picture!);
    _paintWaterShimmer(canvas, terrainCache, ambient.seconds);
    _drawActors(canvas, size, bounds, ambient.seconds);
    _drawPendingConstructions(canvas, size);
    _drawRoadPlan(canvas, size);
    _drawSelection(canvas, size, queries);
  }

  void _recordTerrainLayer(
    _TerrainLayerCache cache,
    Object cacheKey,
    Size size,
    _CellBounds bounds,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);
    final visibleCellCount =
        (bounds.right - bounds.left + 1) * (bounds.bottom - bounds.top + 1);
    var terrainStride = 1;
    while (visibleCellCount ~/ (terrainStride * terrainStride) > 24000) {
      terrainStride *= 2;
    }
    final terrainTop = floorDivide(bounds.top, terrainStride) * terrainStride;
    final terrainLeft = floorDivide(bounds.left, terrainStride) * terrainStride;
    final shimmerBuckets = List<Path>.generate(
      content.ambience.waterShimmer.bands,
      (_) => Path(),
    );
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
          final path = content.tryAssetPath(role);
          if (path == null) continue;
          final image = images[path];
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
            content.ambience.unownedLandWash,
          );
        }
        if (anyWater && terrainStride == 1) {
          final center = _worldToScreen(blockCenter, size, scale, offset);
          final bucket =
              shimmerBuckets[(column - row) %
                  content.ambience.waterShimmer.bands];
          bucket
            ..moveTo(center.dx, center.dy - _logicalTileHeight / 2 * scale)
            ..lineTo(center.dx + _logicalTileWidth / 2 * scale, center.dy)
            ..lineTo(center.dx, center.dy + _logicalTileHeight / 2 * scale)
            ..lineTo(center.dx - _logicalTileWidth / 2 * scale, center.dy)
            ..close();
        }
      }
    }

    _drawOwnedParcels(canvas, size, bounds);
    _drawRoads(canvas, size, queries, bounds);
    cache.picture?.dispose();
    cache.picture = recorder.endRecording();
    cache.key = cacheKey;
    cache.shimmerPaths = shimmerBuckets;
  }

  /// A gentle travelling highlight over the water: diagonal bands of
  /// translucent white whose brightness rises and falls out of phase,
  /// reading as ripples moving across rivers, lakes, and the ocean.
  void _paintWaterShimmer(
    Canvas canvas,
    _TerrainLayerCache cache,
    double seconds,
  ) {
    final paths = cache.shimmerPaths;
    if (paths == null) return;
    final shimmer = content.ambience.waterShimmer;
    for (var bucket = 0; bucket < paths.length; bucket++) {
      final wave =
          0.5 +
          0.5 *
              math.sin(
                2 * math.pi * (seconds / shimmer.periodSeconds) -
                    bucket * 2 * math.pi / paths.length,
              );
      final alpha = wave * shimmer.maxOpacity;
      if (alpha < 0.006) continue;
      final tint = shimmer.colorRgb;
      canvas.drawPath(
        paths[bucket],
        Paint()
          ..color = Color.fromARGB(
            (alpha * 255).round(),
            tint.isNotEmpty ? tint[0] : 255,
            tint.length > 1 ? tint[1] : 255,
            tint.length > 2 ? tint[2] : 255,
          ),
      );
    }
  }

  /// Everything that stands on or rises above the ground — structures,
  /// bridge decks and ramps, ambient pedestrians — shares one
  /// back-to-front pass keyed by base-cell depth, so a raised bridge
  /// deck occludes whatever is behind it and is occluded by whatever
  /// is in front, exactly like any other standing object.
  void _drawActors(
    Canvas canvas,
    Size size,
    _CellBounds bounds,
    double seconds,
  ) {
    pedestrians.update(seconds, state, queries, content.ambience.pedestrians);
    final actors = <(double, void Function())>[];
    for (final structure in queries.structuresInBounds(
      left: bounds.left - 5,
      right: bounds.right + 5,
      top: bounds.top - 5,
      bottom: bounds.bottom + 5,
    )) {
      actors.add((
        _structureDepth(structure).toDouble(),
        () => _drawStructure(canvas, size, structure, seconds),
      ));
    }
    for (final bridge in queries.bridgesInBounds(
      left: bounds.left - 5,
      right: bounds.right + 5,
      top: bounds.top - 5,
      bottom: bounds.bottom + 5,
    )) {
      final bodyRole = bridgeBodyRole(bridge.nearBank, bridge.farBank);
      for (final cell in bridge.waterCells) {
        actors.add((
          (cell.column + cell.row).toDouble(),
          () => _drawTileRole(canvas, bodyRole, cell, size, scale, offset),
        ));
      }
      final nearRamp = bridgeRampRole(bridge.nearBank, bridge.waterCells.first);
      actors.add((
        (bridge.nearBank.column + bridge.nearBank.row).toDouble(),
        () => _drawTileRole(
          canvas,
          nearRamp,
          bridge.nearBank,
          size,
          scale,
          offset,
        ),
      ));
      final farRamp = bridgeRampRole(bridge.farBank, bridge.waterCells.last);
      actors.add((
        (bridge.farBank.column + bridge.farBank.row).toDouble(),
        () =>
            _drawTileRole(canvas, farRamp, bridge.farBank, size, scale, offset),
      ));
    }
    for (final pedestrian in pedestrians.list) {
      actors.add((
        pedestrian.depth,
        () => _drawPedestrian(canvas, size, pedestrian, seconds),
      ));
    }
    actors.sort((a, b) => a.$1.compareTo(b.$1));
    for (final actor in actors) {
      actor.$2();
    }
  }

  void _drawStructure(
    Canvas canvas,
    Size size,
    PlacedStructure structure,
    double seconds,
  ) {
    final definition = content.structure(structure.catalogueId)!;
    final role = structure.assetRole ?? definition.assetRoles.first;
    final image = images[content.tryAssetPathFor(role, structure.facing)];
    if (image == null) return;
    final sprite = content.sprite(role)!;
    final rect = _worldRectToScreen(
      _structureRect(image, definition, structure, content),
      size,
      scale,
      offset,
    );
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (!sprite.sways) {
      canvas.drawImageRect(image, source, rect, paint);
      return;
    }
    // Vegetation rocks a couple of degrees around its ground anchor; the
    // phase and speed derive from the tile so the motion is stable across
    // reloads and neighbouring plants move out of step.
    final origin = structure.origin;
    final phase = origin.column * 1.7 + origin.row * 2.3;
    final sway = content.ambience.vegetationSway;
    final frequency =
        sway.baseFrequency +
        ((origin.column * 3 + origin.row * 7) % sway.frequencySteps) *
            sway.frequencyStep;
    final angle = sway.maxAngleRadians * math.sin(seconds * frequency + phase);
    final pivot = Offset(
      rect.left + rect.width * sprite.groundAnchorX,
      rect.top + rect.height * sprite.groundAnchorY,
    );
    canvas
      ..save()
      ..translate(pivot.dx, pivot.dy)
      ..rotate(angle)
      ..translate(-pivot.dx, -pivot.dy)
      ..drawImageRect(image, source, rect, paint)
      ..restore();
  }

  void _drawPedestrian(
    Canvas canvas,
    Size size,
    _Pedestrian pedestrian,
    double seconds,
  ) {
    final world = pedestrian.worldPosition();
    final screen = _worldToScreen(world, size, scale, offset);
    if (screen.dx < -40 ||
        screen.dx > size.width + 40 ||
        screen.dy < -60 ||
        screen.dy > size.height + 60) {
      return;
    }
    final image =
        images[pedestrian.assetPath(
          seconds,
          content.ambience.pedestrians.walkFrameRate,
        )];
    if (image == null) return;
    final unit = 0.5 * scale * content.ambience.pedestrians.spriteScale;
    final width = image.width * unit;
    final height = image.height * unit;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        screen.dx - width / 2,
        screen.dy + 2 * scale - height,
        width,
        height,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
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
      final path = road.style == RoadStyle.dirt
          ? content.tryAssetPath('terrain.dirt')
          : content.tryAssetPath(
              roadSpriteRole(roadNeighborMask(road.cell, roadCells)),
            );
      final image = path == null ? null : images[path];
      if (image != null) {
        _drawImageAtCell(canvas, image, road.cell, size, scale, offset);
      }
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
    final path = content.tryAssetPath(role);
    final image = path == null ? null : images[path];
    if (image == null) return;
    final sprite = content.sprite(role)!;
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
      if (job.kind == WorldConstructionKind.structure && job.facing != null) {
        _drawFacingArrow(canvas, size, job.footprint, job.facing!);
      }
    }
  }

  /// Door-direction arrow shown while a building plan is unfinished: a
  /// bold overlay-style arrow bobbing above the site, pointing toward the
  /// screen half whose facade carries the door. Freezes along with the
  /// ambient clock under reduced motion.
  void _drawFacingArrow(
    Canvas canvas,
    Size size,
    List<CellCoord> footprint,
    String facing,
  ) {
    if (footprint.isEmpty) return;
    final centers = footprint.map(_cellWorldCenter).toList();
    final centerX =
        centers.map((point) => point.dx).reduce((a, b) => a + b) /
        centers.length;
    final topY =
        centers.map((point) => point.dy).reduce(math.min) -
        _logicalTileHeight / 2;
    final bob = math.sin(ambient.seconds * 2 * math.pi / 1.7) * 3.0;
    final anchor = _worldToScreen(
      Offset(centerX, topY),
      size,
      scale,
      offset,
    ).translate(0, -17 * scale + bob * scale);
    // The door sits on the facade facing the road: right-facing doors are
    // on the grid-east wall (screen south-east), left-facing ones on the
    // grid-south wall (screen south-west).
    final angle = facing == 'right' ? math.atan2(1, 2) : math.atan2(1, -2);
    _drawArrowGlyph(canvas, anchor, angle);
  }

  /// Chunky cartoon arrow in the map-overlay palette (cream fill, deep
  /// green outline, soft shadow) so it reads as game art, not a debug
  /// marker.
  void _drawArrowGlyph(Canvas canvas, Offset anchor, double angle) {
    final s = scale.clamp(0.6, 1.4);
    final length = 30 * s;
    final shaft = 5.5 * s;
    final head = 11 * s;
    final headLength = 13 * s;
    final base = length / 2 - headLength;
    final path = Path()
      ..moveTo(-length / 2, -shaft)
      ..lineTo(base, -shaft)
      ..lineTo(base, -head)
      ..lineTo(length / 2, 0)
      ..lineTo(base, head)
      ..lineTo(base, shaft)
      ..lineTo(-length / 2, shaft)
      ..close();
    canvas
      ..save()
      ..translate(anchor.dx, anchor.dy)
      ..rotate(angle);
    canvas.drawPath(
      path.shift(Offset(0, 2.5 * s)),
      Paint()..color = const Color(0x33162B22),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFF6F1DE));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF1E6552)
        ..strokeWidth = 2.2 * s
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
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
      // Selection highlights everything at the tapped cell: a
      // structure's whole footprint (with its sprite washed in the
      // selection colour), a bridge's full crossing between banks, or
      // the bare tile.
      final structure = queries.structuresByCell[cell];
      final bridgeCells = structure == null ? _bridgeCellsAt(cell) : null;
      final cells = structure?.footprint ?? bridgeCells ?? [cell];
      for (final selected in cells) {
        final center = _worldToScreen(
          _cellWorldCenter(selected),
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
      if (structure != null) {
        _tintStructureSprite(canvas, size, structure);
      }
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
      final definition = content.structure(selectedCatalogueId!);
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
        // Pre-placement preview: show the door side this plan would get,
        // using the same roll and road-side rule placement will apply.
        // The player's preview choice wins while roads touch both halves.
        if (definition.kind == StructureKind.building) {
          final role =
              definition.assetRoles[(state.seed + state.nextEntityNumber) %
                  definition.assetRoles.length];
          final sprite = content.sprite(role);
          if (sprite != null && sprite.hasFacings) {
            final footprint = structureFootprint(definition, selectedCell!);
            final sides = queries.adjacentDoorSides(footprint);
            _drawFacingArrow(
              canvas,
              size,
              footprint,
              sides.length < 2
                  ? doorFacingForSides(sides)
                  : (facingOverride ?? doorFacingForSides(sides)),
            );
          }
        }
      }
    }
  }

  /// The full crossing — every water cell plus both banks — when the
  /// cell belongs to a bridge. Bank roads are shared with the road
  /// network, so tapping a bank stays a plain road tile; only the
  /// bridge's own deck cells select the crossing.
  List<CellCoord>? _bridgeCellsAt(CellCoord cell) {
    for (final bridge in state.bridges) {
      if (bridge.waterCells.contains(cell)) {
        return [...bridge.waterCells, bridge.nearBank, bridge.farBank];
      }
    }
    return null;
  }

  /// Washes the selected structure's own sprite in the selection
  /// colour, so the object itself reads as picked — not just the
  /// footprint diamonds beneath it.
  void _tintStructureSprite(
    Canvas canvas,
    Size size,
    PlacedStructure structure,
  ) {
    final definition = content.structure(structure.catalogueId)!;
    final role = structure.assetRole ?? definition.assetRoles.first;
    final image = images[content.tryAssetPathFor(role, structure.facing)];
    if (image == null) return;
    final screenRect = _worldRectToScreen(
      _structureRect(image, definition, structure, content),
      size,
      scale,
      offset,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      screenRect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = const ColorFilter.mode(
          Color(0x664BC69B),
          BlendMode.srcATop,
        ),
    );
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
      oldDelegate.facingOverride != facingOverride ||
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
  ContentBundle content,
) {
  final cells = structure.footprint;
  final centers = cells.map(_cellWorldCenter).toList();
  final anchorX =
      centers.map((point) => point.dx).reduce((a, b) => a + b) / centers.length;
  final bottomY =
      centers.map((point) => point.dy).reduce(math.max) +
      _logicalTileHeight / 2;
  final sprite = content.sprite(
    structure.assetRole ?? definition.assetRoles.first,
  )!;
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
  UnownedLandWashContent wash,
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
  final tint = wash.colorRgb;
  canvas.drawPath(
    path,
    Paint()
      ..color = Color.fromARGB(
        wash.alpha.clamp(0, 255),
        tint.isNotEmpty ? tint[0] : 255,
        tint.length > 1 ? tint[1] : 255,
        tint.length > 2 ? tint[2] : 255,
      ),
  );
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

/// How large ambient pedestrians render relative to the standard
/// 128×64 tile scale. A 24×32 character frame at this size reads as a
/// person roughly two-thirds of a small building's height.

/// Elapsed-time source for ambient rendering. A raw ticker rather than an
/// [AnimationController] so the value is plainly "seconds since startup",
/// with no repeating wrap that would jump animation phases.
///
/// The ticker callback receives cumulative time since the ticker started,
/// so the elapsed value is *assigned*, never accumulated — accumulating it
/// would advance ambient time once per frame and couple animation speed to
/// the frame rate. The content-provided time scale converts real seconds
/// to animation seconds in one place.
class _AmbientClock extends ChangeNotifier {
  double _seconds = 0;

  double get seconds => _seconds;

  void tick(Duration elapsed, {double timeScale = 1.0}) {
    _seconds =
        elapsed.inMicroseconds / Duration.microsecondsPerSecond * timeScale;
    notifyListeners();
  }
}

/// Records the camera- and world-dependent ground layers (terrain, shores,
/// roads, bridges) plus the prebuilt water-shimmer band paths. Rebuilt
/// whenever any cache-key input changes; replayed every animation frame.
class _TerrainLayerCache {
  ui.Picture? picture;
  List<Path>? shimmerPaths;
  Object? key;

  void dispose() {
    picture?.dispose();
    picture = null;
    shimmerPaths = null;
    key = null;
  }
}

/// Render-only pedestrians that wander along connected roads. They are
/// deliberately excluded from world state and saves: ambience never
/// affects gameplay, and a reload simply repopulates the streets.
class _PedestrianSim {
  final List<_Pedestrian> list = [];
  int _roadCount = -1;
  double _lastSeconds = 0;

  void update(
    double seconds,
    ParcelWorldState state,
    WorldQueries queries,
    PedestrianContent pedestrians,
  ) {
    final roadCells = <CellCoord>{
      for (final road in state.roads)
        if (queries.connectedRoadCells.contains(road.cell)) road.cell,
    };
    if (roadCells.length != _roadCount) {
      _roadCount = roadCells.length;
      _lastSeconds = seconds;
      _reconcile(roadCells, state.seed, pedestrians);
      return;
    }
    final dt = (seconds - _lastSeconds).clamp(0.0, 0.25);
    _lastSeconds = seconds;
    if (dt <= 0) return;
    final random = math.Random();
    for (final pedestrian in list) {
      pedestrian.advance(dt, roadCells, random);
    }
  }

  void _reconcile(
    Set<CellCoord> roadCells,
    int seed,
    PedestrianContent pedestrians,
  ) {
    if (roadCells.length < 2) {
      list.clear();
      return;
    }
    final target = (roadCells.length / pedestrians.roadCellsPerPerson)
        .floor()
        .clamp(0, pedestrians.maxCount);
    final random = math.Random(seed + roadCells.length);
    final cells = roadCells.toList()..shuffle(random);
    while (list.length > target) {
      list.removeLast();
    }
    var cursor = 0;
    while (list.length < target && cells.isNotEmpty) {
      final from = cells[cursor % cells.length];
      cursor++;
      final next = _pickNext(from, null, roadCells, random);
      if (next == null) continue;
      list.add(
        _Pedestrian(
          character: 'abc'[random.nextInt(3)],
          from: from,
          to: next,
          speed:
              pedestrians.speedMin +
              random.nextDouble() * pedestrians.speedRange,
          phase: random.nextDouble() * 4,
          offset: Offset(
            (random.nextDouble() - 0.5) * pedestrians.lateralWanderX,
            (random.nextDouble() - 0.5) * pedestrians.lateralWanderY,
          ),
        ),
      );
    }
  }
}

CellCoord? _pickNext(
  CellCoord cell,
  CellCoord? previous,
  Set<CellCoord> roadCells,
  math.Random random,
) {
  var options = cell.neighbors
      .where((next) => roadCells.contains(next) && next != previous)
      .toList();
  if (options.isEmpty) {
    options = cell.neighbors.where(roadCells.contains).toList();
  }
  if (options.isEmpty) return null;
  return options[random.nextInt(options.length)];
}

class _Pedestrian {
  _Pedestrian({
    required this.character,
    required this.from,
    required this.to,
    required this.speed,
    required this.phase,
    required this.offset,
  });

  final String character;
  CellCoord from;
  CellCoord to;
  final double speed;
  final double phase;
  final Offset offset;
  double progress = 0;

  void advance(double dt, Set<CellCoord> roadCells, math.Random random) {
    progress += speed * dt;
    while (progress >= 1) {
      final previous = from;
      from = to;
      final next = _pickNext(from, previous, roadCells, random);
      if (next == null) {
        progress = 0;
        return;
      }
      to = next;
      progress -= 1;
    }
  }

  /// Pack walk-cycle frames are named for the isometric compass, which maps
  /// onto grid directions: north (row −1) is screen NE, east (col +1) is
  /// SE, south (row +1) is SW, and west (col −1) is NW.
  String get _direction {
    final dx = to.column - from.column;
    final dy = to.row - from.row;
    if (dy < 0) return 'NE';
    if (dx > 0) return 'SE';
    if (dy > 0) return 'SW';
    return 'NW';
  }

  String assetPath(double seconds, double walkFrameRate) {
    final frame = ((seconds * walkFrameRate + phase).floor() % 4) + 1;
    return 'assets/characters/'
        'char_${character}_walk_${_direction}_f0$frame.png';
  }

  Offset worldPosition() {
    final a = _cellWorldCenter(from);
    final b = _cellWorldCenter(to);
    return Offset(
          a.dx + (b.dx - a.dx) * progress,
          a.dy + (b.dy - a.dy) * progress,
        ) +
        offset;
  }

  double get depth =>
      from.column +
      from.row +
      ((to.column - from.column) + (to.row - from.row)) * progress;
}
