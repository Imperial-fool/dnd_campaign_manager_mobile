import 'dart:math';

import 'package:dnd_campaign_manager/logic/formula.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

enum SheetFieldType {
  number,
  text,
  toggle,
  calc,
  roll;

  static SheetFieldType parse(String s) => SheetFieldType.values
      .firstWhere((t) => t.name == s, orElse: () => SheetFieldType.number);
}

/// One element of a DM-designed sheet.
///  - number/text/toggle: editable values stored on the character
///  - calc: read-only, [formula] evaluated against the character
///  - roll: button that rolls the dice template in [formula], e.g.
///    `1d20+{str_mod}+{prof}` or `{1d6}d8` (bullet-die style).
class SheetField {
  SheetField({
    required this.key,
    required this.label,
    this.type = SheetFieldType.number,
    this.section = 'General',
    this.formula = '',
    this.defaultValue = '',
  });

  String key;
  String label;
  SheetFieldType type;
  String section;
  String formula;
  String defaultValue;

  factory SheetField.fromJson(Map<String, dynamic> j) {
    final label = asStr(j['label']);
    final key = asStr(j['key']).isEmpty ? slug(label) : asStr(j['key']);
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      throw FormatException('Field key "$key" must be letters, digits, _.');
    }
    return SheetField(
      key: key,
      label: label.isEmpty ? key : label,
      type: SheetFieldType.parse(asStr(j['type'], 'number')),
      section: asStr(j['section'], 'General'),
      formula: asStr(j['formula']),
      defaultValue: asStr(j['default']),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'section': section,
        if (formula.isNotEmpty) 'formula': formula,
        if (defaultValue.isNotEmpty) 'default': defaultValue,
      };
}

class SheetTemplate implements CatalogItem {
  SheetTemplate({
    String id = '',
    required this.name,
    this.description = '',
    List<SheetField>? fields,
  })  : _id = id,
        fields = fields ?? [];

  final String _id;
  @override
  String get id => _id.isEmpty ? slug(name) : _id;
  @override
  final String name;
  final String description;
  final List<SheetField> fields;

  @override
  String get summary =>
      description.isEmpty ? '${fields.length} field(s)' : description;

  factory SheetTemplate.fromJson(Map<String, dynamic> j) {
    final fields = asMapList(j['fields']).map(SheetField.fromJson).toList();
    final seen = <String>{};
    for (final f in fields) {
      if (!seen.add(f.key)) {
        throw FormatException('Duplicate field key "${f.key}".');
      }
    }
    return SheetTemplate(
      id: asStr(j['id']),
      name: asStr(j['name']),
      description: asStr(j['description']),
      fields: fields,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description.isNotEmpty) 'description': description,
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  List<String> get sections {
    final out = <String>[];
    for (final f in fields) {
      if (!out.contains(f.section)) out.add(f.section);
    }
    return out;
  }
}

/// Reads and writes template values on `character.extras` and evaluates
/// calculated fields (with cycle detection).
class SheetEvaluator {
  SheetEvaluator(this.character, this.template, {int Function(int)? rollDie})
      : _rollDie = rollDie;

  static const templateKey = 'sheetTemplate';
  static const valuesKey = 'sheetValues';

  final Character character;
  final SheetTemplate template;
  final int Function(int sides)? _rollDie;
  final Set<String> _evaluating = {};

  static const componentsKey = 'sheetComponents';

  /// Ids of the components attached to a character, in display order.
  /// Also reads the legacy single `sheetTemplate` value.
  static List<String> componentIds(Character c) {
    final out = <String>[];
    final v = c.extras[componentsKey];
    if (v is List) {
      for (final e in v) {
        if (e is String && e.isNotEmpty && !out.contains(e)) out.add(e);
      }
    }
    final legacy = c.extras[templateKey];
    if (legacy is String && legacy.isNotEmpty && !out.contains(legacy)) {
      out.insert(0, legacy);
    }
    return out;
  }

  static void _setIds(Character c, List<String> ids) {
    c.extras.remove(templateKey);
    if (ids.isEmpty) {
      c.extras.remove(componentsKey);
    } else {
      c.extras[componentsKey] = ids;
    }
  }

  static void addComponent(Character c, String id) {
    final ids = componentIds(c);
    if (!ids.contains(id)) ids.add(id);
    _setIds(c, ids);
  }

  static void removeComponent(Character c, String id) =>
      _setIds(c, componentIds(c)..remove(id));

  static void moveComponent(Character c, String id, int delta) {
    final ids = componentIds(c);
    final i = ids.indexOf(id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= ids.length) return;
    ids.insert(j, ids.removeAt(i));
    _setIds(c, ids);
  }

  Map<String, dynamic> _stored() {
    final all = character.extras[valuesKey];
    final mine = all is Map ? all[template.id] : null;
    return mine is Map ? Map<String, dynamic>.from(mine) : {};
  }

  Object? rawValue(SheetField f) =>
      _stored().containsKey(f.key) ? _stored()[f.key] : f.defaultValue;

  void setValue(SheetField f, Object value) {
    final all = character.extras[valuesKey] is Map
        ? Map<String, dynamic>.from(character.extras[valuesKey] as Map)
        : <String, dynamic>{};
    final mine = all[template.id] is Map
        ? Map<String, dynamic>.from(all[template.id] as Map)
        : <String, dynamic>{};
    mine[f.key] = value;
    all[template.id] = mine;
    character.extras[valuesKey] = all;
  }

  num? _numeric(String name) {
    for (final f in template.fields) {
      if (f.key != name) continue;
      switch (f.type) {
        case SheetFieldType.number:
          final raw = rawValue(f);
          return raw is num ? raw : num.tryParse('$raw') ?? 0;
        case SheetFieldType.toggle:
          final raw = rawValue(f);
          return raw == true || raw == 1 || raw == 'true' ? 1 : 0;
        case SheetFieldType.calc:
          return calc(f);
        case SheetFieldType.text:
        case SheetFieldType.roll:
          return null;
      }
    }
    return FormulaEngine.characterVariable(character, name);
  }

  FormulaEngine get engine => FormulaEngine(
        resolve: _numeric,
        rollDie: _rollDie ?? (s) => Random().nextInt(s) + 1,
      );

  /// Throws [FormatException] on a bad formula or circular reference.
  int calc(SheetField f) {
    if (!_evaluating.add(f.key)) {
      throw FormatException('Circular reference at "${f.key}".');
    }
    try {
      return engine.evaluate(f.formula);
    } finally {
      _evaluating.remove(f.key);
    }
  }

  /// Display text for a calc field; errors are shown instead of thrown.
  String calcText(SheetField f) {
    try {
      return '${calc(f)}';
    } on FormatException catch (e) {
      return 'Error: ${e.message}';
    }
  }

  /// Returns the first problem found in the template, or null.
  String? validate() {
    for (final f in template.fields) {
      try {
        if (f.type == SheetFieldType.calc) {
          calc(f);
        } else if (f.type == SheetFieldType.roll) {
          engine.resolveTemplate(f.formula.isEmpty ? '0' : f.formula);
        }
      } on FormatException catch (e) {
        return '${f.label}: ${e.message}';
      }
    }
    return null;
  }
}
