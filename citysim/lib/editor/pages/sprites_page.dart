import 'package:flutter/material.dart';

import '../edit_fields.dart';
import '../preview_widgets.dart';

/// Sprite editor organized by category → subcategory accordions (mirroring
/// the catalogue page and the disk layout; only one subcategory expanded
/// at a time). Sprites own the taxonomy: each card can edit its category
/// and subcategory, and creating a new subcategory name here makes it
/// available to catalogue models. A sprite's door facings are one entity —
/// every setting is shared by both sides and only the art differs.
/// Code-referenced roles (terrain, shores, road masks, bridges) show a
/// lock badge — their names are constructed in game code and cannot be
/// renamed here.
class SpritesPage extends StatefulWidget {
  const SpritesPage({
    required this.categories,
    required this.onChanged,
    this.focusRole,
    super.key,
  });

  final Map<String, Object?> categories;
  final CategoriesChanged onChanged;

  /// Sprite role to focus on open (set when the user clicks a catalogue
  /// variant). Selects its category, expands its subcategory, scrolls to
  /// it, and highlights it.
  final String? focusRole;

  @override
  State<SpritesPage> createState() => _SpritesPageState();
}

class _SpritesPageState extends State<SpritesPage> {
  String _selectedCategory = 'buildings';
  final GlobalKey _focusKey = GlobalKey();

  /// Key of the expanded subcategory within the selected category; only
  /// one subcategory is expanded at a time.
  String? _expandedSubcategory;

