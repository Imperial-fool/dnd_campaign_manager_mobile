import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

/// Applies a background to a character:
///  - sets the background name/id
///  - removes features granted by the previous background
///  - adds this background's features (tagged with their origin)
///  - grants listed skill / saving-throw proficiencies
/// Granted proficiencies are not revoked when switching (they may overlap with
/// proficiencies from other sources).
void applyBackground(Character c, BackgroundDefinition background) {
  if (c.backgroundId.isNotEmpty) {
    c.traits.removeWhere((t) => t.origin == 'background:${c.backgroundId}');
  }
  c.background = background.name;
  c.backgroundId = background.id;

  for (final f in background.features) {
    final copy = Trait.fromJson(f.toJson(), defaultCategory: 'feature')
      ..origin = 'background:${background.id}'
      ..source = f.source.isEmpty ? 'Background: ${background.name}' : f.source;
    c.traits.add(copy);
  }

  for (final s in background.skillProficiencies) {
    final key = slug(s);
    for (final skill in c.skills.where((k) => k.key == key)) {
      skill.proficient = true;
    }
  }
  for (final s in background.saveProficiencies) {
    c.saveProficiencies.add(Ability.fromKey(s));
  }
}
