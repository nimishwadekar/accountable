import 'package:flutter/material.dart';

import '../edit_fields.dart';

/// Catalogue editor: models grouped by category → subcategory in
/// accordions (only one subcategory expanded at a time). Each variant
/// renders as a sprite thumbnail — click it to jump to that sprite's
/// editor, use the × to remove it, and add variants from the matching
/// category/subcategory pair only. Deleting is never offered — disable
/// keeps old saves loadable.
class CataloguePage extends StatefulWidget {
  const CataloguePage({
    required this.categories,
    required this.onChanged,
    required this.onOpenSprite,
    super.key,
  });

  final Map<String, Object?> categories;
  final CategoriesChanged onChanged;
  final void Function(String role) onOpenSprite;

  @override
  State<CataloguePage> createState() => _CataloguePageState();
}

class _CataloguePageState extends State<CataloguePage> {
  /// Key of the expanded subcategory ("category/subcategory"); only one
  /// subcategory is expanded at a time.
  String? _expandedKey;

  @override
  Widget build(BuildContext context) {
    final models = modelList(widget.categories);
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        for (final category in ['buildings', 'decorations'])
          ..._categorySection(category, models),
      ],
    );
  }

  List<Widget> _categorySection(
    String category,
    List<Map<String, Object?>> models,
  ) {
    final spriteCategory = category == 'buildings' ? 'buildings' : 'props';
    final kind = category == 'buildings' ? 'building' : 'decoration';
    final inCategory = models.where((m) => m['kind'] == kind).toList();

    // Subcategories present among the category's models, plus any sprite
    // subcategories with no models yet (so empty groups stay visible).
    final subcategories = <String>{};
    for (final model in inCategory) {
      subcategories.add(model['subcategory'] as String? ?? '');
    }
    for (final meta in spriteMap(widget.categories).values) {
      if (meta is Map &&
          (meta['category'] as String? ?? 'buildings') == spriteCategory) {
        subcategories.add(meta['subcategory'] as String? ?? spriteCategory);
      }
    }
    final ordered = subcategories.toList()..sort();

    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, top: 4, bottom: 6),
        child: Row(
          children: [
            Text(
              category[0].toUpperCase() + category.substring(1),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            Text(
              '${inCategory.length} model(s)',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
      for (final subcategory in ordered)
        AccordionSection(
          title: subcategory,
          count: inCategory
              .where((m) => (m['subcategory'] as String? ?? '') == subcategory)
              .length,
          expanded: _expandedKey == '$spriteCategory/$subcategory',
          onToggle: () => setState(() {
            _expandedKey = _expandedKey == '$spriteCategory/$subcategory'
                ? null
                : '$spriteCategory/$subcategory';
          }),
          child: Column(
            children: [
              for (final model
                  in inCategory
                      .where(
                        (m) =>
                            (m['subcategory'] as String? ?? '') == subcategory,
                      )
                      .toList())
                _modelCard(model),
            ],
          ),
        ),
      const SizedBox(height: 10),
    ];
  }

  Widget _modelCard(Map<String, Object?> model) {
    final id = model['id']! as String;
    final roles = (model['assetRoles'] as List?)?.cast<String>() ?? const [];
    final firstRole = roles.isNotEmpty ? roles.first : '';
    final sprite = (spriteMap(widget.categories)[firstRole] as Map?)
        ?.cast<String, Object?>();
    final isDecoration = model['kind'] == 'decoration';
    final enabled = model['enabled'] != false;
    final footprint = (model['footprint'] as Map?) ?? const {};
    final subcategory = model['subcategory'] as String? ?? '';

    return Card(
      color: enabled ? Colors.white : Colors.grey.shade100,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SpriteFacingsThumb(sprite: sprite, size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${model['name']}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '$id · '
                        '${isDecoration ? 'decoration · instant' : 'building · builder project'}'
                        '${sprite == null ? ' · ⚠ missing sprite' : ''}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                FieldHelp(
                  'Disabled models stay loadable for existing saves but are '
                  'hidden from new purchases and unlock grants.',
                ),
                Switch(
                  value: enabled,
                  onChanged: (value) =>
                      _editModel(id, (model) => model['enabled'] = value),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                SizedBox(
                  width: 110,
                  child: IntField(
                    label: 'Cost',
                    value: asInt(model['costCoins']),
                    min: 0,
                    help:
                        'Coins to fully fund this model. Building plans are '
                        'free and funded coin by coin; decorations are paid '
                        'once at placement.',
                    onChanged: (v) =>
                        _editModel(id, (model) => model['costCoins'] = v),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: IntField(
                    label: 'Population',
                    value: asInt(model['population']),
                    min: 0,
                    help:
                        'Population this model adds once completed. '
                        'Population is the progression metric: it gates '
                        'model unlocks and builder-capacity grants.',
                    onChanged: (v) =>
                        _editModel(id, (model) => model['population'] = v),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: IntField(
                    label: 'Unlock at pop.',
                    value: asInt(model['unlockAtPopulation']),
                    min: 0,
                    help:
                        'Population the settlement must reach before this '
                        'model can be planned. 0 means available from the '
                        'start.',
                    onChanged: (v) => _editModel(
                      id,
                      (model) => model['unlockAtPopulation'] = v,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: IntField(
                    label: 'Cols',
                    value: asInt(footprint['columns'], 1),
                    min: 1,
                    help:
                        'Footprint width in grid cells, counted along the '
                        'street. Non-square lots turn with their door side, '
                        'so this edge is the one that faces the road. Every '
                        'footprint cell needs owned, vacant, road-adjacent '
                        'land.',
                    onChanged: (v) => _editModel(
                      id,
                      (model) => (model['footprint'] as Map)['columns'] = v,
                    ),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: IntField(
                    label: 'Rows',
                    value: asInt(footprint['rows'], 1),
                    min: 1,
                    help:
                        'Ground footprint depth in grid cells, running away '
                        'from the street. Vertical art height is not part of '
                        'the footprint — it comes from the sprite art and '
                        'its scale.',
                    onChanged: (v) => _editModel(
                      id,
                      (model) => (model['footprint'] as Map)['rows'] = v,
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: TextFieldBox(
                    label: 'Display name',
                    value: '${model['name']}',
                    help:
                        'Name shown in the game catalogue and placement '
                        'dialogs.',
                    onChanged: (v) =>
                        _editModel(id, (model) => model['name'] = v),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: _subcategoryDropdown(id, subcategory, isDecoration),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _variantsEditor(id, roles, isDecoration, subcategory),
            const SizedBox(height: 6),
            TextFieldBox(
              label: 'Description (shown in the game catalogue)',
              value: '${model['description']}',
              maxLines: 2,
              help:
                  'Flavour text shown under the model name in the game '
                  'catalogue.',
              onChanged: (v) =>
                  _editModel(id, (model) => model['description'] = v),
            ),
          ],
        ),
      ),
    );
  }

  /// Subcategory picker: options are the subcategories that exist among the
  /// model's sprite category (the current value is kept even if orphaned,
  /// so validation can flag it instead of silently rewriting).
  Widget _subcategoryDropdown(String id, String current, bool isDecoration) {
    final spriteCategory = isDecoration ? 'props' : 'buildings';
    final options = <String>{};
    for (final meta in spriteMap(widget.categories).values) {
      if (meta is Map &&
          (meta['category'] as String? ?? 'buildings') == spriteCategory) {
        options.add(meta['subcategory'] as String? ?? spriteCategory);
      }
    }
    options.add(current);
    final ordered = options.toList()..sort();
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Subcategory',
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: FieldHelp(
          'Sprite group this model draws its variants from. Variants can '
          'only be picked from sprites with the matching '
          'category/subcategory pair.',
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
            _editModel(id, (model) => model['subcategory'] = value),
      ),
    );
  }

  /// Variant sprites shown as a thumbnail table - one tile per sprite
  /// entity, with every door facing rendered together since sides are not
  /// separate variants. Click a tile to edit its sprite (same editor as
  /// the Sprites page), x removes it. The add-tile picker offers only
  /// sprites from the model's category/subcategory pair.
  Widget _variantsEditor(
    String id,
    List<String> roles,
    bool isDecoration,
    String subcategory,
  ) {
    final spriteCategory = isDecoration ? 'props' : 'buildings';
    final sprites = spriteMap(widget.categories);

    final matching =
        sprites.entries
            .where((entry) {
              final meta = entry.value;
              return meta is Map &&
                  (meta['category'] as String? ?? 'buildings') ==
                      spriteCategory &&
                  (meta['subcategory'] as String? ?? spriteCategory) ==
                      subcategory &&
                  !roles.contains(entry.key);
            })
            .map((entry) => entry.key)
            .toList()
          ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Tooltip(
            message:
                'One of these sprite variants is rolled per placement for '
                'color variety. Buildings also pick a door side from the '
                'adjacent road. Variants come from the '
                '$spriteCategory/$subcategory group. Click a variant to '
                'edit its sprite.',
            child: Text(
              'Variants (${roles.length}) - one is rolled per placement:',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final role in roles)
              _variantTile(
                id,
                role,
                canRemove: roles.length > 1,
                sprite: (sprites[role] as Map?)?.cast<String, Object?>(),
              ),
            if (matching.isNotEmpty) _addVariantTile(id, matching),
          ],
        ),
      ],
    );
  }

  Widget _variantTile(
    String id,
    String role, {
    required bool canRemove,
    Map<String, Object?>? sprite,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Stack(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => widget.onOpenSprite(role),
              child: SpriteFacingsThumb(sprite: sprite, size: 56),
            ),
          ),
          if (canRemove)
            Positioned(
              right: 0,
              top: 0,
              child: Material(
                color: Colors.white70,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _editModel(
                    id,
                    (model) => (model['assetRoles'] as List).remove(role),
                  ),
                  child: const Icon(Icons.close_rounded, size: 14),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 2),
      Text(
        role,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 9, fontFamily: 'monospace'),
      ),
    ],
  );

  Widget _addVariantTile(String id, List<String> matching) =>
      PopupMenuButton<String>(
        tooltip: 'Add a sprite variant',
        position: PopupMenuPosition.under,
        constraints: const BoxConstraints(minWidth: 340, maxHeight: 440),
        itemBuilder: (context) => [
          for (final role in matching)
            PopupMenuItem(
              value: role,
              child: Row(
                children: [
                  SpriteFacingsThumb(
                    sprite: (spriteMap(widget.categories)[role] as Map?)
                        ?.cast<String, Object?>(),
                    size: 30,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      role,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        onSelected: (role) =>
            _editModel(id, (model) => (model['assetRoles'] as List).add(role)),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade300),
            color: Colors.green.shade50,
          ),
          child: const Icon(Icons.add_rounded, color: Colors.green),
        ),
      );

  void _editModel(String id, void Function(Map<String, Object?> model) edit) {
    widget.onChanged((categories) {
      final models = ((categories['catalogue.json'] as Map)['models'] as List)
          .cast<Map>()
          .map((m) => m.cast<String, Object?>())
          .toList();
      edit(models.firstWhere((m) => m['id'] == id));
      (categories['catalogue.json'] as Map)['models'] = models;
    });
  }
}
