/// Asset-bundle-backed content source for the running game and tests.
library;

import 'package:flutter/services.dart' show rootBundle;

import 'content_bundle.dart';

class AssetContentSource implements ContentSource {
  const AssetContentSource();

  @override
  Future<Map<String, Object?>> readCategory(String fileName) async {
    final raw = await rootBundle.loadString('assets/content/$fileName');
    return decodeJsonObject(raw);
  }
}
