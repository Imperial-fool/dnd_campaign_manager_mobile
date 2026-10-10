import 'package:flutter/material.dart';
import 'package:dnd_campaign_manager/models/effect.dart';
import 'package:dnd_campaign_manager/models/equipment_rule_effect.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/equipment_rule_effects_field.dart';
import 'package:dnd_campaign_manager/ui/widgets/formula_field.dart';

enum FieldKind {
  text,
  multiline,
  integer,
  decimal,
  toggle,
  choice,
  multiChoice,
  storageSlots,
  dice,
  effects,
  ruleEffects,
}

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label,
    this.kind, {
    this.help,
    this.choices = const [],
    this.group = 'Basics',
    this.defaultValue,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final String? help;

  /// (stored value, shown label)
  final List<(String, String)> choices;
  final String group;
  final Object? defaultValue;
}

/// Describes the form for one content type. Adding a type to the pack
/// builder only needs a new schema here.
class ItemSchema {
  const ItemSchema(this.key, this.singular, this.icon, this.fields,
      {this.preset = const {}});

  final String key;
  final String singular;
  final IconData icon;
  final List<FieldSpec> fields;

  /// Values always written (e.g. category for feats).
  final Map<String, dynamic> preset;
}

const _abilityChoices = [
  ('str', 'Strength'),
  ('dex', 'Dexterity'),
  ('con', 'Constitution'),
  ('int', 'Intelligence'),
  ('wis', 'Wisdom'),
  ('cha', 'Charisma'),
];

const _effects = FieldSpec('effects', 'Effects', FieldKind.effects,
    group: 'Effects',
    help: 'Bonuses this gives the sheet: AC, speed, skills, saves...');

