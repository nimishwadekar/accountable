import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../content_api.dart';
import '../edit_fields.dart';
import '../../storage/world_usage.dart';
import '../../world/coordinates.dart';

/// Map editor: the terrain map as an isometric canvas. Authored parcels
/// render as diamonds (grass green, water blue, fog pale); the void
/// beyond them is the page background and renders in-game as fog —
/// authoring a parcel is what clears it. A `+` button on every
/// void-facing edge grows the map with a same-kind neighbour;
/// selecting a parcel allows changing its kind or deleting it — locked
/// when the current save occupies its cells (roads, structures,
/// bridges, and plans all count, with footprints and spans expanded),
/// when it is owned (delete only), or when it is the starter parcel.
class MapPage extends StatefulWidget {
  const MapPage({
    required this.categories,
    required this.onChanged,
    this.usageLoader,
    super.key,
  });

  final Map<String, Object?> categories;
  final CategoriesChanged onChanged;

  /// Fetches the current world usage; defaults to the editor server.
  /// Tests inject an in-memory loader.
  final Future<WorldUsage?> Function()? usageLoader;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  WorldUsage? _usage;
  ParcelCoord? _selected;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  Future<void> _loadUsage() async {
    try {
      final usage =
          await (widget.usageLoader?.call() ?? ContentApi().fetchWorldUsage());
      if (mounted) setState(() => _usage = usage);
    } catch (_) {
      if (mounted) setState(() => _usage = null);
    }
  }

  Map<ParcelCoord, String> get _parcels {
    final terrain = widget.categories['terrain.json'] as Map?;
    final raw = terrain?['parcels'] as Map?;
    if (raw == null) return const {};
    final result = <ParcelCoord, String>{};
    for (final entry in raw.entries) {
      final parts = '${entry.key}'.split(',');
      if (parts.length != 2) continue;
      final x = int.tryParse(parts[0].trim());
      final y = int.tryParse(parts[1].trim());
      if (x == null || y == null) continue;
      result[ParcelCoord(x, y)] = '${entry.value}';
    }
    return result;
  }

  Map<ParcelCoord, Set<CellCoord>> get _occupiedByParcel {
    final usage = _usage;
    if (usage == null) return const {};
    final result = <ParcelCoord, Set<CellCoord>>{};
    for (final cell in usage.occupiedCells) {
      result.putIfAbsent(parcelForCell(cell), () => {}).add(cell);
    }
    return result;
  }

  void _editTerrain(void Function(Map<String, Object?> terrain) edit) {
    widget.onChanged((categories) {
      final terrain = (categories['terrain.json'] as Map)
          .cast<String, Object?>();
      edit(terrain);
      categories['terrain.json'] = terrain;
    });
  }

  void _addNeighbor(ParcelCoord coord, int dx, int dy) {
    final kind = _parcels[coord];
    final target = ParcelCoord(coord.x + dx, coord.y + dy);
    if (kind == null || _parcels.containsKey(target)) return;
    _editTerrain(
      (terrain) =>
          (terrain['parcels'] as Map)['${target.x},${target.y}'] = kind,
    );
  }

  void _changeKind(ParcelCoord coord, String kind) {
    _editTerrain(
      (terrain) => (terrain['parcels'] as Map)['${coord.x},${coord.y}'] = kind,
    );
  }

  void _deleteParcel(ParcelCoord coord) {
    _editTerrain(
      (terrain) => (terrain['parcels'] as Map).remove('${coord.x},${coord.y}'),
    );
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final parcels = _parcels;
    return Column(
      children: [
        _toolbar(parcels),
        const Divider(height: 1, color: Color(0xFFE5E3D9)),
        Expanded(child: _canvas(parcels)),
        const Divider(height: 1, color: Color(0xFFE5E3D9)),
        _selectionPanel(),
      ],
    );
  }

  Widget _toolbar(Map<ParcelCoord, String> parcels) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Text('Terrain map', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        Text(
          '${parcels.length} parcel(s)',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const Spacer(),
        Flexible(
          child: _usage == null
              ? Text(
                  'No world save loaded — locks unavailable',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                )
              : Text(
                  'World: ${_usage!.occupiedCells.length} occupied cell(s) · '
                  '${_usage!.ownedParcels.length} owned parcel(s)',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
        ),
        IconButton(
          tooltip: 'Reload the current save',
          onPressed: _loadUsage,
          icon: const Icon(Icons.refresh_rounded, size: 18),
        ),
      ],
    ),
  );

