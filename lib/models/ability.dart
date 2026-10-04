enum Ability {
  str('str', 'STR'),
  dex('dex', 'DEX'),
  con('con', 'CON'),
  intelligence('int', 'INT'),
  wis('wis', 'WIS'),
  cha('cha', 'CHA');

  const Ability(this.key, this.label);

  /// Key used in JSON and in effect targets (e.g. "ability.dex").
  final String key;
  final String label;

  static Ability fromKey(String k) => Ability.values.firstWhere(
        (a) => a.key == k.toLowerCase(),
        orElse: () => Ability.str,
      );
}
