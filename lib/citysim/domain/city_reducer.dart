import '../content/city_content.dart';
import 'city_state.dart';

class CityRuleViolation implements Exception {
  const CityRuleViolation(this.message);

  final String message;

  @override
  String toString() => message;
}

CityState checkInForToday(CityState state) {
  final key = state.dateKey;
  if (state.creditedDates.contains(key)) return state;

  final eventId = 'check-in:$key';
  return state.copyWith(
    coins: state.coins + 1,
    totalCoinsEarned: state.totalCoinsEarned + 1,
    creditedDates: {...state.creditedDates, key},
    events: [
      ...state.events,
      CityEvent(
        id: eventId,
        kind: 'check-in',
        dateKey: key,
        simulationSeconds: state.simulationSeconds,
        description: 'Daily check-in · +1 coin',
      ),
    ],
  );
}

CityState purchaseForLot(
  CityState state, {
  required String catalogueId,
  required String lotId,
}) {
  final item = cityCatalogueById[catalogueId];
  if (item == null) {
    throw const CityRuleViolation('That catalogue item is unavailable.');
  }
  final sprite = citySpriteManifest[catalogueId]!;
  final lot = cityLotById[lotId];
  if (lot == null) throw const CityRuleViolation('That lot does not exist.');
  if (sprite.footprintColumns > lot.footprintColumns ||
      sprite.footprintRows > lot.footprintRows) {
    throw const CityRuleViolation('This addition does not fit on that lot.');
  }
  if (!state.unlockedDistrictIds.contains(lot.districtId)) {
    throw const CityRuleViolation('Unlock this district before building here.');
  }
  if (item.minimumDistrictRank > cityDistrictRank(lot.districtId)) {
    throw const CityRuleViolation(
      'This addition is only available in a later district.',
    );
  }
  if (state.buildings.any((building) => building.lotId == lotId) ||
      state.constructions.any((job) => job.lotId == lotId)) {
    throw const CityRuleViolation('That lot is already occupied.');
  }
  _requireWallet(state, item.costCoins);

  final number = state.nextConstructionNumber;
  final job = CityConstruction(
    id: 'construction-$number',
    catalogueId: item.id,
    lotId: lotId,
    costCoins: item.costCoins,
    startSeconds: state.simulationSeconds,
    durationSeconds: item.durationSeconds,
  );
  return state.copyWith(
    coins: state.coins - item.costCoins,
    totalCoinsSpent: state.totalCoinsSpent + item.costCoins,
    nextConstructionNumber: number + 1,
    constructions: [...state.constructions, job],
    events: [
      ...state.events,
      CityEvent(
        id: 'purchase:${job.id}',
        kind: 'purchase',
        dateKey: state.dateKey,
        simulationSeconds: state.simulationSeconds,
        description: '${item.name} started · −${item.costCoins} coins',
      ),
    ],
  );
}

CityState startDistrictExpansion(CityState state) {
  if (state.hasExpansionInProgress) {
    throw const CityRuleViolation('A district expansion is already underway.');
  }
  CityDistrict? nextDistrict;
  for (final district in cityDistricts) {
    if (!state.unlockedDistrictIds.contains(district.id)) {
      nextDistrict = district;
      break;
    }
  }
  if (nextDistrict == null) {
    throw const CityRuleViolation('Every district is already open.');
  }
  _requireWallet(state, nextDistrict.unlockCost);

  final number = state.nextConstructionNumber;
  final job = CityConstruction(
    id: 'construction-$number',
    catalogueId: 'district-expansion:${nextDistrict.id}',
    districtId: nextDistrict.id,
    costCoins: nextDistrict.unlockCost,
    startSeconds: state.simulationSeconds,
    durationSeconds: nextDistrict.unlockDurationSeconds,
  );
  return state.copyWith(
    coins: state.coins - nextDistrict.unlockCost,
    totalCoinsSpent: state.totalCoinsSpent + nextDistrict.unlockCost,
    nextConstructionNumber: number + 1,
    constructions: [...state.constructions, job],
    events: [
      ...state.events,
      CityEvent(
        id: 'purchase:${job.id}',
        kind: 'district-expansion',
        dateKey: state.dateKey,
        simulationSeconds: state.simulationSeconds,
        description:
            '${nextDistrict.name} expansion started · '
            '−${nextDistrict.unlockCost} coins',
      ),
    ],
  );
}

