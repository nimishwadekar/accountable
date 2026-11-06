import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'package:citysim/rendering/parcel_world_tuning.dart';
import 'package:citysim/rendering/perf_probe.dart';
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

/// Debug/test switch: draw every terrain chunk by replaying its
/// world-space recording instead of its rasterized texture. Tests use
/// this to prove both draw paths place content at identical pixels.
@visibleForTesting
bool debugDrawChunksViaPictures = false;

/// Debug/test switch: draw the water shimmer with the merged-path
/// fallback instead of the fragment shader. Tests use this to prove
/// both shimmer paths produce identical pixels.
@visibleForTesting
bool debugDrawShimmerViaPaths = false;

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
    this.structurePicking = true,
    this.dimStructures = false,
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

  /// Whether taps pick standing structures by their sprites. Only the
  /// inspect tool wants that; every other tool targets the tapped cell
  /// directly, so a road planned over a roof lands on the roof's cell
  /// rather than the building's origin.
  final bool structurePicking;

  /// Whether standing structures draw translucent (x-ray), used by the
  /// road and bridge tools so fundable tiles and banks behind
  /// buildings stay visible.
  final bool dimStructures;

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
  final _TerrainChunkCache _terrainCache = _TerrainChunkCache();

  /// Display pixel ratio, captured per build so chunk textures
  /// rasterize at the display's real density.
  double _pixelRatio = 1.0;

  /// Water-shimmer fragment program; null until it loads or when the
  /// platform cannot run it, in which case the shimmer falls back to
  /// merged path drawing.
  ui.FragmentProgram? _shimmerProgram;
  final _PedestrianSim _pedestrians = _PedestrianSim();

  @override
  void initState() {
    super.initState();
    _loading = _loadMissingImages();
    _ambientTicker.start();
    _loadShimmerShader();
  }

  Future<void> _loadShimmerShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/water_shimmer.frag',
      );
      if (!mounted) return;
      setState(() => _shimmerProgram = program);
    } catch (_) {
      // Shimmer stays on the merged-path fallback.
    }
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
      _pixelRatio = View.of(context).devicePixelRatio;
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
                  dimStructures: widget.dimStructures,
                  ambient: _ambient,
                  terrainCache: _terrainCache,
                  pixelRatio: _pixelRatio,
                  shimmerProgram: _shimmerProgram,
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

  /// Click cycling: a repeated tap near the previous one (within a
  /// quarter tile, a couple of seconds) advances to the next target in
  /// the front-to-back chain — the front structure, what it hides,
  /// then the ground cell — and wraps around.
  static const _cycleTapWorldRadius = 16.0;
  static const _cycleTapWindowMillis = 2500;

  Offset? _lastTapWorld;
  int _lastTapAtMillis = 0;
  int _tapCycleIndex = 0;

  void _dispatchTap(Offset position, Size size) {
    final world = _screenToWorld(position, size, _scale, _offset);
    final structureHits = widget.structurePicking
        ? _hitStructures(
            position,
            size,
            _scale,
            _offset,
            _queries,
            _images,
            _masks,
            _spriteReachCells,
            widget.content,
          )
        : const <_WorldHit>[];
    // The chain every tap walks: pixel-hit structures front to back,
    // then the ground diamond under the tap.
    final chain = [...structureHits, _WorldHit(_nearestCell(world), null)];

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastWorld = _lastTapWorld;
    final sameSpot =
        lastWorld != null &&
        (world - lastWorld).distance < _cycleTapWorldRadius &&
        now - _lastTapAtMillis < _cycleTapWindowMillis;
    final index = sameSpot ? (_tapCycleIndex + 1) % chain.length : 0;
    _lastTapWorld = world;
    _lastTapAtMillis = now;
    _tapCycleIndex = index;

    final hit = chain[index];
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

/// Every structure hit by a tap, in front-to-back painter order —
/// each entry is one sprite with an opaque pixel under the tap point.
List<_WorldHit> _hitStructures(
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
  // walked front to back. Every sprite with an opaque pixel under the
  // tap joins the result in that order, so repeated taps can cycle
  // through what the front one hides; the ground diamond below is the
  // caller's fallback.
  final structures = queries.structuresInBounds(
    left: cell.column - reachCells,
    right: cell.column + reachCells,
    top: cell.row - reachCells,
    bottom: cell.row + reachCells,
  )..sort(_compareStructureDepth);
  final hits = <_WorldHit>[];
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
      hits.add(_WorldHit(structure.origin, structure.id));
      continue;
    }
    if (spritePixelHit(mask, screenRect, position)) {
      hits.add(_WorldHit(structure.origin, structure.id));
    }
  }
  return hits;
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
    required this.dimStructures,
    required this.ambient,
    required this.terrainCache,
    required this.pixelRatio,
    required this.shimmerProgram,
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

  /// Whether standing structures draw translucent (x-ray) so tiles and
  /// banks behind them stay visible while the road and bridge tools
  /// are active.
  final bool dimStructures;
  final _AmbientClock ambient;
  final _TerrainChunkCache terrainCache;
  final double pixelRatio;
  final ui.FragmentProgram? shimmerProgram;
  final _PedestrianSim pedestrians;

  @override
  void paint(Canvas canvas, Size size) {
    ParcelWorldProbe.beginFrame(scale);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFB5DCCF),
    );
    final bounds = _visibleCellBounds(size, scale, offset);
    final viewport = _ViewportGeometry(size, scale, offset);
    ParcelWorldProbe.noteBoundsCells(
      (bounds.right - bounds.left + 1) * (bounds.bottom - bounds.top + 1),
    );
    ParcelWorldProbe.noteOnscreenCells(_visibleCellCount(bounds, viewport));

    // The flat layer — terrain, wash, roads, parcel outlines — is
    // cached as parcel-sized world-space chunks, rasterized to
    // textures and drawn as one quad each. Chunks are camera-
    // independent, so panning and zooming replay cached textures
    // instead of re-recording; only world or sprite changes (or
    // entering unseen areas) record. Everything standing or elevated
    // (bridges included) plus the animated layers (water shimmer,
    // swaying vegetation, pedestrians) draw on top every frame,
    // depth-sorted, so raised geometry occludes correctly.
    ParcelWorldProbe.beginTerrain();
    _drawTerrainChunks(canvas, size, bounds, viewport);
    ParcelWorldProbe.endTerrain();
    _drawActors(canvas, size, bounds, ambient.seconds);
    _drawPendingConstructions(canvas, size);
    _drawRoadPlan(canvas, size);
    _drawSelection(canvas, size, queries);
    ParcelWorldProbe.endFrame();
    ParcelWorldProbe.paintHud(canvas, size);
  }

  /// Draws the visible terrain chunks and the water shimmer. Chunks
  /// draw from rasterized textures; a chunk without a fresh texture
  /// falls back to replaying its world-space recording under the
  /// camera transform, which is slower but always correct.
  void _drawTerrainChunks(
    Canvas canvas,
    Size size,
    _CellBounds bounds,
    _ViewportGeometry viewport,
  ) {
    terrainCache.resetFor(state, images.length);
    terrainCache.setTextureFactor(_textureFactorFor(scale, pixelRatio));
    terrainCache.evictDistant();
    final drawn = <_TerrainChunk>[];
    var rasterBudget = 12;
    for (final coord in _visibleChunkCoords(bounds, viewport)) {
      var chunk = terrainCache.chunks[coord];
      if (chunk == null || chunk.generation != terrainCache.generation) {
        chunk = _recordChunk(coord);
      }
      chunk.lastUsed = terrainCache.nextStamp();
      drawn.add(chunk);
      if (!chunk.imageMatchesBucket && rasterBudget > 0) {
        rasterBudget--;
        _rasterizeChunk(chunk);
      }
    }
    for (final chunk in drawn) {
      ParcelWorldProbe.countChunkDraw();
      ParcelWorldProbe.noteDrawnCells(state.parcelSize * state.parcelSize);
      final image = chunk.image;
      if (!debugDrawChunksViaPictures && image != null) {
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          _worldRectToScreen(chunk.worldRect, size, scale, offset),
          Paint()..filterQuality = FilterQuality.medium,
        );
      } else if (chunk.picture case final picture?) {
        _drawWorldPicture(canvas, size, chunk.worldRect, picture);
      }
    }
    _paintWaterShimmer(canvas, size, drawn);
  }

  /// Replays a world-space recording through the camera transform.
  /// The recording's origin sits at [worldRect]'s top-left, so the
  /// replay adds that origin back after applying the camera: picture
  /// point p (world w minus the rect origin) must land at
  /// `center + offset + w * scale`.
  void _drawWorldPicture(
    Canvas canvas,
    Size size,
    Rect worldRect,
    ui.Picture picture,
  ) {
    canvas
      ..save()
      ..translate(size.width / 2 + offset.dx, size.height / 2 + offset.dy)
      ..scale(scale)
      ..translate(worldRect.left, worldRect.top)
      ..drawPicture(picture)
      ..restore();
  }

  /// Parcel chunks that can hold any visible cell: the lattice
  /// bounding box at parcel granularity, filtered by the exact
  /// per-row visibility windows.
  List<ParcelCoord> _visibleChunkCoords(
    _CellBounds bounds,
    _ViewportGeometry viewport,
  ) {
    final parcelSize = state.parcelSize;
    final result = <ParcelCoord>[];
    for (
      var py = floorDivide(bounds.top, parcelSize);
      py <= floorDivide(bounds.bottom, parcelSize);
      py++
    ) {
      for (
        var px = floorDivide(bounds.left, parcelSize);
        px <= floorDivide(bounds.right, parcelSize);
        px++
      ) {
        final coord = ParcelCoord(px, py);
        if (_chunkVisible(coord, parcelSize, viewport)) result.add(coord);
      }
    }
    return result;
  }

  bool _chunkVisible(
    ParcelCoord coord,
    int parcelSize,
    _ViewportGeometry viewport,
  ) {
    final firstColumn = coord.x * parcelSize;
    final lastColumn = firstColumn + parcelSize - 1;
    for (
      var row = coord.y * parcelSize;
      row < coord.y * parcelSize + parcelSize;
      row++
    ) {
      final window = viewport.columnWindow(row);
      if (window == null) continue;
      if (window.$1 <= lastColumn && window.$2 >= firstColumn) return true;
    }
    return false;
  }

  /// Exact count of cells whose diamonds intersect the viewport.
  int _visibleCellCount(_CellBounds bounds, _ViewportGeometry viewport) {
    var count = 0;
    for (var row = bounds.top; row <= bounds.bottom; row++) {
      final window = viewport.columnWindow(row);
      if (window != null) count += window.$2 - window.$1 + 1;
    }
    return count;
  }

  /// Texture pixels per logical pixel for chunk rasterization. The
  /// pack's art is 2x logical density, so factor 2 preserves full art
  /// detail; smaller factors trade detail for memory when the display
  /// is zoomed out.
  double _textureFactorFor(double cameraScale, double pixelRatio) {
    final density = cameraScale * pixelRatio;
    if (density < 0.75) return 0.5;
    if (density < 1.5) return 1;
    return 2;
  }

  /// Records one parcel chunk in world space: terrain, unowned wash,
  /// roads, shimmer contours, and — separately, so it can draw above
  /// neighbouring chunks — the owned-parcel outline.
  _TerrainChunk _recordChunk(ParcelCoord coord) {
    final parcelSize = state.parcelSize;
    final worldRect = _chunkWorldRect(coord, parcelSize);
    final chunk = _TerrainChunk(coord, worldRect)
      ..generation = terrainCache.generation;
    terrainCache.chunks[coord] = chunk;
    ParcelWorldProbe.countChunkRecord();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & worldRect.size);
    canvas.translate(-worldRect.left, -worldRect.top);

    final shimmer = content.ambience.waterShimmer;
    final shimmerBuckets = List<Path>.generate(shimmer.bands, (_) => Path());
    final shimmerCounts = List<int>.filled(shimmer.bands, 0);

    // Road neighbour masks read the road set around the chunk.
    final roadCells = <CellCoord>{
      ...queries.roadsByCell.keys,
      for (final bridge in state.bridges) ...bridge.waterCells,
    };

    for (final cell in coord.cells(parcelSize)) {
      final terrain = queries.terrainAt(cell);
      final anyWater = !terrain.isLand;
      final center = _cellWorldCenter(cell);
      final roles = anyWater
          ? const ['terrain.water']
          : _terrainSpriteRoles(cell, terrain, queries);
      for (final role in roles) {
        final path = content.tryAssetPath(role);
        if (path == null) continue;
        final image = images[path];
        if (image == null) continue;
        ParcelWorldProbe.countTerrain();
        _drawImageAtWorldCenter(canvas, image, center);
      }
      if (!queries.ownsCell(cell)) {
        ParcelWorldProbe.countWash();
        _drawWorldCellWash(canvas, center, content.ambience.unownedLandWash);
      }
      if (anyWater) {
        final band = (cell.column - cell.row) % shimmer.bands;
        shimmerCounts[band]++;
        final halfWidth = _logicalTileWidth / 2;
        final halfHeight = _logicalTileHeight / 2;
        shimmerBuckets[band]
          ..moveTo(center.dx, center.dy - halfHeight)
          ..lineTo(center.dx + halfWidth, center.dy)
          ..lineTo(center.dx, center.dy + halfHeight)
          ..lineTo(center.dx - halfWidth, center.dy)
          ..close();
      }
      final road = queries.roadsByCell[cell];
      if (road != null) {
        final path = road.style == RoadStyle.dirt
            ? content.tryAssetPath('terrain.dirt')
            : content.tryAssetPath(
                roadSpriteRole(roadNeighborMask(cell, roadCells)),
              );
        final image = path == null ? null : images[path];
        if (image != null) {
          ParcelWorldProbe.countRoad();
          _drawImageAtWorldCenter(canvas, image, center);
        }
      }
    }

    // The owned-parcel outline draws after the chunk's cells. Its
    // stroke bleeds ~0.6 world px into the neighbouring chunk, which
    // the margin covers; a neighbour's tiles may paint over that
    // outer half, which reads fine at 1.2 px.
    if (queries.ownsParcel(coord)) {
      ParcelWorldProbe.countOutline();
      _drawWorldParcelOutline(canvas, coord, parcelSize);
    }

    chunk.picture = recorder.endRecording();
    chunk.shimmerPaths = shimmerBuckets;
    chunk.shimmerCounts = shimmerCounts;

    // The shimmer shader's coverage mask: the same water diamonds as
    // one filled shape.
    if (shimmerCounts.any((count) => count > 0)) {
      final maskRecorder = ui.PictureRecorder();
      final maskCanvas = Canvas(maskRecorder, Offset.zero & worldRect.size);
      maskCanvas.translate(-worldRect.left, -worldRect.top);
      final white = Paint()..color = const Color(0xFFFFFFFF);
      for (final path in shimmerBuckets) {
        maskCanvas.drawPath(path, white);
      }
      chunk.waterMaskPicture = maskRecorder.endRecording();
    }
    return chunk;
  }

  /// Rasterizes a chunk's recording into a texture at the cache's
  /// current texture factor. The recording is wrapped in a scaling
  /// picture so one world-space recording serves every factor.
  void _rasterizeChunk(_TerrainChunk chunk) {
    final picture = chunk.picture;
    if (picture == null) {
      chunk.imageMatchesBucket = true;
      return;
    }
    final factor = terrainCache.textureFactor;
    final width = (chunk.worldRect.width * factor).ceil();
    final height = (chunk.worldRect.height * factor).ceil();
    try {
      final wrapper = ui.PictureRecorder();
      final canvas = Canvas(
        wrapper,
        Offset.zero & Size(width.toDouble(), height.toDouble()),
      );
      canvas
        ..scale(factor)
        ..drawPicture(picture);
      final wrapperPicture = wrapper.endRecording();
      final oldImage = chunk.image;
      final oldWrapper = chunk.rasterWrapper;
      chunk.image = wrapperPicture.toImageSync(width, height);
      chunk.rasterWrapper = wrapperPicture;
      chunk.imageMatchesBucket = true;
      oldImage?.dispose();
      oldWrapper?.dispose();
      if (chunk.waterMaskPicture case final maskPicture?) {
        final maskWrapper = ui.PictureRecorder();
        final maskCanvas = Canvas(
          maskWrapper,
          Offset.zero & Size(width.toDouble(), height.toDouble()),
        );
        maskCanvas
          ..scale(factor)
          ..drawPicture(maskPicture);
        final maskWrapperPicture = maskWrapper.endRecording();
        final oldMask = chunk.waterMask;
        final oldMaskWrapper = chunk.waterMaskWrapper;
        chunk.waterMask = maskWrapperPicture.toImageSync(width, height);
        chunk.waterMaskWrapper = maskWrapperPicture;
        oldMask?.dispose();
        oldMaskWrapper?.dispose();
      }
    } catch (_) {
      // Rasterization unavailable (for example without a GPU
      // context): keep drawing via the picture replay path.
      chunk.imageMatchesBucket = true;
    }
  }

  /// A gentle travelling highlight over the water: diagonal bands of
  /// translucent white whose brightness rises and falls out of phase,
  /// reading as ripples moving across rivers, lakes, and the ocean.
  /// Drawn by the fragment shader when available — one textured quad
  /// per water chunk, with the band pattern computed per pixel — and
  /// by merged world-space paths otherwise.
  void _paintWaterShimmer(Canvas canvas, Size size, List<_TerrainChunk> drawn) {
    final program = shimmerProgram;
    if (program != null && !debugDrawShimmerViaPaths) {
      _paintWaterShimmerViaShader(canvas, size, drawn, program);
    } else {
      _paintWaterShimmerViaPaths(canvas, size, drawn);
    }
  }

  void _paintWaterShimmerViaShader(
    Canvas canvas,
    Size size,
    List<_TerrainChunk> drawn,
    ui.FragmentProgram program,
  ) {
    final shimmer = content.ambience.waterShimmer;
    var quads = 0;
    for (final chunk in drawn) {
      final mask = chunk.waterMask;
      if (mask == null) continue;
      // One shader instance per quad: uniform and sampler values are
      // read at raster time, so a shared instance would draw every
      // quad with the last quad's mask and origin. Indices follow the
      // shader's declaration order, counting only non-sampler
      // uniforms.
      final shader = program.fragmentShader();
      shader.setFloat(0, ambient.seconds);
      shader.setFloat(1, shimmer.periodSeconds);
      shader.setFloat(2, shimmer.bands.toDouble());
      shader.setFloat(3, shimmer.maxOpacity);
      final tint = shimmer.colorRgb;
      shader.setFloat(4, tint.isNotEmpty ? tint[0] / 255 : 1);
      shader.setFloat(5, tint.length > 1 ? tint[1] / 255 : 1);
      shader.setFloat(6, tint.length > 2 ? tint[2] / 255 : 1);
      shader.setFloat(7, 1);
      shader.setFloat(8, chunk.worldRect.left);
      shader.setFloat(9, chunk.worldRect.top);
      shader.setFloat(10, chunk.worldRect.width);
      shader.setFloat(11, chunk.worldRect.height);
      shader.setImageSampler(0, mask, filterQuality: FilterQuality.medium);
      final paint = Paint()..shader = shader;
      quads++;
      canvas
        ..save()
        ..translate(size.width / 2 + offset.dx, size.height / 2 + offset.dy)
        ..scale(scale)
        ..translate(chunk.worldRect.left, chunk.worldRect.top)
        ..drawRect(Offset.zero & chunk.worldRect.size, paint)
        ..restore();
    }
    ParcelWorldProbe.noteShimmerQuads(quads);
  }

  void _paintWaterShimmerViaPaths(
    Canvas canvas,
    Size size,
    List<_TerrainChunk> drawn,
  ) {
    final shimmer = content.ambience.waterShimmer;
    final bands = shimmer.bands;
    final merged = List<Path>.generate(bands, (_) => Path());
    var contours = 0;
    var anyWater = false;
    for (final chunk in drawn) {
      final paths = chunk.shimmerPaths;
      final counts = chunk.shimmerCounts;
      if (paths == null || counts == null) continue;
      for (var band = 0; band < bands; band++) {
        if (counts[band] == 0) continue;
        merged[band].addPath(paths[band], Offset.zero);
        contours += counts[band];
        anyWater = true;
      }
    }
    ParcelWorldProbe.noteShimmerContours(contours);
    if (!anyWater) return;
    canvas.save();
    canvas.translate(size.width / 2 + offset.dx, size.height / 2 + offset.dy);
    canvas.scale(scale);
    for (var band = 0; band < bands; band++) {
      final wave =
          0.5 +
          0.5 *
              math.sin(
                2 * math.pi * (ambient.seconds / shimmer.periodSeconds) -
                    band * 2 * math.pi / bands,
              );
      final alpha = wave * shimmer.maxOpacity;
      if (alpha < 0.006) continue;
      final tint = shimmer.colorRgb;
      canvas.drawPath(
        merged[band],
        Paint()
          ..color = Color.fromARGB(
            (alpha * 255).round(),
            tint.isNotEmpty ? tint[0] : 255,
            tint.length > 1 ? tint[1] : 255,
            tint.length > 2 ? tint[2] : 255,
          ),
      );
    }
    canvas.restore();
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
    ParcelWorldProbe.countActor();
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
    if (dimStructures) {
      // X-ray: modulate the sprite's alpha (white at 40%) so tiles
      // and banks behind the structure show through — one draw call,
      // no offscreen layer.
      paint.color = const Color(0x66FFFFFF);
    }
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
    ParcelWorldProbe.countActor();
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
    ParcelWorldProbe.countActor();
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
      oldDelegate.dimStructures != dimStructures ||
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

/// The viewport rectangle in world coordinates, and the per-row cell
/// windows it covers. The screen is an axis-aligned rect in world
/// space; the cell lattice is rotated 45 degrees relative to it, so
/// the visible cells form a diamond in (column, row) space. Cell
/// diamonds are `_logicalTileWidth x _logicalTileHeight` world units
/// centred on lattice points, so a cell can paint a pixel iff its
/// diamond intersects this rect.
class _ViewportGeometry {
  _ViewportGeometry(Size size, double scale, Offset offset) {
    final center = size.center(Offset.zero);
    left = (-center.dx - offset.dx) / scale;
    right = (size.width - center.dx - offset.dx) / scale;
    top = (-center.dy - offset.dy) / scale;
    bottom = (size.height - center.dy - offset.dy) / scale;
  }

  late final double left;
  late final double right;
  late final double top;
  late final double bottom;

  /// Inclusive column window covering every cell at [row] whose
  /// diamond intersects the viewport, or null when the whole row is
  /// off-screen.
  (int, int)? columnWindow(int row) {
    final halfWidth = _logicalTileWidth / 2;
    final halfHeight = _logicalTileHeight / 2;
    // Cell centre: x = (column - row) * halfWidth, y = (column + row) *
    // halfHeight; the diamond extends halfWidth / halfHeight around it.
    final lowFromX = (left - halfWidth) / halfWidth + row;
    final highFromX = (right + halfWidth) / halfWidth + row;
    final lowFromY = (top - halfHeight) / halfHeight - row;
    final highFromY = (bottom + halfHeight) / halfHeight - row;
    final start = math.max(lowFromX, lowFromY).ceil();
    final end = math.min(highFromX, highFromY).floor();
    return start > end ? null : (start, end);
  }

  /// Whether a flat, tile-footprint cell (terrain, roads) can paint
  /// any pixel in the viewport. Standing sprites overhang their cells
  /// and must not use this test.
  bool containsCell(CellCoord cell) {
    final window = columnWindow(cell.row);
    return window != null &&
        cell.column >= window.$1 &&
        cell.column <= window.$2;
  }
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

/// Draws a tile sprite at its natural aspect ratio in world space:
/// the sprite's ground diamond aligned to the cell's diamond.
void _drawImageAtWorldCenter(Canvas canvas, ui.Image image, Offset center) {
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromCenter(
      center: center,
      width: _logicalTileWidth,
      height: _logicalTileHeight,
    ),
    Paint()..filterQuality = FilterQuality.medium,
  );
}

/// Draws the parcel-outline stroke in world space.
void _drawWorldParcelOutline(
  Canvas canvas,
  ParcelCoord parcel,
  int parcelSize,
) {
  final origin = parcel.origin(parcelSize);
  final vertices = [
    origin,
    origin.offset(parcelSize, 0),
    origin.offset(parcelSize, parcelSize),
    origin.offset(0, parcelSize),
  ];
  final path = Path();
  for (var i = 0; i < vertices.length; i++) {
    final point = _cellWorldCorner(vertices[i]);
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

/// World-space rect covering every cell diamond in a parcel chunk,
/// plus a margin so anti-aliased edges and outline strokes that bleed
/// past the boundary survive rasterization.
Rect _chunkWorldRect(ParcelCoord parcel, int parcelSize) {
  const margin = 2.0;
  final halfWidth = _logicalTileWidth / 2;
  final halfHeight = _logicalTileHeight / 2;
  final firstColumn = parcel.x * parcelSize;
  final firstRow = parcel.y * parcelSize;
  return Rect.fromLTRB(
    (firstColumn - firstRow - parcelSize) * halfWidth - margin,
    (firstColumn + firstRow) * halfHeight - halfHeight - margin,
    (firstColumn - firstRow + parcelSize) * halfWidth + margin,
    (firstColumn + firstRow + 2 * parcelSize - 1) * halfHeight + margin,
  );
}

/// Unowned land is faded toward the map background. The wash is
/// applied once over the cell's fully composed layers, so a cell with
/// layered shore pieces fades exactly like plain ground instead of
/// compounding per-sprite transparency (which made shorelines look
/// darker than the surrounding grass).
void _drawWorldCellWash(
  Canvas canvas,
  Offset center,
  UnownedLandWashContent wash,
) {
  final halfWidth = _logicalTileWidth / 2;
  final halfHeight = _logicalTileHeight / 2;
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

/// One parcel-sized piece of the flat ground layer, recorded in world
/// coordinates so the recording survives camera motion. The [picture]
/// is the source of truth; the [image] is a rasterized texture at the
/// current zoom bucket, drawn as a single quad per frame.
class _TerrainChunk {
  _TerrainChunk(this.coord, this.worldRect);

  final ParcelCoord coord;

  /// World-space rect covering the chunk's cells plus a small margin.
  final Rect worldRect;

  /// World-space recording of terrain, wash, roads, and the parcel
  /// outline, translated so this rect's top-left is the origin.
  ui.Picture? picture;

  /// Rasterized [picture] at the cache's texture factor.
  ui.Image? image;

  /// The scaling wrapper recorded around [picture] for [image];
  /// retained because rasterization may still reference it.
  ui.Picture? rasterWrapper;

  /// Whether [image] was rasterized at the cache's current factor.
  bool imageMatchesBucket = false;

  /// World-space water-shimmer contours, one path per band.
  List<Path>? shimmerPaths;

  /// Water-cell count per shimmer band (the contours in each path).
  List<int>? shimmerCounts;

  /// World-space recording of the chunk's water coverage (filled
  /// diamonds), rasterized into [waterMask] for the shimmer shader.
  ui.Picture? waterMaskPicture;

  /// Rasterized water-coverage mask at the cache's texture factor.
  ui.Image? waterMask;

  /// The scaling wrapper recorded around [waterMaskPicture] for
  /// [waterMask]; retained while rasterization may reference it.
  ui.Picture? waterMaskWrapper;

  /// Cache generation this chunk was recorded in.
  int generation = -1;

  /// Monotonic stamp of the last frame that drew this chunk.
  int lastUsed = 0;

  void dispose() {
    picture?.dispose();
    image?.dispose();
    rasterWrapper?.dispose();
    waterMaskPicture?.dispose();
    waterMask?.dispose();
    waterMaskWrapper?.dispose();
    picture = null;
    image = null;
    rasterWrapper = null;
    waterMaskPicture = null;
    waterMask = null;
    waterMaskWrapper = null;
    shimmerPaths = null;
    shimmerCounts = null;
  }
}

/// Parcel-sized world-space chunks of the flat layer (terrain, wash,
/// roads, parcel outlines). Chunks are recorded and rasterized lazily
/// when visible and survive camera motion: panning and zooming draw
/// cached textures instead of re-recording, and only entering unseen
/// areas records new chunks. Any change to the world or the sprite
/// set re-records everything, matching the previous whole-layer cache
/// semantics; per-chunk dirtying is future work.
class _TerrainChunkCache {
  final Map<ParcelCoord, _TerrainChunk> chunks = {};
  Object? worldKey;
  int imageCount = -1;
  double textureFactor = 1;
  int generation = 0;
  int _stamp = 0;

  /// Cap on cached chunks so roaming the open ocean cannot grow the
  /// cache without bound; the least recently drawn are evicted.
  static const int _maxChunks = 400;

  int nextStamp() => ++_stamp;

  /// Drops every chunk when the world or the sprite set changed.
  void resetFor(Object world, int images) {
    if (worldKey == world && imageCount == images) return;
    worldKey = world;
    imageCount = images;
    generation++;
    for (final chunk in chunks.values) {
      chunk.dispose();
    }
    chunks.clear();
  }

  /// Marks every rasterized texture stale after a zoom-bucket change;
  /// stale textures keep drawing (scaled) until re-rasterized.
  void setTextureFactor(double factor) {
    if (textureFactor == factor) return;
    textureFactor = factor;
    for (final chunk in chunks.values) {
      chunk.imageMatchesBucket = false;
    }
  }

  void evictDistant() {
    if (chunks.length <= _maxChunks) return;
    final ordered = chunks.values.toList()
      ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    final excess = chunks.length - _maxChunks + 100;
    for (final chunk in ordered.take(excess)) {
      chunks.remove(chunk.coord);
      chunk.dispose();
    }
  }

  void dispose() {
    for (final chunk in chunks.values) {
      chunk.dispose();
    }
    chunks.clear();
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
