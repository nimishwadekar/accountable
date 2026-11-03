import 'package:flutter/foundation.dart';

const citySaveSchemaVersion = 1;
const cityMapVersion = 1;

@immutable
class CityCell {
  const CityCell(this.column, this.row);

  final int column;
  final int row;

  String get key => '$column,$row';

  Map<String, Object> toJson() => {'column': column, 'row': row};

  factory CityCell.fromJson(Map<String, Object?> json) =>
      CityCell(json['column']! as int, json['row']! as int);

  @override
  bool operator ==(Object other) =>
      other is CityCell && other.column == column && other.row == row;

  @override
  int get hashCode => Object.hash(column, row);
}

@immutable
class CityBuilding {
  const CityBuilding({
    required this.id,
    required this.lotId,
    required this.catalogueId,
    required this.completedAtSeconds,
  });

  final String id;
  final String lotId;
  final String catalogueId;
  final int completedAtSeconds;

  Map<String, Object> toJson() => {
    'id': id,
    'lotId': lotId,
    'catalogueId': catalogueId,
    'completedAtSeconds': completedAtSeconds,
  };

  factory CityBuilding.fromJson(Map<String, Object?> json) => CityBuilding(
    id: json['id']! as String,
    lotId: json['lotId']! as String,
    catalogueId: json['catalogueId']! as String,
    completedAtSeconds: json['completedAtSeconds']! as int,
  );
}

@immutable
class CityConstruction {
  const CityConstruction({
    required this.id,
    required this.catalogueId,
    required this.costCoins,
    required this.startSeconds,
    required this.durationSeconds,
    this.lotId,
    this.districtId,
  });

  final String id;
  final String catalogueId;
  final String? lotId;
  final String? districtId;
  final int costCoins;
  final int startSeconds;
  final int durationSeconds;

  int get finishesAtSeconds => startSeconds + durationSeconds;
  int remainingAt(int nowSeconds) =>
      (finishesAtSeconds - nowSeconds).clamp(0, durationSeconds);

  Map<String, Object?> toJson() => {
    'id': id,
    'catalogueId': catalogueId,
    'lotId': lotId,
    'districtId': districtId,
    'costCoins': costCoins,
    'startSeconds': startSeconds,
    'durationSeconds': durationSeconds,
  };

  factory CityConstruction.fromJson(Map<String, Object?> json) =>
      CityConstruction(
        id: json['id']! as String,
        catalogueId: json['catalogueId']! as String,
        lotId: json['lotId'] as String?,
        districtId: json['districtId'] as String?,
        costCoins: json['costCoins']! as int,
        startSeconds: json['startSeconds']! as int,
        durationSeconds: json['durationSeconds']! as int,
      );
}

@immutable
class CityEvent {
  const CityEvent({
    required this.id,
    required this.kind,
    required this.dateKey,
    required this.simulationSeconds,
    required this.description,
  });

  final String id;
  final String kind;
  final String dateKey;
  final int simulationSeconds;
  final String description;

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind,
    'dateKey': dateKey,
    'simulationSeconds': simulationSeconds,
    'description': description,
  };

  factory CityEvent.fromJson(Map<String, Object?> json) => CityEvent(
    id: json['id']! as String,
    kind: json['kind']! as String,
    dateKey: json['dateKey']! as String,
    simulationSeconds: json['simulationSeconds']! as int,
    description: json['description']! as String,
  );
}

@immutable
class CityState {
  const CityState({
    required this.calendarDate,
    required this.simulationSeconds,
    required this.coins,
    required this.totalCoinsEarned,
    required this.totalCoinsSpent,
    required this.nextConstructionNumber,
    required this.creditedDates,
    required this.unlockedDistrictIds,
    required this.buildings,
    required this.constructions,
    required this.events,
  });

  /// The calendar clock is deliberately independent from construction time.
  final DateTime calendarDate;
  final int simulationSeconds;
  final int coins;
  final int totalCoinsEarned;
  final int totalCoinsSpent;
  final int nextConstructionNumber;
  final Set<String> creditedDates;
  final Set<String> unlockedDistrictIds;
  final List<CityBuilding> buildings;
  final List<CityConstruction> constructions;
  final List<CityEvent> events;

  String get dateKey => _dateKey(calendarDate);
  int get creditedDayCount => creditedDates.length;
  int get buildingCount => buildings.length;
  bool get hasExpansionInProgress =>
      constructions.any((job) => job.districtId != null);

