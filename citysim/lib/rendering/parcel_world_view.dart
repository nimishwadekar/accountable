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

  /// Composed bank overlays — the ground material cut by its baked
  /// shore mask — keyed by shore role ('shore.grass.quarter.sw').
  /// Filled after the material and mask sprites load.
  final Map<String, ui.Image> _bankImages = {};

  /// Guards [_composeShoreBanks] against overlapping runs when
  /// [_loadMissingImages] is re-triggered mid-composition.
  bool _composingBanks = false;

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
                  banks: _bankImages,
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
    await _composeShoreBanks();
  }

  /// The twelve shore shapes; each has one baked mask shared by the
  /// grass and dirt materials.
  static const _shoreShapes = [
    ('edge', 'n'),
    ('edge', 'e'),
    ('edge', 's'),
    ('edge', 'w'),
    ('corner', 'n'),
    ('corner', 'e'),
    ('corner', 's'),
    ('corner', 'w'),
    ('quarter', 'ne'),
    ('quarter', 'nw'),
    ('quarter', 'se'),
    ('quarter', 'sw'),
  ];

  /// Composes every bank overlay the shoreline can draw: the terrain
  /// material cut by its shape's baked mask — Factorio-style, the mask
  /// shared by the grass and dirt materials. Each mask's pixels are
  /// read once and cut by both materials; runs after sprite loads and
  /// skips roles already composed.
  Future<void> _composeShoreBanks() async {
    if (_composingBanks) return;
    _composingBanks = true;
    try {
      final content = widget.content;
      final maskPixels = <String, Uint8List>{};
      for (final (family, dir) in _shoreShapes) {
        final maskPath = content.tryAssetPath('shore.$family.$dir');
        final mask = maskPath == null ? null : _images[maskPath];
        if (mask == null) continue;
        final data = await mask.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (data == null) continue;
        maskPixels['$family.$dir'] = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      }
      for (final style in const ['grass', 'dirt']) {
        final materialPath = content.tryAssetPath('terrain.$style');
        final material = materialPath == null ? null : _images[materialPath];
        if (material == null) continue;
        final matData = await material.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (matData == null) continue;
        final matPixels = matData.buffer.asUint8List(
          matData.offsetInBytes,
          matData.lengthInBytes,
        );
        for (final (family, dir) in _shoreShapes) {
          final role = 'shore.$style.$family.$dir';
          if (_bankImages.containsKey(role)) continue;
          final msk = maskPixels['$family.$dir'];
          if (msk == null) continue;
          final bank = await decodeRgbaImage(
            composeShoreBankPixels(
              matPixels,
              msk,
              material.width,
              material.height,
            ),
            material.width,
            material.height,
          );
          if (!mounted) {
            bank?.dispose();
            return;
          }
          if (bank != null) setState(() => _bankImages[role] = bank);
        }
      }
    } finally {
      _composingBanks = false;
    }
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

/// Composes one bank overlay from decoded images: the ground material
/// cut by the baked shore mask. See [composeShoreBankPixels].
Future<ui.Image?> composeShoreBank(ui.Image material, ui.Image mask) async {
  try {
    if (material.width != mask.width || material.height != mask.height) {
      return null;
    }
    final matData = await material.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    final maskData = await mask.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (matData == null || maskData == null) return null;
    final matPixels = matData.buffer.asUint8List(
      matData.offsetInBytes,
      matData.lengthInBytes,
    );
    final maskPixels = maskData.buffer.asUint8List(
      maskData.offsetInBytes,
      maskData.lengthInBytes,
    );
    return await decodeRgbaImage(
      composeShoreBankPixels(
        matPixels,
        maskPixels,
        material.width,
        material.height,
      ),
      material.width,
      material.height,
    );
  } catch (_) {
    return null;
  }
}

/// Decodes premultiplied RGBA bytes into a [ui.Image] through the raw
/// descriptor (the same path the old runtime bank mask used).
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

/// Composes bank pixels (premultiplied): the ground material cut by
/// the baked shore mask (greyscale — the waterline gradient).
///
/// The material's transparent pixels are repaired first, but only
/// where the mask has coverage — elsewhere the RGB is never sampled.
/// The pack art carries a jagged transparent fringe along its diamond
/// edges and small alpha holes near the waterline; the mask is opaque
/// in places the material never painted, which would otherwise draw
/// solid black edge pixels along the bank's borders. Colours dilate
/// from the nearest painted neighbour; alpha stays 0 so the mask
/// alone decides opacity. The input [matPixels] is not modified.
Uint8List composeShoreBankPixels(
  Uint8List matPixels,
  Uint8List maskPixels,
  int width,
  int height,
) {
  final pixels = Uint8List.fromList(matPixels);

  final needing = <int>[];
  for (var i = 0; i < width * height; i++) {
    if (maskPixels[i * 4] > 0 && pixels[i * 4 + 3] == 0) {
      needing.add(i);
    }
  }
  final repaired = Uint8List(width * height);
  var remaining = needing.length;
  while (remaining > 0) {
    var progress = false;
    for (final i in needing) {
      if (repaired[i] == 1) continue;
      final x = i % width;
      final y = i ~/ width;
      for (final delta in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nx = x + delta.$1;
        final ny = y + delta.$2;
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
        final j = ny * width + nx;
        if (pixels[j * 4 + 3] == 0 && repaired[j] == 0) continue;
        pixels[i * 4] = pixels[j * 4];
        pixels[i * 4 + 1] = pixels[j * 4 + 1];
        pixels[i * 4 + 2] = pixels[j * 4 + 2];
        repaired[i] = 1;
        remaining--;
        progress = true;
        break;
      }
    }
    if (!progress) break; // Unfillable island: leave as-is.
  }

  // Cut the material through the mask; premultiplied output.
  for (var i = 0; i < width * height; i++) {
    final a = maskPixels[i * 4];
    pixels[i * 4] = (pixels[i * 4] * a / 255).round();
    pixels[i * 4 + 1] = (pixels[i * 4 + 1] * a / 255).round();
    pixels[i * 4 + 2] = (pixels[i * 4 + 2] * a / 255).round();
    pixels[i * 4 + 3] = a;
  }
  return pixels;
}

/// Bank overlays for an outermost water tile: the land-coloured half
/// of the shore pieces, drawn over the water so the shore runs half a
/// tile into the lake instead of the water running half a tile into
/// the land. Land tiles stay dry; their plain ground shows right up to
/// the tile boundary.
///
/// The piece selection mirrors the pre-2026-11 land-side rule with the
/// neighbour test flipped — land neighbours instead of water — which
/// swaps the edge and corner families' roles: two adjacent land
/// neighbours leave a single water wedge (a corner piece's "everything
/// else" bank), and a diagonal-only land neighbour gets a bank wedge
/// (an edge piece's vertex wedge). The pack's sprite families,
/// verified from their pixels:
/// - quarter (water_NE/SE/SW/NW): water along one edge plus the two
///   adjacent vertex wedges — as a bank, the dry half facing one land
///   neighbour;
/// - edge (wateredge_N/E/S/W): water across a full half tile minus one
///   vertex wedge — as a bank, a wedge of land reaching a diagonal
///   neighbour;
/// - corner (watercorner_N/E/S/W): a small water notch at one vertex —
///   as a bank, everything except the wedge of water two adjacent land
///   neighbours leave behind.
List<String> waterBankRoles(
  CellCoord cell,
  TerrainCell Function(CellCoord) terrainAt,
) {
  // Each cardinal neighbour contributes its shore style when it is
  // land; the style follows the land the bank belongs to, so future
  // ground types pick their own shore family.
  String? bankStyle(int dx, int dy) {
    final terrain = terrainAt(cell.offset(dx, dy));
    if (!terrain.isLand) return null;
    return terrain.groundStyle == GroundStyle.dirt ? 'dirt' : 'grass';
  }

  final north = bankStyle(0, -1);
  final east = bankStyle(1, 0);
  final south = bankStyle(0, 1);
  final west = bankStyle(-1, 0);
  // A one-cell pond surrounded by land stays open water: the bank
  // halves would blanket it entirely.
  if (north != null && east != null && south != null && west != null) {
    return const [];
  }

  final roles = <String>[];
  var n = north;
  var e = east;
  var s = south;
  var w = west;
  // Two adjacent land neighbours meet at a vertex; the bank floods
  // both their halves and leaves water only at the opposite vertex's
  // wedge — the corner piece there. The pair's style comes from the
  // first neighbour in north/east/south/west order.
  if (n != null && e != null) {
    roles.add('shore.$n.corner.w');
    n = null;
    e = null;
  } else if (e != null && s != null) {
    roles.add('shore.$e.corner.n');
    e = null;
    s = null;
  } else if (s != null && w != null) {
    roles.add('shore.$s.corner.e');
    s = null;
    w = null;
  } else if (w != null && n != null) {
    roles.add('shore.$n.corner.s');
    w = null;
    n = null;
  }
  // Single land neighbours bank the half of the tile facing them.
  // (Opposite pairs — land north and south, or east and west — cover
  // the tile between them; parcel-granular terrain cannot author the
  // one-tile channels that would need it, and a half-bank each side
  // reads as the shoreline pinching shut.)
  if (n != null) roles.add('shore.$n.quarter.sw');
  if (e != null) roles.add('shore.$e.quarter.nw');
  if (s != null) roles.add('shore.$s.quarter.ne');
  if (w != null) roles.add('shore.$w.quarter.se');

  // Land touching only a diagonal corner fills the shared vertex with
  // a bank wedge, unless a cardinal bank already covers it.
  if (north == null && west == null && bankStyle(-1, -1) != null) {
    roles.add('shore.${bankStyle(-1, -1)}.edge.s');
  }
  if (north == null && east == null && bankStyle(1, -1) != null) {
    roles.add('shore.${bankStyle(1, -1)}.edge.w');
  }
  if (east == null && south == null && bankStyle(1, 1) != null) {
    roles.add('shore.${bankStyle(1, 1)}.edge.n');
  }
  if (south == null && west == null && bankStyle(-1, 1) != null) {
    roles.add('shore.${bankStyle(-1, 1)}.edge.e');
  }
  return roles;
}

class _WorldHit {
  const _WorldHit(this.cell, this.structureId);

  final CellCoord cell;
  final String? structureId;
}

/// Strokes [source] as dashes — [dash] drawn, [gap] skipped, in the
/// path's own coordinate units — so the result scales with whatever
/// transform the source was built in.
Path _dashPath(Path source, double dash, double gap) {
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var draw = true;
    while (distance < metric.length) {
      final length = draw ? dash : gap;
      final next = math.min(distance + length, metric.length);
      if (draw) {
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
      }
      distance = next;
      draw = !draw;
    }
  }
  return dashed;
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
    required this.banks,
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

  /// Composed bank overlays by shore role — the ground material cut
  /// by the baked shape mask.
  final Map<String, ui.Image> banks;

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
    // Authored terrain is uniform per parcel, so the origin cell's
    // kind classifies the chunk.
    final waterChunks = <_TerrainChunk>[];
    final landChunks = <_TerrainChunk>[];
    for (final chunk in drawn) {
      final origin = chunk.coord.origin(state.parcelSize);
      (queries.terrainAt(origin).isLand ? landChunks : waterChunks).add(chunk);
    }
    for (final chunk in waterChunks) {
      _blitChunk(canvas, size, chunk);
    }
    for (final chunk in landChunks) {
      _blitChunk(canvas, size, chunk);
    }
    _drawRoads(canvas, size, bounds);
    _drawShoreBanks(canvas, size, drawn);
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
        final role = roadSpriteRole(roadNeighborMask(cell, roadCells));
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

  /// Shore banks: each bank tile replays its composed overlay — the
  /// ground material cut by the baked shape mask — through the camera
  /// transform. The mask's water half is transparent, so the water
  /// tile beneath stays visible while the bank reads as dry land in
  /// the neighbouring style's material.
  void _drawShoreBanks(Canvas canvas, Size size, List<_TerrainChunk> chunks) {
    for (final chunk in chunks) {
      for (final bank in chunk.banks) {
        _drawBankRole(canvas, bank.$2, bank.$1, size, scale, offset);
      }
    }
  }

  /// Draws one composed bank tile. Bank roles carry the material
  /// style ('shore.grass.quarter.sw'); the sprite metadata comes from
  /// the shape's mask entry.
  void _drawBankRole(
    Canvas canvas,
    String role,
    CellCoord cell,
    Size size,
    double scale,
    Offset offset,
  ) {
    final image = banks[role];
    if (image == null) return;
    final parts = role.split('.');
    final sprite = content.sprite('shore.${parts[2]}.${parts[3]}');
    if (sprite == null) return;
    ParcelWorldProbe.countActor();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      _tileScreenRect(image, sprite, cell, size, scale, offset),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = const Color(0xFFFFFFFF),
    );
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
  /// nothing, so the whole owned region reads as one shape. Visible in
  /// every mode.
  void _drawOwnedOutline(
    Canvas canvas,
    Size size,
    _CellBounds bounds,
    _ViewportGeometry viewport,
  ) {
    var hasEdges = false;
    final path = Path();
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
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }
    }
    if (!hasEdges) return;
    canvas.drawPath(
      _dashPath(path, 10 * scale, 6 * scale),
      Paint()
        ..color = const Color(0xF2FFFFFF)
        ..strokeWidth = math.max(2.0, 3.0 * scale)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
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
      if (!content.terrain.parcels.containsKey(coord)) continue;
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
    if (content.terrain.parcels.containsKey(parcel) &&
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
      final roles = terrain.isLand
          ? _terrainSpriteRoles(cell, terrain)
          : const ['terrain.water'];
      for (final role in roles) {
        final path = content.tryAssetPath(role);
        if (path == null) continue;
        final image = images[path];
        if (image == null) continue;
        ParcelWorldProbe.countTerrain();
        _drawImageAtWorldCenter(canvas, image, center);
      }
      if (!terrain.isLand) {
        // Shore banks are recorded as per-frame draws rather than
        // baked into the chunk picture.
        for (final role in waterBankRoles(cell, queries.terrainAt)) {
          chunk.banks.add((cell, role));
        }
      }
    }

    // Wash pass, after every terrain tile in this chunk so the
    // later cells' opaque skirts cannot punch un-washed fringes
    // through the tint. The unowned wash is a parcel-mode cue;
    // normal play shows unowned terrain as-is.
    if (parcelMode) {
      for (final (cell, _, center) in cells) {
        if (queries.ownsCell(cell)) continue;
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
        final bodyRole = bridgeBodyRole(job.nearBank!, job.farBank!);
        for (final cell in job.waterCells.take(fundedTiles)) {
          actors.add((
            (cell.column + cell.row).toDouble(),
            () => _drawTileRole(canvas, bodyRole, cell, size, scale, offset),
          ));
        }
      }
      if (nearBankFunded) {
        final nearRamp = bridgeRampRole(job.nearBank!, job.waterCells.first);
        actors.add((
          (job.nearBank!.column + job.nearBank!.row).toDouble(),
          () => _drawTileRole(
            canvas,
            nearRamp,
            job.nearBank!,
            size,
            scale,
            offset,
          ),
        ));
      }
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

  List<String> _terrainSpriteRoles(CellCoord cell, TerrainCell terrain) {
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
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      _tileScreenRect(image, sprite, cell, size, scale, offset),
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
            final footprint = structureFootprint(definition, selectedCell!);
            final sides = queries.adjacentRoadSides(footprint);
            _drawFacingArrow(
              canvas,
              size,
              footprint,
              sides.map(facingHalf).toSet().length > 1 &&
                      sides.contains(facingOverride)
                  ? facingOverride!
                  : facingForRoadSides(sides),
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
    if (queries.ownsParcel(parcel)) {
      canvas.drawPath(path, Paint()..color = const Color(0x264BC69B));
    }
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
  // The facing offset leans the art toward the road the door faces;
  // picking and tinting share this rect, so taps follow the lean.
  final facing = structure.facing;
  if (facing == null || sprite.facingOffset == 0) return rect;
  return rect.shift(facingPullOffset(facing, sprite.facingOffset));
}

/// World-space shift for a structure pulled [offset] tiles toward its
/// facing road side: north/east run along the screen-right diagonal,
/// south/west along the left, each a half tile wide and a quarter tile
/// tall per tile of offset.
Offset facingPullOffset(String facing, double offset) => Offset(
  (facing == 'north' || facing == 'east' ? 1 : -1) *
      _logicalTileWidth /
      2 *
      offset,
  (facing == 'east' || facing == 'south' ? 1 : -1) *
      _logicalTileHeight /
      2 *
      offset,
);

/// World rect for a prop: the sprite's ground anchor pinned to its
/// subtile's south vertex — the sub-lattice version of how structures
/// anchor at their footprint's south vertex. The front subtile
/// ([propFrontSubtile] on both axes) is the tile's own south vertex,
/// so a prop placed there renders exactly where the 1×1 structures of
/// pre-lattice saves did.
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
  // The facing offset leans the art toward the road the door faces.
  final facing = prop.facing;
  if (facing == null || sprite.facingOffset == 0) return rect;
  return rect.shift(facingPullOffset(facing, sprite.facingOffset));
}

/// The sprite's ground anchor pinned to a subtile's south vertex —
/// the sub-lattice version of how structures anchor at their
/// footprint's south vertex. The front subtile
/// ([propFrontSubtile] on both axes) is the tile's own south vertex,
/// so props from before the lattice render pixel-identically.
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
  final bottomY =
      center.dy +
      (fx + fy) * _logicalTileHeight / 2 +
      _logicalTileHeight / (propSubtilesPerAxis * 2) -
      surfaceLift;
  final width = image.width * sprite.renderScale;
  final height = image.height * sprite.renderScale;
  return Rect.fromLTWH(
    anchorX - width * sprite.groundAnchorX,
    bottomY - height * sprite.groundAnchorY,
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

/// The body sprite's art width — the tile-fit unit for bridge deck
/// rects is [_logicalTileWidth] divided by this.
const _bridgeBodyArtWidth = 128.0;

/// World-px lift for things standing on a cell. Bridge decks are the
/// one elevated surface today: the body sprite hangs its bottom
/// |baseOffsetY| art px above the cell's south vertex, and props
/// stand on that deck — a lift of 6 world px for the current art.
/// Ground cells lift nothing. This is the seed of the future
/// terrain-elevation lookup (see the prop plan's future notes).
double _surfaceLift(
  CellCoord cell,
  WorldQueries queries,
  ContentBundle content,
) {
  if (!queries.bridgeDeckCells.contains(cell)) return 0;
  final sprite = content.sprite('bridge.body.se');
  if (sprite == null) return 0;
  return -sprite.baseOffsetY * (_logicalTileWidth / _bridgeBodyArtWidth);
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

  /// Shore-bank draws for this chunk's outermost water tiles — one
  /// (cell, role) per masked shore piece — replayed every frame
  /// instead of baked into [picture].
  final List<(CellCoord, String)> banks = [];

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

  /// Cap on cached chunks so roaming the open ocean cannot grow the
  /// cache without bound; the least recently drawn are evicted.
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
    // Pedestrians wander every completed ground road — connectivity to
    // the starter road no longer exists as a rule. Bridge decks are
    // elevated, so they stay off them.
    final roadCells = <CellCoord>{for (final road in state.roads) road.cell};
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
