import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/ui/screens/catalog_screen.dart';
import 'package:dnd_campaign_manager/ui/widgets/ability_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';
import 'package:dnd_campaign_manager/ui/widgets/gear_panels.dart';
import 'package:dnd_campaign_manager/ui/widgets/identity_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/inventory_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/roll_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/skills_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/text_panels.dart';
import 'package:dnd_campaign_manager/ui/widgets/traits_panel.dart';
import 'package:dnd_campaign_manager/ui/widgets/vitals_panel.dart';

class CharacterSheetScreen extends StatefulWidget {
  const CharacterSheetScreen({super.key, required this.character});

  final Character character;

  @override
  State<CharacterSheetScreen> createState() => _CharacterSheetScreenState();
}

class _CharacterSheetScreenState extends State<CharacterSheetScreen> {
  late final CharacterController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        context.read<CampaignController>().editorFor(widget.character);
  }

  @override
  void dispose() {
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
    final campaign = context.read<CampaignController>();

    final left = _stack(const [AbilityPanel(), SkillsPanel()]);
    final middle = _stack(
        const [VitalsPanel(), WeaponsPanel(), ArmorPanel(), InventoryPanel()]);
    final right = _stack(const [
      RollPanel(),
      TraitsPanel(),
      FreeTextPanel(title: 'Equipment', field: SheetText.equipment),
      FreeTextPanel(
          title: 'Proficiencies & Languages', field: SheetText.proficiencies),
      FreeTextPanel(title: 'Notes', field: SheetText.notes),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(ctrl.character.name),
        actions: [
          IconButton(
            tooltip: 'Save character JSON file',
            icon: const Icon(Icons.save_alt),
            onPressed: () => _saveCharacterJson(context, ctrl.character),
          ),
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
              const IdentityPanel(),
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
