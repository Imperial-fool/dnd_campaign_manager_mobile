import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/ui/screens/catalog_screen.dart';

void main() {
  testWidgets('imports a bundled content pack without a file picker',
      (tester) async {
    final assets = _ContentAssetBundle();
    final campaign = CampaignController(repository: _MemoryRepository());
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
    expect(assets.loaded, isTrue);

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

class _ContentAssetBundle extends CachingAssetBundle {
  bool loaded = false;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != 'content/tarkov_character_options.json') {
      throw FlutterError('Unexpected asset: $key');
    }
    loaded = true;
    return File(key).readAsStringSync();
  }

  @override
  Future<ByteData> load(String key) async {
    loaded = true;
    if (key != 'content/tarkov_character_options.json') {
      throw FlutterError('Unexpected asset: $key');
    }
    final bytes =
        File('content/tarkov_character_options.json').readAsBytesSync();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
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
