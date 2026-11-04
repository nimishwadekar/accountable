/// Filesystem-backed content source for the editor server.
///
/// Server-side only: the game reads content from bundled assets, so this
/// file must never be imported by web-compiled code.
library;

import 'dart:convert';
import 'dart:io';

import 'package:citysim/content/content_bundle.dart';

class FileContentSource implements ContentSource {
  FileContentSource(this.contentDirectory);

  final Directory contentDirectory;

  @override
  Future<Map<String, Object?>> readCategory(String fileName) async {
    final file = File(
      '${contentDirectory.path}${Platform.pathSeparator}$fileName',
    );
    if (!await file.exists()) {
      throw FormatException('Missing content file: $fileName');
    }
    return decodeJsonObject(await file.readAsString());
  }
}

/// Validates that every sprite art file exists on disk under the assets
/// directory — one file per door facing where sprites carry them.
/// File-existence checks are server-only: the running game cannot list
/// assets.
List<String> checkSpriteFiles({
  required Map<String, SpriteDefinition> sprites,
  required Directory packDirectory,
}) {
  final issues = <String>[];
  for (final entry in sprites.entries) {
    for (final relative in entry.value.allPaths) {
      final file = File(
        '${packDirectory.path}${Platform.pathSeparator}$relative',
      );
      if (!file.existsSync()) {
        issues.add('Sprite "${entry.key}" points at a missing file: $relative');
      }
    }
  }
  return issues;
}

Map<String, Object?> readJsonFile(File file) =>
    decodeJsonObject(file.readAsStringSync());

Future<void> writeJsonFileAtomic(File file, Map<String, Object?> data) async {
  final encoded = const JsonEncoder.withIndent('  ').convert(data);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(encoded);
  await temp.rename(file.path);
}
