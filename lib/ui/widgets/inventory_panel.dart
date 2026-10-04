import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/gear_panels.dart';
import 'package:dnd_campaign_manager/ui/widgets/roll_panel.dart';

/// Items held: consumables with uses, and ammo stacks that weapons draw from.
class InventoryPanel extends StatelessWidget {
  const InventoryPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;

    // "9x18mm: 90 · 5.45x39mm: 120"
    final ammoTotals = <String, int>{};
    for (final i
        in c.items.where((i) => i.isAmmo && i.ammoType.trim().isNotEmpty)) {
      ammoTotals.update(i.ammoType.trim(), (v) => v + i.quantity,
          ifAbsent: () => i.quantity);
    }

    return SheetCard(
      title: 'Items',
      actions: [
        IconButton(
            tooltip: 'Add item',
            icon: const Icon(Icons.add),
            onPressed: () => ctrl.addBlankItem()),
        IconButton(
            tooltip: 'Add ammo',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => ctrl.addBlankItem(ammo: true)),
        catalogButton(context, 'items', tooltip: 'Add item from catalog'),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ammoTotals.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
                'Ammo: ${ammoTotals.entries.map((e) => '${e.key} ${e.value}').join('  ·  ')}'),
          ),
        if (c.items.isEmpty) const Text('Nothing carried.'),
        for (var i = 0; i < c.items.length; i++)
          Builder(
              key: ObjectKey(c.items[i]),
              builder: (context) {
                final it = c.items[i];
                return SheetTile(
                  index: i,
                  onDelete: () => ctrl.edit((ch) => ch.items.remove(it)),
                  children: [
                    Row(children: [
                      Expanded(
                          child: TextBinding(
                              label: 'Name',
                              value: it.name,
                              onChanged: (v) => ctrl.edit((_) => it.name = v))),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: it.kind,
                        items: const [
                          DropdownMenuItem(value: 'item', child: Text('Item')),
                          DropdownMenuItem(value: 'ammo', child: Text('Ammo')),
                        ],
                        onChanged: (v) =>
                            ctrl.edit((_) => it.kind = v ?? 'item'),
                      ),
                    ]),
                    if (!it.isAmmo)
                      Row(
                        children: [
                          const Text('Active'),
                          Switch(
                            value: it.active,
                            onChanged: (value) =>
                                ctrl.edit((_) => it.active = value),
                          ),
                          const Text('Apply this item’s effects'),
                        ],
                      ),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                              width: 90,
                              child: IntBinding(
                                  label: it.isAmmo ? 'Rounds' : 'Quantity',
                                  value: it.quantity,
                                  onChanged: (v) => ctrl.edit(
                                      (_) => it.quantity = v < 0 ? 0 : v))),
                          if (it.isAmmo) ...[
                            SizedBox(
                                width: 180,
                                child: TextBinding(
                                    label: 'Ammo type (match weapon)',
                                    value: it.ammoType,
                                    onChanged: (v) =>
                                        ctrl.edit((_) => it.ammoType = v))),
                            SizedBox(
                              width: 90,
                              child: IntBinding(
                                label: 'Penetration',
                                value: it.penetration,
                                onChanged: (v) =>
                                    ctrl.edit((_) => it.penetration = v),
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: IntBinding(
                                label: 'Durability burn',
                                value: it.durabilityBurn,
                                onChanged: (v) => ctrl.edit(
                                  (_) => it.durabilityBurn = v < 1 ? 1 : v,
                                ),
                              ),
                            ),
                          ] else ...[
                            SizedBox(
                              width: 130,
                              child: TextBinding(
                                label: 'Damage dice',
                                value: it.damage,
                                onChanged: (v) =>
                                    ctrl.edit((_) => it.damage = v),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: TextBinding(
                                label: 'Damage type',
                                value: it.damageType,
                                onChanged: (v) =>
                                    ctrl.edit((_) => it.damageType = v),
                              ),
                            ),
                            SizedBox(
                              width: 95,
                              child: IntBinding(
                                label: 'Area (ft)',
                                value: it.areaRadius,
                                onChanged: (v) =>
                                    ctrl.edit((_) => it.areaRadius = v),
                              ),
                            ),
                            SizedBox(
                              width: 85,
                              child: IntBinding(
                                label: 'Save DC',
                                value: it.saveDc,
                                onChanged: (v) =>
                                    ctrl.edit((_) => it.saveDc = v),
                              ),
                            ),
                            DropdownButton<String>(
                              value: {
                                '',
                                'str',
                                'dex',
                                'con',
                                'int',
                                'wis',
                                'cha',
                              }.contains(it.saveAbility)
                                  ? it.saveAbility
                                  : '',
                              items: const [
                                DropdownMenuItem(
                                    value: '', child: Text('No save')),
                                DropdownMenuItem(
                                    value: 'str', child: Text('STR save')),
                                DropdownMenuItem(
                                    value: 'dex', child: Text('DEX save')),
                                DropdownMenuItem(
                                    value: 'con', child: Text('CON save')),
                                DropdownMenuItem(
                                    value: 'int', child: Text('INT save')),
                                DropdownMenuItem(
                                    value: 'wis', child: Text('WIS save')),
                                DropdownMenuItem(
                                    value: 'cha', child: Text('CHA save')),
                              ],
                              onChanged: (value) => ctrl.edit(
                                (_) => it.saveAbility = value ?? '',
                              ),
                            ),
                            SizedBox(
                                width: 90,
                                child: IntBinding(
                                    label: 'Uses left',
                                    value: it.uses,
                                    onChanged: (v) =>
                                        ctrl.edit((_) => it.uses = v))),
                            SizedBox(
                                width: 90,
                                child: IntBinding(
                                    label: 'Uses/unit',
                                    value: it.usesMax,
                                    onChanged: (v) => ctrl.edit(
                                        (_) => it.usesMax = v < 0 ? 0 : v))),
                            FilledButton(
                                onPressed: () =>
                                    showRoll(context, ctrl.useItem(it)),
                                child: const Text('Use')),
                          ],
                        ]),
                    TextBinding(
                        label: 'Description',
                        value: it.description,
                        maxLines: 4,
                        minLines: 1,
                        onChanged: (v) => ctrl.edit((_) => it.description = v)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: const Text('Move to player stash'),
                        onPressed: c.player.trim().isEmpty
                            ? null
                            : () => context
                                .read<CampaignController>()
                                .moveToStash(c, 'items', it),
                      ),
                    ),
                    if (!it.isAmmo)
                      EffectsField(
                        effects: it.effects,
                        skills: c.skills,
                        onChanged: (effects) =>
                            ctrl.edit((_) => it.effects = effects),
                      ),
                  ],
                );
              }),
      ]),
    );
  }
}
