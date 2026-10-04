import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

/// Applies an affiliation to a character:
///  - sets the affiliation name/id
///  - removes features granted by the PREVIOUS affiliation
///  - adds this affiliation's features (tagged with their origin)
///  - grants listed skill / saving-throw proficiencies
/// Granted proficiencies are not revoked when switching (they may overlap with
/// proficiencies from other sources).
void applyAffiliation(Character c, Affiliation a) {
  if (c.affiliationId.isNotEmpty) {
    c.traits.removeWhere((t) => t.origin == 'affiliation:${c.affiliationId}');
  }
  c.affiliation = a.name;
  c.affiliationId = a.id;

  for (final f in a.features) {
    final copy = Trait.fromJson(f.toJson(), defaultCategory: 'feature')
      ..origin = 'affiliation:${a.id}'
      ..source = f.source.isEmpty ? 'Affiliation: ${a.name}' : f.source;
    c.traits.add(copy);
  }

  for (final s in a.skillProficiencies) {
    final key = slug(s);
    for (final skill in c.skills.where((k) => k.key == key)) {
      skill.proficient = true;
    }
  }
  for (final s in a.saveProficiencies) {
    c.saveProficiencies.add(Ability.fromKey(s));
  }
}
