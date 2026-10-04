import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/backgrounds.dart';
import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/effect.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/ui/widgets/ability_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/vitals_panel.dart';

void main() {
  test('legacy character affiliations migrate to backgrounds', () {
    final migrated = Character.fromJson({
      'schemaVersion': 1,
      'id': 'legacy-character',
      'affiliation': 'FSB',
      'affiliationId': 'fsb',
      'background': 'Former Soldier',
      'traits': [
        {
          'name': 'Agency Clearance',
          'source': 'Affiliation: FSB',
          'origin': 'affiliation:fsb',
        }
      ],
    });

    expect(migrated.background, 'FSB');
    expect(migrated.backgroundId, 'fsb');
    expect(migrated.affiliation, 'Former Soldier');
    expect(migrated.traits.single.origin, 'background:fsb');
    expect(migrated.traits.single.source, 'Background: FSB');
    expect(migrated.toJson()['schemaVersion'], Character.schemaVersion);
    expect(migrated.toJson().containsKey('affiliationId'), isFalse);
  });

  test('applying a background preserves affiliation and replaces its grants',
      () {
    final character = Character(id: 'background-test')
      ..affiliation = 'Independent';
    applyBackground(
      character,
      BackgroundDefinition(
        id: 'fsb',
        name: 'FSB',
        features: [Trait(name: 'Agency Clearance')],
      ),
    );
    expect(character.background, 'FSB');
    expect(character.affiliation, 'Independent');
    expect(character.traits.single.origin, 'background:fsb');

    applyBackground(
      character,
      BackgroundDefinition(id: 'usec', name: 'USEC'),
    );
    expect(character.background, 'USEC');
    expect(character.affiliation, 'Independent');
    expect(character.traits, isEmpty);
  });

  test('inventory item effects apply only while the item is active', () {
    final character = Character(id: 'effects-test')
      ..armor = [
        Armor(
          name: 'Vest',
          equipped: true,
          effects: [Effect(target: 'ac', value: 2)],
        ),
        Armor(
          name: 'Stored helmet',
          equipped: false,
          effects: [Effect(target: 'ac', value: 4)],
        ),
      ]
      ..items = [
        InventoryItem(
          name: 'Charm',
          active: false,
          effects: [Effect(target: 'ac', value: 3)],
        ),
      ];

    expect(Rules.armorClass(character), 12);

    character.items.single.active = true;
    expect(Rules.armorClass(character), 15);

    final restored = Character.fromJson(character.toJson());
    expect(restored.items.single.active, isTrue);
    expect(restored.items.single.effects.single.target, 'ac');
    expect(Rules.armorClass(restored), 15);
  });

  test('Scout unarmored defense uses DEX and WIS modifiers only without armor',
      () {
    final character = Character(id: 'scout-defense-test')
      ..armorClass = 18
      ..abilityScores[Ability.dex] = 16
      ..abilityScores[Ability.wis] = 14
      ..traits = [
        Trait(
          name: 'Unarmored Defense',
          effects: [
            Effect(
              target: 'ac',
              value: 10,
              components: [
                EffectComponent(ability: 'dex'),
                EffectComponent(ability: 'wis'),
              ],
              condition: 'noBallisticProtection',
              operation: 'setBase',
            ),
          ],
        ),
      ];

    expect(Rules.armorClass(character), 15);

    character.armor.add(Armor(name: 'Clothing', rating: 0, equipped: true));
    expect(Rules.armorClass(character), 15);

    character.armor.add(Armor(name: 'Ballistic vest', rating: 3));
    expect(Rules.armorClass(character), 18);

    character.armor.last.equipped = false;
    expect(Rules.armorClass(character), 15);

    final restored = Character.fromJson(character.toJson());
    expect(Rules.armorClass(restored), 15);
    expect(restored.traits.single.effects.single.components, hasLength(2));
  });

  test('aggregate gear HP is omitted when there is no corresponding gear', () {
    final json = Character(id: 'empty-equipment').toJson();
    expect(json.containsKey('weaponHp'), isFalse);
    expect(json.containsKey('armorHp'), isFalse);
  });

  testWidgets('ability panel shows base score and active bonus separately',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    final character = Character(id: 'ability-bonus-test')
      ..items = [
        InventoryItem(
          name: 'Strength charm',
          active: true,
          effects: [Effect(target: 'ability.str', value: 2)],
        ),
      ];
    final controller = CharacterController(
      character: character,
      repository: _MemoryRepository(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AbilityPanel()),
          ),
        ),
      ),
    );

    expect(find.text('+2 bonus\nTotal 12'), findsOneWidget);
    expect(find.text('+1'), findsNWidgets(2));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.border is OutlineInputBorder &&
            widget.controller?.text == '10',
      ),
      findsNWidgets(6),
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('effect editor selects a stat by its readable name',
      (tester) async {
    var effects = [
      Effect(
        target: 'ac',
        value: 2,
        components: [EffectComponent(ability: 'wis')],
        condition: 'noBallisticProtection',
        operation: 'setBase',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EffectsField(
            effects: effects,
            onChanged: (value) => effects = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit effects (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('effect-target-0-ac')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ability: DEX').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(effects, hasLength(1));
    expect(effects.single.target, 'ability.dex');
    expect(effects.single.value, 2);
    expect(effects.single.components.single.ability, 'wis');
    expect(effects.single.condition, 'noBallisticProtection');
    expect(effects.single.operation, 'setBase');
  });

  testWidgets('current HP controls adjust the value one point at a time',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    final character = Character(id: 'health-controls-test')..hpCurrent = 7;
    final controller = CharacterController(
      character: character,
      repository: _MemoryRepository(),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: VitalsPanel()),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Decrease current HP by 1'));
    await tester.pump();
    expect(character.hpCurrent, 6);
    await tester.tap(find.byTooltip('Increase current HP by 1'));
    await tester.pump();
    expect(character.hpCurrent, 7);
    expect(find.text('Armor Class'), findsOneWidget);
    expect(find.text('Hit Points'), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _MemoryRepository implements CampaignRepository {
  @override
  Future<Map<String, dynamic>> loadCatalogJson() async => {};

  @override
  Future<List<Character>> loadCharacters() async => [];

  @override
  Future<bool> loadRequireXpForLevelUp() async => false;

  @override
  Future<void> saveCatalogJson(Map<String, dynamic> json) async {}

  @override
  Future<void> saveCharacter(Character character) async {}

  @override
  Future<void> saveRequireXpForLevelUp(bool requireXp) async {}

  @override
  Future<void> deleteCharacter(String id) async {}
}
