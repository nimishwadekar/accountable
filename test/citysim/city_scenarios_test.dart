import 'package:accountable/citysim/content/city_content.dart';
import 'package:accountable/citysim/content/city_scenarios.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime.utc(2026, 11, 2);

  test('village, town, and city test scenes are deterministic and valid', () {
    for (final scenario in CityScenario.values) {
      final first = buildCityScenario(scenario, today: today);
      final second = buildCityScenario(scenario, today: today);

      expect(first.toJson(), second.toJson());
      expect(first.constructions, isEmpty);
      expect(first.events.last.kind, 'scenario-load');
      expect(() => validateCityContentState(first), returnsNormally);
    }
  });

  test('town and city scenarios open the right authored districts', () {
    final town = buildCityScenario(CityScenario.town, today: today);
    expect(town.unlockedDistrictIds, {'village', 'town'});
    expect(town.buildingCount, 5);

    final city = buildCityScenario(CityScenario.city, today: today);
    expect(city.unlockedDistrictIds, {'village', 'town', 'city'});
    expect(city.buildingCount, 7);
    expect(city.coins, 6);
  });
}
