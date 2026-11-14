import 'dart:async';

import 'package:flutter/material.dart';

import 'content/asset_content_source.dart';
import 'config/citysim_config.dart';
import 'content/content_bundle.dart';
import 'rendering/parcel_world_view.dart';
import 'storage/server_sheet_store.dart';
import 'world/coordinates.dart';
import 'world/terrain_provider.dart';
import 'world/world_content.dart';
import 'world/world_queries.dart';
import 'world/world_reducer.dart';
import 'world/world_rules.dart';
import 'world/world_save_store.dart';
import 'world/world_state.dart';

enum _WorldTool { inspect, parcel, road, building, decor, bridge }

class ParcelCityApp extends StatelessWidget {
  const ParcelCityApp({super.key, this.store, this.content});

  final ParcelWorldStore? store;

  /// Pre-loaded content bundle; loaded from bundled assets when null.
  /// Widget tests inject one loaded in `setUpAll` because per-test asset
  /// loading is unreliable after a prior test ran the app.
  final ContentBundle? content;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Parcel City Preview',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF4F3EA),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF276B58),
        surface: const Color(0xFFFCFBF6),
      ),
      textTheme: const TextTheme(
        titleMedium: TextStyle(
          color: Color(0xFF193A31),
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    home: ParcelCityPage(store: store, content: content),
  );
}

class ParcelCityPage extends StatefulWidget {
  const ParcelCityPage({super.key, this.store, this.content});

  final ParcelWorldStore? store;
  final ContentBundle? content;

  @override
  State<ParcelCityPage> createState() => _ParcelCityPageState();
}

class _ParcelCityPageState extends State<ParcelCityPage> {
  late TerrainProvider _terrain;
  ContentBundle? _content;
  ParcelWorldStore? _store;
  ParcelWorldSaveCoordinator? _saveCoordinator;

  ParcelWorldState? _world;
  Object? _loadError;
  String? _saveError;
  bool _loading = true;

  _WorldTool _tool = _WorldTool.inspect;
  String? _selectedCatalogueId;
  CellCoord? _selectedCell;

  /// Where in the selected cell the last tap landed (0..7 on the
  /// subtile lattice) — decoration placement anchors there.
  int _selectedSubtileX = propFrontSubtile;
  int _selectedSubtileY = propFrontSubtile;

  /// The selected prop's id — several props may share a tile, so
  /// prop selection is by id, not cell.
  String? _selectedPropId;
  ParcelCoord? _selectedParcel;
  CellCoord? _bridgeStartCell;
  CellCoord? _bridgeEndCell;
  List<CellCoord> _roadPlanCells = const [];
  CellCoord? _roadStartCell;
  Set<CellCoord> _highlightCells = const {};
  int _cameraResetToken = 0;

  /// Pre-placement door-side choice for the building preview, toggled by
  /// the floating swap button while roads touch both halves of the
  /// footprint. Cleared whenever the target cell, model, or tool changes.
  String? _facingOverride;

