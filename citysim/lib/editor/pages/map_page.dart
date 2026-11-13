import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show kSecondaryButton, kTertiaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        BrowserContextMenu,
        HardwareKeyboard,
        KeyDownEvent,
        KeyUpEvent,
        LogicalKeyboardKey;

import '../content_api.dart';
import '../edit_fields.dart';
import '../../storage/world_usage.dart';
import '../../world/coordinates.dart';

/// Map editor: the terrain map as an isometric canvas with one active
/// tool at a time, like the game's map.
///
/// * **Select** (default): dragging pans and the wheel zooms — the
///   game's camera feel. Tapping a parcel selects it; the inspector
///   below re-types it with the terrain swatches or deletes it —
///   locked when the current save occupies its cells, when it is
///   owned (delete only), or when it is the starter parcel. The `+`
///   buttons on void-facing edges grow the map with same-kind
///   neighbours.
/// * **Paint tiles**: dragging paints cells with the active swatch;
///   right-click (or the eraser) restores the parcel's base kind.
///   Panning while painting uses the middle button or holding space,
///   and the wheel still zooms. Cells occupied in the current save
///   refuse paint — a water tile under a road would fail world
///   validation on the next load — and painting a cell to its
///   parcel's base erases the override, keeping the file sparse.
///
/// Every edit — each paint stroke, kind change, delete, and map
/// growth — is one undo step behind Ctrl/Cmd+Z and the toolbar's undo
/// button.
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

/// What the canvas does with the pointer. One tool is active at a
/// time; nothing doubles as both.
enum _MapTool { select, paint }

/// One undo step: the terrain maps as they were before an edit.
class _TerrainSnapshot {
  const _TerrainSnapshot(this.parcels, this.tiles);

  final Map<String, Object?> parcels;
  final Map<String, Object?> tiles;
}

class _MapPageState extends State<MapPage> {
  WorldUsage? _usage;
  ParcelCoord? _selected;
  _MapTool _tool = _MapTool.select;

  /// The brush kind in paint mode; the eraser restores the base.
  String _brush = 'water';
  bool _erasing = false;

  /// The cell under the pointer (paint mode) and the parcel under it
  /// (select mode), for hover feedback.
  CellCoord? _hoverCell;
  ParcelCoord? _hoverParcel;

  /// The active paint stroke: set on pointer down, cleared on up.
  bool _dragging = false;

  /// Right-click strokes erase, as does the eraser toggle.
  bool _strokeErasing = false;

  /// Middle-button or space-held panning, active only while painting
  /// (select mode lets the viewer's own drag pan).
  bool _panning = false;
  Offset _panLast = Offset.zero;
  bool _spaceHeld = false;

  /// Set when a paint attempt hit a locked cell, shown in the toolbar.
  String? _lockHint;

  final List<_TerrainSnapshot> _undoStack = [];
  final TransformationController _viewerController = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();

  /// The canvas content size, recorded each build for the fit button.
  Size? _canvasSize;

  @override
  void initState() {
    super.initState();
    _loadUsage();
    HardwareKeyboard.instance.addHandler(_onKey);
    // Right-click erases; the browser menu would only get in the way.
    if (kIsWeb) {
      BrowserContextMenu.disableContextMenu();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (kIsWeb) {
      BrowserContextMenu.enableContextMenu();
    }
    _viewerController.dispose();
    super.dispose();
  }

  /// Tracks space (the pan modifier while painting) and consumes
  /// Ctrl/Cmd+Z for undo.
  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
      _spaceHeld = true;
    } else if (event is KeyUpEvent &&
        event.logicalKey == LogicalKeyboardKey.space) {
      _spaceHeld = false;
    }
    final undo =
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
    if (undo && _undoStack.isNotEmpty) {
      _undo();
      return true;
    }
    return false;
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