final Map<String, ItemSchema> itemSchemas = {
  'weapons': const ItemSchema('weapons', 'Weapon', Icons.gps_fixed, [
    FieldSpec('name', 'Name', FieldKind.text),
    FieldSpec('weaponType', 'Weapon type', FieldKind.text,
        help: 'e.g. Assault rifle, Longsword'),
    FieldSpec('properties', 'Description / properties', FieldKind.multiline),
    FieldSpec('weightKg', 'Weight (kg)', FieldKind.decimal),
    FieldSpec('damage', 'Damage', FieldKind.dice,
        group: 'Attack',
        help: 'Dice rolled on a hit. Use the Functions button for tricks like '
            'a die that decides how many damage dice you roll.'),
    FieldSpec(
        'damageAbility', 'Add ability modifier to damage', FieldKind.choice,
        group: 'Attack', choices: [('', 'None'), ..._abilityChoices]),
    FieldSpec('attackAbility', 'Attack ability', FieldKind.choice,
        group: 'Attack', choices: _abilityChoices, defaultValue: 'dex'),
    FieldSpec('proficient', 'Proficient (add proficiency to attack)',
        FieldKind.toggle,
        group: 'Attack', defaultValue: true),
    FieldSpec('attackBonus', 'Attack bonus', FieldKind.integer,
        group: 'Attack'),
    FieldSpec('ammoType', 'Ammo type', FieldKind.text,
        group: 'Ammo & firing',
        help: 'Matches inventory ammo with the same type. Blank = no ammo.'),
    FieldSpec('ammoMax', 'Magazine size', FieldKind.integer,
        group: 'Ammo & firing', help: '0 = draw straight from inventory.'),
    FieldSpec('roundsPerShot', 'Rounds per shot', FieldKind.integer,
        group: 'Ammo & firing',
        help: 'Semi-auto rounds. Burst and full-auto update this value from '
            'their burst count or bullet-dice roll.'),
    FieldSpec('fireModes', 'Fire modes', FieldKind.multiChoice,
        group: 'Ammo & firing',
        choices: [
          ('semi', 'Semi'),
          ('burst', 'Burst'),
          ('fullAuto', 'Full auto')
        ],
        defaultValue: [
          'semi'
        ]),
    FieldSpec('burstRounds', 'Burst rounds', FieldKind.integer,
        group: 'Ammo & firing'),
    FieldSpec('burstDamage', 'Burst damage', FieldKind.dice,
        group: 'Ammo & firing'),
    FieldSpec('bulletDice', 'Bullet die (full auto)', FieldKind.dice,
        group: 'Ammo & firing',
        help: 'Full auto: this roll decides how many rounds hit, each '
            'dealing the normal damage.'),
    FieldSpec('hpMax', 'Durability (HP)', FieldKind.integer,
        group: 'Durability'),
    _effects,
  ]),
  'armor': const ItemSchema('armor', 'Armor', Icons.shield_outlined, [
    FieldSpec('name', 'Name', FieldKind.text),
    FieldSpec('equipmentSlot', 'Equipment slot', FieldKind.choice, choices: [
      ('', 'Unspecified'),
      ('head', 'Head'),
      ('body', 'Body'),
      ('rig', 'Rig'),
      ('other', 'Other'),
    ]),
    FieldSpec('properties', 'Description / properties', FieldKind.multiline),
    FieldSpec('rating', 'Ballistic rating', FieldKind.integer),
    FieldSpec('hpMax', 'Durability (HP)', FieldKind.integer),
    FieldSpec('weightKg', 'Weight (kg)', FieldKind.decimal),
    FieldSpec('carryCapacityKg', 'Carry capacity (kg)', FieldKind.decimal),
    FieldSpec('storageSlots', 'Storage slot counts', FieldKind.storageSlots),
    FieldSpec('equipped', 'Equipped by default', FieldKind.toggle),
    _effects,
    FieldSpec('ruleEffects', 'Equipment rules', FieldKind.ruleEffects,
        group: 'Effects'),
  ]),
  'items': const ItemSchema('items', 'Item', Icons.backpack_outlined, [
    FieldSpec('name', 'Name', FieldKind.text),
    FieldSpec('kind', 'Kind', FieldKind.choice,
        choices: [('item', 'Item'), ('ammo', 'Ammo')], defaultValue: 'item'),
    FieldSpec('category', 'Category', FieldKind.choice, choices: [
      ('misc', 'Miscellaneous'),
      ('medical', 'Medical'),
      ('ammo', 'Ammo'),
    ]),
    FieldSpec('description', 'Description', FieldKind.multiline),
    FieldSpec('quantity', 'Quantity', FieldKind.integer),
    FieldSpec('weightKg', 'Weight per unit (kg)', FieldKind.decimal),
    FieldSpec('carryCapacityKg', 'Carry capacity (kg)', FieldKind.decimal),
    FieldSpec('storageSlots', 'Storage slot counts', FieldKind.storageSlots),
    FieldSpec('usesMax', 'Uses per unit', FieldKind.integer),
    FieldSpec('ammoType', 'Ammo type', FieldKind.text,
        group: 'Combat', help: 'For ammo: the weapon ammo type it feeds.'),
    FieldSpec('damage', 'Damage', FieldKind.dice, group: 'Combat'),
    FieldSpec('damageType', 'Damage type', FieldKind.text, group: 'Combat'),
    FieldSpec('areaRadius', 'Area radius (ft)', FieldKind.integer,
        group: 'Combat'),
    FieldSpec('saveAbility', 'Save ability', FieldKind.choice,
        group: 'Combat', choices: [('', 'None'), ..._abilityChoices]),
    FieldSpec('saveDc', 'Save DC', FieldKind.integer, group: 'Combat'),
    FieldSpec('penetration', 'Penetration', FieldKind.integer, group: 'Combat'),
    FieldSpec('durabilityBurn', 'Durability burn', FieldKind.integer,
        group: 'Combat'),
    _effects,
    FieldSpec('ruleEffects', 'Equipment rules', FieldKind.ruleEffects,
        group: 'Effects'),
  ]),
  for (final t in const [
    ('traits', 'Trait', 'trait'),
    ('features', 'Feature', 'feature'),
    ('feats', 'Feat', 'feat'),
  ])
    t.$1: ItemSchema(
      t.$1,
      t.$2,
      Icons.auto_awesome,
      [
        const FieldSpec('name', 'Name', FieldKind.text),
        const FieldSpec('description', 'Description', FieldKind.multiline),
        const FieldSpec('source', 'Source', FieldKind.text),
        _effects,
      ],
      preset: {'category': t.$3},
    ),
};

