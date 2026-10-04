import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';

void main() {
  testWidgets('groups catalog items by type and sorts within groups',
      (tester) async {
    final campaign = CampaignController(repository: _MemoryRepository());
    campaign.catalog
      ..upsert('items', InventoryItem(name: 'Zinc Tool'))
      ..upsert('items',
          InventoryItem(name: '9mm Ammo', kind: 'ammo', category: 'ammo'))
      ..upsert('items',
          InventoryItem(name: 'Army Bandage Pack', category: 'medical'))
      ..upsert(
          'items', InventoryItem(name: 'Aluminum Splint', category: 'medical'))
      ..upsert(
          'items', InventoryItem(name: 'AFAK Medical Kit', category: 'medical'))
      ..upsert('items', InventoryItem(name: 'Flashlight'));

    await tester.pumpWidget(
      ChangeNotifierProvider<CampaignController>.value(
        value: campaign,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => pickCatalogItem(
                  context,
                  ContentRegistry.standard()['items']!,
                ),
                child: const Text('Open items'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open items'));
    await tester.pumpAndSettle();

    expect(find.text('Ammo'), findsOneWidget);
    expect(find.text('Medical equipment'), findsOneWidget);
    expect(find.text('Tools / misc'), findsOneWidget);
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(labels.indexOf('9mm Ammo'),
        lessThan(labels.indexOf('AFAK Medical Kit')));
    expect(
      labels.indexOf('AFAK Medical Kit'),
      lessThan(labels.indexOf('Aluminum Splint')),
    );
    expect(
      labels.indexOf('Aluminum Splint'),
      lessThan(labels.indexOf('Army Bandage Pack')),
    );
    expect(
      labels.indexOf('Army Bandage Pack'),
      lessThan(labels.indexOf('Flashlight')),
    );
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
}
