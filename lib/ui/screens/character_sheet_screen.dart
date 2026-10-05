import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/ui/screens/catalog_screen.dart';
import 'package:dnd_campaign_manager/ui/widgets/ability_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/actions_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/custom_sheet_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';
import 'package:dnd_campaign_manager/ui/widgets/gear_panels.dart';
import 'package:dnd_campaign_manager/ui/widgets/identity_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/inventory_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/roll_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/skills_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/stash_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/text_panels.dart';
import 'package:dnd_campaign_manager/ui/widgets/traits_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/vitals_panel.dart';

class CharacterSheetScreen extends StatefulWidget {
  const CharacterSheetScreen({
    super.key,
    required this.character,
    this.readOnly = false,
    this.allowEditing = false,
  });

  final Character character;
  final bool readOnly;
  final bool allowEditing;

  @override
  State<CharacterSheetScreen> createState() => _CharacterSheetScreenState();
}

class _CharacterSheetScreenState extends State<CharacterSheetScreen> {
  late final CharacterController _controller;
  late final CampaignController _campaign;

  @override
  void initState() {
    super.initState();
    _campaign = context.read<CampaignController>();
    _controller = _campaign.editorFor(
      widget.character,
      forceReadOnly: widget.readOnly,
      allowReadOnlyEditToggle: widget.allowEditing,
    );
    _campaign.addListener(_refreshRemoteCharacter);
  }

  void _refreshRemoteCharacter() {
    for (final character in _campaign.characters) {
      if (character.id == _controller.character.id) {
        _controller.refreshRemoteCharacter(character);
        return;
      }
    }
  }

  @override
  void dispose() {
    _campaign.removeListener(_refreshRemoteCharacter);
    _controller.dispose(); // flushes pending save
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
        value: _controller,
        child: const _SheetView(),
      );
}

class _SheetView extends StatelessWidget {
  const _SheetView();

  Future<void> _saveCharacterJson(
      BuildContext context, Character character) async {
    final fileName = _fileNameFor(character.name);
    try {
      final savedFile = await FilePicker.saveFile(
        fileName: fileName,
        dialogTitle: 'Save character JSON',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        mimeType: 'application/json',
        bytes: Uint8List.fromList(
          utf8.encode(
              context.read<CampaignController>().exportCharacter(character)),
        ),
      );
      if (savedFile != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved character to $savedFile')),
        );
      }
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save character JSON: $error')),
        );
      }
    }
  }

  Future<void> _saveCharacterToDrive(
    BuildContext context,
    GoogleDriveService drive,
    CampaignController campaign,
    Character character,
  ) async {
    if (!drive.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect Google Drive in Campaign Settings first.'),
        ),
      );
      return;
    }
    try {
      await drive.saveCharacterJson(
        id: character.id,
        name: character.name,
        json: campaign.exportCharacter(character),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Character saved to Google Drive.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save to Google Drive: $error')),
        );
      }
    }
  }

  String _fileNameFor(String name) {
    final safeName = name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    return '${safeName.isEmpty ? 'character' : safeName}.json';
  }

  static Widget _stack(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final w in children)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: w)
        ],
      );

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final drive = context.watch<GoogleDriveService>();
    final campaign = context.read<CampaignController>();

    final left = AbsorbPointer(
      absorbing: ctrl.isReadOnly,
      child: _stack(const [AbilityPanel(), SkillsPanel()]),
    );
    final middle = _stack([
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const VitalsPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const CustomSheetPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const WeaponsPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const ArmorPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const InventoryPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const StashPanel(),
      ),
    ]);
    final right = _stack([
      const RollPanel(),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: _stack([
          const ActionsPanel(),
          const TraitsPanel(),
          const FreeTextPanel(title: 'Equipment', field: SheetText.equipment),
          const FreeTextPanel(
              title: 'Proficiencies & Languages',
              field: SheetText.proficiencies),
          const FreeTextPanel(title: 'Notes', field: SheetText.notes),
        ]),
      ),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(ctrl.character.name),
        actions: [
          if (ctrl.allowReadOnlyEditToggle)
            IconButton(
              tooltip: ctrl.isReadOnly ? 'Edit character' : 'Finish editing',
              icon: Icon(ctrl.isReadOnly ? Icons.edit_outlined : Icons.lock),
              onPressed: ctrl.toggleReadOnly,
            ),
          IconButton(
            tooltip: 'Save character JSON file',
            icon: const Icon(Icons.save_alt),
            onPressed: () => _saveCharacterJson(context, ctrl.character),
          ),
          if (!ctrl.isReadOnly && !ctrl.isPlayerMode)
            IconButton(
              tooltip: 'Save character to Google Drive',
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: () => _saveCharacterToDrive(
                context,
                drive,
                campaign,
                ctrl.character,
              ),
            ),
          if (!ctrl.isReadOnly && !ctrl.isPlayerMode)
            IconButton(
              tooltip: 'Catalog',
              icon: const Icon(Icons.inventory_2_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CatalogScreen())),
            ),
          IconButton(
            tooltip: 'View / copy character JSON',
            icon: const Icon(Icons.data_object),
            onPressed: () => showJsonViewDialog(context,
                title: '${ctrl.character.name}.json',
                json: campaign.exportCharacter(ctrl.character)),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 1150;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AbsorbPointer(
                absorbing: ctrl.isReadOnly,
                child: const IdentityPanel(),
              ),
              const SizedBox(height: 12),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 4, child: left),
                  const SizedBox(width: 12),
                  Expanded(flex: 6, child: middle),
                  const SizedBox(width: 12),
                  Expanded(flex: 5, child: right),
                ])
              else ...[left, middle, right],
            ],
          ),
        );
      }),
    );
  }
}
