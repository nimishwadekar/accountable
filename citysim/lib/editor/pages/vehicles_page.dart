import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../content_api.dart';
import '../edit_fields.dart';
import '../preview_widgets.dart' show laneOverlayColors;

/// Vehicles page: per-type render tuning against a live preview.
/// The preview places the sprite on its painted lane exactly as
/// the game does — same anchor math, same scale — with a crosshair
/// on the lane's centreline, so anchor and scale can be nudged
/// until the wheels straddle it. Variants share their type's
/// tuning.
class VehiclesPage extends StatefulWidget {
  const VehiclesPage({
    required this.categories,
    required this.onChanged,
    super.key,
  });

  final Map<String, Object?> categories;
  final CategoriesChanged onChanged;

  @override
  State<VehiclesPage> createState() => _VehiclesPageState();
}

class _VehiclesPageState extends State<VehiclesPage> {
  String? _type;
  String? _variant;
  String _direction = 'NE';

  /// The shown sprite's pixel size, for computing default anchors.
  int _imageWidth = 0;
  int _imageHeight = 0;

  /// Bumped on reset so the fields remount with restored defaults.
  int _resetCount = 0;

  Map<String, Object?> get _cars =>
      subMap(ambienceMap(widget.categories), 'cars');

  Map<String, Object?> get _types => subMap(_cars, 'types');

  List<String> get _typeIds {
    final ids = _types.keys.toList()..sort();
    return ids;
  }

  String get _typeId {
    final ids = _typeIds;
    if (_type != null && ids.contains(_type)) return _type!;
    return ids.isEmpty ? '' : ids.first;
  }

  List<String> get _variants {
    final variants = _types[_typeId];
    if (variants is! Map) return const [];
    final list = variants['variants'];
    if (list is! List) return const [];
    return [for (final variant in list) variant as String];
  }

  String get _variantId {
    if (_variant != null && _variants.contains(_variant)) return _variant!;
    return _variants.isEmpty ? '' : _variants.first;
  }

  /// The sprite path the selection resolves to.
  String get _assetPath => _variantId.isEmpty
      ? 'vehicles/veh_${_typeId}_$_direction.png'
      : 'vehicles/veh_${_typeId}_${_variantId}_$_direction.png';

  Map<String, Object?>? get _typeRender {
    final render = _cars['render'];
    if (render is! Map) return null;
    final entry = render[_typeId];
    return entry is Map ? entry.cast<String, Object?>() : null;
  }

  (double, double)? get _anchorOverride {
    final anchor = _typeRender?['anchor'];
    if (anchor is! Map) return null;
    final entry = anchor[_direction];
    if (entry is! List || entry.length < 2) return null;
    return (
      (entry[0] as num?)?.toDouble() ?? 0.5,
      (entry[1] as num?)?.toDouble() ?? 0.75,
    );
  }

  /// The computed default anchor for the shown sprite: horizontal
  /// centre, and the ground centre of tight iso art — a quarter of
  /// the box width above the box bottom.
  double get _defaultAnchorY => _imageHeight == 0
      ? 0.75
      : (_imageHeight - _imageWidth / 4) / _imageHeight;

  double get _anchorX => _anchorOverride?.$1 ?? 0.5;

  double get _anchorY => _anchorOverride?.$2 ?? _defaultAnchorY;

  double get _scale =>
      (_typeRender?['scale'] as num?)?.toDouble() ??
      asDouble(_cars['spriteScale'], 0.9);

  /// The tuned placement expressed as a world-space nudge from the
  /// computed default, in subtiles along the grid axes — (east-west,
  /// north-south), positive east and south. The same two degrees of
  /// freedom as the anchor fractions, rotated onto the grid axes the
  /// iso screen diagonals hide.
  (double, double) get _shiftSubtiles {
    final override = _anchorOverride;
    if (override == null || _imageWidth == 0) return (0, 0);
    final unit = 0.5 * _scale;
    final screenWidth = _imageWidth * unit;
    final screenHeight = _imageHeight * unit;
    // The car's screen displacement from its default placement:
    // moving the anchor within the art shifts the drawn car the
    // other way.
    final sx = -(override.$1 - 0.5) * screenWidth;
    final sy = -(override.$2 - _defaultAnchorY) * screenHeight;
    // Screen to grid: a cell maps to ((col−row)·32, (col+row)·16)
    // world px, so a subtile step is ((col−row)·4, (col+row)·2).
    return (sx / 8 + sy / 4, sy / 4 - sx / 8);
  }

