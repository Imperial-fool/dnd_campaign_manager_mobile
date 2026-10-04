import 'json_utils.dart';

class EffectComponent {
  EffectComponent({
    required this.ability,
    this.calculation = 'modifier',
    this.multiplier = 1,
    this.divisor = 1,
  });

  final String ability;
  final String calculation;
  final int multiplier;
  final int divisor;

  factory EffectComponent.fromJson(Map<String, dynamic> json) {
    final ability = asStr(json['ability']);
    final calculation = asStr(json['calculation'], 'modifier');
    final divisor = asInt(json['divisor'], 1);
    if (!{'str', 'dex', 'con', 'int', 'wis', 'cha'}.contains(ability)) {
      throw const FormatException(
          'Effect components need a valid ability key.');
    }
    if (!{'modifier', 'score'}.contains(calculation)) {
      throw const FormatException(
          'Effect component calculation must be "modifier" or "score".');
    }
    if (divisor == 0) {
      throw const FormatException('Effect component divisor cannot be zero.');
    }
    return EffectComponent(
      ability: ability,
      calculation: calculation,
      multiplier: asInt(json['multiplier'], 1),
      divisor: divisor,
    );
  }

  Map<String, dynamic> toJson() => {
        'ability': ability,
        'calculation': calculation,
        if (multiplier != 1) 'multiplier': multiplier,
        if (divisor != 1) 'divisor': divisor,
      };
}

/// A numeric modifier that gear/traits apply to the sheet.
///
/// Supported targets (see logic/rules.dart):
///   ac, speed, initiative, proficiency, hp.max,
///   ability.<str|dex|con|int|wis|cha>, save.<ability>, skill.<skill_slug>
class Effect {
  Effect({
    required this.target,
    required this.value,
    this.basedOn,
    this.multiplier = 1,
    this.divisor = 1,
    List<EffectComponent>? components,
    this.condition,
    this.operation = 'add',
  }) : components = components ?? <EffectComponent>[];

  String target;

  /// Legacy flat bonus; retained for backwards compatibility.
  int value;
  String? basedOn;
  int multiplier;
  int divisor;
  List<EffectComponent> components;
  String? condition;
  String operation;

  factory Effect.fromJson(Map<String, dynamic> j) {
    final target = asStr(j['target']);
    final condition =
        j['condition'] is String ? j['condition'] as String : null;
    final operation = asStr(j['operation'], 'add');
    final rawComponents = j['components'];
    if (rawComponents != null && rawComponents is! List) {
      throw const FormatException('"components" must be a list.');
    }
    if (condition != null && condition != 'noBallisticProtection') {
      throw FormatException('Unsupported effect condition "$condition".');
    }
    if (!{'add', 'setBase'}.contains(operation) ||
        (operation == 'setBase' && target != 'ac')) {
      throw FormatException('Unsupported effect operation "$operation".');
    }
    final divisor = asInt(j['divisor'], 1);
    if (divisor == 0) {
      throw const FormatException('Effect divisor cannot be zero.');
    }
    final components = (rawComponents as List? ?? const []).map((component) {
      if (component is! Map) {
        throw const FormatException('Each effect component must be an object.');
      }
      return EffectComponent.fromJson(Map<String, dynamic>.from(component));
    }).toList();
    return Effect(
      target: target,
      value: asInt(j['value']),
      basedOn: j['basedOn'] is String ? j['basedOn'] as String : null,
      multiplier: asInt(j['multiplier'], 1),
      divisor: divisor,
      components: components,
      condition: condition,
      operation: operation,
    );
  }

  Map<String, dynamic> toJson() => {
        'target': target,
        'value': value,
        if (basedOn != null) 'basedOn': basedOn,
        if (multiplier != 1) 'multiplier': multiplier,
        if (divisor != 1) 'divisor': divisor,
        if (components.isNotEmpty)
          'components':
              components.map((component) => component.toJson()).toList(),
        if (condition != null) 'condition': condition,
        if (operation != 'add') 'operation': operation,
      };

  /// Compact editing format: "ac=1, ability.dex=2".
  static String toText(List<Effect> list) =>
      list.map((e) => '${e.target}=${e.value}').join(', ');

  static List<Effect> parseText(String text) {
    final out = <Effect>[];
    for (final part in text.split(RegExp(r'[,\n]'))) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final target = kv[0].trim();
      final value = int.tryParse(kv[1].trim().replaceFirst('+', ''));
      if (target.isEmpty || value == null) continue;
      out.add(Effect(target: target, value: value));
    }
    return out;
  }
}
