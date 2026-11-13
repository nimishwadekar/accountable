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
import '../world/pedestrian_lattice.dart';
import '../world/road_sprite_resolver.dart';
import '../world/terrain_provider.dart';
import '../world/world_content.dart';
import '../world/world_queries.dart';
import '../world/world_rules.dart';
import '../world/world_state.dart';

const _logicalTileWidth = 64.0;
const _logicalTileHeight = 32.0;

/// Debug/test switch: draw every terrain chunk by replaying its
/// world-space recording instead of its rasterized texture. Tests use
/// this to prove both draw paths place content at identical pixels.
@visibleForTesting
bool debugDrawChunksViaPictures = false;

class ParcelWorldView extends StatefulWidget {
  const ParcelWorldView({
    required this.state,
    required this.content,
    required this.terrainProvider,
    required this.onCellTap,
    this.selectedCell,
    this.selectedParcel,
    this.selectedCatalogueId,
    this.selectedPropId,
    this.selectedSubtileX = propFrontSubtile,
    this.selectedSubtileY = propFrontSubtile,
    this.bridgeStartCell,
    this.bridgeEndCell,
    this.roadPlanCells = const [],
    this.roadStartCell,
    this.highlightCells = const {},
    this.cameraResetToken = 0,
    this.facingOverride,
    this.structurePicking = true,
    this.dimStructures = false,
    this.parcelMode = false,
    this.showTileGrid = true,
    super.key,
  });

  final ParcelWorldState state;
  final ContentBundle content;
  final TerrainProvider terrainProvider;

  /// Called on every map tap with the resolved hit — a structure or
  /// prop id when sprite picking is on, else the ground cell — plus
  /// the subtile of the tapped point within its own nearest cell
  /// (0..7 on both axes), so placement tools can land props exactly
  /// where the player tapped.
  final void Function(
    CellCoord cell,
    String? structureId,
    int subtileX,
    int subtileY,
  )
  onCellTap;
  final CellCoord? selectedCell;
  final ParcelCoord? selectedParcel;
  final String? selectedCatalogueId;

  /// The selected prop's id — selection is by id because several
  /// props share a tile. Drives the selection wash.
  final String? selectedPropId;

  /// Where in the selected cell the last tap landed — the decor
  /// ghost's position on touch, where hover does not exist.
  final int selectedSubtileX;
  final int selectedSubtileY;
  final CellCoord? bridgeStartCell;
  final CellCoord? bridgeEndCell;
  final List<CellCoord> roadPlanCells;
  final CellCoord? roadStartCell;

  /// Cells highlighted as a selection group — a road section between
  /// junctions or a whole active project.
  final Set<CellCoord> highlightCells;
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

  /// Parcel-tool view: the cell grid hides (line-free ground tiles),
  /// unowned parcels shade, a strong parcel grid covers the authored
  /// map, and hover highlights the unowned parcel under the pointer.
  final bool parcelMode;

  /// Whether the faint tile grid draws over the ground — every mode
  /// except inspect, where the world renders clean for viewing, and
  /// parcel mode, whose strong parcel grid replaces it.
  final bool showTileGrid;

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

  /// Composed shore-band overlays, keyed by the water cell's
  /// eight-neighbourhood pattern ('g.......'). Filled lazily as
  /// chunks record band cells; each overlay blends the neighbouring
  /// land's material over the water tile (see [composeShoreBandPixels]).
  final Map<String, ui.Image> _bandImages = {};

  /// Decoded ground materials for the shore band — straight-RGBA
  /// bytes and canvas size, keyed by style ('grass', 'dirt'). Read
  /// once the ground sprites load; no masks are involved.
  final Map<String, (Uint8List, int, int)> _bandMaterials = {};

  /// Guards [_scheduleBandComposition] against overlapping runs.
  bool _composingBands = false;

  /// Neighbourhood patterns recorded by chunks, not yet composed.
  final Set<String> _pendingBandPatterns = {};

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

  /// Drives vegetation sway and ambient pedestrians. The clock is muted
  /// when the platform requests reduced motion; the ambient time scale
  /// comes from content so the editor can tune it live.
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

  final _PedestrianSim _pedestrians = _PedestrianSim();

  /// Hovered cell for desktop live previews (touch never hovers).
  CellCoord? _hoverCell;

  /// The hovered subtile within [_hoverCell] — the ghost follows it
  /// at subtile granularity, so it repaints as the pointer crosses
  /// lattice lines inside a tile too.
  int _hoverSubtileX = 0;
  int _hoverSubtileY = 0;

  /// Cache backing [_cameraWorldBounds].
  Rect? _cameraBounds;
  ContentBundle? _cameraBoundsContent;
  TerrainProvider? _cameraBoundsProvider;

  /// Whether the decor ghost is pinned to the last tapped spot: a
  /// tap locks the preview in place (so it stays put while the
  /// pointer travels to the confirm button), the next tap elsewhere
  /// releases it back to following the cursor, and re-tapping the
  /// same spot keeps the lock.
  bool _ghostPinned = false;

  void _updateHover(Offset position, Size size) {
    final world = _screenToWorld(position, size, _scale, _offset);
    final cell = _nearestCell(world);
    final (subtileX, subtileY) = _subtileUnder(world);
    if (cell == _hoverCell &&
        subtileX == _hoverSubtileX &&
        subtileY == _hoverSubtileY) {
      return;
    }
    setState(() {
      _hoverCell = cell;
      _hoverSubtileX = subtileX;
      _hoverSubtileY = subtileY;
    });
  }

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
      // Picking a fresh model starts the ghost in cursor-follow mode.
      _ghostPinned = false;
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
    for (final image in _bandImages.values) {
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
            onPointerHover: (event) => _updateHover(event.localPosition, size),
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
                _clampCamera();
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
                  _clampCamera();
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
                  selectedPropId: widget.selectedPropId,
                  selectedSubtileX: widget.selectedSubtileX,
                  selectedSubtileY: widget.selectedSubtileY,
                  hoverSubtileX: _hoverSubtileX,
                  hoverSubtileY: _hoverSubtileY,
                  ghostPinned: _ghostPinned,
                  bridgeStartCell: widget.bridgeStartCell,
                  bridgeEndCell: widget.bridgeEndCell,
                  roadPlanCells: widget.roadPlanCells,
                  roadStartCell: widget.roadStartCell,
                  highlightCells: widget.highlightCells,
                  hoverCell: _hoverCell,
                  facingOverride: widget.facingOverride,
                  dimStructures: widget.dimStructures,
                  ambient: _ambient,
                  terrainCache: _terrainCache,
                  pixelRatio: _pixelRatio,
                  bands: _bandImages,
                  onBandPattern: _noteBandPattern,
                  parcelMode: widget.parcelMode,
                  showTileGrid: widget.showTileGrid,
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
    _clampCamera();
  }

  /// The camera's play area: the union of the charted parcels' diamond
  /// bounding boxes, inflated by [cameraChartedMargin] of fog. Cached
  /// on content and provider identity — terrain edits arrive as a new
  /// bundle, which is also what grows the play area. Null when nothing
  /// is charted (degenerate content); the camera stays free then.
  Rect? _cameraWorldBounds() {
    if (!identical(widget.content, _cameraBoundsContent) ||
        !identical(widget.terrainProvider, _cameraBoundsProvider)) {
      _cameraBoundsContent = widget.content;
      _cameraBoundsProvider = widget.terrainProvider;
      final parcelSize = widget.state.parcelSize;
      final seed = widget.state.seed;
      Rect? bounds;
      for (final entry in widget.content.terrain.parcels.entries) {
        // Authored fog parcels render as fog; they are not part of
        // the valid map the camera is bounded to.
        if (widget.terrainProvider
                .sample(entry.key.origin(parcelSize), seed)
                .kind ==
            TerrainKind.fog) {
          continue;
        }
        final rect = _parcelWorldRect(entry.key, parcelSize);
        bounds = bounds == null ? rect : bounds.expandToInclude(rect);
      }
      _cameraBounds = bounds?.inflate(cameraChartedMargin);
    }
    return _cameraBounds;
  }