  /// Writes a world-space nudge, in subtiles, back as anchor
  /// fractions against the computed default.
  void _writeShift(double colSubtiles, double rowSubtiles) {
    // The art is still loading — nothing to convert against yet.
    if (_imageWidth == 0) return;
    final unit = 0.5 * _scale;
    final screenWidth = _imageWidth * unit;
    final screenHeight = _imageHeight * unit;
    final sx = (colSubtiles - rowSubtiles) * 4;
    final sy = (colSubtiles + rowSubtiles) * 2;
    final ax = (0.5 - sx / screenWidth).clamp(-0.5, 1.5);
    final ay = (_defaultAnchorY - sy / screenHeight).clamp(-0.5, 1.5);
    _writeAnchor(ax, ay);
  }

  void _editCars(void Function(Map<String, Object?> cars) edit) {
    widget.onChanged((categories) {
      final ambience = (categories['ambience.json'] as Map)
          .cast<String, Object?>();
      var cars = ambience['cars'];
      if (cars is! Map) {
        cars = <String, Object?>{};
        ambience['cars'] = cars;
      }
      edit(cars.cast<String, Object?>());
    });
  }

  void _writeAnchor(double x, double y) {
    _editCars((cars) {
      var render = cars['render'];
      if (render is! Map) {
        render = <String, Object?>{};
        cars['render'] = render;
      }
      var typeRender = render[_typeId];
      if (typeRender is! Map) {
        typeRender = <String, Object?>{};
        render[_typeId] = typeRender;
      }
      var anchor = typeRender['anchor'];
      if (anchor is! Map) {
        anchor = <String, Object?>{};
        typeRender['anchor'] = anchor;
      }
      anchor[_direction] = [x, y];
    });
  }

  void _writeScale(double value) {
    _editCars((cars) {
      var render = cars['render'];
      if (render is! Map) {
        render = <String, Object?>{};
        cars['render'] = render;
      }
      var typeRender = render[_typeId];
      if (typeRender is! Map) {
        typeRender = <String, Object?>{};
        render[_typeId] = typeRender;
      }
      typeRender['scale'] = value;
    });
  }

