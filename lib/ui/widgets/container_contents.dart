import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';

/// Lists each storage slot of a backpack or rig with the items packed in it.
/// Items can be added from the character's inventory, the catalog, or blank,
/// and taken back out into the inventory.
class ContainerContents extends StatelessWidget {
  const ContainerContents({
    super.key,
    required this.owner,
    required this.slots,
    required this.stored,
  });

  /// The backpack or rig these contents belong to (excluded from the
  /// "from inventory" choices).
  final Object owner;
  final Map<String, int> slots;
  final Map<String, List<InventoryItem>> stored;

  @override
  Widget build(BuildContext context) {
    final names = {...slots.keys, ...stored.keys}.toList();
    if (names.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Contents', style: Theme.of(context).textTheme.labelMedium),
        for (final name in names) _slot(context, name),
      ],
    );
  }

  Widget _slot(BuildContext context, String name) {
    final ctrl = context.read<CharacterController>();
    final items = stored[name] ?? const <InventoryItem>[];
    final capacity = slots[name] ?? 0;
    final full = items.length >= capacity;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '$name  ${items.length}/$capacity',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              onPressed: full ? null : () => _add(context, name),
            ),
          ]),
          for (final item in items)
            Row(
              key: ObjectKey(item),
              children: [
                Expanded(
                    child: Text(item.name.isEmpty ? '(unnamed)' : item.name)),
                SizedBox(
                  width: 70,
                  child: IntBinding(
                    label: item.isAmmo ? 'Rounds' : 'Qty',
                    value: item.quantity,
                    onChanged: (v) =>
                        ctrl.edit((_) => item.quantity = v < 0 ? 0 : v),
                  ),
                ),
                IconButton(
                  tooltip: 'Take out to inventory',
                  icon: const Icon(Icons.outbox_outlined),
                  onPressed: () => ctrl.edit((c) {
                    items.remove(item);
                    c.items.add(item);
                  }),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ctrl.edit((_) => items.remove(item)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, String slot) async {
    final ctrl = context.read<CharacterController>();
    final registry = context.read<CampaignController>().registry;
    final inventory = ctrl.character.items
        .where((i) => !identical(i, owner) && !i.isContainer)
        .toList();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Add to $slot'),
        children: [
          if (inventory.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'inventory'),
              child: const Text('From inventory'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'catalog'),
            child: const Text('From catalog'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'blank'),
            child: const Text('Blank item'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    InventoryItem? item;
    var fromInventory = false;
    switch (choice) {
      case 'inventory':
        item = await showDialog<InventoryItem>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Move from inventory'),
            children: [
              for (final i in inventory)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, i),
                  child: Text(i.name.isEmpty ? '(unnamed)' : i.name),
                ),
            ],
          ),
        );
        fromInventory = true;
      case 'catalog':
        final binding = registry['items'];
        if (binding == null) return;
        final picked = await pickCatalogItem(context, binding);
        if (picked != null) {
          final copy = binding.parse(picked.toJson());
          if (copy is InventoryItem) item = copy;
        }
      default:
        item = InventoryItem(name: 'New item');
    }
    if (item == null) return;
    final chosen = item;
    ctrl.edit((c) {
      if (fromInventory) c.items.remove(chosen);
      stored.putIfAbsent(slot, () => []).add(chosen);
    });
  }
}
