import '../domain/city_reducer.dart';
import '../domain/city_state.dart';
import 'city_content.dart';

enum CityScenario { village, town, city }

CityState buildCityScenario(CityScenario scenario, {DateTime? today}) {
  var state = newCityState(today: today);
  if (scenario == CityScenario.village) {
    return _recordScenario(state, scenario);
  }

  state = grantDebugCoins(state, scenario == CityScenario.town ? 20 : 40);
  state = startDistrictExpansion(state);
  state = advanceConstructionClock(
    state,
    cityDistricts[1].unlockDurationSeconds,
  );
  state = purchaseForLot(state, catalogueId: 'fruit-market', lotId: 'town-01');
  state = purchaseForLot(
    state,
    catalogueId: 'community-clinic',
    lotId: 'town-02',
  );
  state = _finishAllConstruction(state);

  if (scenario == CityScenario.city) {
    state = startDistrictExpansion(state);
    state = advanceConstructionClock(
      state,
      cityDistricts[2].unlockDurationSeconds,
    );
    state = purchaseForLot(state, catalogueId: 'apartments', lotId: 'city-01');
    state = purchaseForLot(state, catalogueId: 'city-office', lotId: 'city-02');
    state = _finishAllConstruction(state);
  }

  return _recordScenario(state, scenario);
}

CityState _finishAllConstruction(CityState state) {
  while (state.constructions.isNotEmpty) {
    final seconds = secondsUntilNextCompletion(state)!;
    state = advanceConstructionClock(state, seconds);
  }
  return state;
}

CityState _recordScenario(CityState state, CityScenario scenario) {
  final title = switch (scenario) {
    CityScenario.village => 'Willow Village',
    CityScenario.town => 'Market Town',
    CityScenario.city => 'Cedar Heights',
  };
  return state.copyWith(
    events: [
      ...state.events,
      CityEvent(
        id: 'scenario:${scenario.name}',
        kind: 'scenario-load',
        dateKey: state.dateKey,
        simulationSeconds: state.simulationSeconds,
        description: 'Loaded test scenario · $title',
      ),
    ],
  );
}
