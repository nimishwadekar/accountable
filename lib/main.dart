import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';
import 'app/navigation_history.dart';

void main() {
  usePathUrlStrategy();
  NavigationHistory.captureInitialPath();
  runApp(const MyApp());
}

class MyApp extends AccountableApp {
  const MyApp({super.key, super.dataRepository, super.configLoader});
}
