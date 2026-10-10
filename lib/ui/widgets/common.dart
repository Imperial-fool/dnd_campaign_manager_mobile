import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/effect.dart';
import 'package:dnd_campaign_manager/ui/theme.dart';

String signed(int n) => n >= 0 ? '+$n' : '$n';

class SheetCard extends StatelessWidget {
  const SheetCard(
      {super.key,
      required this.title,
      required this.child,
      this.actions = const []});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
        color: kPanel,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(title.toUpperCase(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ),
                ...actions,
              ]),
              const Divider(height: 18),
              child,
            ],
          ),
        ),
      );
}

/// Text field that edits a string owned by the model. Keeps its own
/// TextEditingController so the cursor never jumps while typing.
class TextBinding extends StatefulWidget {
  const TextBinding({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final int? minLines;
  final bool enabled;

  @override
  State<TextBinding> createState() => _TextBindingState();
}

class _TextBindingState extends State<TextBinding> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(TextBinding old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BindingLabel(widget.label),
          TextField(
            controller: _c,
            focusNode: _focus,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            enabled: widget.enabled,
            onTapOutside: (_) => _focus.unfocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: widget.onChanged,
          ),
        ],
      );
}

/// Integer field (negative allowed). Empty input is treated as 0.
class IntBinding extends StatefulWidget {
  const IntBinding(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.enabled = true});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  State<IntBinding> createState() => _IntBindingState();
}

class _IntBindingState extends State<IntBinding> {
  late final TextEditingController _c =
      TextEditingController(text: '${widget.value}');
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(IntBinding old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && int.tryParse(_c.text) != widget.value) {
      _c.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BindingLabel(widget.label),
          TextField(
            controller: _c,
            focusNode: _focus,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            enabled: widget.enabled,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))
            ],
            onTapOutside: (_) => _focus.unfocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: (s) => widget.onChanged(int.tryParse(s) ?? 0),
          ),
        ],
      );
}

class DoubleBinding extends StatefulWidget {
  const DoubleBinding({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<DoubleBinding> createState() => _DoubleBindingState();
}

class _DoubleBindingState extends State<DoubleBinding> {
  late final TextEditingController _controller =
      TextEditingController(text: '${widget.value}');
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(DoubleBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && double.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BindingLabel(widget.label),
          TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: widget.enabled,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
            ],
            onTapOutside: (_) => _focus.unfocus(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            onChanged: (text) => widget.onChanged(double.tryParse(text) ?? 0),
          ),
        ],
      );
}

class StorageSlotsBinding extends StatefulWidget {
  const StorageSlotsBinding({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Storage slots',
    this.onError,
  });

  final Map<String, int> value;
  final ValueChanged<Map<String, int>> onChanged;
  final String label;
  final ValueChanged<String?>? onError;

  @override
  State<StorageSlotsBinding> createState() => _StorageSlotsBindingState();
}

class _StorageSlotsBindingState extends State<StorageSlotsBinding> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  final FocusNode _focus = FocusNode();
  String? _error;

  String _format(Map<String, int> slots) =>
      slots.entries.map((entry) => '${entry.key}=${entry.value}').join(', ');

  Map<String, int> _parse(String text) {
    final slots = <String, int>{};
    if (text.trim().isEmpty) return slots;
    for (final part in text.split(',')) {
      final pair = part.split('=');
      if (pair.length != 2 || pair.first.trim().isEmpty) {
        throw const FormatException('Use slot=count entries separated by commas.');
      }
      final name = pair.first.trim();
      final count = int.tryParse(pair.last.trim());
      if (count == null || count < 0 || slots.containsKey(name)) {
        throw const FormatException(
            'Slot counts must be non-negative integers with unique names.');
      }
      slots[name] = count;
    }
    return slots;
  }

  @override
  void didUpdateWidget(StorageSlotsBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _format(widget.value) != _controller.text) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BindingLabel(widget.label),
          TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: true,
            onTapOutside: (_) => _focus.unfocus(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              helperText: 'Example: magazine=4, grenade=2',
              errorText: _error,
            ),
            onChanged: (text) {
              try {
                final slots = _parse(text);
                setState(() => _error = null);
                widget.onError?.call(null);
                widget.onChanged(slots);
              } on FormatException catch (error) {
                setState(() => _error = error.message);
                widget.onError?.call(error.message);
              }
            },
          ),
        ],
      );
}

class _BindingLabel extends StatelessWidget {
  const _BindingLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 4),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
}

/// Opens a structured editor for numeric effects.
class EffectsField extends StatelessWidget {
  const EffectsField(
      {super.key, required this.effects, required this.onChanged, this.skills});

