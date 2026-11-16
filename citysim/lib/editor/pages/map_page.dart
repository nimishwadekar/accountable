import 'dart:async';
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
///   owned (delete only), when it is the starter parcel, or when it
///   still carries nature props. The `+` buttons on void-facing
///   edges grow the map with same-kind neighbours.
/// * **Paint tiles**: dragging paints cells with the active swatch;
///   right-click (or the eraser) restores the parcel's base kind.
///   Panning while painting uses the middle button or holding space,
///   and the wheel still zooms. Cells occupied in the current save
///   or carrying nature props refuse paint — a water tile under a
///   road would fail world validation on the next load, and a prop
///   on a water tile would fail content validation — so clear the
///   nature first. Painting a cell to its parcel's base erases the
///   override, keeping the file sparse.
/// * **Nature**: a circle brush that sprinkles the selected item —
///   the catalogue's decorations carrying a legalTerrain tag — onto
///   the map. Each click draws N distinct subtiles uniformly in the
///   disk and places only the legal ones (land, unowned, unoccupied,
///   subtile free): N is an upper bound, so clearings stay clear.
///   Holding the pointer down repeats the placement every quarter
///   second at the cell under it — hold and sweep to paint a
///   forest. The eraser — a toggle, as is right-click — removes the
///   selected item's props inside the circle, all of them,
///   deterministically. Rows land in terrain.json's sparse `props`
///   section — the map's pristine vegetation, materialized into a
///   save when its parcel is purchased.
///
/// Every edit — each paint stroke, kind change, delete, map growth,
/// nature click, and nature clear — is one undo step behind
/// Ctrl/Cmd+Z and the toolbar's undo button.
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
enum _MapTool { select, paint, nature }

/// One undo step: the terrain maps as they were before an edit.
class _TerrainSnapshot {
  const _TerrainSnapshot(this.parcels, this.tiles, this.props);

  final Map<String, Object?> parcels;
  final Map<String, Object?> tiles;
  final List<Object?> props;
}

class _MapPageState extends State<MapPage> {
  WorldUsage? _usage;
  ParcelCoord? _selected;
  _MapTool _tool = _MapTool.select;

  /// The brush kind in paint mode; the eraser restores the base.
  String _brush = 'water';
  bool _erasing = false;

  /// Nature brush state: the selected item (a catalogue id), the
  /// disk radius in cells, the per-click draw count, and the eraser
  /// toggle (right-click also clears).
  String? _natureItem;
  double _brushRadius = 2;
  int _brushCount = 8;
  bool _natureErasing = false;

  /// The hold-to-paint loop: while the brush pointer stays down, the
  /// placement (or erase) repeats every quarter second at the cell
  /// under the pointer — hold and sweep to paint a forest.
  Timer? _natureRepeatTimer;

  /// The action the hold loop repeats: the mode the pressed click
  /// ran (the toggle, or a right-click's erase).
  bool _natureRepeatErasing = false;

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
    _stopNatureRepeat();
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