  Map<CellCoord, String> get _tiles {
    final terrain = widget.categories['terrain.json'] as Map?;
    final raw = terrain?['tiles'] as Map?;
    if (raw == null) return const {};
    final result = <CellCoord, String>{};
    for (final entry in raw.entries) {
      final parts = '${entry.key}'.split(',');
      if (parts.length != 2) continue;
      final x = int.tryParse(parts[0].trim());
      final y = int.tryParse(parts[1].trim());
      if (x == null || y == null) continue;
      result[CellCoord(x, y)] = '${entry.value}';
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

  // -- Undo ---------------------------------------------------------------

  _TerrainSnapshot _snapshot() {
    final terrain = widget.categories['terrain.json'] as Map? ?? const {};
    final parcels = terrain['parcels'] as Map? ?? const {};
    final tiles = terrain['tiles'] as Map? ?? const {};
    return _TerrainSnapshot(
      Map<String, Object?>.from(parcels),
      Map<String, Object?>.from(tiles),
    );
  }

  void _pushUndo() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > 50) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final snapshot = _undoStack.removeLast();
    _editTerrain((terrain) {
      terrain['parcels'] = Map<String, Object?>.from(snapshot.parcels);
      if (snapshot.tiles.isEmpty) {
        terrain.remove('tiles');
      } else {
        terrain['tiles'] = Map<String, Object?>.from(snapshot.tiles);
      }
    });
    setState(() {
      _selected = null;
      _hoverCell = null;
    });
  }

  // -- Parcel edits ---------------------------------------------------------

  void _addNeighbor(ParcelCoord coord, int dx, int dy) {
    final kind = _parcels[coord];
    final target = ParcelCoord(coord.x + dx, coord.y + dy);
    if (kind == null || _parcels.containsKey(target)) return;
    _pushUndo();
    _editTerrain(
      (terrain) =>
          (terrain['parcels'] as Map)['${target.x},${target.y}'] = kind,
    );
  }

  void _changeKind(ParcelCoord coord, String kind) {
    _pushUndo();
    _editTerrain(
      (terrain) => (terrain['parcels'] as Map)['${coord.x},${coord.y}'] = kind,
    );
  }

  void _deleteParcel(ParcelCoord coord) {
    _pushUndo();
    _editTerrain(
      (terrain) => (terrain['parcels'] as Map).remove('${coord.x},${coord.y}'),
    );
    setState(() => _selected = null);
  }

  // -- Tile painting --------------------------------------------------------

  /// Paints one cell with the active stroke. Painting a cell to its
  /// parcel's base erases the override — the file stays sparse. Cells
  /// occupied in the current save refuse paint.
  void _paintCell(CellCoord cell) {
    final base = _parcels[parcelForCell(cell)];
    if (base == null) return;
    if (_usage?.occupiedCells.contains(cell) ?? false) {
      setState(() => _lockHint = 'Skipped locked cells — occupied in the save');
      return;
    }
    setState(() => _lockHint = null);
    final target = _strokeErasing ? base : _brush;
    if ((_tiles[cell] ?? base) == target) return;
    _editTerrain((terrain) {
      var tiles = terrain['tiles'];
      if (tiles is! Map) {
        tiles = <String, Object?>{};
        terrain['tiles'] = tiles;
      }
      final key = '${cell.column},${cell.row}';
      if (target == base) {
        tiles.remove(key);
      } else {
        tiles[key] = target;
      }
    });
  }

  /// The cell under a canvas-space point, if any — the parcel first,
  /// by diamond containment, then the cell within it. [minLeft] and
  /// [minTop] are the canvas offsets the parcel stack is laid out
  /// with, including the padding.
  CellCoord? _cellAt(
    Offset point,
    Map<ParcelCoord, String> parcels,
    double minLeft,
    double minTop,
  ) {
    for (final entry in parcels.entries) {
      final left = (entry.key.x - entry.key.y) * _parcelW / 2 - minLeft;
      final top = (entry.key.x + entry.key.y) * _parcelH / 2 - minTop;
      final local = point - Offset(left, top);
      if (local.dx < 0 ||
          local.dx >= _parcelW ||
          local.dy < 0 ||
          local.dy >= _parcelH) {
        continue;
      }
      for (var cy = 0; cy < 8; cy++) {
        for (var cx = 0; cx < 8; cx++) {
          final centre = Offset(
            _parcelW / 2 + (cx - cy) * _cellW / 2,
            _parcelH / 2 + (cx + cy - 7) * _cellH / 2,
          );
          final dx = (local.dx - centre.dx) / (_cellW / 2);
          final dy = (local.dy - centre.dy) / (_cellH / 2);
          if (dx.abs() + dy.abs() <= 1) {
            return CellCoord(entry.key.x * 8 + cx, entry.key.y * 8 + cy);
          }
        }
      }
    }
    return null;
  }

