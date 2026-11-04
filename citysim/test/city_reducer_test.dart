import 'package:citysim/content/city_content.dart';
import 'package:citysim/domain/city_reducer.dart';
import 'package:citysim/domain/city_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('daily check-ins', () {
    test('award exactly one coin per simulated date', () {
      var city = newCityState(today: DateTime.utc(2026, 11, 2));

      city = checkInForToday(city);
      expect(city.coins, 1);
      expect(city.totalCoinsEarned, 1);

      final duplicate = checkInForToday(city);
      expect(identical(duplicate, city), isTrue);
      expect(duplicate.coins, 1);

      city = moveCalendarBy(city, 1);
      expect(city.coins, 1, reason: 'advancing the date gives no coin');
      city = checkInForToday(city);
      expect(city.coins, 2);

      city = moveCalendarBy(city, -1);
      expect(
        checkInForToday(city).coins,
        2,
        reason: 'rewinds do not re-credit',
      );
    });
  });

  group('lot purchases', () {
    test('validate affordability before reserving or spending', () {
      var city = newCityState(today: DateTime.utc(2026, 11, 2));
      city = checkInForToday(city);
      final before = city;

      expect(
        () => purchaseForLot(
          city,
          catalogueId: 'small-home',
          lotId: 'village-04',
        ),
        throwsA(isA<CityRuleViolation>()),
      );
      expect(city.coins, before.coins);
      expect(city.constructions, isEmpty);
      expect(city.buildings, before.buildings);
    });

    test('debit and reserve a valid lot together; jobs run in parallel', () {
      var city = newCityState(today: DateTime.utc(2026, 11, 2));
      city = grantDebugCoins(city, 10);
      city = purchaseForLot(
        city,
        catalogueId: 'small-home',
        lotId: 'village-04',
      );
      city = purchaseForLot(
        city,
        catalogueId: 'flower-garden',
        lotId: 'village-05',
      );

      expect(city.coins, 6);
      expect(city.totalCoinsSpent, 4);
      expect(city.constructions, hasLength(2));
      expect(city.buildings, hasLength(3));
      expect(
        () => purchaseForLot(city, catalogueId: 'cafe', lotId: 'village-04'),
        throwsA(isA<CityRuleViolation>()),
      );

      city = advanceConstructionClock(city, 30);
      expect(city.buildings, hasLength(4));
      expect(city.constructions, hasLength(1));
      expect(city.constructions.single.remainingAt(city.simulationSeconds), 90);

      city = advanceConstructionClock(city, 90);
      expect(city.buildings, hasLength(5));
      expect(city.constructions, isEmpty);
      final completed = advanceConstructionClock(city, 120);
      expect(completed.buildings, hasLength(5));
    });

    test(
      'reject locked district lots and buildings that need a later tier',
      () {
        var city = grantDebugCoins(
          newCityState(today: DateTime.utc(2026, 11, 2)),
          20,
        );
        expect(
          () =>
              purchaseForLot(city, catalogueId: 'small-home', lotId: 'town-01'),
          throwsA(isA<CityRuleViolation>()),
        );
        expect(
          () => purchaseForLot(
            city,
            catalogueId: 'apartments',
            lotId: 'village-04',
          ),
          throwsA(isA<CityRuleViolation>()),
        );
      },
    );
  });

  group('districts', () {
    test('expansion only exposes new lots when its timer completes', () {
      var city = grantDebugCoins(
        newCityState(today: DateTime.utc(2026, 11, 2)),
        20,
      );
      city = startDistrictExpansion(city);
      expect(city.coins, 12);
      expect(city.unlockedDistrictIds, {'village'});
      expect(city.hasExpansionInProgress, isTrue);

      expect(
        () => startDistrictExpansion(city),
        throwsA(isA<CityRuleViolation>()),
      );
      expect(
        () =>
            purchaseForLot(city, catalogueId: 'fruit-market', lotId: 'town-01'),
        throwsA(isA<CityRuleViolation>()),
      );

      city = advanceConstructionClock(city, 299);
      expect(city.unlockedDistrictIds, {'village'});
      city = advanceConstructionClock(city, 1);
      expect(city.unlockedDistrictIds, {'village', 'town'});
      expect(city.hasExpansionInProgress, isFalse);
    });

    test('calendar rewind does not rewind construction time', () {
      var city = grantDebugCoins(
        newCityState(today: DateTime.utc(2026, 11, 2)),
        4,
      );
      city = purchaseForLot(
        city,
        catalogueId: 'small-home',
        lotId: 'village-04',
      );
      city = advanceConstructionClock(city, 40);
      city = moveCalendarBy(city, -4);
      expect(city.simulationSeconds, 40);
      expect(city.constructions.single.remainingAt(city.simulationSeconds), 80);
    });
  });

  test('state round-trips a deterministic, JSON-compatible snapshot', () {
    var city = newCityState(today: DateTime.utc(2026, 11, 2));
    city = checkInForToday(city);
    city = grantDebugCoins(city, 2);
    city = purchaseForLot(
      city,
      catalogueId: 'flower-garden',
      lotId: 'village-04',
    );
    city = advanceConstructionClock(city, 11);

    final decoded = CityState.fromJson(city.toJson());
    expect(decoded.toJson(), city.toJson());
  });

  test(
    'state loading rejects a wallet that breaks the earned/spent invariant',
    () {
      final city = newCityState(today: DateTime.utc(2026, 11, 2));
      expect(
        () => CityState.fromJson({...city.toJson(), 'coins': 2}),
        throwsFormatException,
      );
    },
  );
}