  /// Clamps the camera so its centre cannot leave the play area: the
  /// world point under the viewport centre stays within the charted
  /// map plus its fog margin, so the map can never be panned out of
  /// view. Called after every camera mutation; mutates [_offset]
  /// only, so it is safe inside a setState block.
  void _clampCamera() {
    final bounds = _cameraWorldBounds();
    if (bounds == null) return;
    final center = Offset(-_offset.dx / _scale, -_offset.dy / _scale);
    final clamped = Offset(
      center.dx.clamp(bounds.left, bounds.right),
      center.dy.clamp(bounds.top, bounds.bottom),
    );
    if (clamped != center) {
      _offset = Offset(-clamped.dx * _scale, -clamped.dy * _scale);
    }
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
    final structureHits = _hitStructures(
      position,
      size,
      _scale,
      _offset,
      _queries,
      _images,
      _masks,
      _spriteReachCells,
      widget.content,
      // Non-inspect tools target the tapped cell directly — except
      // that raised bridge decks still sprite-hit, correcting the
      // ground projection for every tool.
      bridgesOnly: !widget.structurePicking,
    );
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
    // The tapped subtile resolves on the hit's surface: a deck tap
    // ground-projects too far north, so un-project at deck height.
    final lift = _surfaceLift(hit.cell, _queries, widget.content);
    final (subtileX, subtileY) = _subtileUnder(world + Offset(0, lift));
    // The tap drives the ghost pin: a free ghost locks onto the
    // tapped spot; a pinned ghost releases when the tap lands
    // elsewhere and holds when it lands on the same spot.
    if (!_ghostPinned) {
      _ghostPinned = true;
    } else if (hit.cell != widget.selectedCell ||
        subtileX != widget.selectedSubtileX ||
        subtileY != widget.selectedSubtileY) {
      _ghostPinned = false;
    }
    widget.onCellTap(hit.cell, hit.structureId, subtileX, subtileY);
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
      _clampCamera();
    });
  }

  Future<void> _loadMissingImages({bool retryFailed = false}) async {
    final content = widget.content;
    final roles = <String>{
      ...requiredSpriteRoles,
      for (final road in widget.state.roads)
        if (road.style == RoadStyle.asphalt)
          for (var mask = 0; mask < 16; mask++) roadSpriteRole(mask),
      // Placed structures, props, and jobs render their rolled variant
      // at its chosen door side; the selected catalogue model needs
      // every variant's facings since either side can be chosen at
      // placement.
      for (final structure in widget.state.structures)
        structure.assetRole ??
            content.structure(structure.catalogueId)!.assetRoles.first,
      for (final prop in widget.state.props)
        prop.assetRole ?? content.structure(prop.catalogueId)!.assetRoles.first,
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
    await _decodeBandMaterials();
  }

  /// Decodes the ground materials the shore band needs: the land
  /// styles it blends ('grass', 'dirt') and the water tile it blends
  /// them over. No masks and no pre-composed shapes: the band is the
  /// material itself, fading out over the water (see
  /// [composeShoreBandPixels]), and overlays compose per
  /// neighbourhood pattern on demand.
  Future<void> _decodeBandMaterials() async {
    for (final style in const ['grass', 'dirt', 'water']) {
      if (_bandMaterials.containsKey(style)) continue;
      final path = widget.content.tryAssetPath('terrain.$style');
      final image = path == null ? null : _images[path];
      if (image == null) continue;
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data == null) continue;
      _bandMaterials[style] = (
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
      );
    }
    _scheduleBandComposition();
  }

  /// Records a shore-band pattern discovered while a chunk records
  /// and schedules its composition. Called from the painter during
  /// paint, so it must not repaint synchronously; composition
  /// completes in a later event and repaints through [setState].
  void _noteBandPattern(String pattern) {
    if (_bandImages.containsKey(pattern)) return;
    _pendingBandPatterns.add(pattern);
    _scheduleBandComposition();
  }

  /// Composes every pending band pattern into an overlay image. Runs
  /// at most once at a time; patterns recorded while a run is in
  /// flight are picked up by the tail re-schedule.
  void _scheduleBandComposition() {
    if (_composingBands || _pendingBandPatterns.isEmpty) return;
    if (_bandMaterials.isEmpty) return; // Retried once materials decode.
    _composingBands = true;
    final pending = _pendingBandPatterns.toList();
    _pendingBandPatterns.clear();
    unawaited(
      Future<void>.microtask(() async {
        try {
          for (final pattern in pending) {
            if (_bandImages.containsKey(pattern)) continue;
            if (!mounted) return;
            final lands = shoreBandLands(pattern);
            if (lands.isEmpty) continue;
            final waterPixels = _bandMaterials['water']?.$1;
            if (waterPixels == null) continue;
            final styles = lands.map((land) => land.style).toSet();
            final materials = <String, Uint8List>{
              for (final style in styles)
                if (_bandMaterials.containsKey(style))
                  style: _bandMaterials[style]!.$1,
            };
            if (materials.length < styles.length) continue;
            final (_, width, height) = _bandMaterials.values.first;
            final image = await decodeRgbaImage(
              composeShoreBandPixels(
                materials,
                waterPixels,
                lands,
                width,
                height,
              ),
              width,
              height,
            );
            if (image == null) continue;
            if (!mounted) {
              image.dispose();
              return;
            }
            setState(() => _bandImages[pattern] = image);
          }
        } finally {
          _composingBands = false;
        }
        if (mounted && _pendingBandPatterns.isNotEmpty) {
          _scheduleBandComposition();
        }
      }),
    );
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
      return (await codec.getNextFrame()).image;
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

/// Decodes RGBA bytes into a [ui.Image] through the raw descriptor.
///
/// The bytes' alpha must be binary — 0 or 255 only. The engines
/// disagree on partial alpha here: Skia reads the bytes as
/// premultiplied while CanvasKit reads them as straight, so a
/// gradient encoded in alpha renders squared on the web (each
/// partial pixel gets its alpha applied twice). Binary alpha means
/// the same thing in both conventions; keep any gradient in the
/// colour channels (see [composeShoreBandPixels]).
Future<ui.Image?> decodeRgbaImage(
  Uint8List pixels,
  int width,
  int height,
) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
      descriptor.dispose();
    }
  } catch (_) {
    return null;
  }
}

/// How far the shore band reaches into a water tile, in ground-art
/// pixels: half the tile's depth. The band is the only shore art —
/// land tiles stay dry right up to the boundary, and each water tile
/// carries a translucent margin of its neighbouring land's material
/// fading out, like a shallow bank seen through the water.
const double shoreBandReach = 29;

/// One land neighbour contributing to a water cell's shore band: the
/// neighbour's cell offset from the water cell, and its ground
/// material style ('grass' or 'dirt').
class ShoreBandLand {
  const ShoreBandLand(this.dc, this.dr, this.style);

  final int dc;
  final int dr;
  final String style;
}

/// The eight neighbours a shore band considers, in the order their
/// characters appear in a pattern: N, NE, E, SE, S, SW, W, NW. The
/// band reaches half a tile and the nearest land beyond this ring is
/// a full tile away, so no further neighbour can contribute.
const List<(int, int)> _shoreBandNeighborOrder = [
  (0, -1), // N
  (1, -1), // NE
  (1, 0), // E
  (1, 1), // SE
  (0, 1), // S
  (-1, 1), // SW
  (-1, 0), // W
  (-1, -1), // NW
];

/// The shore-band pattern of a water cell: one character per
/// neighbour in [_shoreBandNeighborOrder] — '.' when the neighbour is
/// not land, 'g' for land in grass (and for every ground style
/// without its own band material), 'd' for dirt. Null when no
/// neighbour is land: open water draws no band.
String? shoreBandPattern(
  CellCoord cell,
  TerrainCell Function(CellCoord) terrainAt,
) {
  final chars = List.filled(8, '.');
  var anyLand = false;
  for (var i = 0; i < _shoreBandNeighborOrder.length; i++) {
    final (dc, dr) = _shoreBandNeighborOrder[i];
    final terrain = terrainAt(cell.offset(dc, dr));
    if (!terrain.isLand) continue;
    chars[i] = terrain.groundStyle == GroundStyle.dirt ? 'd' : 'g';
    anyLand = true;
  }
  return anyLand ? chars.join() : null;
}

/// The lands a pattern's band blends over the water tile.
List<ShoreBandLand> shoreBandLands(String pattern) {
  final lands = <ShoreBandLand>[];
  for (var i = 0; i < _shoreBandNeighborOrder.length; i++) {
    if (i >= pattern.length) break;
    final style = switch (pattern[i]) {
      'g' => 'grass',
      'd' => 'dirt',
      _ => null,
    };
    if (style == null) continue;
    final (dc, dr) = _shoreBandNeighborOrder[i];
    lands.add(ShoreBandLand(dc, dr, style));
  }
  return lands;
}

/// Composes one shore-band overlay: the neighbouring lands' materials
/// blended over the water tile's own art with an alpha ramp that is
/// solid at the tile boundary and fades to nothing [shoreBandReach]
/// pixels in.
///
/// Each pixel takes the colour of the *nearest* land, so corners
/// combine as the ramp of the distance to the nearest shore — never
/// a double blend — and mixed materials meet along the midline
/// between their edges. Pixels either art left unpainted (the pack's
/// jagged diamond fringes) are skipped, so the waterline stays ragged
/// at the art's own granularity and the chunk shows through.
///
/// The gradient is baked into the colours against the water tile's
/// own pixels and the output alpha is binary — written pixels are
/// fully opaque, skipped pixels fully transparent. Raw-image
/// decoding disagrees about partial alpha between engines (Skia
/// reads the bytes as premultiplied, CanvasKit as straight), which
/// would square the ramp on the web; binary alpha means the same
/// thing in both conventions. [width] and [height] are the ground
/// family's shared tile canvas (128x64 today).
Uint8List composeShoreBandPixels(
  Map<String, Uint8List> materials,
  Uint8List water,
  List<ShoreBandLand> lands,
  int width,
  int height,
) {
  final out = Uint8List(width * height * 4);
  if (lands.isEmpty || materials.isEmpty || width < 1 || height < 1) {
    return out;
  }
  // Each land's diamond as four edges in canvas space: tile origins
  // sit on the half-canvas pitch of the isometric lattice, and each
  // diamond spans its tile's full canvas.
  final diamonds = <List<(Offset, Offset)>>[];
  final styles = <String>[];
  final halfWidth = width / 2;
  final halfHeight = height / 2;
  for (final land in lands) {
    if (!materials.containsKey(land.style)) continue;
    final cx = (land.dc - land.dr) * halfWidth + halfWidth;
    final cy = (land.dc + land.dr) * halfHeight + halfHeight;
    final north = Offset(cx, cy - halfHeight);
    final east = Offset(cx + halfWidth, cy);
    final south = Offset(cx, cy + halfHeight);
    final west = Offset(cx - halfWidth, cy);
    diamonds.add([(north, east), (east, south), (south, west), (west, north)]);
    styles.add(land.style);
  }
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final px = x + 0.5;
      final py = y + 0.5;
      var best = double.infinity;
      var bestLand = -1;
      for (var i = 0; i < diamonds.length; i++) {
        var nearest = double.infinity;
        for (final (a, b) in diamonds[i]) {
          final d = _distanceToSegment(px, py, a.dx, a.dy, b.dx, b.dy);
          if (d < nearest) nearest = d;
        }
        if (nearest < best) {
          best = nearest;
          bestLand = i;
        }
      }
      if (bestLand < 0 || best >= shoreBandReach) continue;
      final t = (1 - best / shoreBandReach).clamp(0.0, 1.0);
      final ramp = t * t * (3 - 2 * t);
      if (ramp <= 0) continue;
      final land = materials[styles[bestLand]]!;
      final i = (y * width + x) * 4;
      // Either art's fringe stays exactly as the chunk drew it.
      if (land[i + 3] == 0 || water[i + 3] == 0) continue;
      // The blend, decomposed as the water pixel plus its shift
      // toward the land. Shifts smaller than half a unit round back
      // to the water itself — that is the band's visible edge, and
      // those pixels stay transparent so the chunk shows through.
      final dRed = (land[i] - water[i]) * ramp;
      final dGreen = (land[i + 1] - water[i + 1]) * ramp;
      final dBlue = (land[i + 2] - water[i + 2]) * ramp;
      if (dRed.abs() < 0.5 && dGreen.abs() < 0.5 && dBlue.abs() < 0.5) {
        continue;
      }
      out[i] = (water[i] + dRed).round();
      out[i + 1] = (water[i + 1] + dGreen).round();
      out[i + 2] = (water[i + 2] + dBlue).round();
      out[i + 3] = 255;
    }
  }
  return out;
}

/// Plane distance from a point to a segment.
double _distanceToSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final vx = bx - ax;
  final vy = by - ay;
  final wx = px - ax;
  final wy = py - ay;
  final lengthSquared = vx * vx + vy * vy;
  var t = lengthSquared == 0 ? 0.0 : (wx * vx + wy * vy) / lengthSquared;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  final dx = px - (ax + t * vx);
  final dy = py - (ay + t * vy);
  return math.sqrt(dx * dx + dy * dy);
}

class _WorldHit {
  const _WorldHit(this.cell, this.structureId);

  final CellCoord cell;
  final String? structureId;
}

