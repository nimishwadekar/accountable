import 'package:flutter/material.dart';

import 'app/app.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends AccountableApp {
  const MyApp({super.key, super.dataRepository, super.configLoader});
}
