import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/ui/screens/catalog_screen.dart';
import 'package:dnd_campaign_manager/ui/screens/character_creation_screen.dart';
import 'package:dnd_campaign_manager/ui/screens/character_sheet_screen.dart';
import 'package:dnd_campaign_manager/ui/screens/settings_screen.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';

class CharacterListScreen extends StatelessWidget {
  const CharacterListScreen({super.key});

  void _open(BuildContext context, Character c) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CharacterSheetScreen(character: c)),
      );

  Future<void> _createCharacter(
      BuildContext context, CampaignController campaign) async {
    final classes =
        campaign.catalog.items('classes').whereType<ClassDefinition>().toList();
    if (classes.isEmpty) {
      final character = await campaign.createCharacter();
      if (context.mounted) _open(context, character);
      return;
    }
    final character = await Navigator.push<Character>(
      context,
      MaterialPageRoute(builder: (_) => const CharacterCreationScreen()),
    );
    if (!context.mounted) return;
    if (character != null) _open(context, character);
  }

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

  Future<void> _importCharacterFromDrive(BuildContext context) async {
    final campaign = context.read<CampaignController>();
    final drive = context.read<GoogleDriveService>();
    if (!drive.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Connect your Google Drive in Campaign Settings first.'),
        ),
      );
      return;
    }

    final List<DriveJsonFile> files;
    try {
      files = await drive.listCharacterFiles();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not list Drive characters: $error')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final selected = await showDialog<DriveJsonFile>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import character from Google Drive'),
        content: SizedBox(
          width: 480,
          height: 420,
          child: files.isEmpty
              ? const Center(
                  child: Text('No characters saved by this app in your Drive.'),
                )
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(file.name),
                      onTap: () => Navigator.pop(dialogContext, file),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;

    try {
      final json = await drive.readJsonFile(selected.id);
      final character = await campaign.importCharacter(json);
      if (context.mounted) _open(context, character);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not import ${selected.name}: $error'),
          ),
        );
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
          IconButton(
            tooltip: 'Import character from Google Drive',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: () => _importCharacterFromDrive(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('New character'),
        onPressed: () => _createCharacter(context, campaign),
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
                          if (c.background.isNotEmpty)
                            'Background: ${c.background}',
                          if (c.affiliation.isNotEmpty)
                            'Affiliation: ${c.affiliation}',
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