/// Every structure, prop, or bridge tile hit by a tap, in
/// front-to-back painter order — each entry is one sprite with an
/// opaque pixel under the tap point. With [bridgesOnly], used by the
/// non-inspect tools that target the tapped cell directly, only the
/// elevated bridge tiles hit-test: their sprite hits correct the
/// ground projection, which lands north of the deck because decks
/// are raised.
List<_WorldHit> _hitStructures(
  Offset position,
  Size size,
  double scale,
  Offset offset,
  WorldQueries queries,
  Map<String, ui.Image> images,
  Map<String, SpriteMask> masks,
  int reachCells,
  ContentBundle content, {
  bool bridgesOnly = false,
}) {
  final world = _screenToWorld(position, size, scale, offset);
  final cell = _nearestCell(world);
  // Candidates are every structure, prop, and bridge tile whose art
  // could reach the tap, ordered exactly as the painter draws them
  // (back to front) and walked front to back. Every sprite with an
  // opaque pixel under the tap joins the result in that order, so
  // repeated taps can cycle through what the front one hides; the
  // ground diamond below is the caller's fallback.

  _WorldHit? hitAt(Rect screenRect, String? path, _WorldHit hit) {
    if (!screenRect.contains(position)) return null;
    final mask = masks[path];
    if (mask == null) {
      // Mask still decoding: fall back to the rect until it lands.
      return hit;
    }
    return spritePixelHit(mask, screenRect, position) ? hit : null;
  }

  _WorldHit? structureHit(PlacedStructure structure) {
    final definition = content.structure(structure.catalogueId)!;
    final role = structure.assetRole ?? definition.assetRoles.first;
    final path = content.tryAssetPathFor(role, structure.facing);
    final image = images[path];
    if (image == null) return null;
    return hitAt(
      _worldRectToScreen(
        _structureRect(image, definition, structure, content),
        size,
        scale,
        offset,
      ),
      path,
      _WorldHit(structure.origin, structure.id),
    );
  }

  _WorldHit? propHit(PlacedProp prop) {
    final definition = content.structure(prop.catalogueId)!;
    final role = prop.assetRole ?? definition.assetRoles.first;
    final path = content.tryAssetPathFor(role, prop.facing);
    final image = images[path];
    if (image == null) return null;
    return hitAt(
      _worldRectToScreen(
        _propRect(
          image,
          content.sprite(role)!,
          prop,
          surfaceLift: _surfaceLift(prop.cell, queries, content),
        ),
        size,
        scale,
        offset,
      ),
      path,
      _WorldHit(prop.cell, prop.id),
    );
  }

  // A bridge deck or ramp tile: tile-fit art at its cell, hit-tested
  // like any standing sprite. Decks report their own cell — the
  // correction that makes raised bridges tappable across their full
  // width — and ramps report their bank cell. Transparent gaps under
  // the deck miss and let the tap fall through to the ground.
  _WorldHit? bridgeTileHit(CellCoord tileCell, String role) {
    final path = content.tryAssetPath(role);
    final image = path == null ? null : images[path];
    final sprite = path == null ? null : content.sprite(role);
    if (image == null || sprite == null) return null;
    return hitAt(
      _tileScreenRect(image, sprite, tileCell, size, scale, offset),
      path,
      _WorldHit(tileCell, null),
    );
  }

  final bridgeCandidates = <(double, _WorldHit?)>[
    for (final bridge in queries.bridgesInBounds(
      left: cell.column - reachCells,
      right: cell.column + reachCells,
      top: cell.row - reachCells,
      bottom: cell.row + reachCells,
    )) ...[
      for (final deckCell in bridge.waterCells)
        (
          (deckCell.column + deckCell.row).toDouble(),
          bridgeTileHit(
            deckCell,
            bridgeBodyRole(bridge.nearBank, bridge.farBank),
          ),
        ),
      (
        (bridge.nearBank.column + bridge.nearBank.row).toDouble(),
        bridgeTileHit(
          bridge.nearBank,
          bridgeRampRole(bridge.nearBank, bridge.waterCells.first),
        ),
      ),
      (
        (bridge.farBank.column + bridge.farBank.row).toDouble(),
        bridgeTileHit(
          bridge.farBank,
          bridgeRampRole(bridge.farBank, bridge.waterCells.last),
        ),
      ),
    ],
  ];

  final candidates = <(double, _WorldHit?)>[
    if (!bridgesOnly)
      for (final structure in queries.structuresInBounds(
        left: cell.column - reachCells,
        right: cell.column + reachCells,
        top: cell.row - reachCells,
        bottom: cell.row + reachCells,
      )..sort(_compareStructureDepth))
        (_structureDepth(structure).toDouble(), structureHit(structure)),
    if (!bridgesOnly)
      for (final prop in queries.propsInBounds(
        left: cell.column - reachCells,
        right: cell.column + reachCells,
        top: cell.row - reachCells,
        bottom: cell.row + reachCells,
      ))
        (propDepth(prop), propHit(prop)),
    ...bridgeCandidates,
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return [
    for (final candidate in candidates)
      if (candidate.$2 != null) candidate.$2!,
  ];
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
    required this.selectedPropId,
    required this.selectedSubtileX,
    required this.selectedSubtileY,
    required this.hoverSubtileX,
    required this.hoverSubtileY,
    required this.ghostPinned,
    required this.bridgeStartCell,
    required this.bridgeEndCell,
    required this.roadPlanCells,
    required this.roadStartCell,
    required this.highlightCells,
    required this.hoverCell,
    required this.facingOverride,
    required this.dimStructures,
    required this.ambient,
    required this.terrainCache,
    required this.pixelRatio,
    required this.bands,
    required this.onBandPattern,
    required this.parcelMode,
    required this.showTileGrid,
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

  /// The selected prop's id; several props share a tile, so the
  /// selection wash resolves through [WorldQueries.propsById].
  final String? selectedPropId;

  /// The tapped subtile of [selectedCell] — the decor ghost's
  /// position on touch.
  final int selectedSubtileX;
  final int selectedSubtileY;

  /// The hovered subtile of [hoverCell] — the decor ghost's position
  /// on desktop.
  final int hoverSubtileX;
  final int hoverSubtileY;

  /// Whether the decor ghost holds the tapped spot instead of
  /// following the cursor.
  final bool ghostPinned;
  final CellCoord? bridgeStartCell;
  final CellCoord? bridgeEndCell;
  final List<CellCoord> roadPlanCells;
  final CellCoord? roadStartCell;
  final Set<CellCoord> highlightCells;
  final CellCoord? hoverCell;
  final String? facingOverride;

  /// Whether standing structures draw translucent (x-ray) so tiles and
  /// banks behind them stay visible while the road and bridge tools
  /// are active.
  final bool dimStructures;
  final _AmbientClock ambient;
  final _TerrainChunkCache terrainCache;
  final double pixelRatio;

  /// Composed shore-band overlays by neighbourhood pattern — the
  /// neighbouring land's material fading out over the water tile.
  final Map<String, ui.Image> bands;

  /// Reports a newly recorded band pattern to the view state so its
  /// overlay can compose; called during paint, never repainting
  /// synchronously.
  final void Function(String pattern) onBandPattern;

  /// Parcel-tool view mode: unowned shading and the strong parcel grid.
  final bool parcelMode;

  /// Whether the faint tile grid draws — every mode except inspect.
  final bool showTileGrid;
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
    // (bridges included) plus the animated layers (swaying
    // vegetation, pedestrians) draw on top every frame,
    // depth-sorted, so raised geometry occludes correctly.
    ParcelWorldProbe.beginTerrain();
    _drawTerrainChunks(canvas, size, bounds, viewport);
    ParcelWorldProbe.endTerrain();
    if (showTileGrid && !parcelMode) {
      _drawTileGrid(canvas, size, bounds);
    }
    _drawOwnedOutline(canvas, size, bounds, viewport);
    if (parcelMode) {
      _drawParcelGrid(canvas, size, bounds, viewport);
    }
    _drawPlannedGround(canvas, size);
    _drawActors(canvas, size, bounds, ambient.seconds);
    _drawPendingConstructions(canvas, size);
    _drawLinePreview(canvas, size);
    _drawSelection(canvas, size, queries);
    ParcelWorldProbe.endFrame();
    ParcelWorldProbe.paintHud(canvas, size);
  }

  /// Under-construction tiles render as dirt ground: planned road and
  /// bridge cells show the dirt texture until their coins arrive.
  void _drawPlannedGround(Canvas canvas, Size size) {
    final path = content.tryAssetPath('terrain.dirt');
    final image = path == null ? null : images[path];
    for (final job in state.constructions) {
      if (job.kind == WorldConstructionKind.structure) continue;
      final cells = job.kind == WorldConstructionKind.road
          ? job.roadCells
          : [...job.waterCells, job.nearBank!, job.farBank!];
      for (final cell in cells) {
        if (state.roadsByCell.containsKey(cell)) continue;
        if (state.bridges.any((bridge) => bridge.waterCells.contains(cell))) {
          continue;
        }
        final center = _worldToScreen(
          _cellWorldCenter(cell),
          size,
          scale,
          offset,
        );
        if (image != null) {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            Rect.fromCenter(
              center: center,
              width: _logicalTileWidth * scale,
              height: _logicalTileHeight * scale,
            ),
            Paint()..filterQuality = FilterQuality.medium,
          );
        } else {
          _drawCellOutline(
            canvas,
            center,
            const Color(0xFF8B682A),
            scale,
            fill: const Color(0x33836D30),
          );
        }
      }
    }
  }

  /// Draws the visible terrain chunks. Chunks
  /// draw from rasterized textures; a chunk without a fresh texture
  /// falls back to replaying its world-space recording under the
  /// camera transform, which is slower but always correct.
  void _drawTerrainChunks(
    Canvas canvas,
    Size size,
    _CellBounds bounds,
    _ViewportGeometry viewport,
  ) {
    terrainCache.resetFor(state, images.length, parcelMode);
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
    // Blit ocean parcels before land parcels: the water tiles'
    // opaque skirts must never paint over neighbouring land at
    // shores, and the bank overlay only reaches ~1 world px past
    // the shared edge — not far enough to cover a 2 px skirt.
    // Fog parcels blit after land: the cloud deck sits above every
    // other ground, so its tiles cover the terrain edge where the
    // known world ends. Authored terrain is uniform per parcel, so
    // the origin cell's kind classifies the chunk.
    final waterChunks = <_TerrainChunk>[];
    final landChunks = <_TerrainChunk>[];
    final fogChunks = <_TerrainChunk>[];
    for (final chunk in drawn) {
      final origin = chunk.coord.origin(state.parcelSize);
      switch (queries.terrainAt(origin).kind) {
        case TerrainKind.water:
          waterChunks.add(chunk);
        case TerrainKind.grass:
          landChunks.add(chunk);
        case TerrainKind.fog:
          fogChunks.add(chunk);
      }
    }
    for (final chunk in waterChunks) {
      _blitChunk(canvas, size, chunk);
    }
    for (final chunk in landChunks) {
      _blitChunk(canvas, size, chunk);
    }
    for (final chunk in fogChunks) {
      _blitChunk(canvas, size, chunk);
    }
    _drawRoads(canvas, size, bounds);
    _drawShoreBands(canvas, size, drawn);
    _drawFogWisps(canvas, size, drawn);
  }

  /// Every bridge tile the frame draws, with its sprite role: the
  /// completed bridges' decks and ramps, plus the funded tiles of
  /// bridges still building. The surface pass and the actor sort both
  /// draw from this one list, so the split never drifts between them.
  List<(String, CellCoord)> _bridgeTilesInBounds(_CellBounds bounds) {
    final tiles = <(String, CellCoord)>[];
    for (final bridge in queries.bridgesInBounds(
      left: bounds.left - 5,
      right: bounds.right + 5,
      top: bounds.top - 5,
      bottom: bounds.bottom + 5,
    )) {
      final body = bridgeBodyRole(bridge.nearBank, bridge.farBank);
      for (final cell in bridge.waterCells) {
        tiles.add((body, cell));
      }
      tiles.add((
        bridgeRampRole(bridge.nearBank, bridge.waterCells.first),
        bridge.nearBank,
      ));
      tiles.add((
        bridgeRampRole(bridge.farBank, bridge.waterCells.last),
        bridge.farBank,
      ));
    }
    // Bridges still under construction: the near ramp rises with the
    // near-bank road (the first coin), then each funded span tile of
    // the deck appears in order, rising out of the dirt path. The far
    // ramp only draws on the completed bridge — its bank road arrives
    // with the final coin, and a ramp never stands on a non-road tile.
    for (final job in state.constructions) {
      if (job.kind != WorldConstructionKind.bridge) continue;
      if (!boundsOverlapsCells(bounds, [
        ...job.waterCells,
        job.nearBank!,
        job.farBank!,
      ])) {
        continue;
      }
      final fundedTiles = _bridgeFundedSpanCount(job);
      final nearBankFunded =
          job.coinsFunded >= content.economy.roadTileCostCoins;
      if (!nearBankFunded && fundedTiles <= 0) continue;
      if (fundedTiles > 0) {
        final body = bridgeBodyRole(job.nearBank!, job.farBank!);
        for (final cell in job.waterCells.take(fundedTiles)) {
          tiles.add((body, cell));
        }
      }
      if (nearBankFunded) {
        tiles.add((
          bridgeRampRole(job.nearBank!, job.waterCells.first),
          job.nearBank!,
        ));
      }
    }
    return tiles;
  }

  /// One bridge tile, drawn split along its surface plane: the same
  /// sprite, clipped twice. The [surface] piece keeps only the
  /// walkable plane — flat at deck height for bodies, sheared along
  /// the incline for ramps — and sorts just above the posts piece, so
  /// people standing on the tile draw on top of it. The default posts
  /// piece keeps everything else — supports, underside, anything
  /// above the walking plane — and draws first, so the neighbouring
  /// tile's art covers it exactly the way the whole sprite always
  /// was.
  void _drawBridgeTile(
    Canvas canvas,
    String role,
    CellCoord cell,
    Size size,
    double scale,
    Offset offset, {
    bool surface = false,
  }) {
    final path = content.tryAssetPath(role);
    final image = path == null ? null : images[path];
    if (image == null) return;
    ParcelWorldProbe.countActor();
    final sprite = content.sprite(role)!;
    final rect = _tileScreenRect(image, sprite, cell, size, scale, offset);
    final Path clip;
    if (surface) {
      // Grown a hair past the plane so the seam between the two
      // pieces stays fully opaque: the posts piece covers the overlap
      // wherever it has pixels, and each piece's anti-aliased edge
      // sits where the other already painted.
      clip = _bridgeSurfaceQuad(role, cell, size, scale, offset, expand: 0.02);
    } else {
      clip = Path.combine(
        PathOperation.difference,
        Path()..addRect(rect.inflate(2)),
        _bridgeSurfaceQuad(role, cell, size, scale, offset, expand: -0.02),
      );
    }
    canvas
      ..save()
      ..clipPath(clip)
      ..drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = const Color(0xFFFFFFFF),
      )
      ..restore();
  }

  /// The screen-space quad of a bridge tile's walkable surface: the
  /// cell diamond lifted onto the tile's plane — flat at deck height
  /// for bodies, sheared along the incline for ramps. [expand] grows
  /// or shrinks the quad from its centre (fraction of the half-tile):
  /// the two clip pieces overlap along the plane's edge so their
  /// anti-aliased boundaries never thin the sprite to a hairline.
  Path _bridgeSurfaceQuad(
    String role,
    CellCoord cell,
    Size size,
    double scale,
    Offset offset, {
    double expand = 0,
  }) {
    final deckLift = content.sprite('bridge.body.se')?.surfaceLift ?? 0;
    final centre = _cellWorldCenter(cell);
    final path = Path();
    var first = true;
    for (final (fx, fy, _) in bridgeSurfaceCorners(role, deckLift)) {
      final grownFx = fx * (1 + expand);
      final grownFy = fy * (1 + expand);
      final lift = bridgeSurfaceLift(role, grownFx, grownFy, deckLift);
      final world =
          centre +
          Offset(
            (grownFx - grownFy) * _logicalTileWidth / 2,
            (grownFx + grownFy) * _logicalTileHeight / 2 - lift,
          );
      final screen = _worldToScreen(world, size, scale, offset);
      if (first) {
        path.moveTo(screen.dx, screen.dy);
        first = false;
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    return path..close();
  }

  /// The wisp role for a fog cell — one of three, picked from a
  /// different slice of the placement hash so all variants appear.
  String _fogWispRole(int hash) => switch ((hash >> 9) % 3) {
    0 => 'fog.wisp.a',
    1 => 'fog.wisp.b',
    _ => 'fog.wisp.c',
  };

  /// Replays the fog wisps — large soft cloud sprites over the fog
  /// deck, drawn above the banks (clouds ride over roads and banks)
  /// and below everything standing. Each sprite spans two to three
  /// cells and is jittered within its cell by the same hash that
  /// picked it, so the scatter never reads as a lattice.
  void _drawFogWisps(Canvas canvas, Size size, List<_TerrainChunk> chunks) {
    for (final chunk in chunks) {
      for (final (cell, role) in chunk.fogWisps) {
        final path = content.tryAssetPath(role);
        final image = path == null ? null : images[path];
        if (image == null) continue;
        ParcelWorldProbe.countActor();
        final hash =
            (cell.column * 73856093) ^ (cell.row * 19349663) ^ state.seed;
        final jitterX = ((hash >> 3) % 17 - 8).toDouble();
        final jitterY = ((hash >> 6) % 9 - 4).toDouble();
        final center = _worldToScreen(
          _cellWorldCenter(cell) + Offset(jitterX, jitterY),
          size,
          scale,
          offset,
        );
        // Art is 2x world density (renderScale 0.5).
        final width = image.width * scale * 0.5;
        final height = image.height * scale * 0.5;
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromCenter(center: center, width: width, height: height),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }
  }

  /// Draws one cached chunk: its rasterized texture when fresh, or a
  /// replay of its world-space recording otherwise.
  void _blitChunk(Canvas canvas, Size size, _TerrainChunk chunk) {
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

  /// Roads, drawn per frame above every terrain chunk and below the
  /// shore banks. They used to bake into the chunk pictures,
  /// interleaved per cell with terrain — but the ground tiles'
  /// opaque skirts then painted over road art wherever a later cell
  /// (or a later chunk, at parcel boundaries) held plain terrain.
  /// Layered drawing — every ground tile before any road — is the
  /// standard tilemap order (Tiled layers, Godot tilemap layers,
  /// Unity sorting layers), and replaying the few dozen visible
  /// roads per frame is cheap next to the cached terrain.
  void _drawRoads(Canvas canvas, Size size, _CellBounds bounds) {
    // Road neighbour masks read the road set around the view.
    final roadCells = <CellCoord>{
      ...queries.roadsByCell.keys,
      for (final bridge in state.bridges) ...bridge.waterCells,
    };
    for (var row = bounds.top - 1; row <= bounds.bottom + 1; row++) {
      for (var column = bounds.left - 1; column <= bounds.right + 1; column++) {
        final cell = CellCoord(column, row);
        final road = queries.roadsByCell[cell];
        if (road == null) continue;
        final mask = roadNeighborMask(cell, roadCells);
        // Approach tiles beside a junction paint their pelican
        // crossing; every other road tile keeps its connector art.
        final role =
            roadCrossingRole(mask, cell, roadCells) ?? roadSpriteRole(mask);
        final path = content.tryAssetPath(role);
        final image = path == null ? null : images[path];
        final sprite = path == null ? null : content.sprite(role);
        if (image == null || sprite == null) continue;
        ParcelWorldProbe.countRoad();
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          _tileScreenRect(image, sprite, cell, size, scale, offset),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = const Color(0xFFFFFFFF),
        );
      }
    }
  }

  /// Shore bands: each banded water tile replays its composed
  /// overlay — the neighbouring land's material fading out over the
  /// water — through the camera transform. The overlay's canvas is
  /// the ground family's tile canvas, so the water sprite's placement
  /// metadata puts it exactly over its cell.
  void _drawShoreBands(Canvas canvas, Size size, List<_TerrainChunk> chunks) {
    final sprite = content.sprite('terrain.water');
    if (sprite == null) return;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = const Color(0xFFFFFFFF);
    for (final chunk in chunks) {
      for (final band in chunk.bands) {
        final image = bands[band.$2];
        if (image == null) continue;
        ParcelWorldProbe.countActor();
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          _tileScreenRect(image, sprite, band.$1, size, scale, offset),
          paint,
        );
      }
    }
  }

  /// The parcel's diamond outline in screen space.
  Path _parcelScreenPath(ParcelCoord parcel, Size size) {
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
    return path;
  }

  /// The faint cell grid — one renderer-owned lattice over every
  /// visible cell, replacing the inconsistent lines the ground art
  /// used to bake in. Each cell adds only its north and west edges, so
  /// shared edges never double-draw, and one colour reads over land,
  /// water, banks, and roads alike. Drawn above the terrain and below
  /// everything standing.
  void _drawTileGrid(Canvas canvas, Size size, _CellBounds bounds) {
    final grid = content.ambience.tileGrid;
    if (!grid.enabled) return;
    final path = Path();
    Offset corner(int column, int row) => _worldToScreen(
      _cellWorldCorner(CellCoord(column, row)),
      size,
      scale,
      offset,
    );
    for (var row = bounds.top - 1; row <= bounds.bottom + 1; row++) {
      for (var column = bounds.left - 1; column <= bounds.right + 1; column++) {
        // The fog is uncharted — no survey grid over the clouds.
        if (queries.terrainAt(CellCoord(column, row)).kind == TerrainKind.fog) {
          continue;
        }
        final north = corner(column, row);
        final east = corner(column + 1, row);
        final west = corner(column, row + 1);
        path
          ..moveTo(north.dx, north.dy)
          ..lineTo(east.dx, east.dy)
          ..moveTo(north.dx, north.dy)
          ..lineTo(west.dx, west.dy);
      }
    }
    final rgb = grid.colorRgb;
    canvas.drawPath(
      path,
      Paint()
        ..color = Color.fromARGB(grid.alpha, rgb[0], rgb[1], rgb[2])
        ..strokeWidth = math.max(1.0, scale)
        ..style = PaintingStyle.stroke,
    );
  }

  /// The settlement's usable area: a thick dashed white line along the
  /// boundary of the owned region — every owned-parcel edge that faces
  /// unowned land or open water. Edges between owned parcels draw
  /// nothing, so the whole owned region reads as one shape. The
  /// dashes are isometric parallelograms — long sides on the
  /// boundary's own grid angle, ends cut on the crossing angle — one
  /// period per tile edge, lattice-locked (see [_addIsoDashes]).
  /// Visible in every mode.
  void _drawOwnedOutline(
    Canvas canvas,
    Size size,
    _CellBounds bounds,
    _ViewportGeometry viewport,
  ) {
    var hasEdges = false;
    final path = Path();
    final thickness = math.max(2.0, 3.0 * scale);
    for (final coord in _visibleChunkCoords(bounds, viewport)) {
      if (!queries.ownsParcel(coord)) continue;
      final corners = _parcelCorners(coord);
      for (var side = 0; side < 4; side++) {
        if (queries.ownsParcel(coord.neighbors[side])) continue;
        final a = _worldToScreen(
          _cellWorldCorner(corners[side]),
          size,
          scale,
          offset,
        );
        final b = _worldToScreen(
          _cellWorldCorner(corners[(side + 1) % 4]),
          size,
          scale,
          offset,
        );
        hasEdges = true;
        _addIsoDashes(path, a, b, thickness, state.parcelSize);
      }
    }
    if (!hasEdges) return;
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xF2FFFFFF)
        ..style = PaintingStyle.fill,
    );
  }

  /// Appends the outline's dashes along one boundary segment, a to b:
  /// one lattice-locked parallelogram per tile edge. Every side of
  /// every dash sits on an isometric axis — the long sides follow the
  /// boundary's own angle, the ends are cut along the crossing angle
  /// — and each tile edge owns exactly one dash period with the dash
  /// centred on it, so the pattern divides the parcel side evenly
  /// ([cells] dashes, at every zoom) and meets parcel corners in
  /// phase, mid-gap on both edges that share a corner.
  void _addIsoDashes(
    Path path,
    Offset a,
    Offset b,
    double thickness,
    int cells,
  ) {
    final span = b - a;
    final length = span.distance;
    if (length <= 0 || cells <= 0) return;
    final along = span / length;
    // The crossing isometric direction: reflecting the edge direction
    // across the horizontal maps each iso angle onto its partner
    // (2:1 slope onto 1:2), so the dash ends follow the grid.
    final cross = Offset(along.dx, -along.dy);
    // The isometric angle pair encloses 53.13 degrees (cos 3/5,
    // sin 4/5); the ribbon's perpendicular thickness is h * sin, so
    // h compensates to keep the outline's visual weight.
    final half = cross * (thickness / 0.8 / 2);
    final dashLength = length / cells * 0.6;
    for (var i = 0; i < cells; i++) {
      final start = a + span * ((i + 0.2) / cells);
      final end = start + along * dashLength;
      final p0 = start - half;
      final p1 = start + half;
      final p2 = end + half;
      final p3 = end - half;
      path
        ..moveTo(p0.dx, p0.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..close();
    }
  }

  /// The four lattice corners of a parcel's diamond, in north, east,
  /// south, west order — edge `i` runs from corner `i` to corner
  /// `i + 1` and faces `coord.neighbors[i]`.
  List<CellCoord> _parcelCorners(ParcelCoord coord) {
    final origin = coord.origin(state.parcelSize);
    final size = state.parcelSize;
    return [
      origin,
      origin.offset(size, 0),
      origin.offset(size, size),
      origin.offset(0, size),
    ];
  }

  /// Parcel-mode overlay, drawn ground-level after the terrain: a
  /// strong grid over the unowned region — edges between unowned
  /// parcels (and toward open water; the owned frontier belongs to the
  /// dashed outline) — plus a soft highlight over the unowned parcel
  /// under the pointer, a desktop-only hover affordance. Inside the
  /// owned region nothing draws: the dashed white outline already
  /// marks it. The selected parcel keeps its own treatment in
  /// [_drawSelection].
  void _drawParcelGrid(
    Canvas canvas,
    Size size,
    _CellBounds bounds,
    _ViewportGeometry viewport,
  ) {
    final grid = Paint()
      ..color = const Color(0xE0537662)
      ..strokeWidth = math.max(1.5, 2.5 * scale)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    for (final coord in _visibleChunkCoords(bounds, viewport)) {
      // Fog parcels are hidden — no grid and no hover over the
      // clouds; there is nothing to buy there.
      final kind = content.terrain.parcels[coord];
      if (kind == null || kind == TerrainKind.fog) continue;
      if (queries.ownsParcel(coord)) continue;
      final corners = _parcelCorners(coord);
      for (var side = 0; side < 4; side++) {
        // The owned frontier is the dashed outline's job; boundaries
        // stay visible only within the unowned region.
        if (queries.ownsParcel(coord.neighbors[side])) continue;
        final a = _worldToScreen(
          _cellWorldCorner(corners[side]),
          size,
          scale,
          offset,
        );
        final b = _worldToScreen(
          _cellWorldCorner(corners[(side + 1) % 4]),
          size,
          scale,
          offset,
        );
        canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy),
          grid,
        );
      }
    }

    final hover = hoverCell;
    if (hover == null) return;
    final parcel = parcelForCell(hover, parcelSize: state.parcelSize);
    final hoverKind = content.terrain.parcels[parcel];
    if (hoverKind != null &&
        hoverKind != TerrainKind.fog &&
        !queries.ownsParcel(parcel) &&
        parcel != selectedParcel) {
      final path = _parcelScreenPath(parcel, size);
      canvas.drawPath(path, Paint()..color = const Color(0x224BC69B));
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF25745C)
          ..strokeWidth = math.max(1.0, 2.0 * scale)
          ..style = PaintingStyle.stroke,
      );
    }
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
  /// roads, and — separately, so it can draw above neighbouring
  /// chunks — the owned-parcel outline.
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

    final cells = [
      for (final cell in coord.cells(parcelSize))
        (cell, queries.terrainAt(cell), _cellWorldCenter(cell)),
    ];

    // Terrain pass. Roads deliberately do not bake into the chunk:
    // they draw as a per-frame layer above every chunk (see
    // [_drawRoads]) so no terrain skirt can ever paint over them.
    for (final (cell, terrain, center) in cells) {
      for (final role in _terrainSpriteRoles(cell, terrain)) {
        final path = content.tryAssetPath(role);
        if (path == null) continue;
        final image = images[path];
        if (image == null) continue;
        ParcelWorldProbe.countTerrain();
        _drawImageAtWorldCenter(canvas, image, center);
      }
      if (terrain.kind == TerrainKind.water) {
        // Shore bands are recorded as per-frame draws rather than
        // baked into the chunk picture: each neighbourhood's overlay
        // composes asynchronously the first time it is seen. Fog
        // cells never band — the cloud deck is their whole look, and
        // the boundary is deliberately plain.
        final pattern = shoreBandPattern(cell, queries.terrainAt);
        if (pattern != null) {
          chunk.bands.add((cell, pattern));
          onBandPattern(pattern);
        }
      }
      if (terrain.kind == TerrainKind.fog) {
        // Wisps: hash-scattered cloud sprites over roughly a third
        // of the fog cells. No boundary logic — the same rule
        // everywhere the fog is.
        final hash =
            (cell.column * 73856093) ^ (cell.row * 19349663) ^ state.seed;
        if (hash % 3 == 0) {
          chunk.fogWisps.add((cell, _fogWispRole(hash)));
        }
      }
    }

    // Wash pass, after every terrain tile in this chunk so the
    // later cells' opaque skirts cannot punch un-washed fringes
    // through the tint. The unowned wash is a parcel-mode cue;
    // normal play shows unowned terrain as-is. Fog parcels never
    // wash — they are unbuyable, and the cloud stays clean.
    if (parcelMode) {
      for (final (cell, terrain, center) in cells) {
        if (queries.ownsCell(cell) || terrain.kind == TerrainKind.fog) {
          continue;
        }
        ParcelWorldProbe.countWash();
        _drawWorldCellWash(canvas, center, content.ambience.unownedLandWash);
      }
    }

    chunk.picture = recorder.endRecording();
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
    } catch (_) {
      // Rasterization unavailable (for example without a GPU
      // context): keep drawing via the picture replay path.
      chunk.imageMatchesBucket = true;
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
    pedestrians.update(
      seconds,
      state,
      content.ambience.pedestrians,
      (role) => content.sprite(role)?.walkable ?? const [],
      deckLift: content.sprite('bridge.body.se')?.surfaceLift ?? 0,
    );
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
    for (final prop in queries.propsInBounds(
      left: bounds.left - 5,
      right: bounds.right + 5,
      top: bounds.top - 5,
      bottom: bounds.bottom + 5,
    )) {
      actors.add((
        propDepth(prop),
        () => _drawProp(canvas, size, prop, seconds),
      ));
    }
    // Bridge tiles draw split along their surface plane, both pieces
    // in the sort at fractional slots just above their cell: posts at
    // +0.02, surface at +0.05. The slots keep the pieces after
    // same-depth structures (the tie order the full sprites always
    // had) while posts(X) still draw before surface(X+1), exactly the
    // order the whole sprites stacked in — supports hang under the
    // next tile's art and show through its transparent gaps, the way
    // painter's order always painted them. Walkers on bridge tiles
    // floor their depth just above the surface (+0.1), so they stand
    // on decks and ramps without sinking under them, and never cross
    // the next cell's depth — buildings in front still occlude them.
    for (final (role, cell) in _bridgeTilesInBounds(bounds)) {
      final depth = (cell.column + cell.row).toDouble();
      actors.add((
        depth + 0.02,
        () => _drawBridgeTile(canvas, role, cell, size, scale, offset),
      ));
      actors.add((
        depth + 0.05,
        () => _drawBridgeTile(
          canvas,
          role,
          cell,
          size,
          scale,
          offset,
          surface: true,
        ),
      ));
    }
    for (final pedestrian in pedestrians.list) {
      actors.add((
        pedestrian.depth(pedestrians.lattice),
        () => _drawPedestrian(canvas, size, pedestrian, seconds),
      ));
    }
    actors.sort((a, b) => a.$1.compareTo(b.$1));
    for (final actor in actors) {
      actor.$2();
    }
  }

  /// How many span tiles of a bridge project are complete at its
  /// funded coin count: the near bank completes first, then span
  /// tiles, then the far bank.
  int _bridgeFundedSpanCount(WorldConstruction job) {
    final roadTileCost = content.economy.roadTileCostCoins;
    final bridgeTileCost = content.economy.bridgeTileCostCoins;
    var remaining = job.coinsFunded;
    if (remaining < roadTileCost) return 0;
    remaining -= roadTileCost;
    return (remaining ~/ bridgeTileCost).clamp(0, job.waterCells.length);
  }

  bool boundsOverlapsCells(_CellBounds bounds, List<CellCoord> cells) {
    for (final cell in cells) {
      if (cell.column >= bounds.left - 5 &&
          cell.column <= bounds.right + 5 &&
          cell.row >= bounds.top - 5 &&
          cell.row <= bounds.bottom + 5) {
        return true;
      }
    }
    return false;
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

  /// Draws a placed prop — same treatment as a structure (x-ray dim,
  /// vegetation sway), anchored at its subtile instead of a footprint.
  void _drawProp(Canvas canvas, Size size, PlacedProp prop, double seconds) {
    final definition = content.structure(prop.catalogueId)!;
    final role = prop.assetRole ?? definition.assetRoles.first;
    final image = images[content.tryAssetPathFor(role, prop.facing)];
    if (image == null) return;
    ParcelWorldProbe.countActor();
    final sprite = content.sprite(role)!;
    final rect = _worldRectToScreen(
      _propRect(
        image,
        sprite,
        prop,
        surfaceLift: _surfaceLift(prop.cell, queries, content),
      ),
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
      paint.color = const Color(0x66FFFFFF);
    }
    // A selected prop holds still: the selection wash repaints the
    // unswayed sprite, and the swaying original behind it used to
    // show through as a double image.
    if (!sprite.sways || prop.id == selectedPropId) {
      canvas.drawImageRect(image, source, rect, paint);
      return;
    }
    // Sway like vegetation, with the subtile folded into the phase so
    // props clustering on one tile rock out of step.
    final cell = prop.cell;
    final phase =
        cell.column * 1.7 +
        cell.row * 2.3 +
        prop.subtileX * 0.31 +
        prop.subtileY * 0.47;
    final sway = content.ambience.vegetationSway;
    final frequency =
        sway.baseFrequency +
        ((cell.column * 3 + cell.row * 7 + prop.subtileX + prop.subtileY * 3) %
                sway.frequencySteps) *
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
    final world = pedestrian.worldPosition(pedestrians.lattice);
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

  List<String> _terrainSpriteRoles(CellCoord cell, TerrainCell terrain) {
    // The deck is one periodic tile: every cell samples it at the
    // same world-anchored phase, so neighbours continue each other
    // seamlessly.
    if (terrain.kind == TerrainKind.fog) return const ['terrain.fog'];
    if (!terrain.isLand) return const ['terrain.water'];
    return [
      switch (terrain.groundStyle) {
        GroundStyle.grass => 'terrain.grass',
        GroundStyle.grassPuddle => 'terrain.grass.puddle',
        GroundStyle.dirt => 'terrain.dirt',
        GroundStyle.asphalt => 'terrain.asphalt',
        GroundStyle.concrete => 'terrain.concrete',
      },
    ];
  }

  /// Draws a tile sprite at its natural aspect ratio with the sprite's
  /// ground diamond aligned to the cell's diamond. Standard 128×64 ground
  /// tiles land exactly where the old fixed 64×32 rect put them; taller
  /// sprites such as bridge decks and ramps keep their height instead of
  /// being squashed, with [SpriteDefinition.baseOffsetY] letting content
  /// such as support posts hang below the cell.
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
        // Funded tiles are real roads now — road project tiles and
        // bridge banks alike — so the pending outline skips them,
        // matching how planned dirt ground skips completed cells.
        if (state.roadsByCell.containsKey(cell)) {
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
  /// bold overlay-style arrow bobbing above the site, pointing along
  /// the road side the door will face. Freezes along with the
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
    // The arrow points along the road side the door faces: north and
    // east run along the screen-right diagonal, south and west the left.
    final angle = switch (facing) {
      'north' => math.atan2(-1, 2),
      'east' => math.atan2(1, 2),
      'south' => math.atan2(1, -2),
      _ => math.atan2(-1, -2),
    };
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

  /// Translucent preview of the road or bridge line under
  /// construction by the active tool: the projected tiles show as
  /// translucent road art, and tiles that would make the quote fail
  /// (water, unowned, occupied) carry a red mark. The preview follows
  /// the cursor on desktop (hover); on touch it appears once the end
  /// tile is committed.
  void _drawLinePreview(Canvas canvas, Size size) {
    final roadPath = content.tryAssetPath('road.straight.se');
    final roadImage = roadPath == null ? null : images[roadPath];
    List<CellCoord>? line;
    var isBridge = false;
    if (roadStartCell case final start?) {
      line = roadPlanCells.isNotEmpty
          ? roadPlanCells
          : (hoverCell == null ? null : straightLineBetween(start, hoverCell!));
    } else if (bridgeStartCell case final start?) {
      isBridge = true;
      final end = bridgeEndCell ?? hoverCell;
      if (end != null && end != start) {
        line = straightLineBetween(start, end);
      }
    }
    if (line == null) return;

    bool validRoadCell(CellCoord cell) =>
        queries.ownsCell(cell) &&
        queries.terrainAt(cell).isLand &&
        !queries.roadsByCell.containsKey(cell) &&
        !queries.structuresByCell.containsKey(cell) &&
        !queries.reservedCells.contains(cell);
    bool validBridgeCell(CellCoord cell, bool isBank) =>
        queries.ownsCell(cell) &&
        (!isBank || queries.terrainAt(cell).isLand) &&
        !queries.roadsByCell.containsKey(cell) &&
        !queries.structuresByCell.containsKey(cell) &&
        !queries.reservedCells.contains(cell);

    for (var index = 0; index < line.length; index++) {
      final cell = line[index];
      final center = _worldToScreen(
        _cellWorldCenter(cell),
        size,
        scale,
        offset,
      );
      final valid = isBridge
          ? validBridgeCell(cell, index == 0 || index == line.length - 1)
          : validRoadCell(cell);
      final rect = Rect.fromCenter(
        center: center,
        width: _logicalTileWidth * scale,
        height: _logicalTileHeight * scale,
      );
      if (roadImage != null) {
        canvas.drawImageRect(
          roadImage,
          Rect.fromLTWH(
            0,
            0,
            roadImage.width.toDouble(),
            roadImage.height.toDouble(),
          ),
          rect,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = const Color(0x73FFFFFF),
        );
      } else {
        _drawCellOutline(
          canvas,
          center,
          const Color(0xFF8B682A),
          scale,
          fill: const Color(0x447BBE92),
        );
      }
      if (!valid) {
        _drawCellOutline(
          canvas,
          center,
          const Color(0xFFB3261E),
          scale,
          fill: const Color(0x66B3261E),
        );
      }
    }
  }

  void _drawSelection(Canvas canvas, Size size, WorldQueries queries) {
    if (selectedCell case final cell?) {
      // Selection highlights everything at the tapped cell: a
      // structure's whole footprint (with its sprite washed in the
      // selection colour), a bridge's full crossing between banks
      // (deck and ramps washed the same way), or the bare tile.
      final structure = queries.structuresByCell[cell];
      final bridge = structure == null ? _bridgeAt(cell) : null;
      final cells =
          structure?.footprint ??
          (bridge == null
              ? [cell]
              : [...bridge.waterCells, bridge.nearBank, bridge.farBank]);
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
      } else if (bridge != null) {
        _tintBridgeSprite(canvas, size, bridge);
      }
      if (selectedPropId case final id?) {
        final prop = queries.propsById[id];
        if (prop != null) {
          _tintPropSprite(canvas, size, prop);
        }
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
    // Section and project selections: road stretches between
    // junctions, whole bridge crossings, or an active project's span.
    for (final cell in highlightCells) {
      if (cell == selectedCell) continue;
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
        fill: const Color(0x224BC69B),
      );
    }
    if (selectedParcel case final parcel?) {
      _drawParcelSelection(canvas, size, parcel);
    }
    if (selectedCatalogueId != null) {
      final definition = content.structure(selectedCatalogueId!);
      if (definition != null) {
        // Placement validity for the decor preview: the same check
        // the quote runs, on the painter's prebuilt queries, so an
        // invalid spot shows red instead of green.
        bool propSpotValid(CellCoord cell, int subtileX, int subtileY) {
          try {
            checkPropPlacement(
              state,
              queries,
              definition: definition,
              cell: cell,
              subtileX: subtileX,
              subtileY: subtileY,
            );
            return true;
          } on WorldRuleViolation {
            return false;
          }
        }

        // The decor tool's ghost: a translucent sprite at the pending
        // subtile with a small diamond marking the target — the hover
        // point on desktop, the tapped cell and subtile on touch.
        if (definition.kind == StructureKind.decoration) {
          _drawPropGhost(canvas, size, definition, propSpotValid);
        }
        if (selectedCell != null) {
          final invalid =
              definition.kind == StructureKind.decoration &&
              !propSpotValid(selectedCell!, selectedSubtileX, selectedSubtileY);
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
              invalid ? const Color(0xFFB3261E) : const Color(0xFF367D63),
              scale,
              fill: invalid ? const Color(0x33B3261E) : const Color(0x334BC69B),
            );
          }
        }
        // Pre-placement preview: show the door side this plan would get,
        // using the same roll and road-side rule placement will apply.
        // The player's preview choice wins while roads touch both halves
        // and still name a bordering road.
        if (definition.kind == StructureKind.building && selectedCell != null) {
          final role =
              definition.assetRoles[(state.seed + state.nextEntityNumber) %
                  definition.assetRoles.length];
          final sprite = content.sprite(role);
          if (sprite != null && sprite.hasFacings) {
            // The arrow previews the placement's own derivation:
            // non-square lots probe the tapped cell and turn with
            // the door side; squares probe their turn-invariant
            // footprint.
            final probe =
                definition.footprintColumns != definition.footprintRows
                ? [selectedCell!]
                : structureFootprint(definition, selectedCell!);
            final doorSide = facingForPlacement(queries, probe, facingOverride);
            _drawFacingArrow(
              canvas,
              size,
              structureFootprint(
                definition,
                selectedCell!,
                quarterTurns: footprintTurnsFor(definition, doorSide),
              ),
              doorSide,
            );
          }
        }
      }
    }
  }

  /// The decor tool's placement ghost: a translucent sprite at the
  /// pending subtile — the hover point on desktop, the tapped cell
  /// and its subtile on touch — plus a small filled diamond on the
  /// target subtile. Approved as mockup A (prop_ghost_preview.png):
  /// a subtile diamond is only ~8×4 screen px, but together with the
  /// sprite it reads as "lands here". [spotValid] decides the
  /// palette: green when the placement quote would pass, red when it
  /// would not.
  void _drawPropGhost(
    Canvas canvas,
    Size size,
    StructureDefinition definition,
    bool Function(CellCoord cell, int subtileX, int subtileY) spotValid,
  ) {
    (CellCoord, int, int)? pending;
    if (hoverCell case final cell?) {
      // A pinned ghost holds the tapped spot even under the cursor.
      if (!ghostPinned) pending = (cell, hoverSubtileX, hoverSubtileY);
    }
    if (pending == null) {
      if (selectedCell case final cell?) {
        pending = (cell, selectedSubtileX, selectedSubtileY);
      }
    }
    if (pending == null) return;
    final (cell, subtileX, subtileY) = pending;
    final invalid = !spotValid(cell, subtileX, subtileY);

    final role = definition.assetRoles.first;
    final path = content.tryAssetPathFor(role, null);
    final image = path == null ? null : images[path];
    final sprite = content.sprite(role);
    if (image != null && sprite != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _worldRectToScreen(
          _propAnchorWorldRect(
            image,
            sprite,
            cell,
            subtileX,
            subtileY,
            surfaceLift: _surfaceLift(cell, queries, content),
          ),
          size,
          scale,
          offset,
        ),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = invalid ? const Color(0x73B3261E) : const Color(0x73FFFFFF),
      );
    }

    // The subtile diamond marker, centred on the target subtile.
    final fx = (subtileX + 0.5) / propSubtilesPerAxis - 0.5;
    final fy = (subtileY + 0.5) / propSubtilesPerAxis - 0.5;
    final center = _cellWorldCenter(cell);
    final marker = _worldToScreen(
      Offset(
        center.dx + (fx - fy) * _logicalTileWidth / 2,
        center.dy + (fx + fy) * _logicalTileHeight / 2,
      ),
      size,
      scale,
      offset,
    );
    final halfWidth = _logicalTileWidth / propSubtilesPerAxis / 2 * scale;
    final halfHeight = _logicalTileHeight / propSubtilesPerAxis / 2 * scale;
    final diamond = Path()
      ..moveTo(marker.dx, marker.dy - halfHeight)
      ..lineTo(marker.dx + halfWidth, marker.dy)
      ..lineTo(marker.dx, marker.dy + halfHeight)
      ..lineTo(marker.dx - halfWidth, marker.dy)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()
        ..color = invalid ? const Color(0x66B3261E) : const Color(0x804BC69B),
    );
    canvas.drawPath(
      diamond,
      Paint()
        ..color = invalid ? const Color(0xFFB3261E) : const Color(0xFF1E6552)
        ..strokeWidth = 1.5 * scale.clamp(0.7, 1.6)
        ..style = PaintingStyle.stroke,
    );
  }

  /// The bridge whose deck covers [cell]. Bank roads are shared with
  /// the road network, so tapping a bank stays a plain road tile; only
  /// the bridge's own deck cells select the crossing.
  CompletedBridge? _bridgeAt(CellCoord cell) {
    for (final bridge in state.bridges) {
      if (bridge.waterCells.contains(cell)) return bridge;
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

  /// Washes the selected prop's sprite in the selection colour — the
  /// same wash structures and bridges get, so a picked prop reads as
  /// picked however many share its tile.
  void _tintPropSprite(Canvas canvas, Size size, PlacedProp prop) {
    final definition = content.structure(prop.catalogueId)!;
    final role = prop.assetRole ?? definition.assetRoles.first;
    final image = images[content.tryAssetPathFor(role, prop.facing)];
    if (image == null) return;
    final sprite = content.sprite(role)!;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      _worldRectToScreen(
        _propRect(
          image,
          sprite,
          prop,
          surfaceLift: _surfaceLift(prop.cell, queries, content),
        ),
        size,
        scale,
        offset,
      ),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = const ColorFilter.mode(
          Color(0x664BC69B),
          BlendMode.srcATop,
        ),
    );
  }

  /// Washes the selected bridge's deck and ramps in the selection
  /// colour — the same wash structures get — so the crossing itself
  /// reads as picked, not just the tiles beneath it. The same roles
  /// and rects the actor pass draws, repainted through a colour
  /// filter — and in the actor pass's own depth order (base-cell
  /// column + row), so the wash stays a pure recolour: this pass
  /// runs above the actors, and painting the ramps after the bodies
  /// put whichever ramp is visually far on top of the deck tile
  /// that occludes it — the far end of the bridge drew over the
  /// bridge.
  void _tintBridgeSprite(Canvas canvas, Size size, CompletedBridge bridge) {
    const wash = ColorFilter.mode(Color(0x664BC69B), BlendMode.srcATop);
    void tinted(String role, CellCoord cell) {
      final path = content.tryAssetPath(role);
      final image = path == null ? null : images[path];
      final sprite = content.sprite(role);
      if (image == null || sprite == null) return;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _tileScreenRect(image, sprite, cell, size, scale, offset),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = wash,
      );
    }

    final bodyRole = bridgeBodyRole(bridge.nearBank, bridge.farBank);
    final pieces = <(double, void Function())>[
      for (final cell in bridge.waterCells)
        ((cell.column + cell.row).toDouble(), () => tinted(bodyRole, cell)),
      (
        (bridge.nearBank.column + bridge.nearBank.row).toDouble(),
        () => tinted(
          bridgeRampRole(bridge.nearBank, bridge.waterCells.first),
          bridge.nearBank,
        ),
      ),
      (
        (bridge.farBank.column + bridge.farBank.row).toDouble(),
        () => tinted(
          bridgeRampRole(bridge.farBank, bridge.waterCells.last),
          bridge.farBank,
        ),
      ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final piece in pieces) {
      piece.$2();
    }
  }

  /// The selected parcel in parcel mode: a light fill on owned land
  /// (unowned keeps just the outline so the map beneath still reads)
  /// and the strong green outline either way.
  void _drawParcelSelection(Canvas canvas, Size size, ParcelCoord parcel) {
    final path = _parcelScreenPath(parcel, size);
    // A dark wash over the whole parcel makes the selection readable
    // at a glance; the border carries the exact shape.
    canvas.drawPath(path, Paint()..color = const Color(0x4025745C));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF25745C)
        // Thicker than the owned outline's white dashes (which draw
        // under this line where a selected parcel meets owned land),
        // so the border stays dominant on those sides too, and
        // scaled so it keeps its weight at every zoom.
        ..strokeWidth = math.max(2.5, 4.0 * scale)
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
      oldDelegate.selectedPropId != selectedPropId ||
      oldDelegate.selectedSubtileX != selectedSubtileX ||
      oldDelegate.selectedSubtileY != selectedSubtileY ||
      oldDelegate.hoverSubtileX != hoverSubtileX ||
      oldDelegate.hoverSubtileY != hoverSubtileY ||
      oldDelegate.ghostPinned != ghostPinned ||
      oldDelegate.bridgeStartCell != bridgeStartCell ||
      oldDelegate.bridgeEndCell != bridgeEndCell ||
      oldDelegate.facingOverride != facingOverride ||
      oldDelegate.dimStructures != dimStructures ||
      oldDelegate.parcelMode != parcelMode ||
      oldDelegate.showTileGrid != showTileGrid ||
      !listEquals(oldDelegate.roadPlanCells, roadPlanCells) ||
      oldDelegate.roadStartCell != roadStartCell ||
      !setEquals(oldDelegate.highlightCells, highlightCells) ||
      oldDelegate.hoverCell != hoverCell;
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
  final rect = Rect.fromLTWH(
    anchorX - width * sprite.groundAnchorX,
    bottomY - height * sprite.groundAnchorY,
    width,
    height,
  );
  // The per-side shift tunes the art against its road; picking and
  // tinting share this rect, so taps follow the shift.
  final facing = structure.facing;
  if (facing == null) return rect;
  return rect.shift(
    sideShiftOffset(sprite, facing, image.width * sprite.renderScale),
  );
}

