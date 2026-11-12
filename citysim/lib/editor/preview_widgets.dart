import 'dart:math' as math;
import 'dart:ui' as ui show Image;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import 'content_api.dart';
import 'edit_fields.dart' show footprintForRole, spriteMap, spritePathEntries;

import 'package:citysim/world/world_state.dart' show propSubtilesPerAxis;

/// Live previews for the ambience editor. These mirror the game's ambient
/// rendering in miniature: the same sine math, driven by a local ticker.

class _PreviewTicker extends StatefulWidget {
  const _PreviewTicker({required this.builder});

  final Widget Function(BuildContext context, double seconds) builder;

  @override
  State<_PreviewTicker> createState() => _PreviewTickerState();
}

class _PreviewTickerState extends State<_PreviewTicker>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _clock = _Clock();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(
      (elapsed) => _clock.seconds = elapsed.inMicroseconds / 1e6,
    );
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _clock,
    builder: (context, _) => widget.builder(context, _clock.seconds),
  );
}

class _Clock extends ChangeNotifier {
  double _seconds = 0;

  double get seconds => _seconds;

  set seconds(double value) {
    _seconds = value;
    notifyListeners();
  }
}

/// Vegetation sway preview: a pine tree rocking around its base.
class SwayPreview extends StatelessWidget {
  const SwayPreview({
    required this.maxAngle,
    required this.frequency,
    super.key,
  });

  final double maxAngle;
  final double frequency;

  @override
  Widget build(BuildContext context) => _PreviewTicker(
    builder: (context, seconds) => Transform.rotate(
      angle: maxAngle * math.sin(seconds * frequency),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.network(
          ContentApi().assetUrl(
            'sprites/props/trees/prop_tree_pine_medium.png',
          ),
          width: 70,
          height: 90,
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          errorBuilder: (_, _, _) => const Icon(Icons.park_rounded, size: 64),
        ),
      ),
    ),
  );
}

/// Pedestrian walk-cycle preview: cycling the pack's four walk frames at
/// the chosen frame rate and sprite scale.
class WalkCyclePreview extends StatelessWidget {
  const WalkCyclePreview({
    required this.frameRate,
    required this.spriteScale,
    super.key,
  });

  final double frameRate;
  final double spriteScale;