  Widget _canvas(Map<ParcelCoord, String> parcels) {
    if (parcels.isEmpty) {
      return const Center(
        child: Text(
          'No parcels on the map — author the first entry in '
          'terrain.json or restore a backup.',
        ),
      );
    }
    final coords = parcels.keys.toList();
    double minLeft = double.infinity;
    double maxLeft = double.negativeInfinity;
    double minTop = double.infinity;
    double maxTop = double.negativeInfinity;
    for (final coord in coords) {
      final left = (coord.x - coord.y) * _parcelW / 2;
      final top = (coord.x + coord.y) * _parcelH / 2;
      minLeft = math.min(minLeft, left);
      maxLeft = math.max(maxLeft, left + _parcelW);
      minTop = math.min(minTop, top);
      maxTop = math.max(maxTop, top + _parcelH);
    }
    final width = maxLeft - minLeft + 2 * _canvasPadding;
    final height = maxTop - minTop + 2 * _canvasPadding;
    final occupiedByParcel = _occupiedByParcel;

    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.15,
      maxScale: 4,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final entry in parcels.entries)
              Positioned(
                left:
                    (entry.key.x - entry.key.y) * _parcelW / 2 -
                    minLeft +
                    _canvasPadding,
                top:
                    (entry.key.x + entry.key.y) * _parcelH / 2 -
                    minTop +
                    _canvasPadding,
                width: _parcelW,
                height: _parcelH,
                child: _ParcelTile(
                  coord: entry.key,
                  kind: entry.value,
                  occupiedCells:
                      occupiedByParcel[entry.key] ?? const <CellCoord>{},
                  owned: _usage?.ownedParcels.contains(entry.key) ?? false,
                  selected: _selected == entry.key,
                  addDirections: [
                    for (final dir in const [
                      [1, 0],
                      [-1, 0],
                      [0, 1],
                      [0, -1],
                    ])
                      if (!parcels.containsKey(
                        ParcelCoord(entry.key.x + dir[0], entry.key.y + dir[1]),
                      ))
                        dir,
                  ],
                  onSelect: (coord) => setState(() => _selected = coord),
                  onAddNeighbor: _addNeighbor,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _selectionPanel() {
    final selected = _selected;
    if (selected == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Select a parcel to change its kind or delete it. The + '
            'buttons grow the map with same-kind neighbours.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      );
    }
    final kind = _parcels[selected] ?? 'grass';
    final occupied = _occupiedByParcel.containsKey(selected);
    final owned = _usage?.ownedParcels.contains(selected) ?? false;
    final isStarter = selected == const ParcelCoord(0, 0);
    final kindLocked = occupied || isStarter;
    final deleteLocked = occupied || owned || isStarter;
    final reason = isStarter
        ? 'The starter parcel must stay grass on the map.'
        : occupied
        ? 'This parcel has occupied cells in the current save — clear '
              'them in the game first.'
        : owned
        ? 'You own this parcel — it cannot be deleted, only re-typed.'
        : 'Vacant — free to change or delete.';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Parcel ${selected.x},${selected.y} · $kind',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 150,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Kind',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButton<String>(
                    value: kind,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'grass', child: Text('grass')),
                      DropdownMenuItem(value: 'water', child: Text('water')),
                      DropdownMenuItem(value: 'fog', child: Text('fog')),
                    ],
                    onChanged: kindLocked
                        ? null
                        : (value) {
                            if (value != null) _changeKind(selected, value);
                          },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: deleteLocked ? null : () => _deleteParcel(selected),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete parcel'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  reason,
                  style: TextStyle(
                    fontSize: 12,
                    color: kindLocked || deleteLocked
                        ? Colors.orange.shade900
                        : Colors.black54,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One authored parcel: the diamond painter plus the + buttons on its
/// void-facing edges.
class _ParcelTile extends StatelessWidget {
  const _ParcelTile({
    required this.coord,
    required this.kind,
    required this.occupiedCells,
    required this.owned,
    required this.selected,
    required this.addDirections,
    required this.onSelect,
    required this.onAddNeighbor,
  });

  final ParcelCoord coord;
  final String kind;
  final Set<CellCoord> occupiedCells;
  final bool owned;
  final bool selected;
  final List<List<int>> addDirections;
  final ValueChanged<ParcelCoord> onSelect;
  final void Function(ParcelCoord coord, int dx, int dy) onAddNeighbor;

  static const _addButtonSize = 30.0;

  @override
  Widget build(BuildContext context) {
    // Edge midpoints of the parcel diamond, per neighbour direction:
    // +x runs toward the bottom-right edge, −x toward the top-left,
    // +y (row) toward the bottom-left, −y toward the top-right.
    final offsets = <List<int>, Offset>{
      const [1, 0]: const Offset(3 * _parcelW / 4, 3 * _parcelH / 4),
      const [-1, 0]: const Offset(_parcelW / 4, _parcelH / 4),
      const [0, 1]: const Offset(_parcelW / 4, 3 * _parcelH / 4),
      const [0, -1]: const Offset(3 * _parcelW / 4, _parcelH / 4),
    };
    return GestureDetector(
      key: ValueKey('parcel-${coord.x}-${coord.y}'),
      onTap: () => onSelect(coord),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Diamond-clipped so taps in the transparent box corners fall
          // through to the neighbouring parcel they visually belong to.
          ClipPath(
            clipper: _DiamondClipper(),
            child: CustomPaint(
              size: const Size(_parcelW, _parcelH),
              painter: _ParcelPainter(
                coord: coord,
                kind: kind,
                occupiedCells: occupiedCells,
                owned: owned,
                selected: selected,
              ),
            ),
          ),
          for (final dir in addDirections)
            Positioned(
              key: ValueKey('add-${coord.x}-${coord.y}-${dir[0]}-${dir[1]}'),
              left: offsets[dir]!.dx - _addButtonSize / 2,
              top: offsets[dir]!.dy - _addButtonSize / 2,
              child: SizedBox(
                width: _addButtonSize,
                height: _addButtonSize,
                child: IconButton.filledTonal(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: 'Add a $kind parcel ${_directionLabel(dir)}',
                  onPressed: () => onAddNeighbor(coord, dir[0], dir[1]),
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _directionLabel(List<int> dir) => switch (dir) {
    [1, 0] => 'to the east',
    [-1, 0] => 'to the west',
    [0, 1] => 'to the south',
    _ => 'to the north',
  };
}

const _parcelW = 256.0;
const _parcelH = 128.0;

class _DiamondClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width / 2, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width / 2, size.height)
    ..lineTo(0, size.height / 2)
    ..close();

  @override
  bool shouldReclip(covariant _DiamondClipper oldClipper) => false;
}

const _canvasPadding = 44.0;

class _ParcelPainter extends CustomPainter {
  const _ParcelPainter({
    required this.coord,
    required this.kind,
    required this.occupiedCells,
    required this.owned,
    required this.selected,
  });

  final ParcelCoord coord;
  final String kind;
  final Set<CellCoord> occupiedCells;
  final bool owned;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final diamond = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h / 2)
      ..lineTo(w / 2, h)
      ..lineTo(0, h / 2)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()
        ..color = switch (kind) {
          'water' => waterFill,
          'fog' => fogFill,
          _ => grassFill,
        },
    );

    // Faint 8×8 cell grid; cells occupied in the current save are
    // greyed.
    final cellW = w / 8;
    final cellH = h / 8;
    final grid = Paint()
      ..color = const Color(0x28000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final grey = Paint()..color = const Color(0x59000000);
    for (var cy = 0; cy < 8; cy++) {
      for (var cx = 0; cx < 8; cx++) {
        final center = Offset(
          w / 2 + (cx - cy) * cellW / 2,
          h / 2 + (cx + cy - 7) * cellH / 2,
        );
        final cellPath = Path()
          ..moveTo(center.dx, center.dy - cellH / 2)
          ..lineTo(center.dx + cellW / 2, center.dy)
          ..lineTo(center.dx, center.dy + cellH / 2)
          ..lineTo(center.dx - cellW / 2, center.dy)
          ..close();
        if (occupiedCells.contains(
          CellCoord(coord.x * 8 + cx, coord.y * 8 + cy),
        )) {
          canvas.drawPath(cellPath, grey);
        }
        canvas.drawPath(cellPath, grid);
      }
    }

    if (owned) {
      canvas.drawPath(
        diamond,
        Paint()
          ..color = ownedOutline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    if (selected) {
      canvas.drawPath(
        diamond,
        Paint()
          ..color = selectionOutline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
    }

    final label = TextPainter(
      text: TextSpan(
        text: '${coord.x},${coord.y}',
        style: const TextStyle(fontSize: 13, color: Color(0xB3000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(w / 2 - label.width / 2, h / 2 - label.height / 2),
    );
  }

  static const grassFill = Color(0xFFA5C77A);
  static const waterFill = Color(0xFF6FA8DC);
  static const fogFill = Color(0xFFDCE9E3);
  static const ownedOutline = Color(0xFFF5A623);
  static const selectionOutline = Color(0xFF1E6552);

  @override
  bool shouldRepaint(covariant _ParcelPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.owned != owned ||
      oldDelegate.selected != selected ||
      !setEquals(oldDelegate.occupiedCells, occupiedCells);
}

bool setEquals(Set<CellCoord> a, Set<CellCoord> b) =>
    a.length == b.length && a.containsAll(b);
