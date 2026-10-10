import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/firebase_campaign_service.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/ui/widgets/google_sign_in_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _working = false;

  Future<void> _connect(GoogleDriveService drive) async {
    setState(() => _working = true);
    try {
      await drive.signIn();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect to Google Drive: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect(GoogleDriveService drive) async {
    setState(() => _working = true);
    try {
      await drive.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not disconnect Google Drive: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _authorizeDrive(GoogleDriveService drive) async {
    setState(() => _working = true);
    try {
      await drive.authorizeDriveAccess();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not authorize Google Drive access: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createSharedCampaign(
    BuildContext context,
    CampaignController campaign,
  ) async {
    setState(() => _working = true);
    try {
      final code = await campaign.createSharedCampaign();
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Campaign created'),
            content: SelectableText(
              'Share this join code with your players:\n\n$code',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not create shared campaign: $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _joinSharedCampaign(
    BuildContext context,
    CampaignController campaign,
  ) async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final details = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join campaign'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'DM join code'),
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Player name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              (codeController.text, nameController.text),
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    codeController.dispose();
    nameController.dispose();
    if (!context.mounted) return;
    if (details == null) {
      return;
    }
    if (details.$1.trim().isEmpty || details.$2.trim().isEmpty) {
      _showError(context, 'Enter both the join code and your player name.');
      return;
    }
    setState(() => _working = true);
    try {
      await campaign.joinSharedCampaign(
        code: details.$1,
        playerName: details.$2,
      );
    } catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not join campaign: $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _leaveSharedCampaign(
    BuildContext context,
    CampaignController campaign,
  ) async {
    setState(() => _working = true);
    try {
      await campaign.leaveSharedCampaign();
    } catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not leave campaign: $error');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(BuildContext context, String text) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Widget _sharedCampaignCard(
    BuildContext context,
    CampaignController campaign,
    FirebaseCampaignService shared,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.groups_outlined),
              title: Text('Shared campaign'),
              subtitle: Text(
                'Players join without an account. The DM controls character assignments, levels, and item stats.',
              ),
            ),
            if (!shared.isConfigured)
              Text(shared.configurationError ?? 'Firebase is unavailable.')
            else if (shared.isConnected) ...[
              Text(
                shared.isOwner
                    ? 'DM mode · join code ${shared.joinCode}'
                    : 'Player mode · joined as ${shared.playerName}',
              ),
              if (shared.isOwner)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: shared.joinCode!),
                        ),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy join code'),
                      ),
                      TextButton.icon(
                        onPressed: _working
                            ? null
                            : () => _leaveSharedCampaign(context, campaign),
                        icon: const Icon(Icons.cloud_off_outlined),
                        label: const Text('Disconnect on this device'),
                      ),
                    ],
                  ),
                )
              else
                TextButton.icon(
                  onPressed: _working
                      ? null
                      : () => _leaveSharedCampaign(context, campaign),
                  icon: const Icon(Icons.logout),
                  label: const Text('Leave campaign'),
                ),
              TextButton.icon(
                onPressed: _working
                    ? null
                    : () async {
                        setState(() => _working = true);
                        try {
                          await campaign.refreshSharedCampaign();
                        } catch (error) {
                          if (context.mounted) {
                            _showError(
                                context, 'Could not refresh campaign: $error');
                          }
                        } finally {
                          if (mounted) setState(() => _working = false);
                        }
                      },
                icon: const Icon(Icons.sync),
                label: const Text('Refresh rules and items'),
              ),
              if (shared.isOwner) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: campaign.allowPlayerCharacterCreation,
                  title: const Text('Allow players to create characters'),
                  subtitle: const Text(
                    'Players can create a level 1 character assigned to '
                    'themselves. Character level progression and gear '
                    'definitions remain DM-controlled.',
                  ),
                  onChanged: _working
                      ? null
                      : (value) async {
                          setState(() => _working = true);
                          try {
                            await campaign
                                .setAllowPlayerCharacterCreation(value);
                          } catch (error) {
                            if (context.mounted) {
                              _showError(context,
                                  'Could not update character creation: $error');
                            }
                          } finally {
                            if (mounted) setState(() => _working = false);
                          }
                        },
                ),
                _dmAssignments(context, campaign, shared),
              ],
            ] else
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () => _createSharedCampaign(context, campaign),
                    icon: const Icon(Icons.add_link),
                    label: const Text('Create join code'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () => _joinSharedCampaign(context, campaign),
                    icon: const Icon(Icons.login),
                    label: const Text('Join with code'),
                  ),
                ],
              ),
            if (shared.isConfigured) _accountSection(context, campaign, shared),
            if (shared.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Sync error: ${shared.lastError}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _accountSection(
    BuildContext context,
    CampaignController campaign,
    FirebaseCampaignService shared,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          if (!shared.isGoogleLinked) ...[
            const Text(
              'Sign in with Google to keep access to your campaigns on any '
              'device, even if you lose the join code.',
            ),
            TextButton.icon(
              onPressed: _working
                  ? null
                  : () => _runAccountAction(
                        context,
                        'Could not sign in',
                        campaign.signInWithGoogleAccount,
                      ),
              icon: const Icon(Icons.account_circle_outlined),
              label: const Text('Sign in with Google'),
            ),
          ] else ...[
            Text('Signed in as ${shared.accountEmail ?? 'Google account'}'),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : () => _showSavedCampaigns(context, campaign),
                  icon: const Icon(Icons.history),
                  label: const Text('My campaigns'),
                ),
                TextButton(
                  onPressed: _working
                      ? null
                      : () => _runAccountAction(
                            context,
                            'Could not sign out',
                            campaign.signOutGoogleAccount,
                          ),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _runAccountAction(
    BuildContext context,
    String failure,
    Future<void> Function() action,
  ) async {
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (context.mounted) _showError(context, '$failure: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showSavedCampaigns(
    BuildContext context,
    CampaignController campaign,
  ) async {
    final List<SavedCampaign> saved;
    try {
      saved = await campaign.savedCampaigns();
    } catch (error) {
      if (!context.mounted) return;
      _showError(context, 'Could not load your campaigns: $error');
      return;
    }
    if (!context.mounted) return;
    final choice = await showDialog<SavedCampaign>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('My campaigns'),
        content: SizedBox(
          width: 400,
          child: saved.isEmpty
              ? const Text('No campaigns are linked to this account yet.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final s in saved)
                      ListTile(
                        leading: Icon(s.owner
                            ? Icons.shield_outlined
                            : Icons.person_outline),
                        title: Text(s.owner
                            ? 'DM · ${s.code}'
                            : 'Player · ${s.playerName ?? s.code}'),
                        subtitle: Text(s.code),
                        onTap: () => Navigator.pop(dialogContext, s),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    await _runAccountAction(
      context,
      'Could not open campaign',
      () => campaign.resumeSavedCampaign(choice),
    );
  }

  Widget _dmAssignments(
    BuildContext context,
    CampaignController campaign,
    FirebaseCampaignService shared,
  ) {
    return StreamBuilder(
      stream: shared.watchMembers(),
      builder: (context, membersSnapshot) {
        if (membersSnapshot.hasError) {
          return Text('Could not load players: ${membersSnapshot.error}');
        }
        final members = membersSnapshot.data ?? const [];
        return StreamBuilder(
          stream: shared.watchAssignments(),
          builder: (context, assignmentSnapshot) {
            if (assignmentSnapshot.hasError) {
              return Text(
                  'Could not load assignments: ${assignmentSnapshot.error}');
            }
            final assignments = assignmentSnapshot.data ?? const [];
            if (campaign.characters.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Create characters to assign them to players.'),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                Text('Players (${members.length})'),
                if (members.isEmpty)
                  const Text('No players have joined yet.')
                else
                  for (final character in assignments)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(character.characterName),
                      trailing: DropdownButton<String?>(
                        value: members.any((m) => m.uid == character.playerUid)
                            ? character.playerUid
                            : null,
                        hint: const Text('Unassigned'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Unassigned'),
                          ),
                          for (final member in members)
                            DropdownMenuItem<String?>(
                              value: member.uid,
                              child: Text(member.playerName),
                            ),
                        ],
                        onChanged: _working
                            ? null
                            : (uid) async {
                                try {
                                  await campaign.assignCharacterToPlayer(
                                    character.characterId,
                                    uid,
                                  );
                                } catch (error) {
                                  if (context.mounted) {
                                    _showError(context,
                                        'Could not assign character: $error');
                                  }
                                }
                              },
                      ),
                    ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    final drive = context.watch<GoogleDriveService>();
    final shared = context.watch<FirebaseCampaignService?>();
    return Scaffold(
      appBar: AppBar(title: const Text('Campaign Settings')),
      body: ListView(
        children: [
          if (shared != null) _sharedCampaignCard(context, campaign, shared),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: const Text('Google Drive'),
                  subtitle: Text(
                    !drive.isPlatformSupported
                        ? 'Available in web, Android, iOS, and macOS builds.'
                        : !drive.isConfigured
                            ? 'Set GOOGLE_OAUTH_CLIENT_ID when building the app. See the README for setup steps.'
                            : drive.accountEmail == null
                                ? 'Sign in with your Google account to use your Drive.'
                                : drive.isDriveAuthorized
                                    ? 'Connected as ${drive.accountEmail}.'
                                    : 'Signed in as ${drive.accountEmail}. Allow access to Drive to continue.',
                  ),
                ),
                if (drive.authenticationError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Google sign-in failed: ${drive.authenticationError}',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (drive.isSignedIn && drive.isDriveAuthorized)
                        TextButton.icon(
                          onPressed: _working ? null : () => _disconnect(drive),
                          icon: const Icon(Icons.logout),
                          label: const Text('Disconnect'),
                        )
                      else if (drive.isSignedIn)
                        FilledButton.icon(
                          onPressed:
                              _working ? null : () => _authorizeDrive(drive),
                          icon: _working
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_outlined),
                          label: const Text('Allow Drive access'),
                        )
                      else if (drive.isPlatformSupported &&
                          drive.isConfigured &&
                          kIsWeb)
                        SizedBox(
                          width: 240,
                          height: 44,
                          child: buildGoogleSignInButton(),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _working ||
                                  !drive.isPlatformSupported ||
                                  !drive.isConfigured
                              ? null
                              : () => _connect(drive),
                          icon: _working
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: const Text('Connect'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (shared?.isConnected == true && shared?.isOwner == false)
            ListTile(
              title: const Text('Require XP to level up'),
              subtitle: Text(
                'DM-controlled rule · ${campaign.requireXpForLevelUp ? 'required' : 'not required'}',
              ),
            )
          else
            SwitchListTile(
              value: campaign.requireXpForLevelUp,
              title: const Text('Require XP to level up'),
              subtitle: Text(
                campaign.requireXpForLevelUp
                    ? 'Characters must meet the standard XP threshold before advancing.'
                    : 'Level-ups are manual; XP thresholds are informational only.',
              ),
              onChanged: campaign.setRequireXpForLevelUp,
            ),
          if (shared?.isConnected == true && shared?.isOwner == false)
            ListTile(
              title: const Text('Pull ammo from inventory when firing'),
              subtitle: Text(
                'DM-controlled rule · ${campaign.pullAmmoFromInventory ? 'enabled' : 'disabled'}',
              ),
            )
          else
            SwitchListTile(
              value: campaign.pullAmmoFromInventory,
              title: const Text('Pull ammo from inventory when firing'),
              subtitle: Text(
                campaign.pullAmmoFromInventory
                    ? 'Magazine weapons can use inventory rounds when their loaded ammo is short.'
                    : 'Magazine weapons must be reloaded before firing; weapons without a magazine still use inventory ammo.',
              ),
              onChanged: campaign.setPullAmmoFromInventory,
            ),
        ],
      ),
    );
  }
}
