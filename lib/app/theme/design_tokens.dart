import 'package:flutter/material.dart';

abstract final class AppColors {
  static const navy = Color(0xFF12304A);
  static const teal = Color(0xFF0F766E);
  static const success = Color(0xFF17824B);
  static const danger = Color(0xFFB42318);
  static const warning = Color(0xFFB54708);
  static const background = Color(0xFFF7F9FC);
  static const border = Color(0xFFD9E1EA);
  static const mutedText = Color(0xFF667085);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class AppRadii {
  static const card = 16.0;
  static const control = 12.0;
  static const pill = 999.0;
}

abstract final class AppBreakpoints {
  static const compact = 600.0;
  static const medium = 840.0;
  static const maxContentWidth = 1200.0;
}