  ContentBundle get _requireContent => _content!;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  /// Content loads before anything else: the store needs it for
  /// reconciliation, and every rule and reducer call reads from it. Tests
  /// may inject a pre-loaded bundle to avoid per-test asset loading.
  Future<void> _bootstrap() async {
    try {
      final content =
          widget.content ?? await loadContentBundle(const AssetContentSource());
      _terrain = ContentTerrainProvider(content.terrain);
      // The store comes from the config's data source unless a test
      // injects one. The CSV source persists the four sheet documents in
      // local browser storage; the Google Spreadsheet is wired later.
      final store = widget.store ?? await _storeFromConfig(content);
      if (!mounted) return;
      setState(() {
        _content = content;
        _store = store;
        _saveCoordinator = ParcelWorldSaveCoordinator(store);
      });
      await _loadWorld();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<ParcelWorldStore> _storeFromConfig(ContentBundle content) async {
    final config = await CitysimConfig.load();
    if (config.dataSource == CitysimDataSource.sheets) {
      throw UnsupportedError(
        'Google Sheets storage is not wired yet; set citysim.dataSource '
        'to "csv" in assets/config.json.',
      );
    }
    if (config.serverUrl.isEmpty) {
      throw const FormatException(
        'assets/config.json citysim.serverUrl must be set for the csv '
        'data source.',
      );
    }
    return ServerSheetParcelWorldStore(
      content: content,
      terrainProvider: _terrain,
      api: HttpWorldDocumentsApi(config.serverUrl),
    );
  }

  Future<void> _loadWorld() async {
    final store = _store;
    if (store == null) return;
    try {
      final loaded = await store.load();
      if (loaded != null) {
        if (!mounted) return;
        setState(() {
          _world = loaded;
          _loading = false;
        });
        return;
      }
      final initial = _newWorld();
      await store.save(initial);
      if (!mounted) return;
      setState(() {
        _world = initial;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  ParcelWorldState _newWorld() => newParcelWorldState(
    content: _requireContent,
    seed: DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF,
    terrainProvider: _terrain,
  );

  void _commit(ParcelWorldState next, {bool replace = false}) {
    setState(() {
      _world = next;
      _loadError = null;
    });
    final coordinator = _saveCoordinator;
    if (coordinator == null) return;
    final write = replace ? coordinator.replace(next) : coordinator.save(next);
    unawaited(
      write
          .then<void>((_) {
            if (mounted) setState(() => _saveError = null);
          })
          .catchError((Object error) {
            if (mounted) setState(() => _saveError = error.toString());
          }),
    );
  }

  void _runAction(ParcelWorldState Function(ParcelWorldState) action) {
    final world = _world;
    if (world == null) return;
    try {
      _commit(action(world));
    } on WorldRuleViolation catch (error) {
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onCellTap(
    CellCoord cell,
    String? structureId,
    int subtileX,
    int subtileY,
  ) {
    final world = _world;
    if (world == null) return;
    _selectedSubtileX = subtileX;
    _selectedSubtileY = subtileY;
    // A prop hit selects that specific prop — several may share a
    // tile, so prop selection is by id.
    _selectedPropId =
        structureId != null && world.props.any((prop) => prop.id == structureId)
        ? structureId
        : null;
    if (_tool == _WorldTool.road) {
      // A tap on any creeping stretch's tiles selects that whole
      // project. Road creep consumes no builder, so any number of
      // stretches may creep at once and planning is always open.
      final roadProject = world.constructions
          .where((job) => job.kind == WorldConstructionKind.road)
          .where(
            (job) =>
                job.roadCells.contains(cell) ||
                world.roads.any(
                  (road) => road.projectId == job.id && road.cell == cell,
                ),
          )
          .firstOrNull;
      if (roadProject != null) {
        setState(() {
          _selectedCell = cell;
          _highlightCells = {
            ...roadProject.roadCells,
            ...world.roads
                .where((road) => road.projectId == roadProject.id)
                .map((road) => road.cell),
          };
        });
        return;
      }
      if (_roadStartCell == null) {
        // First click: the start tile.
        setState(() {
          _roadStartCell = cell;
          _roadPlanCells = const [];
          _selectedCell = cell;
          _highlightCells = const {};
          _selectedParcel = null;
          _selectedCatalogueId = null;
          _bridgeStartCell = null;
        });
        return;
      }
      // Second and further clicks: the end tile, projected onto the
      // closer axis. Invalid tiles are marked in the preview; the
      // assign button refuses until the line is valid.
      setState(() {
        _roadPlanCells = straightLineBetween(_roadStartCell!, cell);
        _selectedCell = _roadPlanCells.last;
        _selectedParcel = null;
        _selectedCatalogueId = null;
        _bridgeStartCell = null;
      });
      return;
    }
    setState(() {
      if (_tool == _WorldTool.parcel) {
        // Parcel mode highlights buyable parcels only: owned
        // parcels and fog select nothing — there is nothing to
        // choose there, and the panel stays clear.
        final parcel = parcelForCell(cell);
        final kind = _terrain
            .sample(parcel.origin(world.parcelSize), world.seed)
            .kind;
        final buyable =
            kind != TerrainKind.fog &&
            !WorldQueries(world, _terrain).ownsParcel(parcel);
        _selectedParcel = buyable ? parcel : null;
        _selectedCell = null;
        _selectedCatalogueId = null;
        _bridgeStartCell = null;
        _highlightCells = const {};
        return;
      }
      final highlight = _highlightFor(world, cell, structureId);
      if (_tool == _WorldTool.inspect &&
          structureId == null &&
          highlight.isEmpty &&
          !world.bridges.any(
            (bridge) =>
                bridge.waterCells.contains(cell) ||
                bridge.nearBank == cell ||
                bridge.farBank == cell,
          )) {
        // Inspect selects objects only: structures, props, road
        // sections, project spans, bridges. Plain terrain
        // highlights nothing — the tap just clears.
        _selectedCell = null;
        _selectedParcel = null;
        _selectedCatalogueId = null;
        _bridgeStartCell = null;
        _highlightCells = const {};
        return;
      }
      _selectedCell = cell;
      if (_tool == _WorldTool.bridge) {
        _selectedParcel = null;
        _selectedCatalogueId = null;
        if (_bridgeStartCell == null) {
          _bridgeStartCell = cell;
          _bridgeEndCell = null;
        } else {
          _bridgeEndCell = straightLineBetween(_bridgeStartCell!, cell).last;
        }
      } else if (_tool == _WorldTool.building || _tool == _WorldTool.decor) {
        _selectedParcel = null;
        _bridgeStartCell = null;
        _facingOverride = null;
      } else {
        _selectedParcel = null;
        _selectedCatalogueId = null;
        _bridgeStartCell = null;
      }
      _highlightCells = highlight;
      if (structureId != null && _tool == _WorldTool.inspect) {
        _selectedCatalogueId = null;
      }
    });
  }

  /// The cells a tap highlights in the inspect tool: an active
  /// project's whole span (planned and funded tiles), or a completed
  /// road's section between junctions, turns, or dead ends.
  Set<CellCoord> _highlightFor(
    ParcelWorldState world,
    CellCoord cell,
    String? structureId,
  ) {
    for (final job in world.constructions) {
      final cells = switch (job.kind) {
        WorldConstructionKind.road => job.roadCells,
        WorldConstructionKind.bridge => [
          ...job.waterCells,
          job.nearBank!,
          job.farBank!,
        ],
        WorldConstructionKind.structure => job.footprint,
      };
      if (cells.contains(cell)) return cells.toSet();
      final funded = world.roads
          .where((road) => road.projectId == job.id)
          .map((road) => road.cell);
      if (funded.contains(cell)) return {cell, ...funded};
    }
    if (structureId == null) {
      final section = WorldQueries(world, _terrain).roadSectionAt(cell);
      if (section.isNotEmpty) return section.toSet();
    }
    return const {};
  }

  void _selectTool(_WorldTool tool) {
    setState(() {
      _tool = tool;
      _selectedCell = null;
      _selectedPropId = null;
      _selectedParcel = null;
      _bridgeStartCell = null;
      _bridgeEndCell = null;
      _selectedCatalogueId = null;
      _facingOverride = null;
      _highlightCells = const {};
      if (tool != _WorldTool.road) {
        _roadPlanCells = const [];
        _roadStartCell = null;
      }
    });
  }

  /// The door-swap target under the current selection: an unfinished
  /// building plan when the selected cell sits on one, otherwise the
  /// pre-placement preview when a building model and cell are selected.
  /// Null while the door side is fixed — the road borders only one
  /// screen half of the footprint, or the sprite has no door facings.
  ({WorldConstruction? job, String facing, Set<String> roadSides})?
  _doorSwapTarget(ParcelWorldState world) {
    final cell = _selectedCell;
    if (cell == null) return null;
    final content = _requireContent;

    for (final job in world.constructions) {
      if (job.kind != WorldConstructionKind.structure ||
          !job.footprint.contains(cell)) {
        continue;
      }
      final definition = content.structure(job.catalogueId ?? '');
      final role = job.assetRole ?? definition?.assetRoles.first;
      final sprite = role == null ? null : content.sprite(role);
      if (definition == null ||
          definition.kind != StructureKind.building ||
          sprite == null ||
          !sprite.hasFacings ||
          job.facing == null) {
        return null;
      }
      final sides = WorldQueries(
        world,
        _terrain,
      ).adjacentRoadSides(job.footprint);
      return sides.map(facingArtKey).toSet().length >= 2
          ? (job: job, facing: job.facing!, roadSides: sides)
          : null;
    }

    final catalogueId = _selectedCatalogueId;
    if (_tool != _WorldTool.building || catalogueId == null) return null;
    final definition = content.structure(catalogueId);
    if (definition == null || definition.kind != StructureKind.building) {
      return null;
    }
    final role =
        definition.assetRoles[(world.seed + world.nextEntityNumber) %
            definition.assetRoles.length];
    final sprite = content.sprite(role);
    if (sprite == null || !sprite.hasFacings) return null;
    // Non-square lots probe the tapped cell — their footprint is not
    // known until the door side turns it.
    final probe = definition.footprintColumns != definition.footprintRows
        ? [cell]
        : structureFootprint(definition, cell);
    final sides = WorldQueries(world, _terrain).adjacentRoadSides(probe);
    if (sides.map(facingArtKey).toSet().length < 2) return null;
    return (
      job: null,
      facing: _facingOverride ?? facingForRoadSides(sides),
      roadSides: sides,
    );
  }

  /// Flips the door side: an unfinished plan updates through the reducer
  /// (validated, saved, and recorded as an event); the pre-placement
  /// preview just flips the local override that placement will honour.
  void _swapDoorSide(
    ({WorldConstruction? job, String facing, Set<String> roadSides}) target,
  ) {
    final job = target.job;
    if (job != null) {
      _runAction(
        (state) => swapStructureFacing(
          state,
          _requireContent,
          _terrain,
          projectId: job.id,
        ),
      );
      return;
    }
    setState(
      () => _facingOverride = flipFacing(target.facing, target.roadSides),
    );
  }

  Future<void> _resetWorld() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start a new parcel world?'),
        content: const Text(
          'This replaces the current settlement with a fresh starter parcel.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep this world'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start new world'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final fresh = _newWorld();
    try {
      await _saveCoordinator?.replace(fresh);
      if (!mounted) return;
      setState(() {
        _world = fresh;
        _loading = false;
        _saveError = null;
        _roadPlanCells = const [];
        _selectedCell = null;
        _selectedPropId = null;
        _selectedParcel = null;
        _selectedCatalogueId = null;
        _bridgeStartCell = null;
        _facingOverride = null;
        _tool = _WorldTool.inspect;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _confirmParcelPurchase(ParcelCoord coord) async {
    final world = _world;
    if (world == null) return;
    try {
      final quote = quoteParcelPurchase(
        world,
        _requireContent,
        _terrain,
        coord,
      );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Buy parcel ${coord.key}?'),
          content: Text(
            '${quote.price} coins · ${quote.landCellCount} land cells and '
            '${quote.cells.length - quote.landCellCount} water cells.\n\n'
            'Buildings and roads are not included.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Buy parcel'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _runAction(
        (state) =>
            purchaseAdjacentParcel(state, _requireContent, _terrain, coord),
      );
      setState(() => _selectedParcel = null);
    } on WorldRuleViolation catch (error) {
      _showMessage(error.message);
    }
  }

  Future<void> _confirmStructure() async {
    final world = _world;
    final catalogueId = _selectedCatalogueId;
    final cell = _selectedCell;
    if (world == null || catalogueId == null || cell == null) return;
    try {
      final quote = quoteStructurePlacement(
        world,
        _requireContent,
        _terrain,
        catalogueId: catalogueId,
        origin: cell,
        preferredFacing: _facingOverride,
        subtileX: _selectedSubtileX,
        subtileY: _selectedSubtileY,
      );
      final definition = _requireContent.structure(catalogueId)!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            definition.kind == StructureKind.decoration
                ? 'Place ${definition.name.toLowerCase()}?'
                : 'Plan ${definition.name.toLowerCase()}?',
          ),
          content: Text(
            definition.kind == StructureKind.decoration
                ? quote.price > 0
                      ? '${quote.price} coins · placed immediately.'
                      : 'Free · placed immediately.'
                : 'Free to plan. Your builder raises it over '
                      '${definition.constructionStages} stages — one per '
                      'daily check-in. Once complete it pays '
                      '+${definition.taxCoins} tax and costs '
                      '−${definition.upkeepCoins} upkeep at each report.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                definition.kind == StructureKind.decoration
                    ? 'Place decoration'
                    : 'Plan construction',
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _runAction(
        (state) => startStructureConstruction(
          state,
          _requireContent,
          _terrain,
          catalogueId: catalogueId,
          origin: cell,
          preferredFacing: _facingOverride,
          subtileX: _selectedSubtileX,
          subtileY: _selectedSubtileY,
        ),
      );
      setState(() {
        // Keep the site selected after planning a building so the door
        // arrow and the swap button stay visible while it is unfinished;
        // decorations place instantly and clear the selection.
        _selectedCell = definition.kind == StructureKind.building ? cell : null;
        _selectedPropId = null;
        _selectedCatalogueId = null;
        _facingOverride = null;
      });
    } on WorldRuleViolation catch (error) {
      _showMessage(error.message);
    }
  }

  /// Picks the selected prop back up — free, no refund. The game's
  /// one removal action, scoped to decorations; buildings stay
  /// permanent.
  Future<void> _confirmPickUp() async {
    final world = _world;
    final propId = _selectedPropId;
    if (world == null || propId == null) return;
    final prop = world.props.where((prop) => prop.id == propId).firstOrNull;
    if (prop == null) return;
    final definition = _requireContent.structure(prop.catalogueId)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pick up ${definition.name.toLowerCase()}?'),
        content: const Text(
          'Free — no coins are refunded. The tile and subtile become '
          'placeable again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pick up'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _runAction((state) => pickUpProp(state, _requireContent, propId: propId));
    setState(() {
      _selectedCell = null;
      _selectedPropId = null;
    });
  }

  void _startRoadProject() {
    final world = _world;
    if (world == null || _roadPlanCells.isEmpty) return;
    try {
      quoteRoadStretch(world, _requireContent, _terrain, cells: _roadPlanCells);
    } on WorldRuleViolation catch (error) {
      _showMessage(error.message);
      return;
    }
    _runAction(
      (state) => planRoadStretch(
        state,
        _requireContent,
        _terrain,
        cells: _roadPlanCells,
      ),
    );
    setState(() {
      _roadPlanCells = const [];
      _roadStartCell = null;
      _selectedCell = null;
      _highlightCells = const {};
    });
  }

  void _startBridgeProject() {
    final world = _world;
    final nearBank = _bridgeStartCell;
    final farBank = _bridgeEndCell;
    if (world == null || nearBank == null || farBank == null) return;
    try {
      quoteBridge(
        world,
        _requireContent,
        _terrain,
        nearBank: nearBank,
        farBank: farBank,
      );
    } on WorldRuleViolation catch (error) {
      _showMessage(error.message);
      return;
    }
    _runAction(
      (state) => startBridgeConstruction(
        state,
        _requireContent,
        _terrain,
        nearBank: nearBank,
        farBank: farBank,
      ),
    );
    setState(() {
      _bridgeStartCell = null;
      _bridgeEndCell = null;
      _selectedCell = null;
      _highlightCells = const {};
    });
  }

  void _advanceDays(int days) =>
      _runAction((state) => advanceWorldDays(state, days));

  /// Runs the check-in and surfaces its town report — the day's
  /// event, itemized.
  void _checkIn() {
    final world = _world;
    if (world == null) return;
    final next = checkInWorldForToday(world, _requireContent);
    if (identical(next, world)) return;
    _commit(next);
    _showTownReport(next);
  }

  Future<void> _showTownReport(ParcelWorldState world) async {
    WorldEvent? lastReport;
    for (final event in world.events) {
      if (event.kind == 'check-in') lastReport = event;
    }
    // A final binding, so the null promotion survives the dialog
    // closure below.
    final report = lastReport;
    if (report == null) return;
    final payload = report.payload;
    int value(String key) => (payload[key] as num?)?.toInt() ?? 0;
    final taxes = value('taxes');
    final paid = value('upkeepPaid');
    final shortfall = value('upkeepShortfall');
    final net = value('net');
    final advanced = value('stagesAdvanced');
    final completions =
        (payload['completions'] as List?)?.cast<String>() ?? const [];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Town report · ${report.dateKey}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Taxes collected   +$taxes'),
            Text('Upkeep paid        −$paid'),
            if (shortfall > 0)
              Text(
                'Upkeep unpaid     $shortfall — the treasury is empty',
                style: const TextStyle(color: Color(0xFF9A5B2B)),
              ),
            Text(
              'Net                 ${net >= 0 ? '+' : ''}$net',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (advanced > 0) Text('$advanced construction stage(s) advanced'),
            for (final name in completions)
              Text(
                '$name — complete',
                style: const TextStyle(color: Color(0xFF1E6552)),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError case final error?) {
      return _WorldErrorScreen(
        error: error,
        onRetry: () => setState(() {
          _loadError = null;
          _loading = true;
          unawaited(_loadWorld());
        }),
        onReset: _resetWorld,
      );
    }
    final world = _world;
    if (world == null) {
      return const Scaffold(
        body: Center(child: Text('No parcel world loaded.')),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              _WorldHeader(
                state: world,
                saveError: _saveError,
                nextReportNet: townLedger(world, _requireContent).net,
                canCheckIn: canCheckInWorldToday(world),
                onCheckIn: _checkIn,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 980) {
                      return Row(
                        children: [
                          Expanded(child: _mapPanel(world)),
                          const SizedBox(width: 12),
                          SizedBox(width: 360, child: _controlPanel(world)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(flex: 5, child: _mapPanel(world)),
                        const SizedBox(height: 10),
                        Expanded(flex: 4, child: _controlPanel(world)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapPanel(ParcelWorldState world) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFB5DCCF),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFD6E1D6)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned.fill(
          child: ParcelWorldView(
            state: world,
            terrainProvider: _terrain,
            selectedCell: _selectedCell,
            selectedPropId: _selectedPropId,
            selectedSubtileX: _selectedSubtileX,
            selectedSubtileY: _selectedSubtileY,
            selectedParcel: _tool == _WorldTool.parcel ? _selectedParcel : null,
            content: _requireContent,
            selectedCatalogueId: _selectedCatalogueId,
            bridgeStartCell: _bridgeStartCell,
            bridgeEndCell: _bridgeEndCell,
            roadPlanCells: _roadPlanCells,
            roadStartCell: _roadStartCell,
            highlightCells: _highlightCells,
            facingOverride: _facingOverride,
            structurePicking: _tool == _WorldTool.inspect,
            dimStructures:
                _tool == _WorldTool.road || _tool == _WorldTool.bridge,
            parcelMode: _tool == _WorldTool.parcel,
            showTileGrid: _tool != _WorldTool.inspect,
            cameraResetToken: _cameraResetToken,
            onCellTap: _onCellTap,
          ),
        ),
        if (_doorSwapTarget(world) case final target?)
          Positioned(
            right: 12,
            bottom: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1E6552),
                elevation: 3,
              ),
              onPressed: () => _swapDoorSide(target),
              icon: const Icon(Icons.swap_horiz_rounded),
              label: Text('Door faces ${target.facing} · swap'),
            ),
          ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xEFFFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${world.parcels.length} parcel${world.parcels.length == 1 ? '' : 's'}'
              ' · ${world.structures.length} structures',
              style: const TextStyle(
                color: Color(0xFF244F41),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: IconButton.filledTonal(
            tooltip: 'Reset camera',
            onPressed: () => setState(() => _cameraResetToken++),
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xEFFFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _mapHint(world),
              style: const TextStyle(color: Color(0xFF416655), fontSize: 11),
            ),
          ),
        ),
      ],
    ),
  );

  String _mapHint(ParcelWorldState world) => switch (_tool) {
    _WorldTool.inspect => 'Drag to pan · pinch to zoom · inspect any tile',
    _WorldTool.parcel => 'Choose a highlighted neighboring parcel',
    _WorldTool.road =>
      world.constructions.any((job) => job.kind == WorldConstructionKind.road)
          ? 'Select one planned road tile beside a finished road to fund it'
          : 'Tap connected empty tiles to plan a road stretch; planning is free',
    _WorldTool.building ||
    _WorldTool.decor => 'Choose an empty tile for the selected footprint',
    _WorldTool.bridge =>
      _bridgeStartCell == null
          ? 'Choose a connected road tile on the near river bank'
          : 'Choose a dry landing cell on the far bank',
  };

  Widget _controlPanel(ParcelWorldState world) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFCFBF6),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE5E3D9)),
    ),
    clipBehavior: Clip.antiAlias,
    child: ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _ToolPicker(selected: _tool, onSelected: _selectTool),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            '${world.builderCapacity - world.constructions.length} of '
            '${world.builderCapacity} builders available',
            style: const TextStyle(fontSize: 12, color: Color(0xFF617267)),
          ),
        ),
        const SizedBox(height: 10),
        if (_tool == _WorldTool.road) _roadControls(world),
        if (_tool == _WorldTool.parcel && _selectedParcel != null)
          _parcelAction(world, _selectedParcel!),
        if ((_tool == _WorldTool.building || _tool == _WorldTool.decor) &&
            _selectedCatalogueId != null)
          _structureAction(world),
        if (_tool == _WorldTool.bridge) _bridgeAction(world),
        if (_tool == _WorldTool.inspect || _selectedCell == null)
          _cellInspector(world),
        if (_tool == _WorldTool.building || _tool == _WorldTool.decor)
          _catalogue(world),
        for (final job in world.constructions)
          if (job.kind != WorldConstructionKind.road)
            _projectProgressCard(world, job),
        const SizedBox(height: 12),
        _ClockControls(
          state: world,
          onAdvance: _advanceDays,
          onRewind: () => _runAction(
            (state) => setWorldCalendarDate(
              state,
              state.simulatedDate.subtract(const Duration(days: 1)),
            ),
          ),
          onDebugGrant: () =>
              _runAction((state) => grantWorldDebugCoins(state, 10)),
          onCheckIn: _checkIn,
          canCheckIn: canCheckInWorldToday(world),
        ),
        if (world.constructions.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ConstructionList(state: world, content: _requireContent),
        ],
        const SizedBox(height: 12),
        _RecentEvents(events: world.events),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _resetWorld,
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('Reset parcel-world save'),
          ),
        ),
      ],
    ),
  );

  Widget _roadControls(ParcelWorldState world) {
    // Creep cards for every in-flight stretch — roads consume no
    // builder, so any number creep at once and planning stays open.
    final creepCards = [
      for (final job in world.constructions)
        if (job.kind == WorldConstructionKind.road)
          _roadProgressCard(world, job),
    ];

    String? failure;
    RoadProjectQuote? quote;
    if (_roadPlanCells.isNotEmpty) {
      try {
        quote = quoteRoadStretch(
          world,
          _requireContent,
          _terrain,
          cells: _roadPlanCells,
        );
      } on WorldRuleViolation catch (error) {
        failure = error.message;
      }
    }
    return Column(
      children: [
        ...creepCards,
        _PanelCard(
          title: 'Roads',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _roadStartCell == null
                    ? 'Click a start tile, then an end tile — the road projects '
                          'onto the closer axis. Roads go anywhere on owned land.'
                    : _roadPlanCells.isEmpty
                    ? 'Start at ${_roadStartCell!.key}. Now click an end tile.'
                    : failure ??
                          '${_roadPlanCells.length} road tiles · '
                              '${quote!.price} coins, paid upfront. The '
                              'stretch then builds one tile per check-in.',
              ),
              if (quote != null && world.coins < quote.price)
                Text(
                  'Save ${quote.price - world.coins} more coin(s) for this '
                  'road plan.',
                ),
              if (_roadStartCell != null)
                Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _roadPlanCells = const [];
                        _roadStartCell = null;
                        _selectedCell = null;
                      }),
                      child: const Text('Clear plan'),
                    ),
                    if (quote != null)
                      FilledButton(
                        onPressed: world.coins >= quote.price
                            ? _startRoadProject
                            : null,
                        child: Text('Buy road plan · ${quote.price} coins'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roadProgressCard(ParcelWorldState world, WorldConstruction project) {
    final delivered = world.roads
        .where((road) => road.projectId == project.id)
        .length;
    return _PanelCard(
      title: 'Road construction',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$delivered/${project.roadCells.length} tiles laid · '
            'one more per check-in',
          ),
          LinearProgressIndicator(
            value: project.roadCells.isEmpty
                ? 0
                : delivered / project.roadCells.length,
          ),
        ],
      ),
    );
  }

  Widget _projectProgressCard(
    ParcelWorldState world,
    WorldConstruction project,
  ) {
    final definition = _requireContent.structure(project.catalogueId ?? '');
    final isBridge = project.kind == WorldConstructionKind.bridge;
    final title = isBridge ? 'Bridge' : definition?.name ?? 'Building';
    final String status;
    final double progress;
    if (isBridge) {
      final total = project.bridgeDeliveryCells.length;
      status = '${project.stagesDone}/$total cells raised · one per check-in';
      progress = total == 0 ? 0 : project.stagesDone / total;
    } else {
      final stages = definition?.constructionStages ?? 1;
      status =
          'Stage ${project.stagesDone + 1} of $stages · '
          'one stage per check-in';
      progress = stages == 0 ? 0 : project.stagesDone / stages;
    }
    return _PanelCard(
      title: isBridge ? title : '$title · Builder ${project.builderSlot! + 1}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status),
          LinearProgressIndicator(value: progress),
          if (!isBridge)
            const Text(
              'This builder stays assigned until the work is complete.',
              style: TextStyle(fontSize: 11, color: Color(0xFF617267)),
            ),
        ],
      ),
    );
  }

  Widget _parcelAction(ParcelWorldState world, ParcelCoord parcel) {
    ParcelPurchaseQuote? quote;
    String? failure;
    try {
      quote = quoteParcelPurchase(world, _requireContent, _terrain, parcel);
    } on WorldRuleViolation catch (error) {
      failure = error.message;
    }
    return _PanelCard(
      title: 'Neighboring parcel ${parcel.key}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (quote != null) ...[
            Text(
              '${quote.landCellCount} land cells · ${quote.cells.length - quote.landCellCount} water cells',
            ),
            Text(
              '${quote.price} coins · parcels, road plans, and bridges are '
              "the treasury's purchases.",
            ),
            if (world.coins < quote.price)
              Text('Save ${quote.price - world.coins} more coin(s).'),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: world.coins >= quote.price
                  ? () => _confirmParcelPurchase(parcel)
                  : null,
              child: const Text('Review parcel purchase'),
            ),
          ] else
            Text(failure ?? 'This parcel is not available.'),
        ],
      ),
    );
  }

  Widget _structureAction(ParcelWorldState world) {
    final cell = _selectedCell;
    final catalogueId = _selectedCatalogueId!;
    final definition = _requireContent.structure(catalogueId)!;
    StructurePlacementQuote? quote;
    String? failure;
    if (cell != null) {
      try {
        quote = quoteStructurePlacement(
          world,
          _requireContent,
          _terrain,
          catalogueId: catalogueId,
          origin: cell,
          preferredFacing: _facingOverride,
          subtileX: _selectedSubtileX,
          subtileY: _selectedSubtileY,
        );
      } on WorldRuleViolation catch (error) {
        failure = error.message;
      }
    }
    return _PanelCard(
      title: definition.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(definition.description),
          const SizedBox(height: 4),
          Text(
            '${definition.footprintColumns}×${definition.footprintRows} footprint · '
            '${definition.kind == StructureKind.decoration ? 'free · placed instantly' : 'free to plan · ${definition.constructionStages} stages · ${definition.netCoinsPerCheckIn >= 0 ? '+' : ''}${definition.netCoinsPerCheckIn} coins per report'}',
          ),
          const SizedBox(height: 6),
          Text(
            cell == null
                ? 'Select a placement tile.'
                : failure ?? 'Selected origin ${cell.key}.',
          ),
          if (quote != null &&
              definition.kind == StructureKind.decoration &&
              world.coins < quote.price)
            Text('Save ${quote.price - world.coins} more coin(s).'),
          if (quote != null)
            FilledButton(
              onPressed:
                  definition.kind == StructureKind.building ||
                      world.coins >= quote.price
                  ? _confirmStructure
                  : null,
              child: Text(
                definition.kind == StructureKind.decoration
                    ? 'Place instantly'
                    : 'Plan construction',
              ),
            ),
        ],
      ),
    );
  }

  Widget _bridgeAction(ParcelWorldState world) {
    final near = _bridgeStartCell;
    final far = _bridgeEndCell;
    BridgeQuote? quote;
    String? failure;
    if (near != null && far != null && near != far) {
      try {
        quote = quoteBridge(
          world,
          _requireContent,
          _terrain,
          nearBank: near,
          farBank: far,
        );
      } on WorldRuleViolation catch (error) {
        failure = error.message;
      }
    }
    return _PanelCard(
      title: 'Bridge',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            near == null
                ? 'Click a bank tile on owned dry land, then the far bank.'
                : far == null || far == near
                ? 'Start at ${near.key}. Now click the far bank — the span '
                      'projects onto the closer axis.'
                : failure ??
                      '${quote!.spanCells.length} span '
                          '${quote.spanCells.length == 1 ? 'tile' : 'tiles'} · '
                          '${quote.bridgeCost} coins, paid upfront. The deck '
                          'builds one tile per check-in. Spans may cross '
                          'water and land; everything under the bridge must '
                          'be owned.',
          ),
          if (near != null)
            Wrap(
              spacing: 6,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() {
                    _bridgeStartCell = null;
                    _bridgeEndCell = null;
                    _selectedCell = null;
                  }),
                  child: const Text('Clear plan'),
                ),
                if (quote != null)
                  FilledButton(
                    onPressed: world.coins >= quote.bridgeCost
                        ? _startBridgeProject
                        : null,
                    child: Text('Buy bridge plan · ${quote.bridgeCost} coins'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _catalogue(ParcelWorldState world) {
    final definitions = _requireContent.purchaseableModels.where(
      (definition) =>
          definition.kind ==
          (_tool == _WorldTool.decor
              ? StructureKind.decoration
              : StructureKind.building),
    );
    return _PanelCard(
      title: _tool == _WorldTool.decor ? 'Decor catalogue' : 'Building models',
      child: Column(
        children: [
          for (final definition in definitions)
            Builder(
              builder: (context) {
                final unlocked = world.unlockedCatalogueIds.contains(
                  definition.id,
                );
                return Material(
                  color: Colors.transparent,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    selected: _selectedCatalogueId == definition.id,
                    leading: Icon(
                      definition.kind == StructureKind.decoration
                          ? Icons.local_florist_rounded
                          : Icons.home_work_rounded,
                    ),
                    title: Text(definition.name),
                    subtitle: Text(
                      unlocked
                          ? '${definition.costLabel} · '
                                '${definition.kind == StructureKind.decoration ? 'instant placement' : 'coin-funded project'}'
                          : 'Unlocks at ${definition.unlockAtPopulation} population',
                    ),
                    trailing: unlocked
                        ? (_selectedCatalogueId == definition.id
                              ? const Icon(Icons.check_circle_rounded)
                              : const Icon(Icons.chevron_right_rounded))
                        : const Icon(Icons.lock_outline_rounded),
                    onTap: unlocked
                        ? () => setState(() {
                            _selectedCatalogueId = definition.id;
                            _selectedCell = null;
                            _selectedPropId = null;
                            _selectedParcel = null;
                            _bridgeStartCell = null;
                          })
                        : null,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _cellInspector(ParcelWorldState world) {
    final cell = _selectedCell;
    if (cell == null) {
      return const _PanelCard(
        title: 'World tools',
        child: Text('Choose parcels, connect roads, then place buildings.'),
      );
    }
    // A selected prop shows its own card: several props may share the
    // tile, and the pick-up action targets the id, not the cell.
    final selectedProp = _selectedPropId == null
        ? null
        : world.props.where((prop) => prop.id == _selectedPropId).firstOrNull;
    if (selectedProp != null) {
      final definition = _requireContent.structure(selectedProp.catalogueId)!;
      return _PanelCard(
        title: definition.name,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(definition.description),
            const SizedBox(height: 4),
            Text(
              'Decoration · subtile ${selectedProp.subtileX},'
              '${selectedProp.subtileY} of tile ${selectedProp.cell.key}',
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: _confirmPickUp,
              child: const Text('Pick up · free'),
            ),
          ],
        ),
      );
    }
    final queries = WorldQueries(world, _terrain);
    final terrain = queries.terrainAt(cell);
    final parcel = parcelForCell(cell, parcelSize: world.parcelSize);
    final road = queries.roadsByCell[cell];
    final structure = queries.structuresByCell[cell];
    final job = world.constructions
        .where(
          (entry) =>
              entry.footprint.contains(cell) ||
              entry.roadCells.contains(cell) ||
              entry.waterCells.contains(cell) ||
              entry.nearBank == cell ||
              entry.farBank == cell,
        )
        .firstOrNull;
    return _PanelCard(
      title: 'Tile ${cell.key}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parcel ${parcel.key} · ${terrain.kind.name}'),
          Text(queries.ownsCell(cell) ? 'Owned land' : 'Unowned frontier'),
          if (road != null) Text('${road.style.name} road'),
          if (structure != null)
            Text(
              _requireContent.structure(structure.catalogueId)?.name ??
                  'Structure',
            ),
          if (job != null)
            Text(switch (job.kind) {
              WorldConstructionKind.structure =>
                'Under construction · stage ${job.stagesDone + 1} of '
                    '${_requireContent.structure(job.catalogueId ?? '')?.constructionStages ?? 1}',
              WorldConstructionKind.road =>
                'Road plan · ${world.roads.where((road) => road.projectId == job.id).length}/'
                    '${job.roadCells.length} tiles laid',
              WorldConstructionKind.bridge =>
                'Bridge plan · ${job.stagesDone}/'
                    '${job.bridgeDeliveryCells.length} cells raised',
            }),
        ],
      ),
    );
  }
}

class _WorldHeader extends StatelessWidget {
  const _WorldHeader({
    required this.state,
    required this.saveError,
    required this.nextReportNet,
    required this.canCheckIn,
    required this.onCheckIn,
  });

  final ParcelWorldState state;
  final String? saveError;

  /// Projected net of the next check-in's report: taxes minus
  /// upkeep, before the zero floor.
  final int nextReportNet;
  final bool canCheckIn;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final checkedIn =
        state.lastCheckInDate != null &&
        worldDateKey(state.lastCheckInDate!) == state.dateKey;
    final brand = Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF1D6653),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.map_rounded, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PARCEL WORLD · SYNTHETIC PREVIEW',
                style: TextStyle(fontSize: 10, letterSpacing: 1.1),
              ),
              Text(
                'Day ${state.constructionDay} · ${state.dateKey}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message:
              'The town treasury. Each check-in collects taxes and '
              'pays upkeep; purchases draw from it.',
          child: Chip(
            avatar: const Icon(Icons.toll_rounded, color: Color(0xFFAC7C20)),
            label: Text('${state.coins} coins'),
            backgroundColor: const Color(0xFFFFF8DA),
          ),
        ),
        Chip(
          avatar: const Icon(Icons.groups_rounded, color: Color(0xFF35695A)),
          label: Text('${state.population} population'),
          backgroundColor: const Color(0xFFE3F2EA),
        ),
        // The button's number is the next report's projected net —
        // taxes minus upkeep, before the zero floor.
        FilledButton.icon(
          onPressed: canCheckIn ? onCheckIn : null,
          icon: Icon(checkedIn ? Icons.check_rounded : Icons.add_rounded),
          label: Text(
            checkedIn
                ? 'Checked in'
                : canCheckIn
                ? 'Check in · ${nextReportNet >= 0 ? '+' : ''}$nextReportNet'
                : 'Past day',
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (constraints.maxWidth < 600) ...[
            brand,
            Align(alignment: Alignment.centerRight, child: actions),
          ] else
            Row(
              children: [
                Expanded(child: brand),
                actions,
              ],
            ),
          if (saveError != null)
            Text(
              'Save warning: $saveError',
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }
}

class _ToolPicker extends StatelessWidget {
  const _ToolPicker({required this.selected, required this.onSelected});

  final _WorldTool selected;
  final ValueChanged<_WorldTool> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 5,
    runSpacing: 5,
    children: [
      for (final tool in _WorldTool.values)
        ChoiceChip(
          visualDensity: VisualDensity.compact,
          label: Text(switch (tool) {
            _WorldTool.inspect => 'Inspect',
            _WorldTool.parcel => 'Parcels',
            _WorldTool.road => 'Roads',
            _WorldTool.building => 'Buildings',
            _WorldTool.decor => 'Decor',
            _WorldTool.bridge => 'Bridge',
          }),
          selected: selected == tool,
          onSelected: (_) => onSelected(tool),
        ),
    ],
  );
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F3EC),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
        child,
      ],
    ),
  );
}

