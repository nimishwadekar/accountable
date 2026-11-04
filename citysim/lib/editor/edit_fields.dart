import 'package:flutter/material.dart';

import 'content_api.dart';

/// Shared editing helpers for the category pages. All editors mutate the
/// raw category maps directly — the dashboard treats JSON as data, and
/// validation happens server-side through the shared game models.

typedef CategoriesChanged = void Function(
  void Function(Map<String, Object?> categories),
);

List<Map<String, Object?>> modelList(Map<String, Object?> categories) {
  final list = (categories['catalogue.json'] as Map?)?['models'] as List?;
  return list
          ?.cast<Map>()
          .map((model) => model.cast<String, Object?>())
          .toList() ??
      const [];
}

Map<String, Object?> spriteMap(Map<String, Object?> categories) {
  final map = (categories['sprites.json'] as Map?)?['sprites'] as Map?;
  return map?.cast<String, Object?>() ?? const {};
}

/// (label, path) entries for every art file behind a sprite entity: one
/// per door facing — left and right share all settings and are edited as
/// one — or the sprite's single path with an empty label.
List<(String, String)> spritePathEntries(Map<String, Object?> sprite) {
  final facings = sprite['facings'] as Map?;
  if (facings != null) {
    final entries = [
      for (final entry in facings.entries)
        (entry.key as String, entry.value as String),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return entries;
  }
  final path = sprite['path'] as String?;
  return path == null ? const [] : [('', path)];
}

Map<String, Object?> economyMap(Map<String, Object?> categories) =>
    (categories['economy.json'] as Map?)?.cast<String, Object?>() ?? const {};

Map<String, Object?> ambienceMap(Map<String, Object?> categories) =>
    (categories['ambience.json'] as Map?)?.cast<String, Object?>() ?? const {};

Map<String, Object?> subMap(Map<String, Object?> source, String key) =>
    (source[key] as Map?)?.cast<String, Object?>() ?? {};

int asInt(Object? value, [int fallback = 0]) =>
    value is int ? value : (value is num ? value.toInt() : fallback);

double asDouble(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;

/// Small help icon shown beside an editable field. Hovering (or
/// long-pressing) reveals a one-sentence explanation of what the field
/// does in the game.
class FieldHelp extends StatelessWidget {
  const FieldHelp(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Field help',
    tooltip: message,
    child: Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 200),
      child: const Icon(Icons.help_outline_rounded, size: 15),
    ),
  );
}

/// Numeric text field bound to an int slot inside the category maps.
class IntField extends StatelessWidget {
  const IntField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.help,
    super.key,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int? min;
  final int? max;

  /// One-sentence explanation shown by the trailing help icon.
  final String? help;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: '$value',
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: help == null ? null : FieldHelp(help!),
      suffixIconConstraints: const BoxConstraints(minWidth: 22, minHeight: 22),
    ),
    keyboardType: TextInputType.number,
    onChanged: (raw) {
      final parsed = int.tryParse(raw);
      if (parsed == null) return;
      var next = parsed;
      if (min != null && next < min!) next = min!;
      if (max != null && next > max!) next = max!;
      onChanged(next);
    },
  );
}

/// Numeric text field bound to a double slot inside the category maps.
class DoubleField extends StatelessWidget {
  const DoubleField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min,
    this.max,
    this.decimals = 3,
    this.help,
    super.key,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double? min;
  final double? max;
  final int decimals;

  /// One-sentence explanation shown by the trailing help icon.
  final String? help;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: value.toStringAsFixed(decimals),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: help == null ? null : FieldHelp(help!),
      suffixIconConstraints: const BoxConstraints(minWidth: 22, minHeight: 22),
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (raw) {
      final parsed = double.tryParse(raw);
      if (parsed == null) return;
      var next = parsed;
      if (min != null && next < min!) next = min!;
      if (max != null && next > max!) next = max!;
      onChanged(next);
    },
  );
}

/// Slider bound to a double slot.
class DoubleSlider extends StatelessWidget {
  const DoubleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.displayValue,
    this.help,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final String Function(double)? displayValue;

  /// One-sentence explanation shown beside the label.
  final String? help;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              '$label  ${displayValue?.call(value) ?? value.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          if (help != null) FieldHelp(help!),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: displayValue?.call(value) ?? value.toStringAsFixed(2),
        onChanged: onChanged,
      ),
    ],
  );
}

/// Editable text field bound to a string slot.
class TextFieldBox extends StatelessWidget {
  const TextFieldBox({
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.help,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;

  /// One-sentence explanation shown by the trailing help icon.
  final String? help;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: help == null ? null : FieldHelp(help!),
      suffixIconConstraints: const BoxConstraints(minWidth: 22, minHeight: 22),
    ),
    maxLines: maxLines,
    onChanged: onChanged,
  );
}

/// Collapsible section used by the catalogue and sprites pages. Only one
/// subcategory section is expanded at a time (managed by the page).
class AccordionSection extends StatelessWidget {
  const AccordionSection({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.child,
    super.key,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: expanded ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: Colors.green.shade800,
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.green.shade900,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count item(s)',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
      AnimatedCrossFade(
        duration: const Duration(milliseconds: 150),
        crossFadeState: expanded
            ? CrossFadeState.showSecond
            : CrossFadeState.showFirst,
        firstChild: const SizedBox(width: double.infinity),
        secondChild: Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: child,
        ),
      ),
    ],
  );
}

/// Small sprite thumbnail served by the editor server.
class SpriteThumb extends StatelessWidget {
  const SpriteThumb({required this.path, this.size = 64, super.key});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.green.shade100),
    ),
    clipBehavior: Clip.antiAlias,
    child: Image.network(
      ContentApi().assetUrl(path),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.broken_image_outlined, size: 20, color: Colors.grey),
    ),
  );
}

/// Every door facing of a sprite entity rendered side by side — one
/// thumb for single sprites, left and right together for buildings.
/// Takes the raw sprite map from the category JSON (null shows a
/// broken-image placeholder).
class SpriteFacingsThumb extends StatelessWidget {
  const SpriteFacingsThumb({required this.sprite, this.size = 64, super.key});

  final Map<String, Object?>? sprite;
  final double size;

  @override
  Widget build(BuildContext context) {
    final meta = sprite;
    if (meta == null) return SpriteThumb(path: '', size: size);
    final entries = spritePathEntries(meta);
    if (entries.length == 1) {
      return SpriteThumb(path: entries.single.$2, size: size);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const SizedBox(width: 2),
          SpriteThumb(path: entries[index].$2, size: size),
        ],
      ],
    );
  }
}
