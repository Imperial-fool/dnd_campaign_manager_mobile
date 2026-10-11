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
      ..upsert(
          'items',
          InventoryItem(
            name: '9x18mm Ammo',
            kind: 'ammo',
            category: 'ammo',
            ammoType: '9x18mm',
          ))
      ..upsert(
          'items',
          InventoryItem(
            name: '9x39 Alpha',
            kind: 'ammo',
            category: 'ammo',
            ammoType: '9x39',
          ))
      ..upsert(
          'items',
          InventoryItem(
            name: '9x19 Zeta',
            kind: 'ammo',
            category: 'ammo',
            ammoType: '9x19',
          ))
      ..upsert(
          'items',
          InventoryItem(
            name: '5.56x45 Zeta',
            kind: 'ammo',
            category: 'ammo',
            ammoType: '5.56x45',
          ))
      ..upsert(
          'items',
          InventoryItem(
            name: '5.56x45 Alpha',
            kind: 'ammo',
            category: 'ammo',
            ammoType: '5.56x45',
          ))
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
    // Ammo sub sections are sorted by type and start collapsed.
    expect(find.text('5.56x45'), findsOneWidget);
    expect(find.text('5.56x45 Alpha'), findsNothing);
    for (final type in ['5.56x45', '9x18mm', '9x19', '9x39']) {
      await tester.ensureVisible(find.text(type));
      await tester.tap(find.text(type));
      await tester.pumpAndSettle();
    }
    final labels = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    int at(String label) => labels.indexOf(label);
    expect(at('Flashlight'), lessThan(at('Zinc Tool')));
    expect(at('Zinc Tool'), lessThan(at('AFAK Medical Kit')));
    expect(at('AFAK Medical Kit'), lessThan(at('Aluminum Splint')));
    expect(at('Aluminum Splint'), lessThan(at('Army Bandage Pack')));
    expect(at('Army Bandage Pack'), lessThan(at('5.56x45')));
    expect(at('5.56x45 Alpha'), lessThan(at('5.56x45 Zeta')));
    expect(at('5.56x45 Zeta'), lessThan(at('9x18mm Ammo')));
    expect(at('9x19 Zeta'), lessThan(at('9x39 Alpha')));
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
