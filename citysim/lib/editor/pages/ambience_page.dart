import 'package:flutter/material.dart';

import '../edit_fields.dart';
import '../preview_widgets.dart';

/// Ambience editor: sliders for every ambient animation value, each with a
/// live preview beside it. Sliders flow horizontally to use wide screens.
/// The values flow into the game through ambience.json exactly as the old
/// tuning constants did.
class AmbiencePage extends StatefulWidget {
  const AmbiencePage({
    required this.categories,
    required this.onChanged,
    super.key,
  });

  final Map<String, Object?> categories;
  final CategoriesChanged onChanged;

  @override
  State<AmbiencePage> createState() => _AmbiencePageState();
}

class _AmbiencePageState extends State<AmbiencePage> {
  @override
  Widget build(BuildContext context) {
    final ambience = ambienceMap(widget.categories);
    final shimmer = subMap(ambience, 'waterShimmer');
    final sway = subMap(ambience, 'vegetationSway');
    final pedestrians = subMap(ambience, 'pedestrians');
    final wash = subMap(ambience, 'unownedLandWash');

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _section(
          'Global time scale',
          [
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Time scale',
                value: asDouble(ambience['ambientTimeScale'], 1),
                min: 0.1,
                max: 3,
                divisions: 29,
                help:
                    'Multiplier on the ambient clock: 1.0 is real time, '
                    '0.5 halves water, wind, and pedestrian speed together.',
                onChanged: (v) => _edit((a) => a['ambientTimeScale'] = v),
              ),
            ),
          ],
          description:
              '1.0 is real time; 0.5 halves water, wind, and '
              'pedestrian speed together.',
        ),
        _section(
          'Water shimmer',
          [
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Sweep period (s)',
                value: asDouble(shimmer['periodSeconds'], 6.5),
                min: 1,
                max: 20,
                divisions: 38,
                help:
                    'Seconds for one shimmer sweep across the water. '
                    'Longer is calmer.',
                onChanged: (v) => _edit(
                  (a) => (a['waterShimmer'] as Map)['periodSeconds'] = v,
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Peak opacity',
                value: asDouble(shimmer['maxOpacity'], 0.08),
                min: 0.01,
                max: 0.3,
                divisions: 29,
                help:
                    'Maximum overlay opacity of a shimmer band at its '
                    'brightest moment.',
                onChanged: (v) =>
                    _edit((a) => (a['waterShimmer'] as Map)['maxOpacity'] = v),
              ),
            ),
            SizedBox(
              width: 150,
              child: IntField(
                label: 'Bands',
                value: asInt(shimmer['bands'], 6),
                min: 1,
                max: 16,
                help: 'Number of diagonal highlight bands across the water.',
                onChanged: (v) =>
                    _edit((a) => (a['waterShimmer'] as Map)['bands'] = v),
              ),
            ),
            WaterShimmerPreview(
              period: asDouble(shimmer['periodSeconds'], 6.5),
              maxOpacity: asDouble(shimmer['maxOpacity'], 0.08),
              bands: asInt(shimmer['bands'], 6),
            ),
          ],
          description:
              'Diagonal highlight bands sweeping the water. More '
              'bands or a longer period gives calmer ripples.',
        ),
        _section(
          'Vegetation sway',
          [
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Max angle (rad)',
                value: asDouble(sway['maxAngleRadians'], 0.045),
                min: 0,
                max: 0.15,
                divisions: 30,
                help: 'Largest rotation vegetation reaches, in radians.',
                onChanged: (v) => _edit(
                  (a) => (a['vegetationSway'] as Map)['maxAngleRadians'] = v,
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Base frequency (rad/s)',
                value: asDouble(sway['baseFrequency'], 1.1),
                min: 0.2,
                max: 4,
                divisions: 38,
                help:
                    'Sway speed in radians per second; each tile adds a '
                    'small step so neighbours move out of step.',
                onChanged: (v) => _edit(
                  (a) => (a['vegetationSway'] as Map)['baseFrequency'] = v,
                ),
              ),
            ),
            SwayPreview(
              maxAngle: asDouble(sway['maxAngleRadians'], 0.045),
              frequency: asDouble(sway['baseFrequency'], 1.1),
            ),
          ],
          description:
              'Trees and flowers rock around their ground anchor; '
              'phase varies per tile so neighbours move out of step.',
        ),
        _section(
          'Ambient pedestrians',
          [
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Walk frame rate (fps)',
                value: asDouble(pedestrians['walkFrameRate'], 7),
                min: 1,
                max: 15,
                divisions: 28,
                help:
                    'Animation frames per second of the pedestrian walk '
                    'cycle.',
                onChanged: (v) => _edit(
                  (a) => (a['pedestrians'] as Map)['walkFrameRate'] = v,
                ),
              ),
            ),
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Sprite scale',
                value: asDouble(pedestrians['spriteScale'], 0.7),
                min: 0.2,
                max: 3,
                divisions: 28,
                help: 'Size multiplier of pedestrian art relative to a tile.',
                onChanged: (v) =>
                    _edit((a) => (a['pedestrians'] as Map)['spriteScale'] = v),
              ),
            ),
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Min speed (cells/s)',
                value: asDouble(pedestrians['speedMin'], 0.55),
                min: 0.1,
                max: 2,
                divisions: 19,
                help: 'Slowest walking speed, in grid cells per second.',
                onChanged: (v) =>
                    _edit((a) => (a['pedestrians'] as Map)['speedMin'] = v),
              ),
            ),
            SizedBox(
              width: 240,
              child: DoubleSlider(
                label: 'Speed range',
                value: asDouble(pedestrians['speedRange'], 0.35),
                min: 0,
                max: 1.5,
                divisions: 15,
                help:
                    'Random extra speed added on top of the minimum, so '
                    'pedestrians overtake each other.',
                onChanged: (v) =>
                    _edit((a) => (a['pedestrians'] as Map)['speedRange'] = v),
              ),
            ),
            SizedBox(
              width: 200,
              child: IntField(
                label: 'Per N road cells',
                value: asInt(pedestrians['roadCellsPerPerson'], 6),
                min: 1,
                help:
                    'One pedestrian spawns per this many connected road '
                    'cells.',
                onChanged: (v) => _edit(
                  (a) => (a['pedestrians'] as Map)['roadCellsPerPerson'] = v,
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: IntField(
                label: 'Max count',
                value: asInt(pedestrians['maxCount'], 10),
                min: 0,
                help:
                    'Hard cap on simultaneous pedestrians. 0 turns them '
                    'off.',
                onChanged: (v) =>
                    _edit((a) => (a['pedestrians'] as Map)['maxCount'] = v),
              ),
            ),
            WalkCyclePreview(
              frameRate: asDouble(pedestrians['walkFrameRate'], 7),
              spriteScale: asDouble(pedestrians['spriteScale'], 0.7),
            ),
          ],
          description:
              'People wander connected roads using the pack\'s walk '
              'cycles; density scales with road count.',
        ),
        _section(
          'Unowned-land wash',
          [
            _RgbFields(
              alpha: asInt(wash['alpha'], 79),
              rgb: ((wash['colorRgb'] as List?) ?? const [181, 220, 207])
                  .map((v) => asInt(v))
                  .toList(),
              onChangedAlpha: (v) =>
                  _edit((a) => (a['unownedLandWash'] as Map)['alpha'] = v),
              onChangedRgb: (index, v) => _edit(
                (a) => (a['unownedLandWash'] as Map)['colorRgb'] = [
                  for (var i = 0; i < 3; i++)
                    i == index
                        ? v
                        : asInt(
                            ((a['unownedLandWash'] as Map)['colorRgb']
                                as List)[i],
                          ),
                ],
              ),
            ),
          ],
          description:
              'Fades unowned land toward the map background once '
              'per composed cell.',
        ),
      ],
    );
  }

  void _edit(void Function(Map<String, Object?> ambience) edit) {
    widget.onChanged((categories) {
      final ambience = (categories['ambience.json'] as Map)
          .cast<String, Object?>();
      edit(ambience);
      categories['ambience.json'] = ambience;
    });
  }

  Widget _section(
    String title,
    List<Widget> editor, {
    String description = '',
  }) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (description.isNotEmpty) ...[
            Text(
              description,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: editor,
          ),
        ],
      ),
    ),
  );
}