  final List<Effect> effects;
  final ValueChanged<List<Effect>> onChanged;
  final List<Skill>? skills;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.tune),
        label: Text(effects.isEmpty
            ? 'Edit effects'
            : 'Edit effects (${effects.length})'),
        onPressed: () async {
          final edited = await _editEffects(
              context, effects, [...defaultSkills(), ...?skills]);
          if (edited != null) onChanged(edited);
        },
      );

  Future<List<Effect>?> _editEffects(
      BuildContext context, List<Effect> currentEffects, List<Skill> skills) {
    final options = <String, String>{
      'ac': 'Armor Class',
      'speed': 'Speed',
      'initiative': 'Initiative',
      'proficiency': 'Proficiency bonus',
      'hp.max': 'Maximum HP',
      'attack': 'Attack rolls',
      for (final ability in ['str', 'dex', 'con', 'int', 'wis', 'cha'])
        'ability.$ability': 'Ability: ${ability.toUpperCase()}',
      for (final ability in ['str', 'dex', 'con', 'int', 'wis', 'cha'])
        'save.$ability': 'Saving throw: ${ability.toUpperCase()}',
      for (final skill in skills) 'skill.${skill.key}': 'Skill: ${skill.name}',
    };
    for (final effect in currentEffects) {
      options.putIfAbsent(
        effect.target,
        () => _customTargetLabel(effect.target),
      );
    }
    return showDialog<List<Effect>>(
      context: context,
      builder: (dialogContext) {
        final edited = currentEffects
            .map(
              (effect) => Effect(
                target: effect.target,
                value: effect.value,
                basedOn: effect.basedOn,
                multiplier: effect.multiplier,
                divisor: effect.divisor,
                components: effect.components
                    .map(
                      (component) => EffectComponent(
                        ability: component.ability,
                        calculation: component.calculation,
                        multiplier: component.multiplier,
                        divisor: component.divisor,
                      ),
                    )
                    .toList(),
                condition: effect.condition,
                operation: effect.operation,
              ),
            )
            .toList();
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Effects'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (edited.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                            'No effects. Add one to modify a character stat.'),
                      ),
                    for (var index = 0; index < edited.length; index++)
                      Padding(
                        key: ObjectKey(edited[index]),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: DropdownButtonFormField<String>(
                                    key: ValueKey(
                                        'effect-target-$index-${edited[index].target}'),
                                    initialValue: edited[index].target,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Stat'),
                                    items: [
                                      for (final option in options.entries)
                                        DropdownMenuItem(
                                          value: option.key,
                                          child: Text(
                                            option.value,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                    onChanged: (target) {
                                      if (target == null) {
                                        return;
                                      }
                                      setDialogState(
                                          () => edited[index].target = target);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    key: ValueKey(
                                        'effect-value-$index-${edited[index].value}'),
                                    initialValue: '${edited[index].value}',
                                    decoration: const InputDecoration(
                                        labelText: 'Bonus'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            signed: true),
                                    onChanged: (text) {
                                      final value = int.tryParse(text);
                                      if (value != null) {
                                        edited[index].value = value;
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove effect',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => setDialogState(
                                      () => edited.removeAt(index)),
                                ),
                              ],
                            ),
                            for (var componentIndex = 0;
                                componentIndex <
                                    edited[index].components.length;
                                componentIndex++)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 6, left: 12),
                                child: Row(
                                  children: [
                                    const Text('Add'),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: edited[index]
                                            .components[componentIndex]
                                            .ability,
                                        decoration: const InputDecoration(
                                            labelText: 'Ability'),
                                        items: [
                                          for (final ability in [
                                            'str',
                                            'dex',
                                            'con',
                                            'int',
                                            'wis',
                                            'cha',
                                          ])
                                            DropdownMenuItem(
                                              value: ability,
                                              child:
                                                  Text(ability.toUpperCase()),
                                            ),
                                        ],
                                        onChanged: (ability) {
                                          if (ability == null) return;
                                          setDialogState(() {
                                            final old = edited[index]
                                                .components[componentIndex];
                                            edited[index].components[
                                                    componentIndex] =
                                                EffectComponent(
                                              ability: ability,
                                              calculation: old.calculation,
                                              multiplier: old.multiplier,
                                              divisor: old.divisor,
                                            );
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        initialValue: edited[index]
                                            .components[componentIndex]
                                            .calculation,
                                        decoration: const InputDecoration(
                                            labelText: 'Use'),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'modifier',
                                              child: Text('Modifier')),
                                          DropdownMenuItem(
                                              value: 'score',
                                              child: Text('Score')),
                                        ],
                                        onChanged: (calculation) {
                                          if (calculation == null) return;
                                          setDialogState(() {
                                            final old = edited[index]
                                                .components[componentIndex];
                                            edited[index].components[
                                                    componentIndex] =
                                                EffectComponent(
                                              ability: old.ability,
                                              calculation: calculation,
                                              multiplier: old.multiplier,
                                              divisor: old.divisor,
                                            );
                                          });
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Remove ability scaling',
                                      onPressed: () => setDialogState(() =>
                                          edited[index]
                                              .components
                                              .removeAt(componentIndex)),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: () => setDialogState(
                                      () => edited[index].components.add(
                                            EffectComponent(ability: 'dex'),
                                          )),
                                  icon: const Icon(Icons.functions),
                                  label: const Text('Add ability scaling'),
                                ),
                                DropdownButton<String>(
                                  hint: const Text('Condition'),
                                  value: edited[index].condition,
                                  items: const [
                                    DropdownMenuItem(
                                      value: null,
                                      child: Text('Always applies'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'noBallisticProtection',
                                      child: Text('No ballistic armor'),
                                    ),
                                  ],
                                  onChanged: (condition) => setDialogState(() =>
                                      edited[index].condition = condition),
                                ),
                                if (edited[index].target == 'ac')
                                  DropdownButton<String>(
                                    value: edited[index].operation,
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'add',
                                          child: Text('Add to base')),
                                      DropdownMenuItem(
                                          value: 'setBase',
                                          child: Text('Set AC base')),
                                    ],
                                    onChanged: (operation) {
                                      if (operation == null) return;
                                      setDialogState(() =>
                                          edited[index].operation = operation);
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(
                          () => edited.add(
                            Effect(
                              target: options.keys.first,
                              value: 1,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add effect'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, edited),
                child: const Text('Apply'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _customTargetLabel(String target) {
    if (target.startsWith('skill.')) {
      final name = target.substring('skill.'.length).replaceAll('_', ' ');
      return 'Skill: $name (custom)';
    }
    return '$target (custom)';
  }
}

Widget gap([double w = 8, double h = 8]) => SizedBox(width: w, height: h);
