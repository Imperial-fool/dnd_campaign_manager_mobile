import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/sheet_template.dart';

/// Editable component versions of the standard character sheet sections.
/// They read live values from the character, so a DM can copy and tweak them.
/// Weapons, armor, inventory, actions and traits remain built-in lists.
class BuiltinComponent {
  const BuiltinComponent(this.name, this.description, this._build);
  final String name;
  final String description;
  final SheetTemplate Function() _build;
  SheetTemplate build() => _build();
}

SheetField _calc(String key, String label, String formula, String section) =>
    SheetField(
        key: key,
        label: label,
        type: SheetFieldType.calc,
        formula: formula,
        section: section);

SheetField _roll(String key, String label, String formula, String section) =>
    SheetField(
        key: key,
        label: label,
        type: SheetFieldType.roll,
        formula: formula,
        section: section);

SheetField _text(String key, String label, String section) => SheetField(
    key: key, label: label, type: SheetFieldType.text, section: section);

final List<BuiltinComponent> builtinComponents = [
  BuiltinComponent('Ability scores', 'Scores and modifiers with check rolls',
      () {
    return SheetTemplate(name: 'Ability Scores (copy)', fields: [
      for (final a in Ability.values) ...[
        _calc('${a.key}_score', '${a.label} score', a.key, 'Abilities'),
        _calc('${a.key}_modifier', '${a.label} modifier', '${a.key}_mod',
            'Abilities'),
        _roll('${a.key}_check_roll', '${a.label} check',
            '1d20+{${a.key}_mod}', 'Abilities'),
      ],
    ]);
  }),
  BuiltinComponent('Saving throws', 'Save bonuses with rolls', () {
    return SheetTemplate(name: 'Saving Throws (copy)', fields: [
      for (final a in Ability.values) ...[
        _calc('${a.key}_save_bonus', '${a.label} save', '${a.key}_save',
            'Saves'),
        _roll('${a.key}_save_roll', '${a.label} save roll',
            '1d20+{${a.key}_save}', 'Saves'),
      ],
    ]);
  }),
  BuiltinComponent('Skills', 'Every skill bonus with a check roll', () {
    final skills = Character(id: 'builtin').skills;
    return SheetTemplate(name: 'Skills (copy)', fields: [
      for (final s in skills) ...[
        _calc('${s.key}_bonus', s.name, 'skill_${s.key}', 'Skills'),
        _roll('${s.key}_roll', '${s.name} check', '1d20+{skill_${s.key}}',
            'Skills'),
      ],
    ]);
  }),
  BuiltinComponent('Vitals', 'HP, AC, speed, initiative, proficiency', () {
    return SheetTemplate(name: 'Vitals (copy)', fields: [
      _calc('hp_now', 'Hit points', 'hp', 'Vitals'),
      _calc('hp_maximum', 'Max HP', 'hp_max', 'Vitals'),
      _calc('armor_class', 'Armor class', 'ac', 'Vitals'),
      _calc('move_speed', 'Speed', 'speed', 'Vitals'),
      _calc('init_bonus', 'Initiative', 'initiative', 'Vitals'),
      _calc('prof_bonus', 'Proficiency bonus', 'prof', 'Vitals'),
      _calc('char_level', 'Level', 'level', 'Vitals'),
      _roll('init_roll', 'Roll initiative', '1d20+{initiative}', 'Vitals'),
    ]);
  }),
  BuiltinComponent('Notes', 'Equipment, proficiencies and notes text boxes',
      () {
    return SheetTemplate(name: 'Notes (copy)', fields: [
      _text('equipment_notes', 'Equipment', 'Notes'),
      _text('proficiency_notes', 'Proficiencies & languages', 'Notes'),
      _text('general_notes', 'Notes', 'Notes'),
    ]);
  }),
];