class _ClockControls extends StatelessWidget {
  const _ClockControls({
    required this.state,
    required this.onAdvance,
    required this.onRewind,
    required this.onDebugGrant,
    required this.onCheckIn,
    required this.canCheckIn,
  });

  final ParcelWorldState state;
  final ValueChanged<int> onAdvance;
  final VoidCallback onRewind;
  final VoidCallback onDebugGrant;
  final VoidCallback onCheckIn;
  final bool canCheckIn;

  @override
  Widget build(BuildContext context) => _PanelCard(
    title: 'Paused simulation clock',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${state.totalCoinsEarned} earned · ${state.totalCoinsSpent} spent · ${state.checkInCount} check-ins',
        ),
        Wrap(
          spacing: 5,
          children: [
            OutlinedButton(
              onPressed: onRewind,
              child: const Text('−1 calendar day'),
            ),
            OutlinedButton(
              onPressed: () => onAdvance(1),
              child: const Text('+1 day'),
            ),
            OutlinedButton(
              onPressed: () => onAdvance(7),
              child: const Text('+7 days'),
            ),
            OutlinedButton(
              onPressed: () => onAdvance(30),
              child: const Text('+30 days'),
            ),
          ],
        ),
        TextButton.icon(
          onPressed: canCheckIn ? onCheckIn : null,
          icon: const Icon(Icons.task_alt_rounded),
          label: Text(
            canCheckIn
                ? 'Check in current day'
                : state.lastCheckInDate != null &&
                      worldDateKey(state.lastCheckInDate!) == state.dateKey
                ? 'Today already credited'
                : 'Past day cannot be credited',
          ),
        ),
        OutlinedButton(
          onPressed: onDebugGrant,
          child: const Text('Grant +10 test coins'),
        ),
      ],
    ),
  );
}

