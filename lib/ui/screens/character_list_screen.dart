import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/ui/screens/catalog_screen.dart';
import 'package:dnd_campaign_manager/ui/screens/character_sheet_screen.dart';
import 'package:dnd_campaign_manager/ui/screens/settings_screen.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';

class CharacterListScreen extends StatelessWidget {
  const CharacterListScreen({super.key});

  void _open(BuildContext context, Character c) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CharacterSheetScreen(character: c)),
      );

  Future<void> _importCharacter(BuildContext context) async {
    final campaign = context.read<CampaignController>();
    final text =
        await showJsonInputDialog(context, title: 'Import character JSON');
    if (text == null || text.trim().isEmpty) return;
    try {
      final c = await campaign.importCharacter(text);
      if (context.mounted) _open(context, c);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid JSON: ${e.message}')));
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Character c) async {
    final campaign = context.read<CampaignController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text('This removes the character file permanently.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await campaign.deleteCharacter(c);
  }

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campaign Characters'),
        actions: [
          IconButton(
            tooltip: 'Campaign settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Catalog (weapons, armor, traits, features)',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CatalogScreen())),
          ),
          IconButton(
            tooltip: 'Import character JSON',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _importCharacter(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('New character'),
        onPressed: () async => _open(context, await campaign.createCharacter()),
      ),
      body: campaign.loading
          ? const Center(child: CircularProgressIndicator())
          : campaign.characters.isEmpty
              ? const Center(
                  child: Text('No characters yet. Create one to begin.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: campaign.characters.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = campaign.characters[i];
                    return Card(
                      child: ListTile(
                        title: Text(c.name),
                        subtitle: Text([
                          c.race,
                          c.affiliation,
                          if (c.player.isNotEmpty) 'Player: ${c.player}'
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        onTap: () => _open(context, c),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: 'Duplicate',
                            icon: const Icon(Icons.copy),
                            onPressed: () => campaign.duplicateCharacter(c),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(context, c),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
