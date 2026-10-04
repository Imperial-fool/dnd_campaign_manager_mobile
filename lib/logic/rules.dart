import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/effect.dart';
import 'package:dnd_campaign_manager/models/gear.dart';

/// Pure functions: derived stats from a [Character]. No Flutter imports.
class Rules {
  Rules._();

  /// Standard 5e XP needed to REACH level (index 0 = level 1).
  /// Informational only; level is set manually so custom campaigns can differ.
  static const List<int> xpThresholds = [
    0,
    300,
    900,
    2700,
    6500,
    14000,
    23000,
    34000,
    48000,
    64000,
    85000,
    100000,
    120000,
    140000,
    165000,
    195000,
    225000,
    265000,
    305000,
    355000,
  ];

  static int modifier(int score) => ((score - 10) / 2).floor();

  static Iterable<Effect> _allEffects(Character c) sync* {
    for (final t in c.traits) {
      yield* t.effects;
    }
    for (final a in c.armor) {
      if (a.equipped) yield* a.effects;
    }
    for (final w in c.weapons) {
      yield* w.effects;
    }
  }

  /// Sum of every effect (traits, equipped armor, weapons) for [target].
  static int effectTotal(Character c, String target) => _allEffects(c)
      .where((e) => e.target == target)
      .fold(0, (sum, e) => sum + e.value);

  static int abilityScore(Character c, Ability a) =>
      (c.abilityScores[a] ?? 10) + effectTotal(c, 'ability.${a.key}');

  static int abilityMod(Character c, Ability a) => modifier(abilityScore(c, a));

  /// 2 at levels 1-4, 3 at 5-8, ... 6 at 17-20 (plus any "proficiency" effects).
  static int proficiency(Character c) =>
      2 + (c.level.clamp(1, 20) - 1) ~/ 4 + effectTotal(c, 'proficiency');

  /// XP needed for the next level, or null at max level.
  static int? xpForNextLevel(Character c) =>
      c.level >= 20 ? null : xpThresholds[c.level];

  static int saveBonus(Character c, Ability a) =>
      abilityMod(c, a) +
      (c.saveProficiencies.contains(a) ? proficiency(c) : 0) +
      effectTotal(c, 'save.${a.key}');

  /// Proficiency counts once; expertise counts twice.
  static int skillBonus(Character c, Skill s) =>
      abilityMod(c, s.ability) +
      (s.hasExpertise
          ? 2 * proficiency(c)
          : (s.isProficient ? proficiency(c) : 0)) +
      s.misc +
      effectTotal(c, 'skill.${s.key}');

  static int passivePerception(Character c) {
    final p = c.skills.where((s) => s.key == 'perception');
    return 10 +
        (p.isEmpty ? abilityMod(c, Ability.wis) : skillBonus(c, p.first));
  }

  /// Weapon attack: ability mod + proficiency (if proficient) + weapon bonus
  /// + any "attack" effects.
  static int attackBonus(Character c, Weapon w) =>
      abilityMod(c, w.attackAbility) +
      (w.proficient ? proficiency(c) : 0) +
      w.attackBonus +
      effectTotal(c, 'attack');

  static int armorClass(Character c) => c.armorClass + effectTotal(c, 'ac');
  static int speed(Character c) => c.speed + effectTotal(c, 'speed');
  static int initiative(Character c) =>
      abilityMod(c, Ability.dex) +
      c.initiativeBonus +
      effectTotal(c, 'initiative');
  static int maxHp(Character c) => c.hpMax + effectTotal(c, 'hp.max');

  static String signed(int n) => n >= 0 ? '+$n' : '$n';
}