/// World-space offset for a sprite's per-side shift: col runs along
/// the column axis (screen down-right, east-positive), row along the
/// row axis (screen down-left, south-positive), both as fractions of
/// the drawn width. A side with no entry keeps the anchor placement.
Offset sideShiftOffset(SpriteDefinition sprite, String? facing, double width) {
  final shift = sprite.sideShiftFor(facing);
  if (shift == null) return Offset.zero;
  final (col, row) = shift;
  return Offset((col - row) * width, (col + row) * width / 2);
}

/// World rect for a prop: the sprite's ground anchor pinned to its
/// subtile's centre, leaning toward its saved road facing.
Rect _propRect(
  ui.Image image,
  SpriteDefinition sprite,
  PlacedProp prop, {
  double surfaceLift = 0,
}) {
  final rect = _propAnchorWorldRect(
    image,
    sprite,
    prop.cell,
    prop.subtileX,
    prop.subtileY,
    surfaceLift: surfaceLift,
  );
  // The per-side shift tunes the art against its road.
  final facing = prop.facing;
  if (facing == null) return rect;
  return rect.shift(
    sideShiftOffset(sprite, facing, image.width * sprite.renderScale),
  );
}

/// The sprite's ground anchor pinned to a subtile's centre — the
/// same point the ghost marker diamonds, so a placed prop stands
/// inside the slot it was given. (Props once anchored at the
/// subtile's south vertex so pre-lattice [propFrontSubtile]
/// placements rendered pixel-identically to the 1×1 structures they
/// migrated from; point objects read better centred on their slot,
/// so the legacy nudge is gone.)
/// [surfaceLift] raises the anchor onto elevated ground — today, a
/// bridge deck.
Rect _propAnchorWorldRect(
  ui.Image image,
  SpriteDefinition sprite,
  CellCoord cell,
  int subtileX,
  int subtileY, {
  double surfaceLift = 0,
}) {
  final center = _cellWorldCenter(cell);
  final fx = (subtileX + 0.5) / propSubtilesPerAxis - 0.5;
  final fy = (subtileY + 0.5) / propSubtilesPerAxis - 0.5;
  final anchorX = center.dx + (fx - fy) * _logicalTileWidth / 2;
  final anchorY = center.dy + (fx + fy) * _logicalTileHeight / 2 - surfaceLift;
  final width = image.width * sprite.renderScale;
  final height = image.height * sprite.renderScale;
  return Rect.fromLTWH(
    anchorX - width * sprite.groundAnchorX,
    anchorY - height * sprite.groundAnchorY,
    width,
    height,
  );
}