class _RgbFields extends StatelessWidget {
  const _RgbFields({
    required this.alpha,
    required this.rgb,
    required this.onChangedAlpha,
    required this.onChangedRgb,
  });

  final int alpha;
  final List<int> rgb;
  final ValueChanged<int> onChangedAlpha;
  final void Function(int index, int value) onChangedRgb;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        width: 130,
        child: IntField(
          label: 'Alpha (0-255)',
          value: alpha,
          min: 0,
          max: 255,
          help: 'Wash strength over unowned cells; 0 hides the wash.',
          onChanged: onChangedAlpha,
        ),
      ),
      for (var index = 0; index < 3; index++)
        SizedBox(
          width: 110,
          child: IntField(
            label:
                'RGB[${index == 0
                    ? 'R'
                    : index == 1
                    ? 'G'
                    : 'B'}]',
            value: rgb.length > index ? rgb[index] : 181,
            min: 0,
            max: 255,
            help: 'Wash colour channel, 0-255.',
            onChanged: (v) => onChangedRgb(index, v),
          ),
        ),
      Container(
        width: 90,
        height: 34,
        decoration: BoxDecoration(
          color: Color.fromARGB(
            alpha,
            rgb.isNotEmpty ? rgb[0] : 181,
            rgb.length > 1 ? rgb[1] : 220,
            rgb.length > 2 ? rgb[2] : 207,
          ),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black26),
        ),
      ),
    ],
  );
}
