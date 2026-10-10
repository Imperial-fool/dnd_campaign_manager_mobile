import 'dart:math';
import 'dart:io';

import 'package:dnd_campaign_manager/models/equipment_rule_effect.dart';
import 'package:dnd_campaign_manager/models/fire_mode.dart';
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
    expect(catalog.items('weapons'), hasLength(135));
    expect(catalog.items('armor'), hasLength(54));
    expect(catalog.items('items').whereType<InventoryItem>(), hasLength(111));
    final fullAuto = catalog.items('weapons').whereType<Weapon>().singleWhere(
          (weapon) => weapon.name == 'HK G36',
        );
    expect(fullAuto.bulletDice, '1d6');
    expect(fullAuto.burstDamage, '3D6');
    expect(fullAuto.burstRounds, 3);
    expect(fullAuto.roundsPerShot, 1);
    expect(fullAuto.fireModes, contains(FireMode.fullAuto));
    expect(fullAuto.firingMode, FireMode.semi);
    expect(fullAuto.damageAbility, 'dex');
    expect(fullAuto.ammoMax, 30);
    final m855 = catalog.items('items').whereType<InventoryItem>().singleWhere(
          (item) => item.id == 'ammo_5_56x45_m855',
        );
    expect(m855.penetration, 35);
    expect(m855.durabilityBurn, 1);

    final bastion = catalog.items('armor').whereType<Armor>().singleWhere(
          (armor) => armor.id == 'bastion_slaap',
        );
    expect(bastion.equipmentSlot, 'head');
    expect(bastion.weightKg, 0);
    expect(bastion.ruleEffects.single.value, 65);
    final avs = catalog.items('armor').whereType<Armor>().singleWhere(
          (armor) => armor.id == 'avs_armored_rig',
        );
    expect(avs.equipmentSlot, 'rig');
    expect(avs.weightKg, 11);
    expect(avs.storageSlots['magazine'], 4);
    final mechanism = catalog
        .items('items')
        .whereType<InventoryItem>()
        .singleWhere((item) => item.id == 'mechanism_backpack');
    expect(mechanism.weightKg, 2);
    expect(mechanism.carryCapacityKg, 35);
  });

  test('carrying load uses the greatest active container capacity', () {
    final character = Character(id: 'carrying-load')
      ..weapons = [Weapon(name: 'Rifle', weightKg: 1)]
      ..armor = [
        Armor(
          name: 'Equipped rig',
          weightKg: 2,
          carryCapacityKg: 25,
          equipped: true,
        ),
        Armor(
          name: 'Stored armor',
          weightKg: 3,
          carryCapacityKg: 100,
          equipped: false,
        ),
      ]
      ..items = [
        InventoryItem(
          name: 'Active backpack',
          weightKg: 2,
          carryCapacityKg: 30,
          active: true,
        ),
        InventoryItem(
          name: 'Smaller active backpack',
          weightKg: 1,
          carryCapacityKg: 20,
          active: true,
        ),
        InventoryItem(
          name: 'Stored backpack',
          weightKg: 5,
          carryCapacityKg: 90,
          active: false,
        ),
        InventoryItem(name: 'Stacked gear', quantity: 3, weightKg: 0.5),
      ];

    expect(Rules.carriedWeightKg(character), 15.5);
    expect(Rules.carryingCapacityKg(character), 30);
    expect(Rules.exceedsCarryCapacity(character), isFalse);
    character.items.add(InventoryItem(name: 'Heavy load', weightKg: 20));
    expect(Rules.exceedsCarryCapacity(character), isTrue);

    final restored = Character.fromJson(character.toJson());
    expect(Rules.carriedWeightKg(restored), 35.5);
    expect(Rules.carryingCapacityKg(restored), 30);
  });

  test('equipped gear resolves ricochet and faction dispositions', () {
    final character = Character(id: 'gear-rules')
      ..armor = [
        Armor(
          name: 'Helmet',
          equipped: true,
          ruleEffects: [const EquipmentRuleEffect.ricochetChance(65)],
        ),
        Armor(
          name: 'Stored hat',
          equipped: false,
          ruleEffects: [const EquipmentRuleEffect.ricochetChance(0)],
        ),
      ]
      ..items = [
        InventoryItem(
          name: 'Beanie',
          active: true,
          ruleEffects: [
            const EquipmentRuleEffect.factionDisposition(
              faction: 'Killa',
              disposition: 'friendly',
            ),
          ],
        ),
      ];

    expect(Rules.ricochetChance(character), 65);
    expect(Rules.factionDisposition(character, 'kIlLa'), 'friendly');

    final restored = Character.fromJson(character.toJson());
    expect(Rules.ricochetChance(restored), 65);
    expect(Rules.factionDisposition(restored, 'Killa'), 'friendly');

    character.armor.first.equipped = false;
    character.items.single.active = false;
    expect(Rules.ricochetChance(character), 0);
    expect(Rules.factionDisposition(character, 'Killa'), 'neutral');
  });

  test('equipment metadata rejects invalid values', () {
    expect(
      () => Armor.fromJson({'name': 'Bad slot', 'equipmentSlot': 'neck'}),
      throwsFormatException,
    );
    expect(
      () => InventoryItem.fromJson({'name': 'Bad weight', 'weightKg': -1}),
      throwsFormatException,
    );
    expect(
      () => InventoryItem.fromJson({
        'name': 'Bad slots',
        'storageSlots': {'magazine': -1},
      }),
      throwsFormatException,
    );
    expect(
      () => EquipmentRuleEffect.fromJson({
        'type': 'ricochetChance',
        'value': 101,
      }),
      throwsFormatException,
    );
  });

  test('player edits save the current remote character instance', () async {
    final initial = Character(id: 'player-sheet');
    final remote = Character.fromJson(initial.toJson())..name = 'Remote sheet';
    Character? saved;
    final controller = CharacterController(
      character: initial,
      repository: _MemoryRepository(),
      isPlayerMode: true,
      onSaved: (character) => saved = character,
    );

    controller.refreshRemoteCharacter(remote);
    controller.edit((character) => character.hpCurrent = 7);
    await controller.flush();

    expect(saved, same(remote));
    expect(saved!.hpCurrent, 7);
    controller.dispose();
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
      firingMode: FireMode.burst,
      fireModes: [FireMode.semi, FireMode.burst],
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
    expect(result.attackTotal, result.total);
    expect(result.damageTotal, isNotNull);
    expect(result.headline, contains('Attack ${result.attackTotal}'));
    expect(result.headline, contains('Damage ${result.damageTotal}'));
    expect(weapon.ammo, 0);
    expect(weapon.roundsPerShot, 3);
    weapon.selectFiringMode(FireMode.semi);
    expect(weapon.roundsPerShot, 1);
  });

  test('magazine weapons require reload when inventory pulling is disabled',
      () {
    final ammo = InventoryItem(
      name: 'Test ammo',
      kind: 'ammo',
      ammoType: 'test',
      quantity: 5,
    );
    final weapon = Weapon(
      name: 'Magazine rifle',
      ammoType: 'test',
      ammoMax: 3,
      ammo: 0,
      damage: '1d6',
    );
    final controller = CharacterController(
      character: Character(id: 'reload-required')
        ..weapons = [weapon]
        ..items = [ammo],
      repository: _MemoryRepository(),
      dice: DiceRoller(Random(1)),
    );

    final result = controller.fire(weapon);

    expect(result.title, contains('click'));
    expect(result.lines.any((line) => line.startsWith('Attack:')), isFalse);
    expect(weapon.ammo, 0);
    expect(ammo.quantity, 5);
  });

  test('campaign ammo-pulling rule is saved and passed to character editors',
      () async {
    final repository = _MemoryRepository();
    final campaign = CampaignController(repository: repository);

    await campaign.setPullAmmoFromInventory(true);
    final editor = campaign.editorFor(Character(id: 'ammo-rule'));

    expect(repository.pullAmmo, isTrue);
    expect(editor.pullAmmoFromInventory(), isTrue);

    editor.dispose();
    campaign.dispose();
  });

  test('file repository preserves both campaign settings', () async {
    final root =
        await Directory.systemTemp.createTemp('dnd-campaign-ammo-settings-');
    try {
      final repository = FileCampaignRepository(root);
      await repository.saveRequireXpForLevelUp(true);
      await repository.savePullAmmoFromInventory(true);

      expect(await repository.loadRequireXpForLevelUp(), isTrue);
      expect(await repository.loadPullAmmoFromInventory(), isTrue);

      await repository.saveRequireXpForLevelUp(false);
      expect(await repository.loadPullAmmoFromInventory(), isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('magazine weapons pull only the ammo shortfall when enabled', () {
    final ammo = InventoryItem(
      name: 'Test ammo',
      kind: 'ammo',
      ammoType: 'test',
      quantity: 5,
    );
    final weapon = Weapon(
      name: 'Magazine rifle',
      firingMode: FireMode.burst,
      fireModes: [FireMode.semi, FireMode.burst],
      ammoType: 'test',
      ammoMax: 3,
      ammo: 1,
      burstRounds: 3,
      burstDamage: '1d6',
    );
    final controller = CharacterController(
      character: Character(id: 'inventory-pull')
        ..weapons = [weapon]
        ..items = [ammo],
      repository: _MemoryRepository(),
      pullAmmoFromInventory: () => true,
      dice: DiceRoller(Random(1)),
    );

    final result = controller.fire(weapon);

    expect(result.lines, contains('Burst: all 3 rounds hit'));
    expect(weapon.ammo, 0);
    expect(ammo.quantity, 3);
  });

  test('weapons without magazine capacity continue to use inventory ammo', () {
    final ammo = InventoryItem(
      name: 'Test ammo',
      kind: 'ammo',
      ammoType: 'test',
      quantity: 1,
    );
    final weapon = Weapon(
      name: 'Unconfigured weapon',
      ammoType: 'test',
      ammoMax: 0,
      damage: '1d6',
    );
    final controller = CharacterController(
      character: Character(id: 'inventory-fallback')
        ..weapons = [weapon]
        ..items = [ammo],
      repository: _MemoryRepository(),
      dice: DiceRoller(Random(1)),
    );

    final result = controller.fire(weapon);

    expect(result.lines.any((line) => line.startsWith('Attack:')), isTrue);
    expect(ammo.quantity, 0);
  });

  test('full auto can pull its rolled round count from inventory', () {
    final ammo = InventoryItem(
      name: 'Test ammo',
      kind: 'ammo',
      ammoType: 'test',
      quantity: 6,
    );
    final weapon = Weapon(
      name: 'Full-auto rifle',
      firingMode: FireMode.fullAuto,
      fireModes: [FireMode.semi, FireMode.fullAuto],
      ammoType: 'test',
      ammoMax: 6,
      ammo: 0,
      bulletDice: '1d6',
      damage: '1d6',
    );
    final controller = CharacterController(
      character: Character(id: 'full-auto-inventory')
        ..weapons = [weapon]
        ..items = [ammo],
      repository: _MemoryRepository(),
      pullAmmoFromInventory: () => true,
      dice: DiceRoller(Random(1)),
    );

    controller.fire(weapon);

    expect(weapon.roundsPerShot, inInclusiveRange(1, 6));
    expect(ammo.quantity, 6 - weapon.roundsPerShot);
  });

  test('full auto spends the rolled bullet dice and updates rounds per shot',
      () {
    final weapon = Weapon(
      name: 'Full-auto rifle',
      firingMode: FireMode.fullAuto,
      fireModes: [FireMode.semi, FireMode.fullAuto],
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

    expect(weapon.roundsPerShot, inInclusiveRange(1, 6));
    expect(weapon.lastFullAutoRounds, weapon.roundsPerShot);
    expect(weapon.ammo, 6 - weapon.roundsPerShot);
    expect(result.attackTotal, result.total);
    expect(result.damageTotal, isNotNull);
    expect(result.headline, contains('Attack ${result.attackTotal}'));
    expect(result.headline, contains('Damage ${result.damageTotal}'));
    expect(
      result.lines.any((line) => RegExp(
            'Full auto: ${weapon.roundsPerShot} rounds fired',
          ).hasMatch(line)),
      isTrue,
    );
    final json = weapon.toJson();
    expect(json['fireModes'], ['semi', 'fullAuto']);
    expect(json['firingMode'], 'fullAuto');
    expect(Weapon.fromJson(json).roundsPerShot, weapon.roundsPerShot);
    weapon.selectFiringMode(FireMode.semi);
    expect(weapon.roundsPerShot, 1);
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

  test('stash preserves item amount and resets limited uses', () async {
    final repository = _MemoryRepository();
    final campaign = CampaignController(repository: repository);
    await campaign.load();
    final character = await campaign.createCharacter('First')
      ..player = 'Player One';
    final medkit = InventoryItem(
      name: 'Medkit',
      quantity: 2,
      uses: 1,
      usesMax: 4,
    );
    character.items.add(medkit);

    expect(await campaign.moveToStash(character, 'items', medkit), isTrue);
    final stored = campaign.stashForPlayer('Player One').single['item'] as Map;
    expect(stored['quantity'], 2);
    expect(stored['uses'], 4);
    expect(character.items, isEmpty);

    final recipient = await campaign.createCharacter('Second')
      ..player = 'Player One';
    expect(await campaign.moveFromStash(recipient, 0), isTrue);
    expect(recipient.items.single.quantity, 2);
    expect(recipient.items.single.uses, 4);
    expect(campaign.stashForPlayer('Player One'), isEmpty);
  });

  test('new character skills are sourced from bundled skill JSON', () async {
    final repository = _MemoryRepository();
    final legacy = Character(id: 'legacy-skill-list')
      ..skills.removeWhere((skill) => skill.key == 'technology');
    await repository.saveCharacter(legacy);
    final campaign = CampaignController(repository: repository);
    await campaign.load();
    final character = await campaign.createCharacter();

    expect(campaign.catalog.items('weapons'), hasLength(135));
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

  test('shared player sheets are read-only until the DM enables editing',
      () async {
    final character = Character(id: 'shared-read-only');
    final controller = CharacterController(
      character: character,
      repository: _MemoryRepository(),
      isReadOnly: true,
      allowReadOnlyEditToggle: true,
      dice: DiceRoller(Random(1)),
    );

    controller.edit((c) => c.hpCurrent = 1);
    expect(character.hpCurrent, 10);
    controller.rollText('d20');
    expect(controller.rollLog, hasLength(1));

    controller.toggleReadOnly();
    controller.edit((c) => c.hpCurrent = 7);
    expect(character.hpCurrent, 7);
    await controller.flush();
    controller.dispose();
  });
}

class _MemoryRepository implements CampaignRepository {
  final Map<String, Character> characters = {};
  Map<String, dynamic> catalog = {};
  bool pullAmmo = false;

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

  @override
  Future<bool> loadPullAmmoFromInventory() async => pullAmmo;

  @override
  Future<void> savePullAmmoFromInventory(bool value) async {
    pullAmmo = value;
  }
}
