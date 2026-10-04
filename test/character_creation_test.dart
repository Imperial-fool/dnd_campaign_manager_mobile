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
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
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
  });

  testWidgets('keeps direct creation when no class definitions are loaded',
      (tester) async {
    final campaign = CampaignController(
      repository: _MemoryRepository(),
      assetBundle: ContentAssetBundle(),
    );
    await campaign.load();

    await tester.pumpWidget(_app(campaign));
    await tester.tap(find.text('New character'));
    await tester.pumpAndSettle();

    expect(find.text('Character details'), findsNothing);
    expect(campaign.characters, hasLength(1));
    expect(campaign.characters.single.classId, isEmpty);
    expect(find.text('New Character').last, findsOneWidget);
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
}