/// Guided editor for one catalog item: no JSON required. Pops the item map.
class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({
    super.key,
    required this.schema,
    this.initial,
    required this.validate,
  });

  final ItemSchema schema;
  final Map<String, dynamic>? initial;

  /// Parses the data the way the app will; throws to report a problem.
  final void Function(Map<String, dynamic> data) validate;

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  late final Map<String, dynamic> _data;
  String? _storageSlotsError;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.initial ?? {});
    for (final f in widget.schema.fields) {
      if (f.defaultValue != null && !_data.containsKey(f.key)) {
        _data[f.key] = f.defaultValue;
      }
    }
  }

  void _set(String key, Object? value) => setState(() {
        if (value == null || value == '') {
          _data.remove(key);
        } else {
          _data[key] = value;
        }
      });

  void _save() {
    if (_storageSlotsError != null) {
      _snack(_storageSlotsError!);
      return;
    }
    final data = {..._data, ...widget.schema.preset};
    if (asStr(data['name']).trim().isEmpty) {
      _snack('Give it a name first.');
      return;
    }
    try {
      widget.validate(data);
    } catch (e) {
      _snack('$e');
      return;
    }
    Navigator.pop(context, data);
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final groups = <String>[];
    for (final f in widget.schema.fields) {
      if (!groups.contains(f.group)) groups.add(f.group);
    }
    final isNew = widget.initial == null;
    return Scaffold(
      appBar: AppBar(
        title: Text('${isNew ? 'New' : 'Edit'} ${widget.schema.singular}'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final g in groups) ...[
            if (groups.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text(g, style: Theme.of(context).textTheme.titleMedium),
              ),
            for (final f in widget.schema.fields.where((f) => f.group == g))
              _field(f),
          ],
        ],
      ),
    );
  }

  Widget _field(FieldSpec f) {
    switch (f.kind) {
      case FieldKind.text:
      case FieldKind.multiline:
        return _row(TextFormField(
          initialValue: asStr(_data[f.key]),
          maxLines: f.kind == FieldKind.multiline ? 5 : 1,
          minLines: f.kind == FieldKind.multiline ? 2 : 1,
          decoration: InputDecoration(labelText: f.label, helperText: f.help),
          onChanged: (v) => _data[f.key] = v,
        ));
      case FieldKind.integer:
      case FieldKind.decimal:
        final isInt = f.kind == FieldKind.integer;
        return _row(TextFormField(
          initialValue: _data[f.key] == null ? '' : '${_data[f.key]}',
          keyboardType:
              TextInputType.numberWithOptions(decimal: !isInt, signed: true),
          decoration: InputDecoration(labelText: f.label, helperText: f.help),
          onChanged: (v) {
            final n = isInt ? int.tryParse(v) : double.tryParse(v);
            if (n == null) {
              _data.remove(f.key);
            } else {
              _data[f.key] = n;
            }
          },
        ));
      case FieldKind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _data[f.key] == true,
          onChanged: (v) => _set(f.key, v),
        );
      case FieldKind.choice:
        final current = asStr(_data[f.key]);
        return _row(DropdownButtonFormField<String>(
          initialValue: f.choices.any((c) => c.$1 == current)
              ? current
              : (f.choices.any((c) => c.$1 == '') ? '' : null),
          decoration: InputDecoration(labelText: f.label, helperText: f.help),
          items: [
            for (final c in f.choices)
              DropdownMenuItem(value: c.$1, child: Text(c.$2)),
          ],
          onChanged: (v) => _set(f.key, v),
        ));
      case FieldKind.multiChoice:
        final selected = _data[f.key] is List
            ? (_data[f.key] as List).map((e) => '$e').toSet()
            : <String>{};
        return _row(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label),
            Wrap(spacing: 8, children: [
              for (final c in f.choices)
                FilterChip(
                  label: Text(c.$2),
                  selected: selected.contains(c.$1),
                  onSelected: (on) {
                    final next = {...selected};
                    on ? next.add(c.$1) : next.remove(c.$1);
                    _set(
                        f.key,
                        f.choices
                            .map((c) => c.$1)
                            .where(next.contains)
                            .toList());
                  },
                ),
            ]),
          ],
        ));
      case FieldKind.storageSlots:
        final rawSlots = _data[f.key];
        final slots =
            rawSlots is Map ? Map<String, int>.from(rawSlots) : <String, int>{};
        return _row(StorageSlotsBinding(
          value: slots,
          onError: (error) => _storageSlotsError = error,
          onChanged: (value) {
            _set(f.key, value.isEmpty ? null : value);
            _storageSlotsError = null;
          },
        ));
      case FieldKind.dice:
        return FormulaTextField(
          label: f.label,
          help: f.help,
          initialValue: asStr(_data[f.key]),
          onChanged: (v) => _data[f.key] = v,
        );
      case FieldKind.effects:
        List<Effect> effects;
        try {
          effects = asMapList(_data[f.key]).map(Effect.fromJson).toList();
        } on FormatException {
          effects = [];
        }
        return _row(Align(
          alignment: Alignment.centerLeft,
          child: EffectsField(
            effects: effects,
            onChanged: (list) =>
                _set(f.key, list.map((e) => e.toJson()).toList()),
          ),
        ));
      case FieldKind.ruleEffects:
        List<EquipmentRuleEffect> effects;
        try {
          effects = asMapList(_data[f.key])
              .map(EquipmentRuleEffect.fromJson)
              .toList();
        } on FormatException {
          effects = [];
        }
        return _row(EquipmentRuleEffectsField(
          effects: effects,
          onChanged: (list) =>
              _set(f.key, list.map((effect) => effect.toJson()).toList()),
        ));
    }
  }

  Widget _row(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: child);
}
