import 'dart:async';

import 'package:flutter/material.dart';

import 'content/city_content.dart';
import 'content/city_scenarios.dart';
import 'data/city_save_store.dart';
import 'domain/city_reducer.dart';
import 'domain/city_state.dart';
import 'rendering/city_world_view.dart';

class CitySimulatorApp extends StatelessWidget {
  const CitySimulatorApp({super.key, this.saveStore});

  final CitySaveStore? saveStore;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Settlement Preview',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF4F3EA),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF276B58),
        surface: const Color(0xFFFCFBF6),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: Color(0xFF193A31),
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          color: Color(0xFF193A31),
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    home: CitySimulatorPage(saveStore: saveStore),
  );
}

class CitySimulatorPage extends StatefulWidget {
  const CitySimulatorPage({this.saveStore, super.key});

  final CitySaveStore? saveStore;

  @override
  State<CitySimulatorPage> createState() => _CitySimulatorPageState();
}

class _CitySimulatorPageState extends State<CitySimulatorPage>
    with WidgetsBindingObserver {
  late final CitySaveStore _saveStore =
      widget.saveStore ?? SharedPreferencesCitySaveStore();

  CityState? _city;
  Object? _loadError;
  String? _saveError;
  Future<void> _pendingSave = Future<void>.value();
  Timer? _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  int _lastElapsedMicros = 0;
  double _fractionalSimulationSeconds = 0;
  int _speed = 1;
  bool _debugPaused = false;
  bool _lifecyclePaused = false;

  String? _selectedCatalogueId;
  String? _selectedLotId;
  String? _selectedBuildingId;
  int _cameraRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCity());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTicker();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecyclePaused = state != AppLifecycleState.resumed;
    _syncTicker();
  }

  Future<void> _loadCity() async {
    try {
      final loaded = await _saveStore.load();
      final city = loaded ?? newCityState();
      if (loaded == null) {
        try {
          await _saveStore.save(city);
        } catch (error) {
          _saveError = error.toString();
        }
      }
      if (!mounted) return;
      setState(() => _city = city);
      _syncTicker();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  void _commit(CityState next) {
    if (identical(next, _city)) return;
    setState(() => _city = next);
    _pendingSave = _pendingSave.catchError((Object _) {}).then((_) async {
      try {
        await _saveStore.save(next);
        if (mounted) setState(() => _saveError = null);
      } catch (error) {
        if (mounted) setState(() => _saveError = error.toString());
      }
    });
  }

  void _syncTicker() {
    if (_city == null || _lifecyclePaused || _debugPaused) {
      _stopTicker();
      return;
    }
    if (_ticker != null) return;
    _fractionalSimulationSeconds = 0;
    _lastElapsedMicros = 0;
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = _stopwatch.elapsedMicroseconds;
      final elapsedMicros = now - _lastElapsedMicros;
      _lastElapsedMicros = now;
      _fractionalSimulationSeconds +=
          elapsedMicros / Duration.microsecondsPerSecond * _speed;
      final wholeSeconds = _fractionalSimulationSeconds.floor();
      if (wholeSeconds == 0) return;
      _fractionalSimulationSeconds -= wholeSeconds;
      final city = _city;
      if (city != null) {
        _commit(advanceConstructionClock(city, wholeSeconds));
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch
      ..stop()
      ..reset();
  }

  void _runAction(CityState Function(CityState) action) {
    final city = _city;
    if (city == null) return;
    try {
      _commit(action(city));
    } on CityRuleViolation catch (error) {
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onMapTap(CityWorldHit hit) {
    setState(() {
      _selectedLotId = hit.lotId;
      _selectedBuildingId = hit.buildingId;
      if (hit.buildingId != null) _selectedCatalogueId = null;
    });
  }

  Future<void> _confirmPurchase() async {
    final city = _city;
    final item = cityCatalogueById[_selectedCatalogueId];
    final lot = cityLotById[_selectedLotId];
    if (city == null || item == null || lot == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Build ${item.name.toLowerCase()}?'),
        content: Text(
          '${item.costLabel} · ${_durationLabel(item.durationSeconds)} '
          'of construction.\n\n'
          'The coins are spent when construction starts. It can’t be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start construction'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _runAction(
      (state) => purchaseForLot(state, catalogueId: item.id, lotId: lot.id),
    );
    setState(() {
      _selectedCatalogueId = null;
      _selectedLotId = null;
    });
  }

  Future<void> _confirmExpansion(CityDistrict district) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connect ${district.name}?'),
        content: Text(
          '${district.unlockCost} coins · '
          '${_durationLabel(district.unlockDurationSeconds)} to connect.\n\n'
          'The expansion cannot be cancelled once it starts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start expansion'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _runAction(startDistrictExpansion);
    }
  }

  Future<void> _resetSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset this city?'),
        content: const Text(
          'This resets only the local settlement preview. Accountable data is '
          'not read or changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep city'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset preview'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _saveStore.clear();
      if (!mounted) return;
      final fresh = newCityState();
      _commit(fresh);
      setState(() {
        _selectedCatalogueId = null;
        _selectedLotId = null;
        _selectedBuildingId = null;
        _saveError = null;
      });
      _showMessage('The city preview has been reset.');
    } catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
    }
  }

  Future<void> _resetCorruptSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace the unreadable city save?'),
        content: const Text(
          'This clears only the settlement preview save and starts a fresh '
          'synthetic village. Accountable data is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep existing save'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace preview save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _saveStore.clear();
      final fresh = newCityState();
      await _saveStore.save(fresh);
      if (!mounted) return;
      setState(() {
        _city = fresh;
        _loadError = null;
        _saveError = null;
      });
      _syncTicker();
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _runWeekScenario() {
    final currentCity = _city;
    if (currentCity == null) return;
    var city = currentCity;
    for (var day = 0; day < 7; day++) {
      city = moveCalendarBy(city, 1);
      city = checkInForToday(city);
    }
    _commit(city);
    _showMessage('Scenario complete: simulated seven daily check-ins.');
  }

  Future<void> _loadScenario(CityScenario scenario) async {
    final scenarioName = switch (scenario) {
      CityScenario.village => 'Willow Village',
      CityScenario.town => 'Market Town',
      CityScenario.city => 'Cedar Heights',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Load $scenarioName?'),
        content: const Text(
          'This replaces the current local preview with a labelled synthetic '
          'test scene. No Accountable data is affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current city'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Load scenario'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _commit(buildCityScenario(scenario));
    setState(() {
      _selectedCatalogueId = null;
      _selectedLotId = null;
      _selectedBuildingId = null;
    });
    _showMessage('$scenarioName scenario loaded.');
  }

  void _tickToNextCompletion() {
    final city = _city;
    if (city == null) return;
    final remaining = secondsUntilNextCompletion(city);
    if (remaining == null) return;
    _commit(advanceConstructionClock(city, remaining));
  }

  @override
  Widget build(BuildContext context) {
    final city = _city;
    if (_loadError != null) {
      return _LoadFailure(
        error: _loadError!,
        onRetry: _loadCity,
        onReset: _resetCorruptSave,
      );
    }
    if (city == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                state: city,
                onCheckIn: () => _runAction(checkInForToday),
                saveError: _saveError,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 940) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _worldPanel(city)),
                          const SizedBox(width: 14),
                          SizedBox(width: 350, child: _controlPanel(city)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(flex: 5, child: _worldPanel(city)),
                        const SizedBox(height: 12),
                        Expanded(flex: 4, child: _controlPanel(city)),
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

  Widget _worldPanel(CityState city) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFB5DCCF),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFD6E1D6)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x120D392B),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => InteractiveViewer(
              key: ValueKey(_cameraRevision),
              minScale: 0.8,
              maxScale: 2.5,
              boundaryMargin: const EdgeInsets.all(120),
              child: SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: cityWorldWidth,
                    height: cityWorldHeight,
                    child: CityWorldView(
                      state: city,
                      selectedCatalogueId: _selectedCatalogueId,
                      selectedLotId: _selectedLotId,
                      selectedBuildingId: _selectedBuildingId,
                      onMapTap: _onMapTap,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 14,
          left: 16,
          child: _MapLabel(
            title: city.unlockedDistrictIds.length == 1
                ? cityDistricts
                      .firstWhere(
                        (district) =>
                            city.unlockedDistrictIds.contains(district.id),
                      )
                      .name
                : '${city.unlockedDistrictIds.length} connected districts',
            subtitle: 'A little place, growing at your pace',
          ),
        ),
        Positioned(
          right: 14,
          top: 14,
          child: Tooltip(
            message: 'Reset camera',
            child: IconButton.filledTonal(
              onPressed: () => setState(() => _cameraRevision++),
              icon: const Icon(Icons.center_focus_strong_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xEFFFFFFF),
                foregroundColor: const Color(0xFF2A5949),
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          bottom: 14,
          child: _MapHint(
            text: _selectedCatalogueId == null
                ? 'Drag to explore · pinch or scroll to zoom'
                : 'Choose an outlined lot for this addition',
          ),
        ),
      ],
    ),
  );

  Widget _controlPanel(CityState city) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFFCFBF6),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE5E3D9)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        children: [
          _SectionTitle(
            title: 'Choose an addition',
            trailing: TextButton.icon(
              onPressed: _resetSave,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset'),
            ),
          ),
          if (_selectedBuildingId != null) ...[
            const SizedBox(height: 8),
            _buildingInspector(city),
          ],
          const SizedBox(height: 8),
          for (final item in cityCatalogue)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _CatalogueTile(
                item: item,
                selected: _selectedCatalogueId == item.id,
                unlockedRank: city.unlockedDistrictIds
                    .map(cityDistrictRank)
                    .fold<int>(0, (a, b) => a > b ? a : b),
                onTap: () => setState(() {
                  _selectedCatalogueId = item.id;
                  _selectedLotId = null;
                  _selectedBuildingId = null;
                }),
              ),
            ),
          if (_selectedCatalogueId != null) ...[
            const SizedBox(height: 10),
            _selectionDetails(city),
          ],
          const SizedBox(height: 16),
          _districtExpansionCard(city),
          if (city.constructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ActiveConstructionPanel(state: city),
          ],
          const SizedBox(height: 16),
          _DebugPanel(
            state: city,
            paused: _debugPaused,
            speed: _speed,
            onPauseChanged: (paused) {
              setState(() => _debugPaused = paused);
              _syncTicker();
            },
            onSpeedChanged: (speed) {
              setState(() => _speed = speed);
              _syncTicker();
            },
            onDateShift: (days) =>
                _runAction((state) => moveCalendarBy(state, days)),
            onDebugGrant: () =>
                _runAction((state) => grantDebugCoins(state, 10)),
            onWeekScenario: _runWeekScenario,
            onFastForward: _tickToNextCompletion,
            onCalendarCheckIn: () => _runAction(checkInForToday),
            onLoadScenario: _loadScenario,
          ),
          const SizedBox(height: 16),
          _HistoryPanel(events: city.events),
        ],
      ),
    ),
  );

  Widget _selectionDetails(CityState city) {
    final item = cityCatalogueById[_selectedCatalogueId]!;
    final lot = cityLotById[_selectedLotId];
    final hasEnough = city.coins >= item.costCoins;
    final validDistrict =
        lot != null &&
        cityDistrictRank(lot.districtId) >= item.minimumDistrictRank;
    final occupied =
        lot != null &&
        (city.buildings.any((building) => building.lotId == lot.id) ||
            city.constructions.any((job) => job.lotId == lot.id));
    final canStart =
        lot != null &&
        validDistrict &&
        !occupied &&
        city.unlockedDistrictIds.contains(lot.districtId) &&
        hasEnough;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F2EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD3E5D9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(item.description, style: const TextStyle(height: 1.35)),
          const SizedBox(height: 8),
          Text(
            '${item.costLabel}  ·  ${_durationLabel(item.durationSeconds)}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF315E4D),
            ),
          ),
          const SizedBox(height: 10),
          if (lot == null)
            const Text('Tap an outlined lot on the map to choose a site.')
          else if (occupied)
            const Text('This lot is already occupied or under construction.')
          else if (!city.unlockedDistrictIds.contains(lot.districtId))
            const Text('This district is still locked.')
          else if (!validDistrict)
            const Text('This addition needs a later district.')
          else if (!hasEnough)
            Text('Check in for ${item.costCoins - city.coins} more coins.')
          else
            Text('Selected site: ${_districtName(lot.districtId)}'),
          if (item.kind == CityItemKind.decoration && lot == null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Decorations also use an authored lot.'),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canStart ? _confirmPurchase : null,
              child: const Text('Review and build'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildingInspector(CityState city) {
    CityBuilding? selected;
    for (final building in city.buildings) {
      if (building.id == _selectedBuildingId) {
        selected = building;
        break;
      }
    }
    if (selected == null) return const SizedBox.shrink();
    final item = cityCatalogueById[selected.catalogueId];
    final lot = cityLotById[selected.lotId];
    return _InfoCard(
      icon: item?.kind == CityItemKind.decoration
          ? Icons.local_florist_rounded
          : Icons.home_work_rounded,
      title: item?.name ?? 'Settlement addition',
      subtitle:
          '${lot == null ? 'Authored lot' : _districtName(lot.districtId)}'
          ' · complete since build second ${selected.completedAtSeconds}',
    );
  }

  Widget _districtExpansionCard(CityState city) {
    CityDistrict? nextDistrict;
    for (final district in cityDistricts) {
      if (!city.unlockedDistrictIds.contains(district.id)) {
        nextDistrict = district;
        break;
      }
    }
    final expansionJobs = city.constructions
        .where((construction) => construction.districtId != null)
        .toList();
    final job = expansionJobs.isEmpty ? null : expansionJobs.first;
    if (nextDistrict == null && job == null) {
      return const _InfoCard(
        icon: Icons.park_rounded,
        title: 'All districts are open',
        subtitle: 'Your authored map is ready to fill.',
      );
    }
    if (job != null) {
      final target = cityDistricts.firstWhere(
        (district) => district.id == job.districtId,
      );
      return _InfoCard(
        icon: Icons.landscape_rounded,
        title: '${target.name} is being connected',
        subtitle:
            '${_durationLabel(job.remainingAt(city.simulationSeconds))} '
            'remaining · no new lots until it opens.',
      );
    }
    final district = nextDistrict!;
    final canAfford = city.coins >= district.unlockCost;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F0E3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'NEXT DISTRICT',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: Color(0xFF796E50),
            ),
          ),
          const SizedBox(height: 4),
          Text(district.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${district.unlockCost} coins · '
            '${_durationLabel(district.unlockDurationSeconds)} to connect',
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: canAfford ? () => _confirmExpansion(district) : null,
              icon: const Icon(Icons.add_road_rounded),
              label: const Text('Expand settlement'),
            ),
          ),
        ],
      ),
    );
  }

  String _districtName(String id) =>
      cityDistricts.firstWhere((district) => district.id == id).name;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.state,
    required this.onCheckIn,
    required this.saveError,
  });

  final CityState state;
  final VoidCallback onCheckIn;
  final String? saveError;

  @override
  Widget build(BuildContext context) {
    final checkedIn = state.creditedDates.contains(state.dateKey);
    final brand = Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFF1D6653),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.location_city_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SETTLEMENT PREVIEW',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.25,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF63776B),
                ),
              ),
              Text(
                'A place that grows with you',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ],
    );
    final wallet = _WalletPill(coins: state.coins);
    final checkInButton = FilledButton.icon(
      onPressed: checkedIn ? null : onCheckIn,
      icon: Icon(checkedIn ? Icons.check_circle_rounded : Icons.add_rounded),
      label: Text(checkedIn ? 'Checked in' : 'Check in · +1'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF256B56),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFDCE9DF),
        disabledForegroundColor: const Color(0xFF466457),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      ),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [wallet, const SizedBox(width: 8), checkInButton],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              brand,
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 6,
                  children: [wallet, checkInButton],
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(child: brand),
                  actions,
                ],
              ),
            if (saveError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Save warning: $saveError',
                  style: const TextStyle(
                    color: Color(0xFF9B3129),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WalletPill extends StatelessWidget {
  const _WalletPill({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(13, 8, 15, 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF8DA),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE8DFAF)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.toll_rounded, color: Color(0xFFAC7C20), size: 21),
        const SizedBox(width: 7),
        Text(
          '$coins',
          style: const TextStyle(
            color: Color(0xFF59451C),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        const SizedBox(width: 4),
        const Text('coins', style: TextStyle(color: Color(0xFF756642))),
      ],
    ),
  );
}

class _MapLabel extends StatelessWidget {
  const _MapLabel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xEFFFFFFF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF244F41),
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF4C7162), fontSize: 11),
        ),
      ],
    ),
  );
}

