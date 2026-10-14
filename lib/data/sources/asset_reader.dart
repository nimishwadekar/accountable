import 'package:flutter/services.dart';

abstract interface class AssetReader {
  Future<String> readString(String assetPath);
}

class FlutterAssetReader implements AssetReader {
  const FlutterAssetReader();

  @override
  Future<String> readString(String assetPath) {
    return rootBundle.loadString(assetPath);
  }
}
