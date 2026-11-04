/// The loaded content bundle: typed access over the JSON content layer.
///
/// The game loads exactly one bundle at startup (from bundled assets) and
/// every rule, reducer, renderer, and test reads from it. The editor
/// server loads the same files from disk, so both sides always agree on
/// what the content means.
library;

import 'dart:convert';

import '../world/coordinates.dart';
import 'content_models.dart';

export 'content_models.dart';

/// Reads the raw category files of the content layer.
abstract interface class ContentSource {
  /// Reads and decodes a category file such as `catalogue.json`.
  Future<Map<String, Object?>> readCategory(String fileName);
}

class ContentBundle {
  const ContentBundle({
    required this.manifest,
    required this.catalogue,
    required this.sprites,
    required this.economy,
    required this.ambience,
  });

  final ContentManifest manifest;
  final List<StructureDefinition> catalogue;
  final Map<String, SpriteDefinition> sprites;
  final EconomyContent economy;
  final AmbienceContent ambience;

  /// Root that sprite paths are resolved against.
  static const packRoot = 'assets';

  StructureDefinition? structure(String id) {
    for (final model in catalogue) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// Enabled models only — what new purchases and unlock grants see.
  Iterable<StructureDefinition> get purchaseableModels =>
      catalogue.where((model) => model.enabled);

  SpriteDefinition? sprite(String role) => sprites[role];

  /// Full asset path for a sprite role, or null when the role is unknown.
  /// Single-facing sprites ignore [facing].
  String? tryAssetPathFor(String role, String? facing) {
    final sprite = sprites[role];
    return sprite == null ? null : '$packRoot/${sprite.pathFor(facing)}';
  }

  String? tryAssetPath(String role) => tryAssetPathFor(role, null);

  /// Every art file behind a role (both door facings when present), with
  /// the assets-root prefix. Empty for unknown roles.
  List<String> allAssetPaths(String role) {
    final sprite = sprites[role];
    if (sprite == null) return const [];
    return [for (final path in sprite.allPaths) '$packRoot/$path'];
  }

  /// Strict variant for call sites that assert the role exists.
  String assetPath(String role) => tryAssetPath(role)!;

  int roadTileCost() => economy.roadTileCostCoins;

  int parcelCost(ParcelCoord coord, int ownedCount) =>
      economy.parcelBaseCoins +
      ((coord.x.abs() + coord.y.abs()) ~/ economy.parcelDistanceStepCells) +
      (((ownedCount - 1).clamp(0, 100)) ~/ economy.parcelOwnedStepParcels);

  /// Population-sorted model list for progression previews.
  List<StructureDefinition> get progressionOrder {
    final models = [...catalogue];
    models.sort((a, b) {
      final byUnlock = a.unlockAtPopulation.compareTo(b.unlockAtPopulation);
      return byUnlock != 0 ? byUnlock : a.id.compareTo(b.id);
    });
    return models;
  }

  Map<String, Object?> toRawJson() => {
    'manifest': manifest.toJson(),
    'catalogue': {
      'models': [for (final model in catalogue) model.toJson()],
    },
    'sprites': {
      'sprites': {
        for (final entry in sprites.entries) entry.key: entry.value.toJson(),
      },
    },
    'economy': economy.toJson(),
    'ambience': ambience.toJson(),
  };
}

/// Parses a full content bundle from already-decoded category maps.
/// Throws [FormatException] on malformed data; structural issues are also
/// collected by [validateContentData] for callers that want warnings.
ContentBundle parseContentBundle({
  required Map<String, Object?> manifest,
  required Map<String, Object?> catalogue,
  required Map<String, Object?> sprites,
  required Map<String, Object?> economy,
  required Map<String, Object?> ambience,
}) {
  final bundle = ContentBundle(
    manifest: ContentManifest.fromJson(manifest),
    catalogue: [
      for (final model in catalogue['models']! as List)
        StructureDefinition.fromJson((model as Map).cast<String, Object?>()),
    ],
    sprites: {
      for (final entry in (sprites['sprites']! as Map).entries)
        entry.key as String: SpriteDefinition.fromJson(
          (entry.value as Map).cast<String, Object?>(),
        ),
    },
    economy: EconomyContent.fromJson(economy),
    ambience: AmbienceContent.fromJson(ambience),
  );
  final issues = validateContentData(
    catalogue: bundle.catalogue,
    sprites: bundle.sprites,
    economy: bundle.economy,
    ambience: bundle.ambience,
  );
  final errors = issues.where((issue) => issue.severity == 'error').toList();
  if (errors.isNotEmpty) {
    throw FormatException('Invalid game content: ${errors.first.message}');
  }
  return bundle;
}

/// Loads and validates the content bundle from a [ContentSource].
Future<ContentBundle> loadContentBundle(ContentSource source) async {
  final manifest = await source.readCategory('manifest.json');
  final catalogue = await source.readCategory('catalogue.json');
  final sprites = await source.readCategory('sprites.json');
  final economy = await source.readCategory('economy.json');
  final ambience = await source.readCategory('ambience.json');
  return parseContentBundle(
    manifest: manifest,
    catalogue: catalogue,
    sprites: sprites,
    economy: economy,
    ambience: ambience,
  );
}

Map<String, Object?> decodeJsonObject(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Content file is not a JSON object.');
  }
  return decoded.cast<String, Object?>();
}