class _MapHint extends StatelessWidget {
  const _MapHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xEFFFFFFF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFF416655), fontSize: 11),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      ?trailing,
    ],
  );
}

class _CatalogueTile extends StatelessWidget {
  const _CatalogueTile({
    required this.item,
    required this.selected,
    required this.unlockedRank,
    required this.onTap,
  });

  final CityCatalogueItem item;
  final bool selected;
  final int unlockedRank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locked = item.minimumDistrictRank > unlockedRank;
    return Material(
      color: selected ? const Color(0xFFE5F1E9) : const Color(0xFFF4F3ED),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF80B59A)
                  : const Color(0xFFE9E7DD),
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.kind == CityItemKind.decoration
                    ? Icons.local_florist_rounded
                    : Icons.home_work_rounded,
                size: 19,
                color: selected
                    ? const Color(0xFF286B53)
                    : const Color(0xFF6F796C),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      locked
                          ? 'Unlock a later district'
                          : '${item.costLabel} · ${_durationLabel(item.durationSeconds)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF68766D),
                      ),
                    ),
                  ],
                ),
              ),
              if (locked)
                const Icon(Icons.lock_outline_rounded, size: 17)
              else if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Color(0xFF286B53),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({
    required this.state,
    required this.paused,
    required this.speed,
    required this.onPauseChanged,
    required this.onSpeedChanged,
    required this.onDateShift,
    required this.onDebugGrant,
    required this.onWeekScenario,
    required this.onFastForward,
    required this.onCalendarCheckIn,
    required this.onLoadScenario,
  });

  final CityState state;
  final bool paused;
  final int speed;
  final ValueChanged<bool> onPauseChanged;
  final ValueChanged<int> onSpeedChanged;
  final ValueChanged<int> onDateShift;
  final VoidCallback onDebugGrant;
  final VoidCallback onWeekScenario;
  final VoidCallback onFastForward;
  final VoidCallback onCalendarCheckIn;
  final ValueChanged<CityScenario> onLoadScenario;

  @override
  Widget build(BuildContext context) {
    final remaining = secondsUntilNextCompletion(state);
    final creditedToday = state.creditedDates.contains(state.dateKey);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2EC),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE1E6DD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 18,
                color: Color(0xFF45634F),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'TEST CONTROLS',
                  style: TextStyle(
                    letterSpacing: 1,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4C6252),
                  ),
                ),
              ),
              Text(
                '${state.creditedDayCount} check-ins',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _formatDate(state.calendarDate),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              _SmallButton(label: '−1 day', onPressed: () => onDateShift(-1)),
              _SmallButton(label: '+1 day', onPressed: () => onDateShift(1)),
              _SmallButton(label: '+7 days', onPressed: () => onDateShift(7)),
              _SmallButton(label: '+30 days', onPressed: () => onDateShift(30)),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: creditedToday ? null : onCalendarCheckIn,
              icon: const Icon(Icons.task_alt_rounded, size: 16),
              label: Text(
                creditedToday ? 'Today already credited' : 'Check in today',
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
          const Divider(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Build clock · ${_durationLabel(state.simulationSeconds)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DropdownButton<int>(
                value: speed,
                underline: const SizedBox.shrink(),
                isDense: true,
                items: const [1, 10, 60]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value×'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onSpeedChanged(value);
                },
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onPauseChanged(!paused),
                  icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  ),
                  label: Text(paused ? 'Resume' : 'Pause'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: remaining == null ? null : onFastForward,
                  icon: const Icon(Icons.fast_forward_rounded),
                  label: Text(remaining == null ? 'No builds' : 'Finish next'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              _SmallButton(
                label: 'Grant +10 test coins',
                onPressed: onDebugGrant,
              ),
              _SmallButton(
                label: 'Run 7-day check-in scenario',
                onPressed: onWeekScenario,
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Load a map scenario',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              _SmallButton(
                label: 'Village',
                onPressed: () => onLoadScenario(CityScenario.village),
              ),
              _SmallButton(
                label: 'Town',
                onPressed: () => onLoadScenario(CityScenario.town),
              ),
              _SmallButton(
                label: 'City',
                onPressed: () => onLoadScenario(CityScenario.city),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${state.totalCoinsEarned} earned · ${state.totalCoinsSpent} spent · '
            '${state.buildingCount} additions · ${state.unlockedDistrictIds.length} districts',
            style: const TextStyle(fontSize: 10, color: Color(0xFF66756A)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Synthetic preview only · time pauses when this page is away.',
            style: TextStyle(fontSize: 10, color: Color(0xFF66756A)),
          ),
        ],
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.events});

  final List<CityEvent> events;

  @override
  Widget build(BuildContext context) {
    final recent = events.reversed.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Recent changes'),
        const SizedBox(height: 6),
        if (recent.isEmpty)
          const Text(
            'Your first check-in will appear here.',
            style: TextStyle(fontSize: 12, color: Color(0xFF68766D)),
          )
        else
          for (final event in recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.circle,
                      size: 7,
                      color: Color(0xFF398267),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${event.description}  ·  ${event.dateKey}',
                      style: const TextStyle(fontSize: 11, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _ActiveConstructionPanel extends StatelessWidget {
  const _ActiveConstructionPanel({required this.state});

  final CityState state;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1EF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDDE8E3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Under construction',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 9),
        for (final job in state.constructions) ...[
          if (job != state.constructions.first) const SizedBox(height: 10),
          _ConstructionProgressRow(state: state, job: job),
        ],
      ],
    ),
  );
}

class _ConstructionProgressRow extends StatelessWidget {
  const _ConstructionProgressRow({required this.state, required this.job});

  final CityState state;
  final CityConstruction job;

  @override
  Widget build(BuildContext context) {
    final item = cityCatalogueById[job.catalogueId];
    final district = job.districtId == null
        ? null
        : cityDistricts.firstWhere((entry) => entry.id == job.districtId);
    final title = item?.name ?? district?.name ?? 'Settlement addition';
    final elapsed = state.simulationSeconds - job.startSeconds;
    final progress = (elapsed / job.durationSeconds).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 12))),
            Text(
              '${job.remainingAt(state.simulationSeconds)} sec left',
              style: const TextStyle(fontSize: 11, color: Color(0xFF617267)),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: const Color(0xFFD4E1DA),
            color: const Color(0xFF358269),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF4F0E3),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF716344)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      side: const BorderSide(color: Color(0xFFD7DDD2)),
    ),
    child: Text(label),
  );
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 42),
              const SizedBox(height: 12),
              Text(
                'The saved city could not be loaded.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(
                onPressed: onReset,
                child: const Text('Reset prototype save…'),
              ),
              const Text(
                'The existing save stays untouched unless you confirm reset.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _durationLabel(int seconds) {
  if (seconds < 60) return '$seconds sec';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  if (remainder == 0) return '$minutes min';
  return '$minutes min ${remainder}s';
}

String _formatDate(DateTime date) {
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} '
      '${date.day}, ${date.year}';
}
