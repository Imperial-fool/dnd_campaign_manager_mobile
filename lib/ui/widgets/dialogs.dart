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
  final groupedItems =
      binding.key == 'items' ? _groupInventoryItems(items) : null;
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
          : groupedItems != null
              ? [
                  for (final entry in groupedItems.entries)
                    _catalogSection(ctx, entry.key, entry.value),
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

Widget _catalogTile(BuildContext ctx, CatalogItem item) => SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, item),
      child: ListTile(
        title: Text(item.name),
        subtitle: Text(
          item.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

/// A section is expanded by default; ammo is split into collapsible
/// sub sections by ammo type.
Widget _catalogSection(
    BuildContext ctx, String title, List<CatalogItem> items) {
  final children = <Widget>[];
  if (title == 'Ammo') {
    final byType = <String, List<CatalogItem>>{};
    for (final item in items) {
      final type = item is InventoryItem && item.ammoType.trim().isNotEmpty
          ? item.ammoType.trim()
          : 'Other';
      byType.putIfAbsent(type, () => []).add(item);
    }
    for (final entry in byType.entries) {
      children.add(ExpansionTile(
        key: PageStorageKey('catalog-ammo-${entry.key}'),
        title: Text(entry.key),
        childrenPadding: const EdgeInsets.only(left: 16),
        children: [for (final item in entry.value) _catalogTile(ctx, item)],
      ));
    }
  } else {
    children.addAll(items.map((item) => _catalogTile(ctx, item)));
  }
  return ExpansionTile(
    key: PageStorageKey('catalog-section-$title'),
    initiallyExpanded: true,
    title: Text(title, style: Theme.of(ctx).textTheme.titleSmall),
    children: children,
  );
}

Map<String, List<CatalogItem>> _groupInventoryItems(List<CatalogItem> items) {
  const groups = ['Backpacks', 'Tools / misc', 'Medical equipment', 'Ammo'];
  final grouped = {
    for (final group in groups) group: <CatalogItem>[],
  };
  for (final item in items) {
    final group = switch (item) {
      InventoryItem(:final category) when category == 'ammo' => 'Ammo',
      InventoryItem(:final category) when category == 'medical' =>
        'Medical equipment',
      InventoryItem(:final category) when category == 'backpack' => 'Backpacks',
      _ => 'Tools / misc',
    };
    grouped[group]!.add(item);
  }
  for (final itemsInGroup in grouped.values) {
    itemsInGroup.sort(
      (a, b) {
        if (a is InventoryItem &&
            b is InventoryItem &&
            a.category == 'ammo' &&
            b.category == 'ammo') {
          final typeComparison = a.ammoType
              .trim()
              .toLowerCase()
              .compareTo(b.ammoType.trim().toLowerCase());
          if (typeComparison != 0) return typeComparison;

          final subtypeComparison = _ammoSubtype(a)
              .toLowerCase()
              .compareTo(_ammoSubtype(b).toLowerCase());
          if (subtypeComparison != 0) return subtypeComparison;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      },
    );
  }
  return {
    for (final group in groups)
      if (grouped[group]!.isNotEmpty) group: grouped[group]!,
  };
}

String _ammoSubtype(InventoryItem item) {
  final type = item.ammoType.trim();
  final name = item.name.trim();
  if (type.isNotEmpty && name.toLowerCase().startsWith(type.toLowerCase())) {
    return name.substring(type.length).trimLeft();
  }
  return name;
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
            initialValue: ability,
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
