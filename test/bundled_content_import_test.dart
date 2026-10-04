import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/ui/screens/catalog_screen.dart';
import 'support/content_asset_bundle.dart';

void main() {
  testWidgets('imports a bundled content pack without a file picker',
      (tester) async {
    final assets = ContentAssetBundle();
    final campaign = CampaignController(
        repository: _MemoryRepository(), assetBundle: assets);
    await campaign.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CampaignController>.value(value: campaign),
          ChangeNotifierProvider<GoogleDriveService>.value(
            value: GoogleDriveService(),
          ),
        ],
        child: MaterialApp(
          home: CatalogScreen(assetBundle: assets),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Import built-in content pack'));
    await tester.pumpAndSettle();
    expect(find.text('Tarkov Character Options'), findsOneWidget);
    await tester.tap(find.text('Tarkov Character Options'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      assets.loadedAssets,
      contains('content/tarkov_character_options.json'),
    );

    expect(
      find.text('Import complete'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join('\n'),
    );
    expect(
      campaign.catalog.items('classes'),
      isNotEmpty,
      reason: campaign.exportCatalog(),
    );
    expect(campaign.catalog.items('weapons'), isNotEmpty);
  });
}

class _MemoryRepository implements CampaignRepository {
  Map<String, dynamic> catalogJson = {};

  @override
  Future<List<Character>> loadCharacters() async => [];

  @override
  Future<void> saveCharacter(Character character) async {}

  @override
  Future<void> deleteCharacter(String id) async {}

  @override
  Future<Map<String, dynamic>> loadCatalogJson() async => catalogJson;

  @override
  Future<void> saveCatalogJson(Map<String, dynamic> json) async {
    catalogJson = json;
  }

  @override
  Future<bool> loadRequireXpForLevelUp() async => false;

  @override
  Future<void> saveRequireXpForLevelUp(bool requireXp) async {}
}
