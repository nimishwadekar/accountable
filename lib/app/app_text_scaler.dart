import 'package:flutter/painting.dart';

double normalizeAppTextScale(double? value) {
  if (value == null || !value.isFinite) return 1;
  return value.clamp(0.75, 1.5).toDouble();
}

/// Composes the user's app preference with the operating system text scaler.
/// A legacy app reduction cannot undo system-level accessibility enlargement.
final class AccountableTextScaler extends TextScaler {
  const AccountableTextScaler({
    required this.systemScaler,
    required this.appScale,
  });

  final TextScaler systemScaler;
  final double appScale;

  @override
  double scale(double fontSize) {
    final systemSize = systemScaler.scale(fontSize);
    if (appScale < 1 && systemSize > fontSize) return systemSize;
    return systemSize * appScale;
  }

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is AccountableTextScaler &&
      other.systemScaler == systemScaler &&
      other.appScale == appScale;

  @override
  int get hashCode => Object.hash(systemScaler, appScale);
}
