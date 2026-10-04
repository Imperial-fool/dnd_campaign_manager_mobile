import 'json_utils.dart';

/// A numeric modifier that gear/traits apply to the sheet.
///
/// Supported targets (see logic/rules.dart):
///   ac, speed, initiative, proficiency, hp.max,
///   ability.<str|dex|con|int|wis|cha>, save.<ability>, skill.<skill_slug>
class Effect {
  Effect({required this.target, required this.value});

  String target;
  int value;

  factory Effect.fromJson(Map<String, dynamic> j) =>
      Effect(target: asStr(j['target']), value: asInt(j['value']));

  Map<String, dynamic> toJson() => {'target': target, 'value': value};

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
