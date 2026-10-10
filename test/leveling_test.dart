import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/logic/sample_content.dart';

void main() {
  group('JSON-driven character progression', () {
    test('sample content imports class definitions from JSON', () {
      final catalog = Catalog();
      final result = ContentImporter(ContentRegistry.standard())
          .importJson(sampleContentPack, catalog);

      expect(result.ok, isTrue, reason: result.errors.join('\n'));
      expect(catalog.items('classes'), hasLength(1));
      expect(catalog.items('classes').single, isA<ClassDefinition>());
    });

    final definition = ClassDefinition({
      'id': 'vanguard',
      'name': 'Vanguard',
      'hitDie': 10,
      'savingThrows': ['str', 'con'],
      'subclassLevel': 3,
      'levels': [
        {
          'level': 1,
          'features': [
            {'name': 'Combat Training', 'description': 'Level one feature.'}
          ],
          'choices': [
            {
              'id': 'combat_style',
              'prompt': 'Choose one combat style',
              'count': 1,
              'options': [
                {
                  'id': 'tactical_adept',
                  'name': 'Tactical Adept',
                  'description': 'A selected feature.'
                }
              ]
            },
            {
              'id': 'trained_skill',
              'prompt': 'Choose one skill',
              'count': 1,
              'options': [
                {
                  'id': 'survival',
                  'name': 'Survival',
                  'grantType': 'skill',
                  'skillAbility': 'wis'
                }
              ]
            },
            {
              'id': 'starting_weapon',
              'prompt': 'Choose one weapon',
              'count': 1,
              'options': [
                {
                  'id': 'starter_blade',
                  'name': 'Starter Blade',
                  'grantType': 'catalog',
                  'catalogKey': 'weapons',
                  'itemId': 'starter_blade'
                }
              ]
            }
          ]
        },
        {
          'level': 2,
          'features': [
            {'name': 'Tactical Surge', 'description': 'Level two feature.'}
          ]
        }
      ],
      'subclasses': [
        {
          'id': 'sentinel',
          'name': 'Sentinel',
          'features': [
            {
              'level': 3,
              'name': 'Guardian Stance',
              'description': 'Subclass feature.'
            }
          ]
        }
      ]
    });

    test('class and subclass features unlock at configured levels', () async {
      final character = Character(id: 'test')..abilityScores[Ability.con] = 14;
      final controller = CharacterController(
        character: character,
        repository: _MemoryRepository(),
      );

      final catalog = Catalog();
      catalog.upsert(
          'weapons', Weapon(id: 'starter_blade', name: 'Starter Blade'));
      final startingChoices = {
        'class:vanguard:level:1:combat_style': ['tactical_adept'],
        'class:vanguard:level:1:trained_skill': ['survival'],
        'class:vanguard:level:1:starting_weapon': ['starter_blade'],
      };
      expect(
        controller.advanceLevel(
          definition,
          catalog: catalog,
          selections: startingChoices,
        ),
        isNull,
      );
      expect(character.level, 1);
      expect(character.className, 'Vanguard');
      expect(character.hitDiceTotal, 1);
      expect(character.saveProficiencies, contains(Ability.str));
      expect(character.traits.map((trait) => trait.name),
          ['Combat Training', 'Tactical Adept']);
      expect(
          character.skills
              .singleWhere((skill) => skill.key == 'survival')
              .isProficient,
          isTrue);
      expect(character.weapons.single.origin,
          'class:vanguard:level:1:choice:starting_weapon');

      expect(
        controller.advanceLevel(definition, catalog: catalog),
        isNull,
      );
      expect(character.level, 2);
      expect(character.hpMax, 18);
      expect(character.hpCurrent, 18);
      expect(character.hitDiceTotal, 2);
      expect(character.classHpLevels, 1);
      expect(
        character.traits.map((trait) => trait.name),
        ['Combat Training', 'Tactical Adept', 'Tactical Surge'],
      );

      expect(
        controller.advanceLevel(definition, catalog: catalog),
        isNotNull,
      );
      expect(character.level, 2);

      expect(
        controller.advanceLevel(
          definition,
          catalog: catalog,
          subclass: ClassSubclass(definition.subclasses.single),
        ),
        isNull,
      );
      expect(character.level, 3);
      expect(character.subclassName, 'Sentinel');
      expect(character.traits.last.name, 'Guardian Stance');
      expect(character.classHpLevels, 2);

      final restored = Character.fromJson(character.toJson());
      expect(restored.classId, 'vanguard');
      expect(restored.subclassId, 'sentinel');
      expect(restored.traits.last.origin, 'subclass:vanguard:sentinel:level:3');

      controller.changeLevel(-1);
      expect(character.level, 2);
      expect(character.traits.map((trait) => trait.name),
          ['Combat Training', 'Tactical Adept', 'Tactical Surge']);
      expect(character.hpMax, 18);
      expect(character.classHpLevels, 1);

      await controller.flush();
      controller.dispose();
    });

    test('XP requirement blocks advancement only when enabled', () {
      final character = Character(id: 'xp-test')
        ..classId = definition.id
        ..className = definition.name
        ..classHitDie = definition.hitDie;
      final controller = CharacterController(
        character: character,
        repository: _MemoryRepository(),
      );

      expect(
        controller.advanceLevel(
          definition,
          catalog: Catalog(),
          requireXp: true,
        ),
        contains('XP'),
      );
      expect(character.level, 1);
      expect(
        controller.advanceLevel(definition, catalog: Catalog()),
        isNull,
      );
      expect(character.level, 2);
      controller.dispose();
    });

    test('XP-leveling setting persists through campaign repository', () async {
      final repository = _MemoryRepository();
      final campaign = CampaignController(repository: repository);
      await campaign.load();
      expect(campaign.requireXpForLevelUp, isFalse);

      await campaign.setRequireXpForLevelUp(true);
      final reloaded = CampaignController(repository: repository);
      await reloaded.load();
      expect(reloaded.requireXpForLevelUp, isTrue);
    });

    test('rejects malformed class definitions', () {
      expect(
        () => ClassDefinition({'name': 'Broken', 'hitDie': 0}),
        throwsFormatException,
      );
      expect(
        () => ClassDefinition({
          'name': 'Broken',
          'hitDie': 8,
          'levels': [
            {'level': 21}
          ]
        }),
        throwsFormatException,
      );
    });
  });
}

class _MemoryRepository implements CampaignRepository {
  bool requireXp = false;

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
  Future<bool> loadRequireXpForLevelUp() async => requireXp;

  @override
  Future<void> saveRequireXpForLevelUp(bool value) async {
    requireXp = value;
  }

  @override
  Future<bool> loadPullAmmoFromInventory() async => false;

  @override
  Future<void> savePullAmmoFromInventory(bool pullAmmo) async {}
}
