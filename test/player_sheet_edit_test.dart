import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/ui/screens/character_sheet_screen.dart';
import 'package:dnd_campaign_manager/ui/widgets/gear_panels.dart';
import 'package:dnd_campaign_manager/ui/widgets/inventory_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/stash_panel.dart';
import 'support/content_asset_bundle.dart';

void main() {
  testWidgets('character sheet separates sections and supports spell editing',
      (tester) async {
    final repository = _MemoryRepository();
    final campaign = CampaignController(
      repository: repository,
      assetBundle: ContentAssetBundle(),
    );
    await campaign.load();
    final character = Character(id: 'sectioned-sheet')..name = 'Test Hero';
    final drive = GoogleDriveService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CampaignController>.value(value: campaign),
          ChangeNotifierProvider<GoogleDriveService>.value(value: drive),
        ],
        child: MaterialApp(
          home: CharacterSheetScreen(character: character),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final section in [
      'Abilities',
      'Skills',
      'Combat',
      'Spells',
      'Inventory',
      'Feats',
      'Features & Traits',
      'Notes',
    ]) {
      expect(find.text(section), findsOneWidget);
    }

    await tester.tap(
      find.descendant(
        of: find.byType(TabBar).first,
        matching: find.text('Combat'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar).first)).index,
      3,
    );
    expect(find.text('DICE'), findsOneWidget);
    expect(find.text('Roll (e.g. 2d6+3)'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Roll'));
    await tester.pump();
    expect(find.text('No rolls yet.'), findsNothing);

    await tester.ensureVisible(find.text('Spells'));
    await tester.tap(find.text('Spells'));
    await tester.pumpAndSettle();
    expect(find.text('No spells yet. Add one or import spells to the catalog.'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Add blank spell'));
    await tester.pump();
    expect((character.extras['spells'] as List).single['name'], 'New Spell');
    expect(find.text('Spell name'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    drive.dispose();
    campaign.dispose();
  });

  testWidgets('player mode exposes the full editable gear panels',
      (tester) async {
    final repository = _MemoryRepository();
    final campaign = CampaignController(
      repository: repository,
      assetBundle: ContentAssetBundle(),
    );
    await campaign.load();
    final character = Character(id: 'player-sheet')
      ..items = [InventoryItem(name: 'Ration')]
      ..weapons = [Weapon(name: 'Rifle')]
      ..armor = [Armor(name: 'Vest')];
    final editor = CharacterController(
      character: character,
      repository: repository,
      isPlayerMode: true,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CampaignController>.value(value: campaign),
          ChangeNotifierProvider<CharacterController>.value(value: editor),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  WeaponsPanel(),
                  ArmorPanel(),
                  InventoryPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.widgetList<TextField>(find.byType(TextField)).every(
            (field) => field.enabled == true,
          ),
      isTrue,
    );
    expect(find.text('Weapon name'), findsOneWidget);
    expect(find.text('Ammo type'), findsOneWidget);
    expect(find.text('Armor name'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('Damage dice'), findsOneWidget);
    expect(find.text('Description'), findsWidgets);

    final addWeapon = find.byTooltip('Add blank').first;
    await tester.ensureVisible(addWeapon);
    await tester.pumpAndSettle();
    await tester.tap(addWeapon);
    await tester.pump();
    final addArmor = find.byTooltip('Add blank').last;
    await tester.ensureVisible(addArmor);
    await tester.pumpAndSettle();
    await tester.tap(addArmor);
    await tester.pump();
    final addItem = find.byTooltip('Add item');
    await tester.ensureVisible(addItem);
    await tester.pumpAndSettle();
    await tester.tap(addItem);
    await tester.pump();

    expect(character.weapons, hasLength(2));
    expect(character.armor, hasLength(2));
    expect(character.items, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    campaign.dispose();
  });

  testWidgets('stash displays item quantity and weapon and armor details',
      (tester) async {
    final repository = _MemoryRepository();
    final campaign = CampaignController(
      repository: repository,
      assetBundle: ContentAssetBundle(),
    );
    await campaign.load();
    final character = await campaign.createCharacter('Player')
      ..player = 'Player One';
    final weapon = Weapon(name: 'Stored rifle', ammoType: '5.56', ammoMax: 30);
    final armor = Armor(name: 'Stored vest', rating: 4, hp: 7, hpMax: 10);
    final item = InventoryItem(name: 'Rations', quantity: 5);
    character.weapons.add(weapon);
    character.armor.add(armor);
    character.items.add(item);
    await campaign.moveToStash(character, 'weapons', weapon);
    await campaign.moveToStash(character, 'armor', armor);
    await campaign.moveToStash(character, 'items', item);
    final editor = CharacterController(
      character: character,
      repository: repository,
      isPlayerMode: true,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CampaignController>.value(value: campaign),
          ChangeNotifierProvider<CharacterController>.value(value: editor),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: StashPanel())),
        ),
      ),
    );

    expect(find.text('x5'), findsOneWidget);
    expect(find.text('x1'), findsNWidgets(2));
    expect(find.textContaining('Magazine 0/30'), findsOneWidget);
    expect(find.textContaining('Rating 4 · HP 7/10'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    editor.dispose();
    campaign.dispose();
  });
}

class _MemoryRepository implements CampaignRepository {
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

  @override
  Future<bool> loadPullAmmoFromInventory() async => false;

  @override
  Future<void> savePullAmmoFromInventory(bool pullAmmo) async {}
}