class _ConstructionList extends StatelessWidget {
  const _ConstructionList({required this.state, required this.content});

  final ParcelWorldState state;
  final ContentBundle content;

  @override
  Widget build(BuildContext context) => _PanelCard(
    title: 'Under construction',
    child: Column(
      children: [
        for (final job in state.constructions)
          Material(
            color: Colors.transparent,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(switch (job.kind) {
                WorldConstructionKind.structure =>
                  content.structure(job.catalogueId ?? '')?.name ?? 'Building',
                WorldConstructionKind.road =>
                  '${job.roadCells.length}-tile road stretch',
                WorldConstructionKind.bridge => 'Bridge',
              }),
              subtitle: Text(switch (job.kind) {
                WorldConstructionKind.structure =>
                  'Stage ${job.stagesDone + 1} of '
                      '${content.structure(job.catalogueId ?? '')?.constructionStages ?? 1} · one per check-in',
                WorldConstructionKind.road =>
                  '${state.roads.where((road) => road.projectId == job.id).length}/'
                      '${job.roadCells.length} tiles laid · one per check-in',
                WorldConstructionKind.bridge =>
                  '${job.stagesDone}/${job.bridgeDeliveryCells.length} cells raised · one per check-in',
              }),
              trailing: SizedBox(
                width: 64,
                child: LinearProgressIndicator(
                  value: switch (job.kind) {
                    WorldConstructionKind.structure =>
                      job.stagesDone /
                          (content
                                  .structure(job.catalogueId ?? '')
                                  ?.constructionStages ??
                              1),
                    WorldConstructionKind.road =>
                      state.roads
                              .where((road) => road.projectId == job.id)
                              .length /
                          job.roadCells.length,
                    WorldConstructionKind.bridge =>
                      job.stagesDone / job.bridgeDeliveryCells.length,
                  },
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _RecentEvents extends StatelessWidget {
  const _RecentEvents({required this.events});

  final List<WorldEvent> events;

  @override
  Widget build(BuildContext context) {
    final recent = events.reversed.take(4).toList();
    return _PanelCard(
      title: 'Recent changes',
      child: recent.isEmpty
          ? const Text('Check in, buy a parcel, or connect a road to begin.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final event in recent) Text('• ${event.description}'),
              ],
            ),
    );
  }
}

class _WorldErrorScreen extends StatelessWidget {
  const _WorldErrorScreen({
    required this.error,
    required this.onRetry,
    required this.onReset,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 42),
            const Text('The parcel-world save could not be loaded.'),
            Text('$error', textAlign: TextAlign.center),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
            TextButton(
              onPressed: onReset,
              child: const Text('Start a new parcel world…'),
            ),
          ],
        ),
      ),
    ),
  );
}