  CityState copyWith({
    DateTime? calendarDate,
    int? simulationSeconds,
    int? coins,
    int? totalCoinsEarned,
    int? totalCoinsSpent,
    int? nextConstructionNumber,
    Set<String>? creditedDates,
    Set<String>? unlockedDistrictIds,
    List<CityBuilding>? buildings,
    List<CityConstruction>? constructions,
    List<CityEvent>? events,
  }) => CityState(
    calendarDate: calendarDate ?? this.calendarDate,
    simulationSeconds: simulationSeconds ?? this.simulationSeconds,
    coins: coins ?? this.coins,
    totalCoinsEarned: totalCoinsEarned ?? this.totalCoinsEarned,
    totalCoinsSpent: totalCoinsSpent ?? this.totalCoinsSpent,
    nextConstructionNumber:
        nextConstructionNumber ?? this.nextConstructionNumber,
    creditedDates: creditedDates ?? this.creditedDates,
    unlockedDistrictIds: unlockedDistrictIds ?? this.unlockedDistrictIds,
    buildings: buildings ?? this.buildings,
    constructions: constructions ?? this.constructions,
    events: events ?? this.events,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': citySaveSchemaVersion,
    'mapVersion': cityMapVersion,
    'calendarDate': dateKey,
    'simulationSeconds': simulationSeconds,
    'coins': coins,
    'totalCoinsEarned': totalCoinsEarned,
    'totalCoinsSpent': totalCoinsSpent,
    'nextConstructionNumber': nextConstructionNumber,
    'creditedDates': creditedDates.toList()..sort(),
    'unlockedDistrictIds': unlockedDistrictIds.toList()..sort(),
    'buildings': buildings.map((building) => building.toJson()).toList(),
    'constructions': constructions
        .map((construction) => construction.toJson())
        .toList(),
    'events': events.map((event) => event.toJson()).toList(),
  };

  factory CityState.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != citySaveSchemaVersion ||
        json['mapVersion'] != cityMapVersion) {
      throw const FormatException('This city save version is not supported.');
    }

    final dateKey = json['calendarDate']! as String;
    final date = DateTime.tryParse(dateKey);
    if (date == null ||
        _dateKey(date) != dateKey ||
        (json['coins']! as int) < 0 ||
        (json['simulationSeconds']! as int) < 0) {
      throw const FormatException('The city save contains invalid values.');
    }

    final state = CityState(
      calendarDate: DateTime.utc(date.year, date.month, date.day),
      simulationSeconds: json['simulationSeconds']! as int,
      coins: json['coins']! as int,
      totalCoinsEarned: json['totalCoinsEarned']! as int,
      totalCoinsSpent: json['totalCoinsSpent']! as int,
      nextConstructionNumber: json['nextConstructionNumber']! as int,
      creditedDates: Set<String>.from(json['creditedDates']! as List),
      unlockedDistrictIds: Set<String>.from(
        json['unlockedDistrictIds']! as List,
      ),
      buildings: (json['buildings']! as List)
          .map((value) => CityBuilding.fromJson(_map(value)))
          .toList(),
      constructions: (json['constructions']! as List)
          .map((value) => CityConstruction.fromJson(_map(value)))
          .toList(),
      events: (json['events']! as List)
          .map((value) => CityEvent.fromJson(_map(value)))
          .toList(),
    );
    if (state.totalCoinsEarned < 0 ||
        state.totalCoinsSpent < 0 ||
        state.totalCoinsEarned - state.totalCoinsSpent != state.coins ||
        state.nextConstructionNumber < 1 ||
        state.unlockedDistrictIds.isEmpty ||
        !_hasUnique(state.buildings.map((building) => building.id)) ||
        !_hasUnique(state.buildings.map((building) => building.lotId)) ||
        !_hasUnique(state.constructions.map((job) => job.id)) ||
        !_hasUnique(state.events.map((event) => event.id)) ||
        !_hasUnique(state.creditedDates)) {
      throw const FormatException('The city save violates its state rules.');
    }

    final occupiedLots = state.buildings
        .map((building) => building.lotId)
        .toSet();
    final constructionLots = <String>{};
    for (final job in state.constructions) {
      if (job.costCoins <= 0 ||
          job.durationSeconds <= 0 ||
          job.startSeconds < 0 ||
          job.finishesAtSeconds <= state.simulationSeconds ||
          (job.lotId == null) == (job.districtId == null) ||
          (job.lotId != null &&
              (occupiedLots.contains(job.lotId) ||
                  !constructionLots.add(job.lotId!)))) {
        throw const FormatException(
          'The city save contains an invalid construction job.',
        );
      }
    }
    for (final building in state.buildings) {
      if (building.completedAtSeconds < 0 ||
          building.completedAtSeconds > state.simulationSeconds) {
        throw const FormatException(
          'The city save contains an invalid completed building.',
        );
      }
    }
    for (final creditedDate in state.creditedDates) {
      final parsed = DateTime.tryParse(creditedDate);
      if (parsed == null || _dateKey(parsed) != creditedDate) {
        throw const FormatException(
          'The city save contains an invalid check-in date.',
        );
      }
    }
    return state;
  }
}

String cityDateKey(DateTime date) => _dateKey(date);

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

Map<String, Object?> _map(Object? value) =>
    (value as Map).map((key, value) => MapEntry(key as String, value));

bool _hasUnique(Iterable<Object> values) {
  final list = values.toList();
  return list.toSet().length == list.length;
}
