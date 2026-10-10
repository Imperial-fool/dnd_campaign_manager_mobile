import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/logic/sample_content.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/ui/screens/character_list_screen.dart';
import 'support/content_asset_bundle.dart';

void main() {
  testWidgets('uses guided creation when class definitions are loaded',
      (tester) async {
    final campaign = CampaignController(
      repository: _MemoryRepository(),
      assetBundle: ContentAssetBundle(),
    );
    await campaign.load();
    await campaign.importContent(sampleContentPack);

    await tester.pumpWidget(_app(campaign));
    await tester.tap(find.text('New character'));
    await tester.pumpAndSettle();

    expect(find.text('Character details'), findsOneWidget);
    final backgroundDropdown =
        find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(backgroundDropdown);
    await tester.pumpAndSettle();
    await tester.tap(backgroundDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zaslon').last);
    await tester.pumpAndSettle();

    final classDropdown = find.byType(DropdownButtonFormField<String>).last;
    await tester.ensureVisible(classDropdown);
    await tester.pumpAndSettle();
    await tester.tap(classDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vanguard').last);
    await tester.pumpAndSettle();
    final createButton = find.widgetWithText(FilledButton, 'Create character');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(campaign.characters, hasLength(1));
    expect(campaign.characters.single.className, 'Vanguard');
    expect(campaign.characters.single.level, 1);
    expect(campaign.characters.single.hitDiceTotal, 1);
    expect(campaign.characters.single.background, 'Zaslon');
    expect(
      campaign.characters.single.traits.map((trait) => trait.name),
      contains('Zaslon Operative'),
    );
  });

  testWidgets('shows character creation when no class definitions are loaded',
      (tester) async {
    final campaign = CampaignController(
      repository: _MemoryRepository(),
      assetBundle: ContentAssetBundle(),
    );
    await campaign.load();

    await tester.pumpWidget(_app(campaign));
    await tester.tap(find.text('New character'));
    await tester.pumpAndSettle();

    expect(find.text('Character details'), findsOneWidget);
    final backgroundDropdown =
        find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(backgroundDropdown);
    await tester.pumpAndSettle();
    await tester.tap(backgroundDropdown);
    await tester.pumpAndSettle();
    expect(find.text('Zaslon'), findsOneWidget);
    await tester.tap(find.text('Zaslon').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('No class definitions are loaded.'),
        findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, 'Create character');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(campaign.characters, hasLength(1));
    expect(campaign.characters.single.classId, isEmpty);
    expect(campaign.characters.single.background, 'Zaslon');
    expect(find.text('New Character').last, findsOneWidget);
  });

  testWidgets('rolls and displays six 4d6 drop-lowest ability scores',
      (tester) async {
    final campaign = CampaignController(
      repository: _MemoryRepository(),
      assetBundle: ContentAssetBundle(),
    );
    await campaign.load();

    await tester.pumpWidget(_app(campaign));
    await tester.tap(find.text('New character'));
    await tester.pumpAndSettle();
    final rollButton = find.text('Roll 4d6 · drop lowest 1');
    await tester.ensureVisible(rollButton);
    await tester.pumpAndSettle();
    await tester.tap(rollButton);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.textContaining('Roll 6:'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Roll 1:'), findsOneWidget);
    expect(find.textContaining('Roll 6:'), findsOneWidget);
    expect(find.textContaining('score '), findsNWidgets(6));
  });
}

Widget _app(CampaignController campaign) => MultiProvider(
      providers: [
        ChangeNotifierProvider<CampaignController>.value(value: campaign),
        ChangeNotifierProvider<GoogleDriveService>.value(
            value: GoogleDriveService()),
      ],
      child: const MaterialApp(home: CharacterListScreen()),
    );

class _MemoryRepository implements CampaignRepository {
  final characters = <Character>[];
  Map<String, dynamic> catalog = {};

  @override
  Future<List<Character>> loadCharacters() async => characters;

  @override
  Future<void> saveCharacter(Character character) async {
    if (!characters.any((existing) => existing.id == character.id)) {
      characters.add(character);
    }
  }

  @override
  Future<void> deleteCharacter(String id) async {
    characters.removeWhere((character) => character.id == id);
  }

  @override
  Future<Map<String, dynamic>> loadCatalogJson() async => catalog;

  @override
  Future<void> saveCatalogJson(Map<String, dynamic> json) async {
    catalog = json;
  }

  @override
  Future<bool> loadRequireXpForLevelUp() async => false;

  @override
  Future<void> saveRequireXpForLevelUp(bool requireXp) async {}

  @override
  Future<bool> loadPullAmmoFromInventory() async => false;

  @override
  Future<void> savePullAmmoFromInventory(bool pullAmmo) async {}
}
