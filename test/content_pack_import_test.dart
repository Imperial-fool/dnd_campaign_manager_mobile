import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

void main() {
  test('Tarkov pack imports from its standalone JSON file', () {
    final json =
        File('content/tarkov_character_options.json').readAsStringSync();
    final catalog = Catalog();
    final result =
        ContentImporter(ContentRegistry.standard()).importJson(json, catalog);

    expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    final classes =
        catalog.items('classes').whereType<ClassDefinition>().toList();
    expect(classes, hasLength(4));
    expect(catalog.items('backgrounds'), hasLength(15));
    expect(catalog.items('weapons'), hasLength(34));
    expect(catalog.items('armor'), hasLength(9));
    expect(catalog.items('items'), hasLength(33));
    final items = catalog.items('items').whereType<InventoryItem>();
    expect(
      items.singleWhere((item) => item.id == 'ammo_5_56_m855').category,
      'ammo',
    );
    expect(
      items.singleWhere((item) => item.id == 'ifak_medical_kit').category,
      'medical',
    );
    expect(
      items.singleWhere((item) => item.id == 'water_bottle').category,
      'misc',
    );

    final juggernaut =
        classes.singleWhere((definition) => definition.id == 'juggernaut');
    expect(
      juggernaut.featuresAtLevel(1).map((feature) => feature['name']),
      containsAll(['Strong Arm', 'Suppressive Fire']),
    );
    expect(
      juggernaut.featuresAtLevel(14).map((feature) => feature['name']),
      contains('Kaban option'),
    );
    expect(
      juggernaut.choicesAtLevel(1).map((choice) => choice['id']),
      [
        'juggernaut_skills',
        'juggernaut_primary',
        'juggernaut_sidearm',
      ],
    );
    final expectedJuggernautEquipment = {
      'weapons': {'m249_lmg', 'm1911'},
      'armor': {'juggernaut_fast_mt', 'avs_level_4'},
      'items': {
        'cat_tourniquet',
        'army_bandage_pack',
        'aluminum_splint',
        'ifak_medical_kit',
        'water_bottle',
        'ration',
        'leatherman_multitool',
        'entrenching_tool',
        'ammo_5_56_m855',
      },
    };
    final expectedChoiceOptions = {
      'operator': {
        'operator_skills': {
          'athletics',
          'acrobatics',
          'survival',
          'perception',
          'weapon_maintenance',
        },
        'operator_primary': {
          'm4a1',
          'hk416',
          'hkg36c',
          'steyr_aug',
          'scar_l',
          'hk_mp7',
          'hk_mp5',
          'sig_mpx',
        },
        'operator_secondary': {'usp_45', 'beretta_m9'},
        'operator_armor': {'plate_carrier_level_3', 'armored_vest_level_3'},
      },
      'cqb': {
        'cqb_skills': {
          'athletics',
          'acrobatics',
          'survival',
          'perception',
          'stealth',
        },
        'cqb_primary': {
          'hk_mp7a2',
          'hk_mp5_ap_6_3',
          'hk_mpx_ap_6_3',
          'hk_ump',
          'remington_r870',
          'mossberg_590a1',
          'benelli_m3_super_90',
        },
        'cqb_secondary': {
          'glock_17',
          'glock_19x',
          'beretta_m9_ap_6_3',
          'usp_45_fmj',
        },
        'cqb_melee': {
          'sog_voodoo_tactical_tomahawk',
          'miller_bros_m_2_tactical_sword',
        },
        'cqb_headgear': {'cqb_caimen_helmet', 'usec_ball_cap'},
        'cqb_armor': {
          'cqb_plate_carrier_level_3',
          'bulletproof_vest_level_3',
        },
      },
      'juggernaut': {
        'juggernaut_skills': {
          'athletics',
          'armaments',
          'perception',
          'armor_repair',
        },
        'juggernaut_primary': {'m249_lmg', 'aa12'},
        'juggernaut_sidearm': {
          'm1911',
          'usp_45_ap',
          'beretta_m9_ap_6_3',
          'glock_17',
        },
      },
      'scout': {
        'scout_skills': {
          'acrobatics',
          'investigation',
          'sleight_of_hand',
          'perception',
        },
        'scout_primary': {
          'remington_m700',
          'knight_s_armament_sr_25',
          'lone_star_armories_tx',
        },
        'scout_secondary': {
          'glock_17',
          'glock_19x',
          'beretta_m9',
          'usp_45_fmj',
        },
      },
    };
    for (final definition in classes) {
      for (final grant in definition.startingEquipment) {
        expect(
          catalog.items(asStr(grant['catalogKey'])).any(
                (item) => item.id == asStr(grant['itemId']),
              ),
          isTrue,
          reason: '${definition.id} references missing ${grant['itemId']}',
        );
      }
      final choices = definition.choicesAtLevel(1);
      final expectedChoices = expectedChoiceOptions[definition.id]!;
      expect(
        choices.map((choice) => choice['id']).toSet(),
        expectedChoices.keys.toSet(),
        reason: '${definition.name} has unexpected starting choices',
      );
      for (final choice in choices) {
        final choiceId = asStr(choice['id']);
        final options = asMapList(choice['options']);
        expect(
          options.map((option) => asStr(option['id'])).toSet(),
          expectedChoices[choiceId],
          reason: '${definition.name} $choiceId options differ from source',
        );
        for (final option in options.where(
          (option) => asStr(option['grantType'], 'feature') == 'catalog',
        )) {
          expect(
            catalog.items(asStr(option['catalogKey'])).any(
                  (item) => item.id == asStr(option['itemId']),
                ),
            isTrue,
            reason: '${definition.name} references missing ${option['itemId']}',
          );
          for (final grant in asMapList(option['grants'])) {
            expect(
              catalog.items(asStr(grant['catalogKey'])).any(
                    (item) => item.id == asStr(grant['itemId']),
                  ),
              isTrue,
              reason:
                  '${definition.name} references missing ${grant['itemId']}',
            );
          }
        }
      }
      final selections = {
        for (final choice in choices)
          asStr(choice['selectionKey']): asMapList(choice['options'])
              .take(asInt(choice['count'], 1))
              .map((option) => asStr(option['id']))
              .toList(),
      };
      final editor = CharacterController(
        character: Character(id: '${definition.id}-starting-gear'),
        repository: _NoopRepository(),
      );
      expect(
        editor.advanceLevel(
          definition,
          catalog: catalog,
          selections: selections,
        ),
        isNull,
        reason: 'Failed to grant ${definition.name} starting equipment',
      );
      for (final grant in definition.startingEquipment) {
        final grantedIds = switch (asStr(grant['catalogKey'])) {
          'weapons' => editor.character.weapons.map((item) => item.id),
          'armor' => editor.character.armor.map((item) => item.id),
          'items' => editor.character.items.map((item) => item.id),
          _ => const <String>[],
        };
        expect(
          grantedIds,
          contains(asStr(grant['itemId'])),
          reason: '${definition.id} did not receive ${grant['itemId']}',
        );
      }
      if (definition.id == 'juggernaut') {
        expect(
          {
            'weapons': editor.character.weapons.map((item) => item.id).toSet(),
            'armor': editor.character.armor.map((item) => item.id).toSet(),
            'items': editor.character.items.map((item) => item.id).toSet(),
          },
          expectedJuggernautEquipment,
        );
        expect(
          editor.character.items
              .singleWhere((item) => item.id == 'ammo_5_56_m855')
              .quantity,
          320,
        );
      }
      editor.dispose();
    }

    for (final selection in [
      (
        primary: 'm249_lmg',
        expectedWeapon: 'm249_lmg',
        expectedAmmo: 'ammo_5_56_m855',
        expectedQuantity: 320,
      ),
      (
        primary: 'aa12',
        expectedWeapon: 'aa12',
        expectedAmmo: 'ammo_12_gauge_00_buckshot',
        expectedQuantity: 60,
      ),
    ]) {
      final choices = juggernaut.choicesAtLevel(1);
      final selections = {
        for (final choice in choices)
          asStr(choice['selectionKey']): asMapList(choice['options'])
              .take(asInt(choice['count'], 1))
              .map((option) => asStr(option['id']))
              .toList(),
      };
      final primaryChoice = choices.singleWhere(
        (choice) => choice['id'] == 'juggernaut_primary',
      );
      selections[asStr(primaryChoice['selectionKey'])] = [selection.primary];
      final editor = CharacterController(
        character: Character(id: 'juggernaut-${selection.primary}'),
        repository: _NoopRepository(),
      );
      expect(
        editor.advanceLevel(
          juggernaut,
          catalog: catalog,
          selections: selections,
        ),
        isNull,
      );
      expect(
        editor.character.weapons.map((weapon) => weapon.id).toSet(),
        {selection.expectedWeapon, 'm1911'},
      );
      expect(
        editor.character.items
            .where((item) => item.category == 'ammo')
            .map((item) => item.id),
        [selection.expectedAmmo],
      );
      expect(
        editor.character.items
            .singleWhere((item) => item.id == selection.expectedAmmo)
            .quantity,
        selection.expectedQuantity,
      );
      editor.dispose();
    }

    for (final testCase in [
      (
        classId: 'operator',
        choiceId: 'operator_armor',
        optionId: 'armored_vest_level_3',
        grantId: 'blackrock_tactical_rig'
      ),
      (
        classId: 'cqb',
        choiceId: 'cqb_armor',
        optionId: 'bulletproof_vest_level_3',
        grantId: 'six_slot_tactical_rig'
      ),
    ]) {
      final definition =
          classes.singleWhere((item) => item.id == testCase.classId);
      final choices = definition.choicesAtLevel(1);
      final selections = {
        for (final choice in choices)
          asStr(choice['selectionKey']): asMapList(choice['options'])
              .take(asInt(choice['count'], 1))
              .map((option) => asStr(option['id']))
              .toList(),
      };
      final armorChoice =
          choices.singleWhere((choice) => choice['id'] == testCase.choiceId);
      selections[asStr(armorChoice['selectionKey'])] = [testCase.optionId];
      final editor = CharacterController(
        character: Character(id: '${testCase.classId}-vest-rig'),
        repository: _NoopRepository(),
      );
      expect(
        editor.advanceLevel(
          definition,
          catalog: catalog,
          selections: selections,
        ),
        isNull,
      );
      expect(
        editor.character.items.map((item) => item.id),
        contains(testCase.grantId),
      );
      editor.dispose();
    }

    final scout = classes.singleWhere((definition) => definition.id == 'scout');
    final unarmoredDefense = scout
        .featuresAtLevel(1)
        .singleWhere((feature) => feature['name'] == 'Unarmored Defense');
    expect(unarmoredDefense['effects'], [
      {
        'target': 'ac',
        'value': 10,
        'components': [
          {'ability': 'dex', 'calculation': 'modifier'},
          {'ability': 'wis', 'calculation': 'modifier'},
        ],
        'condition': 'noBallisticProtection',
        'operation': 'setBase',
      }
    ]);

    final cqb = classes.singleWhere((definition) => definition.id == 'cqb');
    final virtuoso =
        cqb.subclasses.singleWhere((subclass) => subclass['id'] == 'virtuoso');
    final choices = virtuoso['choices'] as List;
    expect(choices, hasLength(5));
    expect(
      choices.map((choice) => (choice as Map)['options'] as List),
      everyElement(hasLength(3)),
    );
    final enforcer =
        cqb.subclasses.singleWhere((subclass) => subclass['id'] == 'enforcer');
    expect(
      ClassSubclass(enforcer)
          .featuresAtLevel(6)
          .map((feature) => feature['name']),
      containsAll(['Weapon Jam Aura', 'Martial Artist']),
    );
  });

  test('legacy affiliation sections import as backgrounds', () {
    final catalog = Catalog();
    final result = ContentImporter(ContentRegistry.standard()).importJson(
      '{"affiliations":[{"id":"fsb","name":"FSB"}]}',
      catalog,
    );

    expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    expect(catalog.items('backgrounds'), hasLength(1));
    expect(catalog.toJson().containsKey('backgrounds'), isTrue);
    expect(catalog.toJson().containsKey('affiliations'), isFalse);
  });

  test('legacy item entries infer a category when category is omitted', () {
    final medical = InventoryItem.fromJson({
      'id': 'legacy_medkit',
      'name': 'Field Medical Kit',
      'kind': 'item',
    });
    final ammo = InventoryItem.fromJson({
      'id': 'legacy_ammo',
      'name': '9mm rounds',
      'kind': 'ammo',
    });

    expect(medical.category, 'medical');
    expect(ammo.category, 'ammo');
    expect(InventoryItem.fromJson(medical.toJson()).category, 'medical');
  });
}

class _NoopRepository implements CampaignRepository {
  @override
  Future<List<Character>> loadCharacters() async => [];

  @override
  Future<void> saveCharacter(Character character) async {}

  @override
  Future<void> deleteCharacter(String id) async {}

  @override
  Future<Map<String, dynamic>> loadCatalogJson() async => {};

  @override
  Future<void> saveCatalogJson(Map<String, dynamic> json) async {}

  @override
  Future<bool> loadRequireXpForLevelUp() async => false;

  @override
  Future<void> saveRequireXpForLevelUp(bool requireXp) async {}
}
