import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';

const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

Future<String?> showJsonInputDialog(
  BuildContext context, {
  required String title,
  String? sample,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 600,
        child: TextField(
          controller: controller,
          onTapOutside: (_) => FocusScope.of(ctx).unfocus(),
          maxLines: 18,
          style: _mono,
          decoration: const InputDecoration(hintText: 'Paste JSON here'),
        ),
      ),
      actions: [
        if (sample != null)
          TextButton(
              onPressed: () => controller.text = sample,
              child: const Text('Insert sample')),
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Import')),
      ],
    ),
  );
}

Future<void> showJsonViewDialog(BuildContext context,
        {required String title, required String json}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 600,
          height: 420,
          child:
              SingleChildScrollView(child: SelectableText(json, style: _mono)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(const SnackBar(content: Text('Copied')));
              }
            },
            child: const Text('Copy'),
          ),
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );

void showImportResult(BuildContext context, ImportResult r) {
  final lines = [
    r.summary,
    ...r.errors.map((e) => '✗ $e'),
    ...r.warnings.map((w) => '! $w')
  ];
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(r.ok ? 'Import complete' : 'Import finished with problems'),
      content: SingleChildScrollView(child: Text(lines.join('\n'))),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('OK'))
      ],
    ),
  );
}

/// Pick one item from the catalog for the given binding.
Future<CatalogItem?> pickCatalogItem(
    BuildContext context, ContentBinding binding) {
  final items = context.read<CampaignController>().catalog.items(binding.key);
  return showDialog<CatalogItem>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Add from catalog: ${binding.label}'),
      children: items.isEmpty
          ? [
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'Nothing here yet. Import a content pack from the catalog screen.'),
              )
            ]
          : [
              for (final item in items)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, item),
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: Text(item.summary,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
            ],
    ),
  );
}

Future<Skill?> promptNewSkill(BuildContext context) {
  final name = TextEditingController();
  var ability = Ability.str;
  return showDialog<Skill>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('New skill'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: name,
            onTapOutside: (_) => FocusScope.of(ctx).unfocus(),
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Ability>(
            value: ability,
            decoration: const InputDecoration(labelText: 'Ability'),
            items: [
              for (final a in Ability.values)
                DropdownMenuItem(value: a, child: Text(a.label))
            ],
            onChanged: (a) => setState(() => ability = a ?? ability),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(
                  ctx, Skill(name: name.text.trim(), ability: ability));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
