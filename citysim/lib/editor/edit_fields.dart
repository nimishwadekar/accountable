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

/// The tile footprint of the first catalogue model using [role], or 1×1
/// when no model references it — the plot a sprite's preview stands on.
(int, int) footprintForRole(Map<String, Object?> categories, String role) {
  for (final model in modelList(categories)) {
    final roles = model['assetRoles'];
    if (roles is List && roles.contains(role)) {
      final footprint = model['footprint'] as Map?;
      return (
        (footprint?['columns'] as num?)?.toInt() ?? 1,
        (footprint?['rows'] as num?)?.toInt() ?? 1,
      );
    }
  }
  return (1, 1);
}

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

/// Slider with an editable number box beside its label: drag for coarse
/// adjustment, type for exact values. The box tracks value changes made
/// elsewhere (slider drags, reverts) but never fights the user mid-typing.
class DoubleSliderField extends StatefulWidget {
  const DoubleSliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.decimals = 3,
    this.divisions,
    this.help,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int decimals;
  final int? divisions;

  /// One-sentence explanation shown beside the label.
  final String? help;

  @override
  State<DoubleSliderField> createState() => _DoubleSliderFieldState();
}

class _DoubleSliderFieldState extends State<DoubleSliderField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value.toStringAsFixed(widget.decimals);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DoubleSliderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync the box when the value moved elsewhere (slider drag,
    // revert), unless the user is mid-typing something unparsable or the
    // box already shows this value.
    final typed = double.tryParse(_controller.text);
    if (typed != null && (typed - widget.value).abs() > 1e-9) {
      _controller.text = widget.value.toStringAsFixed(widget.decimals);
    }
  }

  void _commit(String raw) {
    final parsed = double.tryParse(raw);
    if (parsed == null) return;
    var next = parsed;
    if (next < widget.min) next = widget.min;
    if (next > widget.max) next = widget.max;
    if ((next - widget.value).abs() > 1e-9) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              widget.label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.help != null) FieldHelp(widget.help!),
          const SizedBox(width: 6),
          SizedBox(
            width: 62,
            child: TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
              ),
              style: const TextStyle(fontSize: 12),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: _commit,
            ),
          ),
        ],
      ),
      Slider(
        value: widget.value.clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        label: widget.value.toStringAsFixed(widget.decimals),
        onChanged: widget.onChanged,
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
