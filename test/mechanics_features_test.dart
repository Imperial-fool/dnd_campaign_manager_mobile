import 'dart:math';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/logic/dice.dart';
import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/models/gear.dart';

void main() {
  test('bundled armory content contains parsed weapon and ammo mechanics', () {
    final json = File('content/tarkov_armory.json').readAsStringSync();
    final catalog = Catalog();
    final result =
        ContentImporter(ContentRegistry.standard()).importJson(json, catalog);

    expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    expect(catalog.items('weapons'), hasLength(105));
    expect(catalog.items('items').whereType<InventoryItem>(), hasLength(88));
    final fullAuto = catalog.items('weapons').whereType<Weapon>().singleWhere(
          (weapon) => weapon.name == 'HK G36',
        );
    expect(fullAuto.bulletDice, '1d6');
    expect(fullAuto.burstDamage, '3D6');
    expect(fullAuto.burstRounds, 3);
    expect(fullAuto.roundsPerShot, 1);
    expect(fullAuto.damageAbility, 'dex');
    expect(fullAuto.ammoMax, 30);
    final m855 = catalog.items('items').whereType<InventoryItem>().singleWhere(
          (item) => item.id == 'ammo_5_56x45_m855',
        );
    expect(m855.penetration, 35);
    expect(m855.durabilityBurn, 1);
  });

  test('trait descriptions grant skill proficiency and expertise', () {
    final character = Character(id: 'described-skill-grants')
      ..level = 5
      ..abilityScores[Ability.intelligence] = 14
      ..traits = [
        Trait(
          name: 'Technology training',
          description: 'You have Expertise in Technology.',
        ),
        Trait(
          name: 'Armament training',
          description: 'You have expertise with the Armament skill.',
        ),
      ];
    final technology =
        character.skills.singleWhere((skill) => skill.key == 'technology');
    final armaments =
        character.skills.singleWhere((skill) => skill.key == 'armaments');

    expect(Rules.skillBonus(character, technology), 8);
    expect(Rules.skillBonus(character, armaments), 8);
  });

  test('class JSON feat levels require and grant an imported feat', () {
    final character = Character(id: 'feat-level-up')
      ..classId = 'test_class'
      ..className = 'Test Class'
      ..level = 3;
    final controller = CharacterController(
      character: character,
      repository: _MemoryRepository(),
    );
    final definition = ClassDefinition({
      'id': 'test_class',
      'name': 'Test Class',
      'hitDie': 10,
      'featLevels': [4, 8, 12],
      'levels': [],
    });
    final catalog = Catalog();

    expect(
      controller.advanceLevel(definition, catalog: catalog),
      contains('Import at least one feat'),
    );

    final importResult = ContentImporter(ContentRegistry.standard()).importJson(
      '{"feats":[{"id":"field_awareness","name":"Field Awareness",'
      '"description":"A test feat.",'
      '"effects":[{"target":"ability.str","value":2}]}]}',
      catalog,
    );
    expect(importResult.errors, isEmpty);
    expect(
      controller.advanceLevel(
        definition,
        catalog: catalog,
        selections: {
          'class:test_class:level:4:feat': ['field_awareness'],
        },
      ),
      isNull,
    );
    expect(character.level, 4);
    expect(character.traits.single.category, 'feat');
    expect(Rules.abilityScore(character, Ability.str), 12);
  });

  test('item use rolls damage and reports area and save information', () {
    final item = InventoryItem(
      name: 'Fragmentation grenade',
      quantity: 1,
      damage: '2d6',
      damageType: 'piercing',
      areaRadius: 20,
      saveDc: 15,
      saveAbility: 'dex',
    );
    final controller = CharacterController(
      character: Character(id: 'grenade-use')..items = [item],
      repository: _MemoryRepository(),
      dice: DiceRoller(Random(1)),
    );

    final result = controller.useItem(item);
    expect(result.total, isNotNull);
    expect(result.lines, contains('Area radius: 20 ft'));
    expect(result.lines, contains('Saving throw: DC 15 DEX'));
    expect(item.quantity, 0);
  });

  test('burst fire rolls one attack and all rounds hit without bullet dice',
      () {
    final weapon = Weapon(
      name: 'Burst rifle',
      firingMode: 'burst',
      fireModes: ['semi', 'burst'],
      ammoType: 'test',
      ammoMax: 3,
      ammo: 3,
      roundsPerShot: 1,
      burstRounds: 3,
      burstDamage: '3d6',
    );
    final controller = CharacterController(
      character: Character(id: 'burst-fire')..weapons = [weapon],
      repository: _MemoryRepository(),
      dice: DiceRoller(Random(1)),
    );

    final result = controller.fire(weapon);

    expect(result.lines.any((line) => line.startsWith('Attack: d20')), isTrue);
    expect(result.lines, contains('Burst: all 3 rounds hit'));
    expect(result.lines.any((line) => line.contains('bullet dice')), isFalse);
    expect(weapon.ammo, 0);
  });

  test('full auto spends the maximum bullet dice and rolls bullets that hit',
      () {
    final weapon = Weapon(
      name: 'Full-auto rifle',
      firingMode: 'fullAuto',
      fireModes: ['semi', 'fullAuto'],
      ammoType: 'test',
      ammoMax: 6,
      ammo: 6,
      bulletDice: '1d6',
      damage: '1d6',
    );
    final controller = CharacterController(
      character: Character(id: 'full-auto-fire')..weapons = [weapon],
      repository: _MemoryRepository(),
      dice: DiceRoller(Random(1)),
    );

    final result = controller.fire(weapon);

    expect(weapon.ammo, 0);
    expect(
      result.lines.any((line) =>
          RegExp(r'Full auto: \d+ hits from 6 rounds').hasMatch(line)),
      isTrue,
    );
  });

  test('stash is shared by player name and persisted outside character data',
      () async {
    final repository = _MemoryRepository();
    final campaign = CampaignController(repository: repository);
    await campaign.load();
    final first = await campaign.createCharacter('First');
    first.player = 'Player One';
    final weapon = Weapon(name: 'Stored rifle');
    first.weapons.add(weapon);

    expect(await campaign.moveToStash(first, 'weapons', weapon), isTrue);
    expect(first.weapons, isEmpty);
    expect(repository.catalog['playerStashes'], isA<Map>());
    expect(campaign.stashForPlayer('player one'), hasLength(1));
    expect(campaign.stashForPlayer('Player Two'), isEmpty);

    final second = await campaign.createCharacter('Second');
    second.player = 'PLAYER ONE';
    expect(await campaign.moveFromStash(second, 0), isTrue);
    expect(second.weapons.single.name, 'Stored rifle');
    expect(campaign.stashForPlayer('Player One'), isEmpty);
    expect(
      Character.fromJson(first.toJson()).weapons,
      isEmpty,
    );
  });

  test('new character skills are sourced from bundled skill JSON', () async {
    final repository = _MemoryRepository();
    final legacy = Character(id: 'legacy-skill-list')
      ..skills.removeWhere((skill) => skill.key == 'technology');
    await repository.saveCharacter(legacy);
    final campaign = CampaignController(repository: repository);
    await campaign.load();
    final character = await campaign.createCharacter();

    expect(campaign.catalog.items('weapons'), hasLength(105));
    expect(campaign.catalog.items('actions'), hasLength(14));
    expect(character.skills.map((skill) => skill.key), contains('technology'));
    expect(character.skills.map((skill) => skill.key), contains('survival'));
    expect(
      campaign.characters
          .singleWhere((entry) => entry.id == 'legacy-skill-list')
          .skills
          .map((skill) => skill.key),
      contains('technology'),
    );
  });
}

class _MemoryRepository implements CampaignRepository {
  final Map<String, Character> characters = {};
  Map<String, dynamic> catalog = {};

  @override
  Future<List<Character>> loadCharacters() async => characters.values.toList();

  @override
  Future<void> saveCharacter(Character character) async {
    characters[character.id] = Character.fromJson(character.toJson());
  }

  @override
  Future<void> deleteCharacter(String id) async {
    characters.remove(id);
  }

  @override
  Future<Map<String, dynamic>> loadCatalogJson() async => catalog;

  @override
  Future<void> saveCatalogJson(Map<String, dynamic> json) async {
    catalog = Map<String, dynamic>.from(json);
  }

  @override
  Future<bool> loadRequireXpForLevelUp() async => false;

  @override
  Future<void> saveRequireXpForLevelUp(bool requireXp) async {}
}
