import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/logic/sample_content.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';

/// Browse the campaign catalog and import content packs (JSON).
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  Future<void> _import(BuildContext context) async {
    final campaign = context.read<CampaignController>();
    final text = await showJsonInputDialog(
      context,
      title: 'Import content pack',
      sample: sampleContentPack,
    );
    if (text == null || text.trim().isEmpty) return;
    final result = await campaign.importContent(text);
    if (context.mounted) showImportResult(context, result);
  }

  Future<void> _importFile(BuildContext context) async {
    final campaign = context.read<CampaignController>();
    final PlatformFile? file;
    final List<int> bytes;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return;
      bytes = await file.readAsBytes();
    } on PlatformException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Could not open JSON file picker: ${error.message ?? error.code}')),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final String jsonText;
    try {
      jsonText = utf8.decode(bytes);
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${file.name} is not valid UTF-8 JSON text: ${error.message}')),
      );
      return;
    }

    final result = await campaign.importContent(jsonText);
    if (context.mounted) showImportResult(context, result);
  }

  Future<void> _importFromDrive(BuildContext context) async {
    final campaign = context.read<CampaignController>();
    final drive = context.read<GoogleDriveService>();
    if (!drive.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect Google Drive in Campaign Settings first.'),
        ),
      );
      return;
    }

    final List<DriveJsonFile> files;
    try {
      files = await drive.listJsonFiles();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not list Google Drive files: $error')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    final selected = await showDialog<DriveJsonFile>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import content pack from Google Drive'),
        content: SizedBox(
          width: 480,
          height: 420,
          child: files.isEmpty
              ? const Center(
                  child: Text('No JSON files found in Google Drive.'))
              : ListView.separated(
                  itemCount: files.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final file = files[index];
                    return ListTile(
                      leading: const Icon(Icons.data_object),
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
      final text = await drive.readJsonFile(selected.id);
      final result = await campaign.importContent(text);
      if (context.mounted) showImportResult(context, result);
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

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    final bindings = campaign.registry.bindings;
    return DefaultTabController(
      length: bindings.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Campaign Catalog'),
          actions: [
            IconButton(
              tooltip: 'Import JSON text',
              icon: const Icon(Icons.content_paste),
              onPressed: () => _import(context),
            ),
            IconButton(
              tooltip: 'Import JSON from Google Drive',
              icon: const Icon(Icons.cloud_download_outlined),
              onPressed: () => _importFromDrive(context),
            ),
            IconButton(
              tooltip: 'View catalog JSON',
              icon: const Icon(Icons.data_object),
              onPressed: () => showJsonViewDialog(context,
                  title: 'catalog.json', json: campaign.exportCatalog()),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final b in bindings) Tab(text: b.label)],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.upload_file),
          label: const Text('Import JSON file'),
          onPressed: () => _importFile(context),
        ),
        body: TabBarView(children: [
          for (final b in bindings)
            Builder(builder: (context) {
              final items = campaign.catalog.items(b.key);
              if (items.isEmpty) {
                return Center(
                    child: Text(
                        'No ${b.label.toLowerCase()} yet. Import a content pack.'));
              }
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final item in items)
                    Card(
                      child: ListTile(
                        title: Text(item.name),
                        subtitle: Text(item.summary,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              campaign.removeCatalogItem(b.key, item.id),
                        ),
                      ),
                    ),
                ],
              );
            }),
        ]),
      ),
    );
  }
}
