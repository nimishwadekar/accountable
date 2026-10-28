import 'money.dart';

class NetWorthAchievement {
  const NetWorthAchievement({
    required this.id,
    required this.name,
    required this.target,
    required this.earned,
  });

  final String id;
  final String name;
  final Money target;
  final bool earned;

  NetWorthAchievement copyWith({bool? earned}) => NetWorthAchievement(
    id: id,
    name: name,
    target: target,
    earned: earned ?? this.earned,
  );
}