CityState advanceConstructionClock(CityState state, int elapsedSeconds) {
  if (elapsedSeconds <= 0) return state;
  final newTime = state.simulationSeconds + elapsedSeconds;
  final due =
      state.constructions
          .where((job) => job.finishesAtSeconds <= newTime)
          .toList()
        ..sort((a, b) {
          final byTime = a.finishesAtSeconds.compareTo(b.finishesAtSeconds);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
  if (due.isEmpty) return state.copyWith(simulationSeconds: newTime);

  final completedIds = due.map((job) => job.id).toSet();
  final buildings = [...state.buildings];
  final unlockedDistricts = {...state.unlockedDistrictIds};
  final events = [...state.events];
  for (final job in due) {
    if (job.lotId case final lotId?) {
      buildings.add(
        CityBuilding(
          id: 'building:${job.id}',
          lotId: lotId,
          catalogueId: job.catalogueId,
          completedAtSeconds: job.finishesAtSeconds,
        ),
      );
      final item = cityCatalogueById[job.catalogueId]!;
      events.add(
        CityEvent(
          id: 'complete:${job.id}',
          kind: 'construction-complete',
          dateKey: state.dateKey,
          simulationSeconds: job.finishesAtSeconds,
          description: '${item.name} is complete',
        ),
      );
    } else if (job.districtId case final districtId?) {
      unlockedDistricts.add(districtId);
      final district = cityDistricts.firstWhere(
        (entry) => entry.id == districtId,
      );
      events.add(
        CityEvent(
          id: 'complete:${job.id}',
          kind: 'district-unlocked',
          dateKey: state.dateKey,
          simulationSeconds: job.finishesAtSeconds,
          description: '${district.name} is now open',
        ),
      );
    }
  }

  return state.copyWith(
    simulationSeconds: newTime,
    buildings: buildings,
    unlockedDistrictIds: unlockedDistricts,
    constructions: state.constructions
        .where((job) => !completedIds.contains(job.id))
        .toList(),
    events: events,
  );
}

CityState moveCalendarBy(CityState state, int days) {
  if (days == 0) return state;
  return setCalendarDate(state, state.calendarDate.add(Duration(days: days)));
}

CityState setCalendarDate(CityState state, DateTime date) {
  final normalized = DateTime.utc(date.year, date.month, date.day);
  if (normalized == state.calendarDate) return state;
  return state.copyWith(calendarDate: normalized);
}

CityState grantDebugCoins(CityState state, int amount) {
  if (amount <= 0) {
    throw const CityRuleViolation('A debug grant must be a positive amount.');
  }
  return state.copyWith(
    coins: state.coins + amount,
    totalCoinsEarned: state.totalCoinsEarned + amount,
    events: [
      ...state.events,
      CityEvent(
        id: 'debug-grant:${state.nextConstructionNumber}:${state.events.length}',
        kind: 'debug-grant',
        dateKey: state.dateKey,
        simulationSeconds: state.simulationSeconds,
        description: 'Test-only coin grant · +$amount coins',
      ),
    ],
  );
}

int? secondsUntilNextCompletion(CityState state) {
  if (state.constructions.isEmpty) return null;
  final next = state.constructions
      .map((job) => job.finishesAtSeconds)
      .reduce((a, b) => a < b ? a : b);
  return (next - state.simulationSeconds).clamp(0, next);
}

void _requireWallet(CityState state, int cost) {
  if (state.coins < cost) {
    throw CityRuleViolation('You need $cost coins for this addition.');
  }
}
