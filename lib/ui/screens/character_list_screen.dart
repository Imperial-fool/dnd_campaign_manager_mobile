import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/firebase_campaign_service.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/ui/screens/catalog_screen.dart';
import 'package:dnd_campaign_manager/ui/screens/character_creation_screen.dart';
import 'package:dnd_campaign_manager/ui/screens/character_sheet_screen.dart';
import 'package:dnd_campaign_manager/ui/screens/settings_screen.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_screen.dart';

class CharacterListScreen extends StatelessWidget {
  const CharacterListScreen({super.key});

  void _open(
    BuildContext context,
    Character c, {
    bool readOnly = false,
    bool allowEditing = false,
  }) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CharacterSheetScreen(
            character: c,
            readOnly: readOnly,
            allowEditing: allowEditing,
          ),
        ),
      );

  Future<void> _createCharacter(
      BuildContext context, CampaignController campaign) async {
    final character = await Navigator.push<Character>(
      context,
      MaterialPageRoute(builder: (_) => const CharacterCreationScreen()),
    );
    if (!context.mounted) return;
    if (character != null) _open(context, character);
  }

  Future<void> _importCharacter(
    BuildContext context, {
    required bool asPlayer,
  }) async {
    final campaign = context.read<CampaignController>();
    final text =
        await showJsonInputDialog(context, title: 'Import character JSON');
    if (text == null || text.trim().isEmpty) return;
    try {
      final c = asPlayer
          ? await campaign.importPlayerCharacter(text)
          : await campaign.importCharacter(text);
      if (context.mounted) _open(context, c);
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Invalid JSON: ${e.message}')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import character: $error')),
        );
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
    final shared = context.watch<FirebaseCampaignService?>();
    final playerMode = shared?.isConnected == true && shared?.isOwner == false;
    final dmDashboard = shared?.isConnected == true && shared?.isOwner == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          playerMode
              ? 'Your Characters'
              : dmDashboard
                  ? 'DM Campaign Dashboard'
                  : 'Campaign Characters',
        ),
        actions: [
          if (shared?.isConnected == true)
            IconButton(
              tooltip: 'Campaign board',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VttScreen(characters: campaign.characters),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Campaign settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          if (!playerMode) ...[
            IconButton(
              tooltip: 'Catalog (weapons, armor, traits, features)',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CatalogScreen())),
            ),
            IconButton(
              tooltip: 'Import character JSON',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => _importCharacter(context, asPlayer: false),
            ),
            IconButton(
              tooltip: 'Import character from Google Drive',
              icon: const Icon(Icons.cloud_download_outlined),
              onPressed: () => _importCharacterFromDrive(context),
            ),
          ] else if (campaign.allowPlayerCharacterCreation) ...[
            IconButton(
              tooltip: 'Import character JSON',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => _importCharacter(context, asPlayer: true),
            ),
          ],
        ],
      ),
      floatingActionButton: playerMode && !campaign.allowPlayerCharacterCreation
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.person_add),
              label: Text(
                playerMode ? 'Create character' : 'New character',
              ),
              onPressed: () => _createCharacter(context, campaign),
            ),
      body: campaign.loading
          ? const Center(child: CircularProgressIndicator())
          : campaign.characters.isEmpty && !dmDashboard
              ? Center(
                  child: Text(playerMode
                      ? campaign.allowPlayerCharacterCreation
                          ? 'No character yet. Use Create character to get started.'
                          : 'Waiting for the DM to assign a character.'
                      : 'No characters yet. Create one to begin.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: campaign.characters.length + (dmDashboard ? 2 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (dmDashboard && i == 0) {
                      return _dashboardOverview(
                        context,
                        campaign.characters,
                        shared!,
                      );
                    }
                    if (dmDashboard && i == 1) {
                      return _recentPlayerRolls(shared!);
                    }
                    final characterIndex = i - (dmDashboard ? 2 : 0);
                    final c = campaign.characters[characterIndex];
                    return Card(
                      child: ListTile(
                        title: Text(c.name),
                        subtitle: Text([
                          'HP ${c.hpCurrent}/${c.hpMax}',
                          'AC ${c.armorClass}',
                          'Level ${c.level}${c.className.isEmpty ? '' : ' ${c.className}'}',
                          '${c.weapons.length} weapons',
                          '${c.armor.length} armor',
                          '${c.items.length} inventory items',
                          c.race,
                          if (c.background.isNotEmpty)
                            'Background: ${c.background}',
                          if (c.affiliation.isNotEmpty)
                            'Affiliation: ${c.affiliation}',
                          if (c.player.isNotEmpty) 'Player: ${c.player}'
                        ].where((s) => s.isNotEmpty).join(' · ')),
                        onTap: () => _open(
                          context,
                          c,
                          readOnly: dmDashboard,
                          allowEditing: dmDashboard,
                        ),
                        trailing: playerMode
                            ? null
                            : Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  tooltip: 'Duplicate',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () =>
                                      campaign.duplicateCharacter(c),
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

  Widget _dashboardOverview(
    BuildContext context,
    List<Character> characters,
    FirebaseCampaignService shared,
  ) {
    final players = characters
        .map((character) => character.player.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Campaign overview',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${characters.length} characters')),
                Chip(label: Text('${players.length} assigned players')),
              ],
            ),
            const Text(
              'Open a character for a read-only player view. Use Edit in that view to make DM changes.',
            ),
            const SizedBox(height: 12),
            const Text('Players'),
            StreamBuilder<List<CampaignMember>>(
              stream: shared.watchMembers(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Could not load players: ${snapshot.error}');
                }
                final members = snapshot.data ?? const [];
                if (members.isEmpty) {
                  return const Text('No players have joined yet.');
                }
                return Wrap(
                  spacing: 8,
                  children: [
                    for (final member in members)
                      Chip(
                        label: Text(
                          '${member.playerName} · ${characters.where((c) => c.player.toLowerCase() == member.playerName.toLowerCase()).length} characters',
                        ),
                      ),
                  ],
                );
              },
            ),
            const Divider(),
            const Text('Character health'),
            for (final character in characters)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(character.name),
                subtitle: LinearProgressIndicator(
                  value: character.hpMax <= 0
                      ? 0
                      : (character.hpCurrent / character.hpMax).clamp(0.0, 1.0),
                ),
                trailing: Text(
                  '${character.hpCurrent}/${character.hpMax} HP',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _recentPlayerRolls(FirebaseCampaignService shared) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: shared.watchRolls(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Card(
              child: ListTile(
                title: const Text('Player rolls'),
                subtitle: Text('Could not load rolls: ${snapshot.error}'),
              ),
            );
          }
          final rolls = snapshot.data ?? const [];
          return Card(
            child: ExpansionTile(
              title: const Text('Recent player rolls'),
              subtitle: Text('${rolls.length} shown'),
              children: [
                if (rolls.isEmpty)
                  const ListTile(title: Text('No player rolls yet.')),
                for (final roll in rolls.take(12))
                  ListTile(
                    dense: true,
                    leading: roll['total'] is num
                        ? CircleAvatar(child: Text('${roll['total']}'))
                        : const Icon(Icons.casino_outlined),
                    title: Text(
                      '${roll['playerName'] ?? 'Player'} · ${roll['characterName'] ?? 'Character'}',
                    ),
                    subtitle: Text([
                      '${roll['title'] ?? 'Roll'}',
                      if (roll['lines'] is List)
                        (roll['lines'] as List).join(' · '),
                    ].join(' — ')),
                  ),
              ],
            ),
          );
        },
      );
}