/// Depth for a prop in the shared actor pass. The fraction is the
/// anchor's subtile position at HALF weight — (sx + sy + 1) / 16 — so
/// every prop stays strictly inside its tile's depth slot: a
/// front-corner prop still draws behind whatever stands on the tile
/// in front, exactly like the 1×1 structures props used to be.
/// Pedestrian-weight fractions would let front-corner props paint
/// over front-tile actors.
@visibleForTesting
double propDepth(PlacedProp prop) =>
    (prop.cell.column + prop.cell.row) +
    (prop.subtileX + prop.subtileY + 1) / (propSubtilesPerAxis * 2);

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

/// World-space rect covering every cell diamond in a parcel chunk,
/// plus a margin so the tiles' opaque skirts (2 world px past their
/// diamonds, added 2026-11-10 to stop background bleed along tile and
/// parcel seams) and anti-aliased edges survive rasterization.
Rect _chunkWorldRect(ParcelCoord parcel, int parcelSize) {
  const margin = 4.0;
  return _parcelWorldRect(parcel, parcelSize).inflate(margin);
}

/// The world-space diamond bounding box of one parcel — the parcel's
/// ground diamond, axis-aligned. Shared by the chunk rects and the
/// camera's play area.
Rect _parcelWorldRect(ParcelCoord parcel, int parcelSize) {
  final firstColumn = parcel.x * parcelSize;
  final firstRow = parcel.y * parcelSize;
  return Rect.fromLTRB(
    (firstColumn - firstRow - parcelSize) * _logicalTileWidth / 2,
    (firstColumn + firstRow) * _logicalTileHeight / 2 - _logicalTileHeight / 2,
    (firstColumn - firstRow + parcelSize) * _logicalTileWidth / 2,
    (firstColumn + firstRow + 2 * parcelSize - 1) * _logicalTileHeight / 2,
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

/// Screen rect for a tile-fit sprite at [cell] — width stretched to
/// the tile, height kept at the art's aspect, hanging below the
/// diamond by the sprite's baseOffsetY. Shared by tile drawing, the
/// water grid, the bridge selection tint, and bridge hit-testing.
Rect _tileScreenRect(
  ui.Image image,
  SpriteDefinition sprite,
  CellCoord cell,
  Size size,
  double scale,
  Offset offset,
) {
  final center = _worldToScreen(_cellWorldCenter(cell), size, scale, offset);
  final unit = (_logicalTileWidth * scale) / image.width;
  final width = image.width * unit;
  final height = image.height * unit;
  final southVertexY =
      center.dy + (_logicalTileHeight / 2) * scale + sprite.baseOffsetY * unit;
  return Rect.fromLTWH(
    center.dx - width / 2,
    southVertexY - height,
    width,
    height,
  );
}

/// World-px lift for things standing on a cell. Bridge decks are the
/// one elevated surface today: the body sprite's [SpriteDefinition
/// .surfaceLift] says how far its deck sits above the ground plane —
/// measured at 12 world px for the current art. Ground cells lift
/// nothing. This is the seed of the future terrain-elevation lookup
/// (see the prop plan's future notes).
double _surfaceLift(
  CellCoord cell,
  WorldQueries queries,
  ContentBundle content,
) {
  if (!queries.bridgeDeckCells.contains(cell)) return 0;
  return content.sprite('bridge.body.se')?.surfaceLift ?? 0;
}

/// The subtile of [world] within its own nearest cell — where on the
/// 8×8 lattice a tap or hover lands. Offsets from the cell centre:
/// one column runs (+32, +16) world px and one row (−32, +16), so the
/// inverse halves the sum and difference of the axis-normalized
/// terms. Points just outside a cell diamond clamp to its edge
/// subtiles; the subtile is relative to the tap's own nearest cell,
/// which is also the reported cell for ground taps (the only hits
/// placement tools consume).
(int, int) _subtileUnder(Offset world) {
  final cell = _nearestCell(world);
  final center = _cellWorldCenter(cell);
  final dx = world.dx - center.dx;
  final dy = world.dy - center.dy;
  final columnTerm = dx / (_logicalTileWidth / 2);
  final rowTerm = dy / (_logicalTileHeight / 2);
  final fx = (columnTerm + rowTerm) / 2;
  final fy = (rowTerm - columnTerm) / 2;
  final subtileX = ((fx + 0.5) * propSubtilesPerAxis).floor().clamp(
    0,
    propSubtilesPerAxis - 1,
  );
  final subtileY = ((fy + 0.5) * propSubtilesPerAxis).floor().clamp(
    0,
    propSubtilesPerAxis - 1,
  );
  return (subtileX, subtileY);
}

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

  /// Shore-band draws for this chunk's banded water tiles — one
  /// (cell, pattern) per water cell with land in its eight
  /// neighbourhood — replayed every frame instead of baked into
  /// [picture], because the pattern's overlay composes asynchronously
  /// after the chunk records.
  final List<(CellCoord, String)> bands = [];

  /// Fog-wisp draws for this chunk's fog cells — one (cell, role)
  /// per hash-scattered cloud sprite — replayed every frame above
  /// the banks. Per-frame rather than baked because the sprites
  /// overhang their cell, and the chunk picture is clipped to its
  /// rect; replaying keeps every wisp whole.
  final List<(CellCoord, String)> fogWisps = [];

  /// Cache generation this chunk was recorded in.
  int generation = -1;

  /// Monotonic stamp of the last frame that drew this chunk.
  int lastUsed = 0;

  void dispose() {
    picture?.dispose();
    image?.dispose();
    rasterWrapper?.dispose();
    picture = null;
    image = null;
    rasterWrapper = null;
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
  bool parcelModeKey = false;
  double textureFactor = 1;
  int generation = 0;
  int _stamp = 0;

  /// Cap on cached chunks as a safety net. Panning is clamped to the
  /// charted map plus its fog margin, so roaming cannot grow the
  /// cache without bound on its own; the least recently drawn are
  /// evicted when it somehow does.
  static const int _maxChunks = 400;

  int nextStamp() => ++_stamp;

  /// Drops every chunk when the world, the sprite set, or the terrain
  /// view mode changed — parcel mode swaps the ground tiles, the
  /// unowned wash, and the owned outlines inside the recording.
  void resetFor(Object world, int images, bool parcelMode) {
    if (worldKey == world &&
        imageCount == images &&
        parcelModeKey == parcelMode) {
      return;
    }
    worldKey = world;
    imageCount = images;
    parcelModeKey = parcelMode;
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

/// Render-only pedestrians that wander the painted walkable lattice —
/// sidewalks and crossings authored per road role in the editor. They
/// are deliberately excluded from world state and saves: ambience
/// never affects gameplay, and a reload simply repopulates the
/// streets.
class _PedestrianSim {
  final List<_Pedestrian> list = [];
  int _roadCount = -1;
  int _bridgeCount = -1;
  double _lastSeconds = 0;

  /// The walkable surface, rebuilt whenever the road or bridge count
  /// changes, together with the population reconcile. Blank content
  /// (the shipping state) yields an empty lattice: nobody walks until
  /// the road roles are painted.
  PedestrianLattice lattice = PedestrianLattice(
    roadCells: const {},
    connectionCells: const {},
    maskFor: _blankMask,
  );

  static List<int> _blankMask(String role) => const [];

  void update(
    double seconds,
    ParcelWorldState state,
    PedestrianContent pedestrians,
    List<int> Function(String role) maskFor, {
    double deckLift = 0,
  }) {
    // Pedestrians wander every completed ground road's painted
    // subtiles plus the painted bridge surfaces. Bridge decks are
    // elevated, so people on them render lifted, not sunk.
    final roadCells = <CellCoord>{for (final road in state.roads) road.cell};
    // Bridge completion changes the walkable surface without touching
    // the road count — banks were already roads — so it triggers too.
    if (roadCells.length != _roadCount ||
        state.bridges.length != _bridgeCount) {
      _roadCount = roadCells.length;
      _bridgeCount = state.bridges.length;
      _lastSeconds = seconds;
      _reconcile(roadCells, state, pedestrians, maskFor, deckLift);
      return;
    }
    final dt = (seconds - _lastSeconds).clamp(0.0, 0.25);
    _lastSeconds = seconds;
    if (dt <= 0) return;
    final random = math.Random();
    for (final pedestrian in list) {
      pedestrian.advance(dt, lattice, random);
    }
  }

  void _reconcile(
    Set<CellCoord> roadCells,
    ParcelWorldState state,
    PedestrianContent pedestrians,
    List<int> Function(String role) maskFor,
    double deckLift,
  ) {
    // Banks are road tiles with ramp art over them; they join the
    // lattice as ramps instead, so painted straight masks never put
    // people under them. The connection set keeps every road (and
    // bridge water cell) so the remaining tiles still resolve their
    // true roles.
    lattice = PedestrianLattice(
      roadCells: pedestrianRoadCells(state),
      connectionCells: {
        ...roadCells,
        for (final bridge in state.bridges) ...bridge.waterCells,
      },
      maskFor: maskFor,
      bridgeRoles: pedestrianBridgeRoles(state),
      deckLift: deckLift,
    );
    // Walkers caught on retired paint — or removed roads — go away.
    list.removeWhere(
      (pedestrian) =>
          !lattice.containsSpot(pedestrian.from) ||
          !lattice.containsSpot(pedestrian.to),
    );
    // The population formula stays road-cell based, capped by the
    // paint that actually exists: an unpainted world is empty.
    final target = math.min(
      (roadCells.length / pedestrians.roadCellsPerPerson).floor().clamp(
        0,
        pedestrians.maxCount,
      ),
      lattice.walkableCount,
    );
    while (list.length > target) {
      list.removeLast();
    }
    final random = math.Random(state.seed + roadCells.length);
    while (list.length < target) {
      final from = lattice.randomSpawn(random);
      if (from == null) break;
      final next = _pickNext(from, null, lattice, random);
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

LatticeSpot? _pickNext(
  LatticeSpot spot,
  LatticeSpot? previous,
  PedestrianLattice lattice,
  math.Random random,
) {
  final neighbors = lattice.neighborsOf(spot);
  var options = [
    for (final next in neighbors)
      if (next != previous) next,
  ];
  if (options.isEmpty) {
    // A painted dead end turns the walker around.
    options = neighbors;
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
  LatticeSpot from;
  LatticeSpot to;

  /// Cells per second; one cell is [propSubtilesPerAxis] subtiles, so
  /// progress advances through subtiles at eight times this rate.
  final double speed;
  final double phase;
  final Offset offset;
  double progress = 0;

  void advance(double dt, PedestrianLattice lattice, math.Random random) {
    progress += speed * propSubtilesPerAxis * dt;
    while (progress >= 1) {
      final previous = from;
      from = to;
      final next = _pickNext(from, previous, lattice, random);
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
  /// SE, south (row +1) is SW, and west (col −1) is NW. Steps across a
  /// cell border fold into the same compass (seven subtiles plus a border
  /// is one more subtile east, not a whole cell).
  String get _direction {
    final columnSteps =
        (to.cell.column - from.cell.column) * propSubtilesPerAxis +
        to.x -
        from.x;
    final rowSteps =
        (to.cell.row - from.cell.row) * propSubtilesPerAxis + to.y - from.y;
    if (rowSteps < 0) return 'NE';
    if (columnSteps > 0) return 'SE';
    if (rowSteps > 0) return 'SW';
    return 'NW';
  }

  String assetPath(double seconds, double walkFrameRate) {
    final frame = ((seconds * walkFrameRate + phase).floor() % 4) + 1;
    return 'assets/characters/'
        'char_${character}_walk_${_direction}_f0$frame.png';
  }

  /// Where the walker stands in world space, lifted onto elevated
  /// surfaces: a person crossing a bank tile climbs the ramp's
  /// incline and stands at deck height over the water.
  Offset worldPosition(PedestrianLattice lattice) {
    final a = _spotWorldCenter(from);
    final b = _spotWorldCenter(to);
    final lift =
        lattice.liftAt(from) +
        (lattice.liftAt(to) - lattice.liftAt(from)) * progress;
    return Offset(
          a.dx + (b.dx - a.dx) * progress,
          a.dy + (b.dy - a.dy) * progress - lift,
        ) +
        offset;
  }

  /// Painter's depth, lerped between the spots' sort depths. Bridge
  /// spots floor theirs just above their tile's surface piece; ground
  /// spots keep the plain ground depth; mixed road↔ramp steps blend
  /// across the seam.
  double depth(PedestrianLattice lattice) {
    final a = lattice.walkerSortDepth(from);
    final b = lattice.walkerSortDepth(to);
    return a + (b - a) * progress;
  }
}

/// Where a lattice spot's subtile centre sits in world space — the
/// same placement the props renderer uses, so people and street
/// furniture share one subtile geometry.
Offset _spotWorldCenter(LatticeSpot spot) {
  final fx = (spot.x + 0.5) / propSubtilesPerAxis - 0.5;
  final fy = (spot.y + 0.5) / propSubtilesPerAxis - 0.5;
  return _cellWorldCenter(spot.cell) +
      Offset(
        (fx - fy) * _logicalTileWidth / 2,
        (fx + fy) * _logicalTileHeight / 2,
      );
}