  @override
  Widget build(BuildContext context) => _PreviewTicker(
    builder: (context, seconds) {
      final frame = (seconds * frameRate).floor() % 4 + 1;
      return Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0xFFB5DCCF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Image.network(
            ContentApi().assetUrl('characters/char_a_walk_SE_f0$frame.png'),
            width: 24 * spriteScale * 2,
            height: 32 * spriteScale * 2,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.directions_walk_rounded, size: 48),
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Sprite plot preview
// ---------------------------------------------------------------------------

const _previewTileWidth = 64.0;
const _previewTileHeight = 32.0;

Offset _previewCellCenter(int column, int row) => Offset(
  (column - row) * _previewTileWidth / 2,
  (column + row) * _previewTileHeight / 2,
);

/// The sprite rect the game's structure path computes (`_structureRect` in
/// the renderer): footprint-average X, footprint south corner depth, art
/// placed by its own render scale and ground anchor.
Rect _previewStructureRect(
  ui.Image image, {
  required double renderScale,
  required double anchorX,
  required double anchorY,
  required int columns,
  required int rows,
}) {
  final centers = [
    for (var row = 0; row < rows; row++)
      for (var column = 0; column < columns; column++)
        _previewCellCenter(column, row),
  ];
  final centerX =
      centers.map((point) => point.dx).reduce((a, b) => a + b) / centers.length;
  final bottomY =
      centers.map((point) => point.dy).reduce(math.max) +
      _previewTileHeight / 2;
  final width = image.width * renderScale;
  final height = image.height * renderScale;
  return Rect.fromLTWH(
    centerX - width * anchorX,
    bottomY - height * anchorY,
    width,
    height,
  );
}

/// The sprite rect the game's tile path computes (`_drawTileRole`): width
/// fitted to the tile, height kept at the art's aspect, art hanging below
/// the diamond by baseOffsetY art pixels.
Rect _previewTileRect(ui.Image image, Offset center, {double baseOffsetY = 0}) {
  final unit = _previewTileWidth / image.width;
  final width = image.width * unit;
  final height = image.height * unit;
  final southY = center.dy + _previewTileHeight / 2 + baseOffsetY * unit;
  return Rect.fromLTWH(center.dx - width / 2, southY - height, width, height);
}

/// The sprite rect the game's prop path computes
/// (`_propAnchorWorldRect` in the renderer): the ground anchor pinned
/// to the centre of the tile's [propSubtilesPerAxis]² subtile lattice
/// slot, art placed by its own render scale and ground anchor.
Rect _previewPropRect(
  ui.Image image, {
  required double renderScale,
  required double anchorX,
  required double anchorY,
  required int subtileX,
  required int subtileY,
}) {
  final fx = (subtileX + 0.5) / propSubtilesPerAxis - 0.5;
  final fy = (subtileY + 0.5) / propSubtilesPerAxis - 0.5;
  final width = image.width * renderScale;
  final height = image.height * renderScale;
  return Rect.fromLTWH(
    (fx - fy) * _previewTileWidth / 2 - width * anchorX,
    (fx + fy) * _previewTileHeight / 2 - height * anchorY,
    width,
    height,
  );
}

/// A sprite rendered the way the game renders it, standing on its plot:
/// the footprint's tile diamonds outlined, a road strip along one edge
/// for scale and frontage, and the art placed with its own render scale
/// and ground anchor — so tuning either here shows exactly how the
/// sprite sits in the world. Sprites with door facings get a four-way
/// road-side picker: it moves the strip, swaps to that side's art
/// variant, and applies the facing offset toward it, so one number can
/// be tuned against every direction it can meet. Tile-category sprites
/// (ground, roads, shores, bridges) render tile-style instead: width
/// fitted to the tile, height kept. Props render on their subtile: one
/// tile's 8×8 lattice with a slot picker, the art anchored exactly
/// where the game anchors placed props.
class SpritePlotPreview extends StatefulWidget {
  const SpritePlotPreview({
    required this.categories,
    required this.role,
    this.width = 300,
    super.key,
  });

  final Map<String, Object?> categories;
  final String role;

  /// Preview width in logical pixels; the height follows the content.
  final double width;

  @override
  State<SpritePlotPreview> createState() => _SpritePlotPreviewState();
}

class _SpritePlotPreviewState extends State<SpritePlotPreview> {
  ui.Image? _image;
  ui.Image? _roadColumnAxisImage; // Strips running down-right (se art).
  ui.Image? _roadRowAxisImage; // Strips running down-left (sw art).
  String? _loadedPath;
  ImageStream? _spriteStream;
  ImageStreamListener? _spriteListener;
  final List<ImageStream> _roadStreams = [];
  final List<ImageStreamListener> _roadListeners = [];

  /// Road side the preview faces: where the strip runs, which art
  /// variant shows, and which way the facing offset pulls.
  String _roadSide = 'south';

  /// Slots the prop preview can stand on: the tile's back corner,
  /// centre, and front corner — the placements worth tuning against.
  static const List<(String, int, int)> _propSubtileChoices = [
    ('back', 0, 0),
    ('centre', 3, 3),
    ('front', 7, 7),
  ];
  int _propSubtileIndex = 1;

  Map<String, Object?> get _sprite {
    final raw = spriteMap(widget.categories)[widget.role];
    return raw is Map ? raw.cast<String, Object?>() : const {};
  }

  @override
  void initState() {
    super.initState();
    _resolveSprite();
    _resolveRoads();
  }

  @override
  void didUpdateWidget(covariant SpritePlotPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_spritePath(_roadSide) != _loadedPath) _resolveSprite();
  }

  @override
  void dispose() {
    if (_spriteStream != null && _spriteListener != null) {
      _spriteStream!.removeListener(_spriteListener!);
    }
    for (var index = 0; index < _roadStreams.length; index++) {
      _roadStreams[index].removeListener(_roadListeners[index]);
    }
    super.dispose();
  }

  bool get _hasFacings =>
      spritePathEntries(_sprite).any((entry) => entry.$1.isNotEmpty);

  /// The art file for a road side: facings sprites pick the variant for
  /// the side's screen half (north/east right, south/west left);
  /// single-facing sprites keep their only file.
  String? _spritePath(String side) {
    final entries = spritePathEntries(_sprite);
    final half = side == 'north' || side == 'east' ? 'right' : 'left';
    for (final entry in entries) {
      if (entry.$1 == half) return entry.$2;
    }
    return entries.isEmpty ? null : entries.first.$2;
  }

  void _resolveSprite() {
    if (_spriteStream != null && _spriteListener != null) {
      _spriteStream!.removeListener(_spriteListener!);
    }
    _spriteStream = null;
    _spriteListener = null;
    _loadedPath = _spritePath(_roadSide);
    final path = _loadedPath;
    if (path == null) return;
    final stream = NetworkImage(ContentApi().assetUrl(path))
        .resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (frame, _) {
        if (mounted) setState(() => _image = frame.image);
      },
      // Missing art just leaves the plot preview without the sprite.
      onError: (Object error, StackTrace? stackTrace) {},
    );
    _spriteStream = stream;
    _spriteListener = listener;
    stream.addListener(listener);
  }

  void _resolveRoads() {
    _resolveRoad('road.straight.se', (image) {
      _roadColumnAxisImage = image;
    });
    _resolveRoad('road.straight.sw', (image) {
      _roadRowAxisImage = image;
    });
  }

  void _resolveRoad(String role, void Function(ui.Image) setImage) {
    final road = spriteMap(widget.categories)[role];
    final path = road is Map ? road['path'] as String? : null;
    if (path == null) return;
    final stream = NetworkImage(ContentApi().assetUrl(path))
        .resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((frame, _) {
      if (mounted) setState(() => setImage(frame.image));
    }, onError: (Object error, StackTrace? stackTrace) {});
    _roadStreams.add(stream);
    _roadListeners.add(listener);
    stream.addListener(listener);
  }

  void _setRoadSide(String side) {
    if (side == _roadSide) return;
    setState(() => _roadSide = side);
    // The facing's art variant changes with the side.
    _resolveSprite();
  }

  @override
  Widget build(BuildContext context) {
    final meta = _sprite;
    final renderScale = (meta['renderScale'] as num?)?.toDouble() ?? 0.5;
    final anchor = (meta['groundAnchor'] as List?) ?? const [0.5, 1.0];
    final anchorX = anchor.isNotEmpty ? (anchor[0] as num).toDouble() : 0.5;
    final anchorY = anchor.length > 1 ? (anchor[1] as num).toDouble() : 1.0;
    final baseOffsetY = (meta['baseOffsetY'] as num?)?.toDouble() ?? 0.0;
    final facingOffset = (meta['facingOffset'] as num?)?.toDouble() ?? 0.0;
    final category = meta['category'] as String? ?? 'buildings';
    final tileStyle = const {
      'ground',
      'roads',
      'shores',
      'bridges',
    }.contains(category);
    final propStyle = category == 'props';
    final (columns, rows) = footprintForRole(widget.categories, widget.role);
    // Props live on one tile's subtile lattice, whatever their model's
    // footprint says — placement is per-tile.
    final plotColumns = propStyle ? 1 : columns;
    final plotRows = propStyle ? 1 : rows;
    // Only facings sprites can lean — their structures are the ones
    // that save a facing to pull toward.
    final pull = _hasFacings
        ? _previewPull(_roadSide, facingOffset)
        : Offset.zero;

    // Logical-space bounds of everything drawn: plot diamonds, the road
    // strip, and the sprite's rect once its art has decoded.
    var bounds = Rect.fromLTRB(
      -_previewTileWidth / 2,
      -_previewTileHeight / 2,
      _previewTileWidth / 2,
      _previewTileHeight / 2,
    );
    for (var row = 0; row < plotRows; row++) {
      for (var column = 0; column < plotColumns; column++) {
        final center = _previewCellCenter(column, row);
        bounds = bounds.expandToInclude(
          Rect.fromCenter(
            center: center,
            width: _previewTileWidth,
            height: _previewTileHeight,
          ),
        );
      }
    }
    if (!tileStyle && !propStyle) {
      for (final center in _roadStripCenters(columns, rows, _roadSide)) {
        bounds = bounds.expandToInclude(
          Rect.fromCenter(
            center: center,
            width: _previewTileWidth,
            height: _previewTileHeight,
          ),
        );
      }
    }
    final image = _image;
    Rect? spriteRect;
    if (image != null) {
      final choice = _propSubtileChoices[_propSubtileIndex];
      spriteRect = tileStyle
          ? _previewTileRect(
              image,
              _previewCellCenter(0, 0),
              baseOffsetY: baseOffsetY,
            )
          : propStyle
          ? _previewPropRect(
              image,
              renderScale: renderScale,
              anchorX: anchorX,
              anchorY: anchorY,
              subtileX: choice.$2,
              subtileY: choice.$3,
            ).shift(pull)
          : _previewStructureRect(
              image,
              renderScale: renderScale,
              anchorX: anchorX,
              anchorY: anchorY,
              columns: columns,
              rows: rows,
            ).shift(pull);
      bounds = bounds.expandToInclude(spriteRect);
    }
    bounds = bounds.inflate(6);

    final height = (widget.width * bounds.height / bounds.width).clamp(
      70.0,
      240.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasFacings)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                for (final side in const ['north', 'east', 'south', 'west'])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(side[0].toUpperCase()),
                      tooltip: 'Road on the $side side',
                      selected: _roadSide == side,
                      onSelected: (_) => _setRoadSide(side),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
              ],
            ),
          ),
        if (propStyle)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                for (final (index, choice) in _propSubtileChoices.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ChoiceChip(
                      label: Text(choice.$1),
                      tooltip: 'subtile (${choice.$2},${choice.$3})',
                      selected: _propSubtileIndex == index,
                      onSelected: (_) =>
                          setState(() => _propSubtileIndex = index),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
              ],
            ),
          ),
        CustomPaint(
          size: Size(widget.width, height),
          painter: _SpritePlotPainter(
            bounds: bounds,
            columns: plotColumns,
            rows: plotRows,
            tileStyle: tileStyle,
            propStyle: propStyle,
            subtileX: _propSubtileChoices[_propSubtileIndex].$2,
            subtileY: _propSubtileChoices[_propSubtileIndex].$3,
            image: image,
            spriteRect: spriteRect,
            roadColumnAxisImage: _roadColumnAxisImage,
            roadRowAxisImage: _roadRowAxisImage,
            roadSide: _roadSide,
          ),
        ),
        Text(
          propStyle
              ? '8×8 lattice · subtile '
                    '(${_propSubtileChoices[_propSubtileIndex].$2},'
                    '${_propSubtileChoices[_propSubtileIndex].$3})'
              : '$columns×$rows plot${tileStyle ? ' · drawn tile-fit' : ''}',
          style: const TextStyle(
            fontSize: 9,
            color: Colors.black45,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SpritePlotPainter extends CustomPainter {
  const _SpritePlotPainter({
    required this.bounds,
    required this.columns,
    required this.rows,
    required this.tileStyle,
    required this.propStyle,
    required this.subtileX,
    required this.subtileY,
    required this.image,
    required this.spriteRect,
    required this.roadColumnAxisImage,
    required this.roadRowAxisImage,
    required this.roadSide,
  });

  final Rect bounds;
  final int columns;
  final int rows;
  final bool tileStyle;
  final bool propStyle;
  final int subtileX;
  final int subtileY;
  final ui.Image? image;

  /// The sprite's on-plot rect, computed by the preview exactly as
  /// the game computes it for this sprite's category.
  final Rect? spriteRect;
  final ui.Image? roadColumnAxisImage;
  final ui.Image? roadRowAxisImage;
  final String roadSide;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = math.min(
      size.width / bounds.width,
      size.height / bounds.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - bounds.width * fit) / 2 - bounds.left * fit,
      (size.height - bounds.height * fit) / 2 - bounds.top * fit,
    );
    canvas.scale(fit);

    Path diamond(Offset center) => Path()
      ..moveTo(center.dx, center.dy - _previewTileHeight / 2)
      ..lineTo(center.dx + _previewTileWidth / 2, center.dy)
      ..lineTo(center.dx, center.dy + _previewTileHeight / 2)
      ..lineTo(center.dx - _previewTileWidth / 2, center.dy)
      ..close();

    // Road strip along the chosen side, for scale and frontage. Strips
    // on the north/south edges run along the column axis (down-right,
    // se art); east/west strips run along the row axis (down-left, sw).
    final road = roadSide == 'east' || roadSide == 'west'
        ? roadRowAxisImage
        : roadColumnAxisImage;
    if (!tileStyle && !propStyle && road != null) {
      for (final center in _roadStripCenters(columns, rows, roadSide)) {
        canvas.drawImageRect(
          road,
          Rect.fromLTWH(0, 0, road.width.toDouble(), road.height.toDouble()),
          _previewTileRect(road, center),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }

    // The plot's tile diamonds.
    final fill = Paint()..color = const Color(0x2266BB6A);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / math.max(fit, 0.25)
      ..color = const Color(0xFF4E9B51);
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final path = diamond(_previewCellCenter(column, row));
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      }
    }

    if (propStyle) {
      // The tile's 8×8 subtile lattice, faint, with the chosen slot
      // highlighted the way the game's ghost marker diamonds it.
      Offset latticePoint(double fx, double fy) => Offset(
        (fx - fy) * _previewTileWidth / 2,
        (fx + fy) * _previewTileHeight / 2,
      );
      final lattice = Paint()
        ..strokeWidth = 1 / math.max(fit, 0.25)
        ..color = const Color(0x59FFFFFF);
      for (var k = 0; k <= propSubtilesPerAxis; k++) {
        final c = -0.5 + k / propSubtilesPerAxis;
        final extent = 0.5 - c.abs();
        canvas.drawLine(
          latticePoint(c, -extent),
          latticePoint(c, extent),
          lattice,
        );
        canvas.drawLine(
          latticePoint(-extent, c),
          latticePoint(extent, c),
          lattice,
        );
      }
      final fx = (subtileX + 0.5) / propSubtilesPerAxis - 0.5;
      final fy = (subtileY + 0.5) / propSubtilesPerAxis - 0.5;
      final centre = latticePoint(fx, fy);
      final halfWidth = _previewTileWidth / propSubtilesPerAxis / 2;
      final halfHeight = _previewTileHeight / propSubtilesPerAxis / 2;
      final slot = Path()
        ..moveTo(centre.dx, centre.dy - halfHeight)
        ..lineTo(centre.dx + halfWidth, centre.dy)
        ..lineTo(centre.dx, centre.dy + halfHeight)
        ..lineTo(centre.dx - halfWidth, centre.dy)
        ..close();
      canvas.drawPath(slot, Paint()..color = const Color(0x804BC69B));
      canvas.drawPath(
        slot,
        Paint()
          ..color = const Color(0xFF1E6552)
          ..strokeWidth = 1.5 / math.max(fit, 0.25)
          ..style = PaintingStyle.stroke,
      );
    }

    // The sprite itself, placed exactly as the game places it.
    final image = this.image;
    final rect = spriteRect;
    if (image != null && rect != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SpritePlotPainter oldDelegate) =>
      oldDelegate.bounds != bounds ||
      oldDelegate.columns != columns ||
      oldDelegate.rows != rows ||
      oldDelegate.tileStyle != tileStyle ||
      oldDelegate.propStyle != propStyle ||
      oldDelegate.subtileX != subtileX ||
      oldDelegate.subtileY != subtileY ||
      oldDelegate.image != image ||
      oldDelegate.spriteRect != spriteRect ||
      oldDelegate.roadColumnAxisImage != roadColumnAxisImage ||
      oldDelegate.roadRowAxisImage != roadRowAxisImage ||
      oldDelegate.roadSide != roadSide;
}

/// Cell centres of a road strip along one side of a plot, one tile past
/// each end so the strip reads as a running road.
List<Offset> _roadStripCenters(int columns, int rows, String side) {
  switch (side) {
    case 'north':
      return [
        for (var column = -1; column <= columns; column++)
          _previewCellCenter(column, -1),
      ];
    case 'east':
      return [
        for (var row = -1; row <= rows; row++) _previewCellCenter(columns, row),
      ];
    case 'west':
      return [
        for (var row = -1; row <= rows; row++) _previewCellCenter(-1, row),
      ];
    default: // south — the plot's front edge
      return [
        for (var column = -1; column <= columns; column++)
          _previewCellCenter(column, rows),
      ];
  }
}

/// The preview's copy of the renderer's facing pull: [offset] tiles
/// along the road side's screen diagonal — north/east toward the
/// plot's right corners, south/west toward its left.
Offset _previewPull(String side, double offset) => Offset(
  (side == 'north' || side == 'east' ? 1 : -1) * _previewTileWidth / 2 * offset,
  (side == 'east' || side == 'south' ? 1 : -1) *
      _previewTileHeight /
      2 *
      offset,
);
