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
import 'package:dnd_campaign_manager/ui/widgets/spells_panel.dart';
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

    final overview = _stack([
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const IdentityPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const VitalsPanel(),
      ),
      const RollPanel(),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const ActionsPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const CustomSheetPanel(),
      ),
    ]);
    final combat = _stack([
      const RollPanel(),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const WeaponsPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const ArmorPanel(),
      ),
    ]);
    final items = _stack([
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const InventoryPanel(),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const StashPanel(),
      ),
    ]);
    final feats = AbsorbPointer(
      absorbing: ctrl.isReadOnly,
      child: const TraitsPanel(filter: TraitPanelFilter.feats),
    );
    final features = AbsorbPointer(
      absorbing: ctrl.isReadOnly,
      child: const TraitsPanel(filter: TraitPanelFilter.featuresAndTraits),
    );
    final notes = _stack([
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child:
            const FreeTextPanel(title: 'Equipment', field: SheetText.equipment),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const FreeTextPanel(
          title: 'Proficiencies & Languages',
          field: SheetText.proficiencies,
        ),
      ),
      AbsorbPointer(
        absorbing: ctrl.isReadOnly,
        child: const FreeTextPanel(title: 'Notes', field: SheetText.notes),
      ),
    ]);

    return DefaultTabController(
        length: 9,
        child: Scaffold(
          endDrawer: const Drawer(child: SafeArea(child: _RollHistoryDrawer())),
          appBar: AppBar(
            title: Text(ctrl.character.name),
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(icon: Icon(Icons.person_outline), text: 'Overview'),
                Tab(icon: Icon(Icons.grid_view_outlined), text: 'Abilities'),
                Tab(icon: Icon(Icons.checklist), text: 'Skills'),
                Tab(icon: Icon(Icons.sports_martial_arts), text: 'Combat'),
                Tab(icon: Icon(Icons.auto_fix_high), text: 'Spells'),
                Tab(icon: Icon(Icons.backpack_outlined), text: 'Inventory'),
                Tab(icon: Icon(Icons.military_tech_outlined), text: 'Feats'),
                Tab(
                    icon: Icon(Icons.workspace_premium_outlined),
                    text: 'Features & Traits'),
                Tab(icon: Icon(Icons.notes_outlined), text: 'Notes'),
              ],
            ),
            actions: [
              if (ctrl.allowReadOnlyEditToggle)
                IconButton(
                  tooltip:
                      ctrl.isReadOnly ? 'Edit character' : 'Finish editing',
                  icon:
                      Icon(ctrl.isReadOnly ? Icons.edit_outlined : Icons.lock),
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
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Roll history',
                  icon: const Icon(Icons.history),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                ),
              ),
            ],
          ),
          body: TabBarView(children: [
            _scroll(overview),
            _scroll(AbsorbPointer(
              absorbing: ctrl.isReadOnly,
              child: const AbilityPanel(),
            )),
            _scroll(AbsorbPointer(
              absorbing: ctrl.isReadOnly,
              child: const SkillsPanel(),
            )),
            _scroll(combat),
            _scroll(AbsorbPointer(
              absorbing: ctrl.isReadOnly,
              child: const SpellsPanel(),
            )),
            _scroll(items),
            _scroll(feats),
            _scroll(features),
            _scroll(notes),
          ]),
        ));
  }

  Widget _scroll(Widget child) =>
      SingleChildScrollView(padding: const EdgeInsets.all(12), child: child);
}

class _RollHistoryDrawer extends StatelessWidget {
  const _RollHistoryDrawer();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        title: const Text('Roll history'),
        trailing: IconButton(
          tooltip: 'Clear log',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: ctrl.clearLog,
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: ctrl.rollLog.isEmpty
            ? const Center(child: Text('No rolls yet.'))
            : ListView(padding: const EdgeInsets.all(8), children: [
                for (final e in ctrl.rollLog)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: e.crit
                          ? Colors.green.withValues(alpha: 0.18)
                          : e.fumble
                              ? Colors.red.withValues(alpha: 0.18)
                              : Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.headline,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        for (final l in e.lines)
                          Text(l, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
              ]),
      ),
    ]);
  }
}