  // -- Camera ---------------------------------------------------------------

  /// Moves the content with the pointer while painting, where the
  /// viewer's own drag pan is disabled.
  void _panBy(Offset screenDelta) {
    _viewerController.value = Matrix4.translationValues(
      screenDelta.dx,
      screenDelta.dy,
      0,
    ).multiplied(_viewerController.value);
  }

  /// Fits the whole map in the viewport at 1:1 or smaller, centred.
  void _fitView() {
    final box = _viewerKey.currentContext?.findRenderObject();
    final size = _canvasSize;
    if (box is! RenderBox || size == null || box.size.isEmpty) return;
    final scale = math.min(
      1.0,
      math.min(box.size.width / size.width, box.size.height / size.height),
    );
    _viewerController.value = Matrix4.translationValues(
      (box.size.width - size.width * scale) / 2,
      (box.size.height - size.height * scale) / 2,
      0,
    ).multiplied(Matrix4.diagonal3Values(scale, scale, 1));
  }

  // -- Build ----------------------------------------------------------------

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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Terrain map', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            Text(
              '${parcels.length} parcel(s)'
              '${_tiles.isEmpty ? '' : ' · ${_tiles.length} tile override(s)'}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Spacer(),
            Flexible(
              child: _lockHint != null
                  ? Text(
                      _lockHint!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    )
                  : _usage == null
                  ? Text(
                      'No world save loaded — locks unavailable',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    )
                  : Text(
                      'World: ${_usage!.occupiedCells.length} occupied cell(s) · '
                      '${_usage!.ownedParcels.length} owned parcel(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
            ),
            IconButton(
              tooltip: 'Undo (Ctrl+Z)',
              onPressed: _undoStack.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo_rounded, size: 18),
            ),
            IconButton(
              tooltip: 'Fit map',
              onPressed: _fitView,
              icon: const Icon(Icons.fit_screen_rounded, size: 18),
            ),
            IconButton(
              tooltip: 'Reload the current save',
              onPressed: _loadUsage,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<_MapTool>(
              segments: const [
                ButtonSegment(
                  value: _MapTool.select,
                  icon: Icon(Icons.near_me_outlined, size: 16),
                  label: Text('Select'),
                ),
                ButtonSegment(
                  value: _MapTool.paint,
                  icon: Icon(Icons.brush_rounded, size: 16),
                  label: Text('Paint tiles'),
                ),
              ],
              selected: {_tool},
              onSelectionChanged: (selection) => setState(() {
                _tool = selection.first;
                // One tool at a time: painting never reads as selecting.
                _dragging = false;
                _lockHint = null;
                if (_tool == _MapTool.paint) {
                  _selected = null;
                  _hoverParcel = null;
                } else {
                  _hoverCell = null;
                }
              }),
              showSelectedIcon: false,
            ),
            if (_tool == _MapTool.paint) ...[
              _TerrainSwatches(
                selected: _erasing ? null : _brush,
                onPick: (kind) => setState(() {
                  _brush = kind;
                  _erasing = false;
                }),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Eraser — or right-click while painting',
                child: IconButton.filledTonal(
                  onPressed: _erasing
                      ? null
                      : () => setState(() => _erasing = true),
                  isSelected: _erasing,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                ),
              ),
            ],
          ],
        ),
        if (_tool == _MapTool.paint)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Drag to paint; middle-drag or space to pan; wheel zooms. '
              'Painting a cell back to its parcel\'s kind erases it.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
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
    _canvasSize = Size(width, height);
    final canvasMinLeft = minLeft - _canvasPadding;
    final canvasMinTop = minTop - _canvasPadding;
    final occupiedByParcel = _occupiedByParcel;
    final tiles = _tiles;
    final painting = _tool == _MapTool.paint;
    final hoverLocked =
        _hoverCell != null &&
        (_usage?.occupiedCells.contains(_hoverCell) ?? false);

    CellCoord? cellAt(Offset local) =>
        _cellAt(local, parcels, canvasMinLeft, canvasMinTop);

    void updateHover(Offset local) {
      if (painting) {
        final cell = cellAt(local);
        if (cell != _hoverCell) setState(() => _hoverCell = cell);
      } else {
        final cell = cellAt(local);
        final parcel = cell == null ? null : parcelForCell(cell);
        if (parcel != _hoverParcel) setState(() => _hoverParcel = parcel);
      }
    }

    return InteractiveViewer(
      key: _viewerKey,
      transformationController: _viewerController,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.15,
      maxScale: 4,
      // Drag pans only in select mode — the game's camera feel. While
      // painting, the drag belongs to the brush; panning moves to the
      // middle button (or holding space) so the two can never fight.
      panEnabled: !painting,
      child: SizedBox(
        width: width,
        height: height,
        child: Listener(
          key: const ValueKey('tile-brush-canvas'),
          onPointerDown: (event) {
            if (painting && (event.buttons == kTertiaryButton || _spaceHeld)) {
              _panning = true;
              _panLast = event.position;
              return;
            }
            if (!painting) return;
            // One undo step per stroke, whatever it ends up painting.
            _pushUndo();
            _dragging = true;
            _strokeErasing =
                _erasing || (event.buttons & kSecondaryButton) != 0;
            final cell = cellAt(event.localPosition);
            if (cell != null) _paintCell(cell);
          },
          onPointerMove: (event) {
            if (_panning) {
              _panBy(event.position - _panLast);
              _panLast = event.position;
              return;
            }
            if (_dragging) {
              final cell = cellAt(event.localPosition);
              if (cell != null) _paintCell(cell);
              return;
            }
            updateHover(event.localPosition);
          },
          onPointerHover: (event) => updateHover(event.localPosition),
          onPointerUp: (_) {
            _dragging = false;
            _panning = false;
          },
          onPointerCancel: (_) {
            _dragging = false;
            _panning = false;
          },
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
                    hovered: _hoverParcel == entry.key,
                    tileKinds: {
                      for (final tile in tiles.entries)
                        if (parcelForCell(tile.key) == entry.key)
                          tile.key: tile.value,
                    },
                    hoverCell: _hoverCell,
                    hoverLocked: hoverLocked,
                    addDirections: painting
                        ? const []
                        : [
                            for (final dir in const [
                              [1, 0],
                              [-1, 0],
                              [0, 1],
                              [0, -1],
                            ])
                              if (!parcels.containsKey(
                                ParcelCoord(
                                  entry.key.x + dir[0],
                                  entry.key.y + dir[1],
                                ),
                              ))
                                dir,
                          ],
                    onSelect: painting
                        ? null
                        : (coord) => setState(() => _selected = coord),
                    onAddNeighbor: _addNeighbor,
                  ),
                ),
            ],
          ),
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
            'Select a parcel to re-type or delete it; the + buttons grow '
            'the map. The Paint tiles tool paints individual cells.',
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
              _TerrainSwatches(
                selected: kind,
                onPick: kindLocked
                    ? null
                    : (kind) => _changeKind(selected, kind),
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

/// The terrain palette, shared by the paint brush and the parcel
/// inspector so "terrain kind" is one control everywhere: the kinds
/// you author. Fog is not among them — it is not a terrain type,
/// only the look of uncharted space, so leaving a parcel unauthored
/// is how you get fog.
class _TerrainSwatches extends StatelessWidget {
  const _TerrainSwatches({required this.selected, required this.onPick});

  final String? selected;

  /// Null disables the palette (locked parcels).
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    Widget swatch(String kind, Color fill) => ChoiceChip(
      label: Text(kind),
      avatar: CircleAvatar(backgroundColor: fill, radius: 6),
      selected: selected == kind,
      onSelected: onPick == null ? null : (_) => onPick!(kind),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch('grass', _ParcelPainter.grassFill),
        const SizedBox(width: 4),
        swatch('water', _ParcelPainter.waterFill),
      ],
    );
  }
}