  /// The map's authored nature rows, decoded like the pipeline would
  /// (dynamic values). Each row is the save's Props-table shape with
  /// named fields: catalogueId, x, y, subtileX, subtileY, and the
  /// optional rolled variant fields.
  List<Map<String, Object?>> get _natureRows {
    final terrain = widget.categories['terrain.json'] as Map?;
    final raw = terrain?['props'];
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map) row.cast<String, Object?>(),
    ];
  }

  /// The nature brush's palette: catalogue decorations carrying a
  /// legalTerrain tag — the field is the vocabulary, so new nature
  /// items are content, not code.
  List<({String id, String name, List<String> roles})> get _natureItems {
    final models = (widget.categories['catalogue.json'] as Map?)?['models'];
    if (models is! List) return const [];
    return [
      for (final model in models)
        if (model is Map &&
            model['kind'] == 'decoration' &&
            (model['legalTerrain'] as List?)?.isNotEmpty == true)
          (
            id: model['id']! as String,
            name: model['name']! as String,
            roles: [
              for (final role in model['assetRoles']! as List) role as String,
            ],
          ),
    ];
  }

  /// Whether a sprite role carries door facings — the brush rolls a
  /// facing exactly like the reducer does, but only for sprites
  /// that have them.
  bool _roleHasFacings(String role) {
    final sprites = widget.categories['sprites.json'] as Map?;
    final sprite = sprites?[role];
    return sprite is Map && sprite['facings'] != null;
  }

  /// Nature rows grouped by the cell they stand on — the paint and
  /// kind-change refusals read this.
  Map<CellCoord, List<Map<String, Object?>>> get _natureRowsByCell {
    final result = <CellCoord, List<Map<String, Object?>>>{};
    for (final row in _natureRows) {
      final x = row['x'];
      final y = row['y'];
      if (x is! int || y is! int) continue;
      result.putIfAbsent(CellCoord(x, y), () => []).add(row);
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
    final props = terrain['props'] as List? ?? const [];
    return _TerrainSnapshot(
      Map<String, Object?>.from(parcels),
      Map<String, Object?>.from(tiles),
      List<Object?>.of(props),
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
      if (snapshot.props.isEmpty) {
        terrain.remove('props');
      } else {
        terrain['props'] = List<Object?>.of(snapshot.props);
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
  /// occupied in the current save or carrying nature props refuse
  /// paint (a prop on water fails content validation — clear the
  /// nature first).
  void _paintCell(CellCoord cell) {
    final base = _parcels[parcelForCell(cell)];
    if (base == null) return;
    if (_usage?.occupiedCells.contains(cell) ?? false) {
      setState(() => _lockHint = 'Skipped locked cells — occupied in the save');
      return;
    }
    if (_natureRowsByCell.containsKey(cell)) {
      setState(
        () => _lockHint =
            'Skipped propped cells — clear their nature first (Nature tool)',
      );
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

  // -- Nature brush ----------------------------------------------------------

  /// How many nature rows a parcel carries — the inspector's clear
  /// button and lock reasons read this.
  int _parcelNatureCount(ParcelCoord coord) {
    final rows = _natureRows;
    if (rows.isEmpty) return 0;
    var count = 0;
    for (final row in rows) {
      final x = row['x'];
      final y = row['y'];
      if (x is int && y is int && parcelForCell(CellCoord(x, y)) == coord) {
        count++;
      }
    }
    return count;
  }

  /// Whether a subtile accepts the selected item: authored land the
  /// item's legalTerrain covers, in a parcel the save does not own,
  /// without occupation, on a free subtile.
  bool _natureSubtileLegal(
    CellCoord cell,
    int subtileX,
    int subtileY,
    Set<String> anchors,
  ) {
    final base = _parcels[parcelForCell(cell)];
    if (base == null) return false;
    if ((_tiles[cell] ?? base) != 'grass') return false;
    if (_usage?.ownedParcels.contains(parcelForCell(cell)) ?? false) {
      return false;
    }
    if (_usage?.occupiedCells.contains(cell) ?? false) return false;
    return !anchors.contains('${cell.key}:$subtileX.$subtileY');
  }

  /// One click of the nature brush: draw [count] distinct subtiles
  /// uniformly in the disk, keep the legal ones, and write their
  /// rows — the variant rolled now and stored, so the game's
  /// frontier render and the purchase copy draw the identical
  /// sprite. A click that places nothing pushes no undo step.
  void _sprinkleNature(CellCoord center) {
    final items = _natureItems;
    if (items.isEmpty) return;
    final selected = _natureItem;
    final item = selected == null || items.every((i) => i.id != selected)
        ? items.first
        : items.firstWhere((i) => i.id == selected);
    if (_natureItem != item.id) setState(() => _natureItem = item.id);
    final itemId = item.id;
    final random = math.Random();
    final anchors = <String>{
      for (final row in _natureRows)
        '${row['x']},${row['y']}:${row['subtileX']}.${row['subtileY']}',
    };
    final placements = sampleNatureBrush(
      centerCol: center.column + 0.5,
      centerRow: center.row + 0.5,
      radiusCells: _brushRadius,
      count: _brushCount,
      legal: (cell, subtileX, subtileY) =>
          _natureSubtileLegal(cell, subtileX, subtileY, anchors),
      random: random,
    );
    if (placements.isEmpty) {
      setState(
        () => _lockHint =
            'Nothing placed — the disk holds no legal subtile for $itemId',
      );
      return;
    }
    setState(() => _lockHint = null);
    final newRows = <Map<String, Object?>>[];
    for (final (cell, subtileX, subtileY) in placements) {
      final role = item.roles[random.nextInt(item.roles.length)];
      final facing = _roleHasFacings(role)
          ? (random.nextBool() ? 'south' : 'east')
          : null;
      newRows.add({
        'catalogueId': itemId,
        'x': cell.column,
        'y': cell.row,
        'subtileX': subtileX,
        'subtileY': subtileY,
        'assetRole': role,
        'facing': ?facing,
      });
    }
    _pushUndo();
    _editTerrain((terrain) {
      var rows = terrain['props'];
      if (rows is! List) {
        rows = <Object?>[];
        terrain['props'] = rows;
      }
      rows.addAll(newRows);
    });
  }

  /// The eraser stroke: every row of the selected item inside the
  /// brush disk goes — deterministic, the exact opposite of the
  /// sprinkle's sample. Rows of other items, and rows of this item
  /// outside the circle, stay untouched.
  void _eraseNature(CellCoord center) {
    final items = _natureItems;
    if (items.isEmpty) return;
    final selected = _natureItem;
    final item = selected == null || items.every((i) => i.id != selected)
        ? items.first
        : items.firstWhere((i) => i.id == selected);
    final rows = _natureRows;
    final radiusSq = _brushRadius * _brushRadius;
    final centerCol = center.column + 0.5;
    final centerRow = center.row + 0.5;
    final kept = <Map<String, Object?>>[];
    for (final row in rows) {
      final x = row['x'];
      final y = row['y'];
      if (x is int &&
          y is int &&
          row['catalogueId'] == item.id &&
          x >= (centerCol - _brushRadius).floor() - 1 &&
          x <= (centerCol + _brushRadius).ceil() + 1 &&
          y >= (centerRow - _brushRadius).floor() - 1 &&
          y <= (centerRow + _brushRadius).ceil() + 1) {
        final col = x + (((row['subtileX'] as int?) ?? 0) + 0.5) / 8;
        final gridRow = y + (((row['subtileY'] as int?) ?? 0) + 0.5) / 8;
        final dCol = col - centerCol;
        final dRow = gridRow - centerRow;
        if (dCol * dCol + dRow * dRow <= radiusSq) {
          continue; // Inside the disk: erased.
        }
      }
      kept.add(row);
    }
    if (kept.length == rows.length) return;
    _pushUndo();
    _editTerrain(
      (terrain) =>
          kept.isEmpty ? terrain.remove('props') : terrain['props'] = kept,
    );
  }

  /// Clears a whole parcel's nature rows, from the inspector — one
  /// undo step, refused on owned parcels (their props live in the
  /// save, not the map).
  void _clearNatureParcel(ParcelCoord coord) {
    if (_usage?.ownedParcels.contains(coord) ?? false) return;
    final rows = _natureRows;
    final kept = [
      for (final row in rows)
        if (row['x'] is int &&
            row['y'] is int &&
            parcelForCell(CellCoord(row['x'] as int, row['y'] as int)) != coord)
          row,
    ];
    if (kept.length == rows.length) return;
    _pushUndo();
    _editTerrain(
      (terrain) =>
          kept.isEmpty ? terrain.remove('props') : terrain['props'] = kept,
    );
  }

  /// Runs the brush's current action at a cell — placing or erasing
  /// per [erasing] — shared by the press and the hold loop.
  void _runNatureAction(CellCoord cell, {required bool erasing}) {
    if (erasing) {
      _eraseNature(cell);
    } else {
      _sprinkleNature(cell);
    }
  }

  /// The hold loop: every quarter second while the pointer stays
  /// down, the action repeats at the cell under it — the mode the
  /// pressed click ran. Starts on press, stops on release, tool
  /// switch, and teardown.
  void _startNatureRepeat() {
    _stopNatureRepeat();
    _natureRepeatTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      final cell = _hoverCell;
      if (cell != null) {
        _runNatureAction(cell, erasing: _natureRepeatErasing);
      }
    });
  }

  void _stopNatureRepeat() {
    _natureRepeatTimer?.cancel();
    _natureRepeatTimer = null;
  }

  /// A cell's centre on the canvas — the nature brush's snapped
  /// disk centre, where the ellipse preview anchors. [minLeft] and
  /// [minTop] are the canvas offsets the parcel stack is laid out
  /// with, padding already included (as `_cellAt` takes them).
  Offset _cellCanvasCenter(CellCoord cell, double minLeft, double minTop) {
    final parcel = parcelForCell(cell);
    final cx = cell.column - parcel.x * 8;
    final cy = cell.row - parcel.y * 8;
    return Offset(
      (parcel.x - parcel.y) * _parcelW / 2 -
          minLeft +
          _parcelW / 2 +
          (cx - cy) * _cellW / 2,
      (parcel.x + parcel.y) * _parcelH / 2 -
          minTop +
          _parcelH / 2 +
          (cx + cy - 7) * _cellH / 2,
    );
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
            // The summary ellipsizes rather than pushing the status
            // text out — the Row can never overflow, and the status
            // never collapses to zero width (which, under the
            // toolbar's unbounded height, wraps into a column that
            // eats the canvas).
            Flexible(
              child: Text(
                '${parcels.length} parcel(s)'
                '${_tiles.isEmpty ? '' : ' · ${_tiles.length} tile override(s)'}'
                '${_natureRows.isEmpty ? '' : ' · ${_natureRows.length} nature prop(s)'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const Spacer(),
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
        const SizedBox(height: 2),
        // The lock hint and world summary take their own line at full
        // width — bounded to two lines, so long messages wrap instead
        // of exploding.
        Text(
          _lockHint ??
              (_usage == null
                  ? 'No world save loaded — locks unavailable'
                  : 'World: ${_usage!.occupiedCells.length} occupied cell(s) · '
                        '${_usage!.ownedParcels.length} owned parcel(s)'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: _lockHint == null && _usage != null
                ? Colors.black54
                : Colors.orange.shade900,
          ),
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
                ButtonSegment(
                  value: _MapTool.nature,
                  icon: Icon(Icons.forest_rounded, size: 16),
                  label: Text('Nature'),
                ),
              ],
              selected: {_tool},
              onSelectionChanged: (selection) => setState(() {
                _tool = selection.first;
                // One tool at a time: painting never reads as selecting.
                _dragging = false;
                _lockHint = null;
                _stopNatureRepeat();
                if (_tool == _MapTool.paint || _tool == _MapTool.nature) {
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
                message:
                    'Eraser — or right-click while painting. '
                    'Click again to paint',
                child: IconButton.filledTonal(
                  onPressed: () => setState(() => _erasing = !_erasing),
                  isSelected: _erasing,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                ),
              ),
            ],
            if (_tool == _MapTool.nature) ...[
              _NatureItemPicker(
                items: _natureItems,
                selected: _natureItem ?? _natureItems.firstOrNull?.id,
                onPick: (id) => setState(() {
                  _natureItem = id;
                  _natureErasing = false;
                }),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 168,
                child: Row(
                  children: [
                    const Text('Radius', style: TextStyle(fontSize: 11)),
                    Expanded(
                      child: Slider(
                        value: _brushRadius,
                        min: 0.5,
                        max: 8,
                        divisions: 15,
                        label: '${_brushRadius.toStringAsFixed(1)}c',
                        onChanged: (value) =>
                            setState(() => _brushRadius = value),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 168,
                child: Row(
                  children: [
                    const Text('Per click', style: TextStyle(fontSize: 11)),
                    Expanded(
                      child: Slider(
                        value: _brushCount.toDouble(),
                        min: 1,
                        max: 40,
                        divisions: 39,
                        label: '$_brushCount',
                        onChanged: (value) =>
                            setState(() => _brushCount = value.round()),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: _natureErasing
                    ? 'Erasing — click again to place'
                    : 'Erase the selected item in the circle — or right-click',
                child: IconButton.filledTonal(
                  onPressed: () =>
                      setState(() => _natureErasing = !_natureErasing),
                  isSelected: _natureErasing,
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
        if (_tool == _MapTool.nature)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Click to sprinkle the item in the circle; N subtiles are '
              'drawn and only the legal ones land (land, unowned, '
              'unoccupied, free). Hold to keep placing every quarter '
              'second — sweep while held to paint a forest. The eraser — '
              'or right-click — removes the selected item\'s props inside '
              'the circle, and toggles back to placing. Owned parcels and '
              'occupied cells never take nature.',
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
    final brushing = _tool == _MapTool.nature;
    final hoverLocked =
        _hoverCell != null &&
        (_usage?.occupiedCells.contains(_hoverCell) ?? false);
    final natureRows = _natureRows;
    final natureByParcel = <ParcelCoord, List<(CellCoord, int, int, String)>>{};
    for (final row in natureRows) {
      final x = row['x'];
      final y = row['y'];
      if (x is! int || y is! int) continue;
      final cell = CellCoord(x, y);
      natureByParcel.putIfAbsent(parcelForCell(cell), () => []).add((
        cell,
        row['subtileX'] as int? ?? 0,
        row['subtileY'] as int? ?? 0,
        row['catalogueId'] as String? ?? '',
      ));
    }

    CellCoord? cellAt(Offset local) =>
        _cellAt(local, parcels, canvasMinLeft, canvasMinTop);

    void updateHover(Offset local) {
      if (painting || brushing) {
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
      // Drag pans only in select mode — the game's camera feel.
      // While a brush is out, the drag belongs to it; panning moves
      // to the middle button (or holding space) so the two can
      // never fight.
      panEnabled: !painting && !brushing,
      child: SizedBox(
        width: width,
        height: height,
        child: Listener(
          key: const ValueKey('tile-brush-canvas'),
          onPointerDown: (event) {
            if ((painting || brushing) &&
                (event.buttons == kTertiaryButton || _spaceHeld)) {
              _panning = true;
              _panLast = event.position;
              return;
            }
            if (brushing) {
              final cell = cellAt(event.localPosition);
              if (cell == null) return;
              // The press anchors the hover (and the preview) even
              // without a prior hover event; right-click erases
              // regardless of the toggle, and the hold loop repeats
              // whichever mode this press ran.
              _hoverCell = cell;
              _natureRepeatErasing =
                  _natureErasing || (event.buttons & kSecondaryButton) != 0;
              if (_natureRepeatErasing) {
                _eraseNature(cell);
              } else {
                _sprinkleNature(cell);
              }
              _startNatureRepeat();
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
            _stopNatureRepeat();
          },
          onPointerCancel: (_) {
            _dragging = false;
            _panning = false;
            _stopNatureRepeat();
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
                    props: natureByParcel[entry.key] ?? const [],
                    hoverCell: _hoverCell,
                    hoverLocked: hoverLocked,
                    addDirections: painting || brushing
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
                    onSelect: painting || brushing
                        ? null
                        : (coord) => setState(() => _selected = coord),
                    onAddNeighbor: _addNeighbor,
                  ),
                ),
              // The nature brush's footprint: the disk's iso ellipse —
              // semi-axes √2·R half-cells, the projection of the grid
              // circle the sampler actually draws from — anchored at
              // the hovered cell's centre, where clicks land. Green
              // while placing, red while erasing.
              if (brushing)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _NatureBrushPreview(
                        center: _hoverCell == null
                            ? null
                            : _cellCanvasCenter(
                                _hoverCell!,
                                canvasMinLeft,
                                canvasMinTop,
                              ),
                        radiusCells: _brushRadius,
                        erasing: _natureErasing,
                      ),
                    ),
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
    final natureCount = _parcelNatureCount(selected);
    final natureLocked = natureCount > 0;
    final kindLocked = occupied || isStarter || natureLocked;
    final deleteLocked = occupied || owned || isStarter || natureLocked;
    final reason = isStarter
        ? 'The starter parcel must stay grass on the map.'
        : occupied
        ? 'This parcel has occupied cells in the current save — clear '
              'them in the game first.'
        : natureLocked
        ? 'This parcel carries $natureCount nature prop(s) — clear them '
              'before re-typing or deleting it.'
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
          // The actions wrap and the reason takes its own line, so
          // the panel stays compact however wide the buttons run.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _TerrainSwatches(
                selected: kind,
                onPick: kindLocked
                    ? null
                    : (kind) => _changeKind(selected, kind),
              ),
              OutlinedButton.icon(
                onPressed: deleteLocked ? null : () => _deleteParcel(selected),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete parcel'),
              ),
              if (!owned && natureCount > 0)
                OutlinedButton.icon(
                  onPressed: () => _clearNatureParcel(selected),
                  icon: const Icon(Icons.eco_outlined, size: 18),
                  label: Text('Clear $natureCount nature prop(s)'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: TextStyle(
              fontSize: 12,
              color: kindLocked || deleteLocked
                  ? Colors.orange.shade900
                  : Colors.black54,
            ),
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
    required this.props,
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

  /// Authored nature rows within this parcel — (cell, subtileX,
  /// subtileY, catalogueId), one dot each on the schematic canvas.
  final List<(CellCoord, int, int, String)> props;

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
                props: props,
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
    required this.props,
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

  /// Authored nature rows within this parcel, painted as dots.
  final List<(CellCoord, int, int, String)> props;

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
    // Nature rows: one dot per prop at its subtile centre — the
    // schematic language of this canvas; the game draws the sprites.
    if (props.isNotEmpty) {
      final dot = Paint()..style = PaintingStyle.fill;
      for (final (cell, subtileX, subtileY, model) in props) {
        final cx = cell.column - coord.x * 8;
        final cy = cell.row - coord.y * 8;
        if (cx < 0 || cx > 7 || cy < 0 || cy > 7) continue;
        final cellCentre = Offset(
          w / 2 + (cx - cy) * cellW / 2,
          h / 2 + (cx + cy - 7) * cellH / 2,
        );
        final dCol = (subtileX + 0.5) / 8 - 0.5;
        final dRow = (subtileY + 0.5) / 8 - 0.5;
        dot.color = natureDotColor(model);
        canvas.drawCircle(
          cellCentre.translate(
            (dCol - dRow) * cellW / 2,
            (dCol + dRow) * cellH / 2,
          ),
          2.4,
          dot,
        );
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
      oldDelegate.hovered != hovered ||
      oldDelegate.hoverCell != hoverCell ||
      oldDelegate.hoverLocked != hoverLocked ||
      oldDelegate.coord != coord ||
      !setEquals(oldDelegate.occupiedCells, occupiedCells) ||
      !_mapEquals(oldDelegate.tileKinds, tileKinds) ||
      _propsDiffer(oldDelegate.props, props);
}

bool _propsDiffer(
  List<(CellCoord, int, int, String)> a,
  List<(CellCoord, int, int, String)> b,
) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
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

/// Schematic dot colour per nature model — the map canvas's stand-in
/// for the sprite (the game draws the real art).
Color natureDotColor(String catalogueId) => switch (catalogueId) {
  'pine-tree' || 'common-tree' || 'tree-stump' => const Color(0xFF2F6B3A),
  'flower-garden' || 'wild-grass' => const Color(0xFFB0568A),
  'rocks' => const Color(0xFF8D8D84),
  _ => const Color(0xFF6B5B45),
};

/// The nature brush's item picker: the catalogue's decorations
/// carrying a legalTerrain tag. The field is the palette — new
/// nature items are content, not code.
class _NatureItemPicker extends StatelessWidget {
  const _NatureItemPicker({
    required this.items,
    required this.selected,
    required this.onPick,
  });

  final List<({String id, String name, List<String> roles})> items;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'No brushable items — give a decoration a legalTerrain tag',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      );
    }
    final value = selected != null && items.any((item) => item.id == selected)
        ? selected
        : items.first.id;
    return DropdownButton<String>(
      value: value,
      borderRadius: BorderRadius.circular(8),
      items: [
        for (final item in items)
          DropdownMenuItem(
            value: item.id,
            child: Text(item.name, style: const TextStyle(fontSize: 13)),
          ),
      ],
      onChanged: (id) {
        if (id != null) onPick(id);
      },
    );
  }
}

/// The nature brush's footprint on the canvas: the projection of the
/// sampling disk — a grid circle of [radiusCells] maps to an
/// axis-aligned ellipse with semi-axes √2·R times the half-cell —
/// anchored at the hovered cell's centre, where clicks land. Green
/// while placing, red while the eraser is on. Null centre hides it.
class _NatureBrushPreview extends CustomPainter {
  const _NatureBrushPreview({
    required this.center,
    required this.radiusCells,
    this.erasing = false,
  });

  final Offset? center;
  final double radiusCells;
  final bool erasing;

  @override
  void paint(Canvas canvas, Size size) {
    final center = this.center;
    if (center == null) return;
    final radius = Radius.elliptical(
      _cellW / 2 * math.sqrt2 * radiusCells,
      _cellH / 2 * math.sqrt2 * radiusCells,
    );
    final rect = Rect.fromCenter(
      center: center,
      width: radius.x * 2,
      height: radius.y * 2,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = erasing ? const Color(0x2EB3261E) : const Color(0x2E00A95C),
    );
    canvas.drawOval(
      rect,
      Paint()
        ..color = erasing ? const Color(0xCCB3261E) : const Color(0xCC00A95C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _NatureBrushPreview oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.radiusCells != radiusCells ||
      oldDelegate.erasing != erasing;
}

/// The nature brush's sample: [count] distinct subtiles drawn
/// uniformly from the grid disk of [radiusCells] around
/// ([centerCol], [centerRow]) — the disk includes every subtile,
/// legal or not, exactly as specified — then filtered by [legal], so
/// N is an upper bound: clearings stay clear, owned parcels and
/// water silently drop their draws, and a click may place nothing.
/// Returns the (cell, subtileX, subtileY) anchors that landed.
List<(CellCoord, int, int)> sampleNatureBrush({
  required double centerCol,
  required double centerRow,
  required double radiusCells,
  required int count,
  required bool Function(CellCoord cell, int subtileX, int subtileY) legal,
  math.Random? random,
}) {
  final rng = random ?? math.Random();
  final candidates = <(CellCoord, int, int)>[];
  final minCol = (centerCol - radiusCells).floor() - 1;
  final maxCol = (centerCol + radiusCells).ceil() + 1;
  final minRow = (centerRow - radiusCells).floor() - 1;
  final maxRow = (centerRow + radiusCells).ceil() + 1;
  for (var column = minCol; column <= maxCol; column++) {
    for (var row = minRow; row <= maxRow; row++) {
      final cell = CellCoord(column, row);
      for (var subtileY = 0; subtileY < 8; subtileY++) {
        for (var subtileX = 0; subtileX < 8; subtileX++) {
          final col = column + (subtileX + 0.5) / 8;
          final gridRow = row + (subtileY + 0.5) / 8;
          final dCol = col - centerCol;
          final dRow = gridRow - centerRow;
          if (dCol * dCol + dRow * dRow <= radiusCells * radiusCells) {
            candidates.add((cell, subtileX, subtileY));
          }
        }
      }
    }
  }
  // Draw without replacement — every subtile in the disk weighs the
  // same, duplicates cannot waste a draw — then keep the legal ones.
  final drawn = <(CellCoord, int, int)>[];
  for (var i = 0; i < count && candidates.isNotEmpty; i++) {
    drawn.add(candidates.removeAt(rng.nextInt(candidates.length)));
  }
  return [
    for (final anchor in drawn)
      if (legal(anchor.$1, anchor.$2, anchor.$3)) anchor,
  ];
}
