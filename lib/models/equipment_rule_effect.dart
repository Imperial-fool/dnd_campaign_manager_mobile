import 'json_utils.dart';

class EquipmentRuleEffect {
  const EquipmentRuleEffect._({
    required this.type,
    this.value = 0,
    this.faction = '',
    this.disposition = '',
  });

  const EquipmentRuleEffect.ricochetChance(int value)
      : this._(type: 'ricochetChance', value: value);

  const EquipmentRuleEffect.factionDisposition({
    required String faction,
    required String disposition,
  }) : this._(
          type: 'factionDisposition',
          faction: faction,
          disposition: disposition,
        );

  final String type;
  final int value;
  final String faction;
  final String disposition;

  factory EquipmentRuleEffect.fromJson(Map<String, dynamic> json) {
    final type = asStr(json['type']);
    switch (type) {
      case 'ricochetChance':
        final value = asInt(json['value'], -1);
        if (value < 0 || value > 100) {
          throw const FormatException(
              'Ricochet chance must be between 0 and 100.');
        }
        return EquipmentRuleEffect.ricochetChance(value);
      case 'factionDisposition':
        final faction = asStr(json['faction']).trim();
        final disposition = asStr(json['disposition']);
        if (faction.isEmpty) {
          throw const FormatException(
              'Faction disposition effects need a faction.');
        }
        if (!{'friendly', 'neutral', 'hostile'}.contains(disposition)) {
          throw const FormatException(
              'Faction disposition must be friendly, neutral, or hostile.');
        }
        return EquipmentRuleEffect.factionDisposition(
          faction: faction,
          disposition: disposition,
        );
      default:
        throw FormatException('Unsupported equipment rule effect "$type".');
    }
  }

  Map<String, dynamic> toJson() => switch (type) {
        'ricochetChance' => {'type': type, 'value': value},
        'factionDisposition' => {
            'type': type,
            'faction': faction,
            'disposition': disposition,
          },
        _ => throw FormatException('Unsupported equipment rule effect "$type".')
      };

  String get summary => switch (type) {
        'ricochetChance' => 'Ricochet chance: $value%',
        'factionDisposition' => '$disposition to $faction',
        _ => type,
      };
}
