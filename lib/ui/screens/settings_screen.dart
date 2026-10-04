import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
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

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    final drive = context.watch<GoogleDriveService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Campaign Settings')),
      body: ListView(
        children: [
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
        ],
      ),
    );
  }
}