  void _resetAnchor() {
    // Bumped so the fields remount with the restored defaults —
    // their initial values only read at creation.
    _resetCount++;
    widget.onChanged((categories) {
      final ambience = (categories['ambience.json'] as Map)
          .cast<String, Object?>();
      final cars = ambience['cars'];
      final render = cars is Map ? cars['render'] : null;
      final typeRender = render is Map ? render[_typeId] : null;
      final anchor = typeRender is Map ? typeRender['anchor'] : null;
      if (anchor is Map) anchor.remove(_direction);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_typeIds.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(10),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('No vehicle types — add them on the Ambience page.'),
            ),
          ),
        ],
      );
    }
    final overridden = _anchorOverride != null;
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vehicle render tuning',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Text(
                  'The preview places the sprite on its lane exactly as '
                  'the game does, crosshair on the lane centreline — '
                  'tune until the wheels straddle it. Variants share '
                  'their type\'s tuning.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _typeDropdown(),
                    if (_variants.isNotEmpty) ...[
                      const Text('colour'),
                      for (final variant in _variants)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text(variant),
                            selected: _variantId == variant,
                            onSelected: (_) =>
                                setState(() => _variant = variant),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                          ),
                        ),
                    ],
                    const Text('facing'),
                    for (final direction in const ['NE', 'NW', 'SE', 'SW'])
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ChoiceChip(
                          label: Text(direction),
                          tooltip: 'The $direction-facing sprite',
                          selected: _direction == direction,
                          onSelected: (_) =>
                              setState(() => _direction = direction),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                VehicleAnchorPreview(
                  categories: widget.categories,
                  assetPath: _assetPath,
                  direction: _direction,
                  anchorX: _anchorX,
                  anchorY: _anchorY,
                  scale: _scale,
                  onImageResolved: (width, height) {
                    if (_imageWidth != width || _imageHeight != height) {
                      setState(() {
                        _imageWidth = width;
                        _imageHeight = height;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                // Keyed so switching vehicle, facing, — or the
                // sprite resolving with its true pixel size, which
                // moves the computed default — refreshes the
                // fields' initial values.
                KeyedSubtree(
                  key: ValueKey(
                    'fields-$_typeId-$_variantId-$_direction-'
                    '$_imageWidth-$_imageHeight-$_resetCount',
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 170,
                        child: DoubleField(
                          label: 'Shift E–W',
                          value: _shiftSubtiles.$1,
                          decimals: 2,
                          help:
                              'World-space nudge along the east-west '
                              'grid axis, in subtiles (a subtile is 1/8 of '
                              'a tile); positive moves the car east. '
                              'Measured from the computed ground-centre '
                              'placement — tune until the wheels straddle '
                              'the crosshair.',
                          onChanged: (v) => _writeShift(v, _shiftSubtiles.$2),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: DoubleField(
                          label: 'Shift N–S',
                          value: _shiftSubtiles.$2,
                          decimals: 2,
                          help:
                              'World-space nudge along the north-south '
                              'grid axis, in subtiles; positive moves the '
                              'car south. Measured from the computed '
                              'ground-centre placement.',
                          onChanged: (v) => _writeShift(_shiftSubtiles.$1, v),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: DoubleField(
                          label: 'Scale',
                          value: _scale,
                          min: 0.05,
                          help:
                              'Draw size for this vehicle type, '
                              'overriding the global car sprite scale.',
                          onChanged: _writeScale,
                        ),
                      ),
                      if (overridden)
                        OutlinedButton(
                          onPressed: _resetAnchor,
                          child: const Text('Reset facing to default'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'shift (${_shiftSubtiles.$1.toStringAsFixed(2)}, '
                  '${_shiftSubtiles.$2.toStringAsFixed(2)}) subtiles '
                  '${overridden ? '' : '— computed default'} · '
                  'anchor (${_anchorX.toStringAsFixed(3)}, '
                  '${_anchorY.toStringAsFixed(3)}) · '
                  'scale ${_scale.toStringAsFixed(2)} · '
                  '${_imageWidth == 0 ? 'loading art' : '$_imageWidth×$_imageHeight px'}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _typeDropdown() {
    final ids = _typeIds;
    return DropdownButton<String>(
      value: ids.contains(_typeId) ? _typeId : null,
      items: [
        for (final id in ids) DropdownMenuItem(value: id, child: Text(id)),
      ],
      onChanged: (value) => setState(() {
        _type = value;
        _variant = null;
      }),
      underline: const SizedBox.shrink(),
    );
  }
}

/// The tuning preview: a three-tile road run with the selected
/// direction's lane painted on it, a crosshair at the lane's
/// centreline, and the sprite placed with the game's exact anchor
/// math.
class VehicleAnchorPreview extends StatefulWidget {
  const VehicleAnchorPreview({
    required this.categories,
    required this.assetPath,
    required this.direction,
    required this.anchorX,
    required this.anchorY,
    required this.scale,
    this.width = 1200,
    this.onImageResolved,
    super.key,
  });

  final Map<String, Object?> categories;
  final String assetPath;
  final String direction;
  final double anchorX;
  final double anchorY;
  final double scale;
  final double width;
  final void Function(int width, int height)? onImageResolved;

  @override
  State<VehicleAnchorPreview> createState() => _VehicleAnchorPreviewState();
}

class _VehicleAnchorPreviewState extends State<VehicleAnchorPreview> {
  ui.Image? _image;
  ui.Image? _roadImage;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageStream? _roadStream;
  ImageStreamListener? _roadListener;
  String _loadedPath = '';

  @override
  void initState() {
    super.initState();
    _resolveVehicle();
    _resolveRoad();
  }

  @override
  void didUpdateWidget(covariant VehicleAnchorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assetPath != _loadedPath) _resolveVehicle();
    if (oldWidget.direction != widget.direction) _resolveRoad();
  }

  @override
  void dispose() {
    _detach(_stream, _listener);
    _detach(_roadStream, _roadListener);
    super.dispose();
  }

  void _detach(ImageStream? stream, ImageStreamListener? listener) {
    if (stream != null && listener != null) stream.removeListener(listener);
  }

  void _resolveVehicle() {
    _detach(_stream, _listener);
    _stream = null;
    _listener = null;
    _loadedPath = widget.assetPath;
    // Drop the previous facing's art immediately — the preview
    // shows road, lane, and crosshair until the new sprite
    // resolves, never the wrong car.
    _image = null;
    final stream = NetworkImage(ContentApi().assetUrl(widget.assetPath))
        .resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((frame, _) {
      if (!mounted) return;
      setState(() => _image = frame.image);
      widget.onImageResolved?.call(frame.image.width, frame.image.height);
    }, onError: (Object error, StackTrace? stackTrace) {});
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  /// The road tile under the tuned travel direction: east/west
  /// travel runs along an east-west road, north/south along a
  /// north-south one.
  void _resolveRoad() {
    _detach(_roadStream, _roadListener);
    _roadStream = null;
    _roadListener = null;
    final travel = _travelOf(widget.direction);
    final role = travel == 'north' || travel == 'south'
        ? 'road.straight.sw'
        : 'road.straight.se';
    final road = spriteMap(widget.categories)[role];
    final path = road is Map ? road['path'] as String? : null;
    if (path == null) return;
    final stream = NetworkImage(ContentApi().assetUrl(path))
        .resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((frame, _) {
      if (mounted) setState(() => _roadImage = frame.image);
    }, onError: (Object error, StackTrace? stackTrace) {});
    _roadStream = stream;
    _roadListener = listener;
    stream.addListener(listener);
  }

  static String _travelOf(String direction) => switch (direction) {
    'NE' => 'north',
    'SE' => 'east',
    'SW' => 'south',
    _ => 'west',
  };

  @override
  Widget build(BuildContext context) {
    const tileW = 64.0;
    const tileH = 32.0;
    Offset cellCenter(int column, int row) =>
        Offset((column - row) * tileW / 2, (column + row) * tileH / 2);

    final travel = _travelOf(widget.direction);
    final northSouth = travel == 'north' || travel == 'south';
    // Three tiles through the origin: a horizontal run for east/
    // west travel, a vertical one for north/south.
    final cells = <(int, int)>[
      for (var k = -1; k <= 1; k++) northSouth ? (0, k) : (k, 0),
    ];
    var bounds = const Rect.fromLTRB(-100, -56, 100, 56);
    final image = _image;
    if (image != null) {
      final unit = 0.5 * widget.scale;
      bounds = bounds.expandToInclude(
        Rect.fromCenter(
          center: cellCenter(0, 0),
          width: image.width * unit + 8,
          height: image.height * unit + 8,
        ),
      );
    }
    bounds = bounds.inflate(6);
    final height = (widget.width * bounds.height / bounds.width).clamp(
      120.0,
      widget.width * 0.8,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomPaint(
          size: Size(widget.width, height),
          painter: _VehicleAnchorPainter(
            bounds: bounds,
            cells: cells,
            image: image,
            roadImage: _roadImage,
            travel: travel,
            anchorX: widget.anchorX,
            anchorY: widget.anchorY,
            scale: widget.scale,
          ),
        ),
      ],
    );
  }
}

class _VehicleAnchorPainter extends CustomPainter {
  const _VehicleAnchorPainter({
    required this.bounds,
    required this.cells,
    required this.image,
    required this.roadImage,
    required this.travel,
    required this.anchorX,
    required this.anchorY,
    required this.scale,
  });

  final Rect bounds;
  final List<(int, int)> cells;
  final ui.Image? image;
  final ui.Image? roadImage;
  final String travel;
  final double anchorX;
  final double anchorY;
  final double scale;

  static const double _tileW = 64;
  static const double _tileH = 32;

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

    Offset cellCenter(int column, int row) =>
        Offset((column - row) * _tileW / 2, (column + row) * _tileH / 2);

    // The road run, drawn tile-fit like the game draws road art.
    final road = roadImage;
    if (road != null) {
      for (final (column, row) in cells) {
        final center = cellCenter(column, row);
        canvas.drawImageRect(
          road,
          Rect.fromLTWH(0, 0, road.width.toDouble(), road.height.toDouble()),
          Rect.fromCenter(
            center: center,
            width: _tileW,
            height: _tileW * road.height / road.width,
          ),
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
    }

    // The tuned direction's lane band — right-hand drive, the
    // same rows and columns the paint uses.
    final bandStart = switch (travel) {
      'east' => 4,
      'west' => 2,
      'north' => 4,
      _ => 2,
    };
    final (fillColor, edgeColor, _) = laneOverlayColors[travel]!;
    Offset latticePoint(int column, int row, double fx, double fy) =>
        cellCenter(column, row) +
        Offset((fx - fy) * _tileW / 2, (fx + fy) * _tileH / 2);
    for (final (column, row) in cells) {
      for (var k = 0; k < 2; k++) {
        for (var i = 0; i < 8; i++) {
          final west =
              (travel == 'east' || travel == 'west' ? i : bandStart + k) / 8 -
              0.5;
          final east =
              (travel == 'east' || travel == 'west'
                      ? i + 1
                      : bandStart + k + 1) /
                  8 -
              0.5;
          final north =
              (travel == 'east' || travel == 'west' ? bandStart + k : i) / 8 -
              0.5;
          final south =
              (travel == 'east' || travel == 'west'
                      ? bandStart + k + 1
                      : i + 1) /
                  8 -
              0.5;
          final cell = Path()
            ..moveTo(
              latticePoint(column, row, west, north).dx,
              latticePoint(column, row, west, north).dy,
            )
            ..lineTo(
              latticePoint(column, row, east, north).dx,
              latticePoint(column, row, east, north).dy,
            )
            ..lineTo(
              latticePoint(column, row, east, south).dx,
              latticePoint(column, row, east, south).dy,
            )
            ..lineTo(
              latticePoint(column, row, west, south).dx,
              latticePoint(column, row, west, south).dy,
            )
            ..close();
          canvas.drawPath(cell, Paint()..color = fillColor);
          canvas.drawPath(
            cell,
            Paint()
              ..color = edgeColor
              ..strokeWidth = 1 / math.max(fit, 0.25)
              ..style = PaintingStyle.stroke,
          );
        }
      }
    }

    // The spot: the lane band's centreline through the middle
    // tile — where the game anchors the car.
    final laneCentre = (bandStart + 1) / 8 - 0.5;
    final spot = travel == 'east' || travel == 'west'
        ? latticePoint(0, 0, 0, laneCentre)
        : latticePoint(0, 0, laneCentre, 0);

    // The sprite, placed exactly as the game places it: the
    // anchor fractions over the spot, the type scale over the
    // tile unit.
    final image = this.image;
    if (image != null) {
      final unit = 0.5 * scale;
      final width = image.width * unit;
      final height = image.height * unit;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(
          spot.dx - anchorX * width,
          spot.dy + 2 - anchorY * height,
          width,
          height,
        ),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    // The anchor crosshair, drawn over the sprite so it visibly
    // intersects the car at its contact point — tune Anchor X/Y
    // until the wheels straddle the cross.
    final cross = Paint()
      ..color = const Color(0xB3FF3355)
      ..strokeWidth = 1.6 / math.max(fit, 0.25)
      ..strokeCap = StrokeCap.round;
    const reach = 9.0;
    canvas.drawLine(
      Offset(spot.dx - reach, spot.dy),
      Offset(spot.dx + reach, spot.dy),
      cross,
    );
    canvas.drawLine(
      Offset(spot.dx, spot.dy - reach),
      Offset(spot.dx, spot.dy + reach),
      cross,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VehicleAnchorPainter oldDelegate) =>
      oldDelegate.bounds != bounds ||
      oldDelegate.image != image ||
      oldDelegate.roadImage != roadImage ||
      oldDelegate.travel != travel ||
      oldDelegate.anchorX != anchorX ||
      oldDelegate.anchorY != anchorY ||
      oldDelegate.scale != scale;
}