/// One authored parcel: the diamond painter plus the + buttons on its
/// void-facing edges. In paint mode the buttons hide and taps pass
/// through to the canvas-level paint listener.
class _ParcelTile extends StatelessWidget {
  const _ParcelTile({
    required this.coord,
    required this.kind,
    required this.occupiedCells,
    required this.owned,
    required this.selected,
    required this.hovered,
    required this.tileKinds,
    required this.hoverCell,
    required this.hoverLocked,
    required this.addDirections,
    required this.onSelect,
    required this.onAddNeighbor,
  });

  final ParcelCoord coord;
  final String kind;
  final Set<CellCoord> occupiedCells;
  final bool owned;
  final bool selected;
  final bool hovered;

  /// Painted tile overrides within this parcel, by absolute cell.
  final Map<CellCoord, String> tileKinds;

  /// The cell under the pointer while painting, and whether it is
  /// locked — the brush footprint preview.
  final CellCoord? hoverCell;
  final bool hoverLocked;

  final List<List<int>> addDirections;
  final ValueChanged<ParcelCoord>? onSelect;
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
      onTap: onSelect == null ? null : () => onSelect!(coord),
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
                hovered: hovered,
                tileKinds: tileKinds,
                hoverCell: hoverCell,
                hoverLocked: hoverLocked,
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

/// One cell within a parcel diamond on the map canvas.
const _cellW = _parcelW / 8;
const _cellH = _parcelH / 8;

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
    required this.hovered,
    required this.tileKinds,
    required this.hoverCell,
    required this.hoverLocked,
  });

  final ParcelCoord coord;
  final String kind;
  final Set<CellCoord> occupiedCells;
  final bool owned;
  final bool selected;
  final bool hovered;

  /// Painted tile overrides within this parcel, by absolute cell.
  final Map<CellCoord, String> tileKinds;

  /// The brush footprint: the cell under the pointer while painting.
  final CellCoord? hoverCell;
  final bool hoverLocked;

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
    // greyed, painted overrides carry their own kind's fill, and the
    // hovered cell shows the brush footprint — green where paintable,
    // red where locked.
    final cellW = w / 8;
    final cellH = h / 8;
    final grid = Paint()
      ..color = const Color(0x28000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final grey = Paint()..color = const Color(0x59000000);
    for (var cy = 0; cy < 8; cy++) {
      for (var cx = 0; cx < 8; cx++) {
        final cell = CellCoord(coord.x * 8 + cx, coord.y * 8 + cy);
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
        final override = tileKinds[cell];
        if (override != null) {
          canvas.drawPath(
            cellPath,
            Paint()
              ..color = switch (override) {
                'water' => waterFill,
                'fog' => fogFill,
                _ => grassFill,
              },
          );
        }
        if (cell == hoverCell) {
          canvas.drawPath(
            cellPath,
            Paint()
              ..color = hoverLocked
                  ? const Color(0x80B3261E)
                  : const Color(0x6600A95C),
          );
        }
        if (occupiedCells.contains(cell)) {
          canvas.drawPath(cellPath, grey);
        }
        canvas.drawPath(cellPath, grid);
      }
    }

    if (hovered && !selected) {
      canvas.drawPath(
        diamond,
        Paint()
          ..color = const Color(0x66000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
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
      oldDelegate.hovered != hovered ||
      oldDelegate.hoverCell != hoverCell ||
      oldDelegate.hoverLocked != hoverLocked ||
      oldDelegate.coord != coord ||
      !setEquals(oldDelegate.occupiedCells, occupiedCells) ||
      !_mapEquals(oldDelegate.tileKinds, tileKinds);
}

bool setEquals(Set<CellCoord> a, Set<CellCoord> b) =>
    a.length == b.length && a.containsAll(b);

bool _mapEquals(Map<CellCoord, String> a, Map<CellCoord, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