  @override
  void initState() {
    super.initState();
    final role = widget.focusRole;
    if (role != null) {
      final meta = spriteMap(widget.categories)[role];
      if (meta is Map) {
        _selectedCategory = (meta['category'] as String?) ?? 'buildings';
        _expandedSubcategory =
            (meta['subcategory'] as String?) ?? _selectedCategory;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _focusKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sprites = spriteMap(widget.categories);
    final categories = <String>{
      ...sprites.entries.map((entry) {
        final meta = entry.value;
        return (meta is Map)
            ? (meta['category'] as String? ?? 'buildings')
            : 'buildings';
      }),
      'ground',
      'shores',
      'roads',
      'bridges',
      'buildings',
      'props',
    };
    final ordered = categories.toList()..sort();

    // Group the selected category's sprites by subcategory.
    final inCategory = <String, List<MapEntry<String, Map<String, Object?>>>>{};
    for (final entry in sprites.entries) {
      final meta = entry.value;
      if (meta is! Map) continue;
      if ((meta['category'] as String? ?? 'buildings') != _selectedCategory) {
        continue;
      }
      final subcategory = (meta['subcategory'] as String?) ?? _selectedCategory;
      inCategory
          .putIfAbsent(subcategory, () => [])
          .add(MapEntry(entry.key, meta.cast<String, Object?>()));
    }
    for (final list in inCategory.values) {
      list.sort((a, b) => a.key.compareTo(b.key));
    }
    final orderedSubcategories = inCategory.keys.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            children: [
              for (final category in ordered)
                ChoiceChip(
                  label: Text(category),
                  visualDensity: VisualDensity.compact,
                  selected: _selectedCategory == category,
                  onSelected: (_) => setState(() {
                    _selectedCategory = category;
                    _expandedSubcategory = null;
                  }),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            children: [
              for (final subcategory in orderedSubcategories)
                AccordionSection(
                  title: subcategory,
                  count: inCategory[subcategory]!.length,
                  expanded: _expandedSubcategory == subcategory,
                  onToggle: () => setState(() {
                    _expandedSubcategory = _expandedSubcategory == subcategory
                        ? null
                        : subcategory;
                  }),
                  child: Column(
                    children: [
                      for (final entry in inCategory[subcategory]!)
                        KeyedSubtree(
                          key: entry.key == widget.focusRole ? _focusKey : null,
                          child: _spriteCard(
                            entry.key,
                            entry.value,
                            focused: entry.key == widget.focusRole,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _spriteCard(
    String role,
    Map<String, Object?> meta, {
    focused = false,
  }) {
    final pathEntries = spritePathEntries(meta);
    final anchor = ((meta['groundAnchor'] as List?) ?? const [0.5, 1.0]);
    final codeReferenced = meta['codeReferenced'] == true;
    final category = (meta['category'] as String? ?? 'buildings');
    final subcategory = (meta['subcategory'] as String? ?? category);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: focused ? Colors.green.shade50 : null,
      shape: focused
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.green.shade400, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Every door facing of the sprite renders here; the settings
            // to the right are shared by all of them.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (label, path) in pathEntries) ...[
                  if (label.isNotEmpty)
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  SpriteThumb(path: path, size: 52),
                  const SizedBox(height: 4),
                ],
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          role,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (codeReferenced)
                        Tooltip(
                          message:
                              'This role name is constructed in game code; '
                              'renaming it would break rendering. Only its '
                              'metadata is editable.',
                          child: Chip(
                            avatar: const Icon(Icons.lock_rounded, size: 12),
                            label: const Text(
                              'code',
                              style: TextStyle(fontSize: 10),
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                    ],
                  ),
                  Text(
                    pathEntries.map((entry) => entry.$2).join('  |  '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  // The sprite on its plot, placed exactly as the game
                  // places it — tune scale and anchor here and watch it
                  // settle live instead of hot-restarting the game. The
                  // road-side selection is controlled so the per-side
                  // shift fields below always edit the side the plot
                  // shows.
                  SpritePlotPreview(
                    categories: widget.categories,
                    role: role,
                    roadSide: _roadSides[role] ?? 'south',
                    onRoadSideChanged: (side) =>
                        setState(() => _roadSides[role] = side),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      SizedBox(
                        width: 150,
                        child: _categoryDropdown(role, category),
                      ),
                      SizedBox(
                        width: 150,
                        child: TextFieldBox(
                          label: 'Subcategory',
                          value: subcategory,
                          help:
                              'Group within the category. Catalogue models '
                              'pick variants only from sprites sharing this '
                              'subcategory; typing a new name creates a new '
                              'group.',
                          onChanged: (v) => _editRole(
                            role,
                            (sprite) => sprite['subcategory'] = v,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: DoubleField(
                          label: 'Scale',
                          value: asDouble(meta['renderScale'], 0.5),
                          min: 0.05,
                          help:
                              'Art scaling factor. 0.5 renders the '
                              "pack's 128px art at one tile; smaller values "
                              'shrink the sprite.',
                          onChanged: (v) => _editRole(
                            role,
                            (sprite) => sprite['renderScale'] = v,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: DoubleField(
                          label: 'Offset Y',
                          value: asDouble(meta['baseOffsetY']),
                          min: 0,
                          help:
                              'Pixels of art hanging below the ground '
                              'diamond (for example bridge support posts). '
                              'The renderer shifts the sprite down by this '
                              'amount.',
                          onChanged: (v) => _editRole(
                            role,
                            (sprite) => sprite['baseOffsetY'] = v,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: DoubleSliderField(
                          label: 'Anchor X',
                          value: asDouble(anchor[0], 0.5),
                          min: 0,
                          max: 1,
                          divisions: 100,
                          help:
                              'Horizontal point of the art pinned to the '
                              'footprint, as a fraction of image width '
                              '(0.5 = centred). Drag the slider or type an '
                              'exact value.',
                          onChanged: (v) => _editRole(role, (sprite) {
                            if (sprite['groundAnchor'] is! List) {
                              sprite['groundAnchor'] = [0.5, 1.0];
                            }
                            (sprite['groundAnchor'] as List)[0] = v;
                          }),
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: DoubleSliderField(
                          label: 'Anchor Y',
                          value: asDouble(anchor.length > 1 ? anchor[1] : 1, 1),
                          min: 0,
                          max: 1,
                          divisions: 100,
                          help:
                              'Vertical point of the art pinned to the '
                              'footprint, as a fraction of image height '
                              '(1 = bottom edge rests on the ground). Drag '
                              'the slider or type an exact value.',
                          onChanged: (v) => _editRole(role, (sprite) {
                            if (sprite['groundAnchor'] is! List) {
                              sprite['groundAnchor'] = [0.5, 1.0];
                            }
                            (sprite['groundAnchor'] as List)[1] = v;
                          }),
                        ),
                      ),
                      // Only facings sprites shift per road side —
                      // their structures are the ones that save a
                      // facing. The sliders edit the side the plot
                      // preview above is showing.
                      if (pathEntries.any((entry) => entry.$1.isNotEmpty)) ...[
                        SizedBox(
                          width: 210,
                          child: DoubleSliderField(
                            label:
                                'Shift E–W · ${_roadSides[role] ?? 'south'} side',
                            value: _sideShiftValue(
                              meta,
                              _roadSides[role] ?? 'south',
                              0,
                            ),
                            min: -0.5,
                            max: 0.5,
                            divisions: 100,
                            help:
                                'Slides the art east (positive) or west '
                                '(negative) for this road side, in '
                                'fractions of the sprite width. Pick the '
                                'road side on the plot preview above, then '
                                'drag — the preview follows live.',
                            onChanged: (v) => _editSideShift(
                              role,
                              _roadSides[role] ?? 'south',
                              0,
                              v,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 210,
                          child: DoubleSliderField(
                            label:
                                'Shift N–S · ${_roadSides[role] ?? 'south'} side',
                            value: _sideShiftValue(
                              meta,
                              _roadSides[role] ?? 'south',
                              1,
                            ),
                            min: -0.5,
                            max: 0.5,
                            divisions: 100,
                            help:
                                'Slides the art south (positive) or north '
                                '(negative) for this road side — hug the '
                                'road with the sign that matches it, in '
                                'fractions of the sprite width.',
                            onChanged: (v) => _editSideShift(
                              role,
                              _roadSides[role] ?? 'south',
                              1,
                              v,
                            ),
                          ),
                        ),
                      ],
                      // Only props sway in the wind; the option stays
                      // hidden for every other category.
                      if (category == 'props')
                        SizedBox(
                          width: 190,
                          child: SwitchListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Flexible(
                                  child: Text(
                                    'Sways in wind',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                FieldHelp(
                                  'Gently rocks the sprite around its '
                                  'ground anchor to suggest wind. Only '
                                  'props may sway.',
                                ),
                              ],
                            ),
                            value: meta['sways'] == true,
                            onChanged: (v) => _editRole(
                              role,
                              (sprite) => sprite['sways'] = v,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Category dropdown: moving a sprite between categories regroups it in
  /// both the editor and (after save) the game's asset organization.
  Widget _categoryDropdown(String role, String current) {
    final options = <String>{
      'ground',
      'shores',
      'roads',
      'bridges',
      'buildings',
      'props',
      current,
    };
    final ordered = options.toList()..sort();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Category',
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: FieldHelp(
          'Top-level group. Building models draw from "buildings" and '
          'decorations from "props"; the disk layout under '
          'assets/sprites/ mirrors it.',
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 22,
          minHeight: 22,
        ),
      ),
      child: DropdownButton<String>(
        value: current,
        isDense: true,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: [
          for (final option in ordered)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (value) =>
            _editRole(role, (sprite) => sprite['category'] = value),
      ),
    );
  }

  void _editRole(String role, void Function(Map<String, Object?> sprite) edit) {
    widget.onChanged((categories) {
      final sprites = (categories['sprites.json'] as Map)['sprites'] as Map;
      final sprite = (sprites[role] as Map).cast<String, Object?>();
      edit(sprite);
    });
  }

  /// The road side each role's plot preview is showing.
  final Map<String, String> _roadSides = {};

  /// One component of a side's shift entry, straight from the raw
  /// sprite map; missing entries read as zero.
  double _sideShiftValue(Map<String, Object?> meta, String side, int index) {
    final shifts = meta['sideShifts'];
    if (shifts is! Map) return 0;
    final entry = shifts[side];
    if (entry is! List || entry.length <= index) return 0;
    return asDouble(entry[index]);
  }

  /// Writes one component of a side's shift entry, creating the side's
  /// `[col, row]` list (and the sideShifts map) on first edit.
  void _editSideShift(String role, String side, int index, double value) {
    _editRole(role, (sprite) {
      var map = sprite['sideShifts'];
      if (map is! Map) {
        map = <String, Object?>{};
        sprite['sideShifts'] = map;
      }
      final entry = map[side];
      final list = entry is List ? entry : (map[side] = [0.0, 0.0]);
      while (list.length < 2) {
        list.add(0.0);
      }
      list[index] = value;
    });
  }
}
