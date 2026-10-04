import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/inventory.dart';
import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/ui/theme.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';
import 'package:dnd_campaign_manager/ui/widgets/roll_panel.dart';

/// Button that lets the user pick an item from the catalog (via its content
/// binding) and clone it onto the current character.
Widget catalogButton(BuildContext context, String bindingKey, {String? tooltip}) {
  final ctrl = context.read<CharacterController>();
  final registry = context.read<CampaignController>().registry;
  return IconButton(
    tooltip: tooltip ?? 'Add from catalog',
    icon: const Icon(Icons.library_add_outlined),
    onPressed: () async {
      final binding = registry[bindingKey];
      if (binding == null) return;
      final item = await pickCatalogItem(context, binding);
      if (item != null) ctrl.applyCatalogItem(binding, item);
    },
  );
}

List<Widget> addButtons(
  BuildContext context, {
  required String bindingKey,
  required VoidCallback onBlank,
}) =>
    [
      IconButton(tooltip: 'Add blank', icon: const Icon(Icons.add), onPressed: onBlank),
      catalogButton(context, bindingKey),
    ];

class SheetTile extends StatelessWidget {
  const SheetTile({required this.index, required this.onDelete, required this.children});

  final int index;
  final VoidCallback onDelete;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: kTan, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 13, child: Text('${index + 1}')),
            const Spacer(),
            IconButton(
                tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
          ]),
          for (final c in children) Padding(padding: const EdgeInsets.only(top: 8), child: c),
        ]),
      );
}

class WeaponsPanel extends StatelessWidget {
  const WeaponsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;
    return SheetCard(
      title: 'Weapons',
      actions: addButtons(context, bindingKey: 'weapons', onBlank: ctrl.addBlankWeapon),
      child: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 140,
            child: IntBinding(
                label: 'Weapon HP', value: c.weaponHp, onChanged: (v) => ctrl.edit((_) => c.weaponHp = v)),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < c.weapons.length; i++)
          Builder(key: ObjectKey(c.weapons[i]), builder: (context) {
            final w = c.weapons[i];
            final usesAmmo = w.ammoType.trim().isNotEmpty;
            final magazine = w.ammoMax > 0;
            final inv = Inventory.available(c, w.ammoType);
            return SheetTile(
              index: i,
              onDelete: () => ctrl.edit((ch) => ch.weapons.remove(w)),
              children: [
                TextBinding(label: 'Weapon name', value: w.name, onChanged: (v) => ctrl.edit((_) => w.name = v)),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(width: 150, child: TextBinding(label: 'Ammo type', value: w.ammoType, onChanged: (v) => ctrl.edit((_) => w.ammoType = v))),
                  SizedBox(width: 90, child: IntBinding(label: 'Mag size', value: w.ammoMax, onChanged: (v) => ctrl.edit((_) => w.ammoMax = v))),
                  if (magazine)
                    SizedBox(width: 80, child: IntBinding(label: 'Loaded', value: w.ammo, onChanged: (v) => ctrl.edit((_) => w.ammo = v))),
                  SizedBox(width: 90, child: IntBinding(label: 'Rounds/shot', value: w.roundsPerShot, onChanged: (v) => ctrl.edit((_) => w.roundsPerShot = v < 1 ? 1 : v))),
                  SizedBox(width: 130, child: TextBinding(label: 'Damage (2d6+2)', value: w.damage, onChanged: (v) => ctrl.edit((_) => w.damage = v))),
                  DropdownButton<Ability>(
                    value: w.attackAbility,
                    items: [for (final a in Ability.values) DropdownMenuItem(value: a, child: Text(a.label))],
                    onChanged: (a) => ctrl.edit((_) => w.attackAbility = a ?? w.attackAbility),
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Checkbox(value: w.proficient, visualDensity: VisualDensity.compact, onChanged: (v) => ctrl.edit((_) => w.proficient = v ?? false)),
                    const Text('Proficient'),
                  ]),
                  SizedBox(width: 90, child: IntBinding(label: 'Atk bonus', value: w.attackBonus, onChanged: (v) => ctrl.edit((_) => w.attackBonus = v))),
                  SizedBox(width: 80, child: IntBinding(label: 'HP', value: w.hp, onChanged: (v) => ctrl.edit((_) => w.hp = v))),
                  SizedBox(width: 80, child: IntBinding(label: 'Max HP', value: w.hpMax, onChanged: (v) => ctrl.edit((_) => w.hpMax = v))),
                ]),
                Text(
                  [
                    'Attack ${signed(Rules.attackBonus(c, w))}',
                    if (usesAmmo) 'Inventory ${w.ammoType}: $inv',
                    if (usesAmmo && !magazine) 'firing draws from inventory',
                    if (magazine) 'firing uses loaded rounds; Reload pulls from inventory',
                  ].join('  ·  '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.gps_fixed, size: 18),
                    label: const Text('Fire'),
                    onPressed: () => showRoll(context, ctrl.fire(w)),
                  ),
                  OutlinedButton(onPressed: () => showRoll(context, ctrl.attack(w)), child: const Text('Attack only')),
                  OutlinedButton(onPressed: () => showRoll(context, ctrl.damage(w)), child: const Text('Damage')),
                  OutlinedButton(onPressed: () => showRoll(context, ctrl.damage(w, crit: true)), child: const Text('Crit damage')),
                  if (magazine)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reload'),
                      onPressed: () => showRoll(context, ctrl.reload(w)),
                    ),
                ]),
                TextBinding(label: 'Properties', value: w.properties, onChanged: (v) => ctrl.edit((_) => w.properties = v)),
                EffectsField(effects: w.effects, onChanged: (e) => ctrl.edit((_) => w.effects = e)),
              ],
            );
          }),
      ]),
    );
  }
}

class ArmorPanel extends StatelessWidget {
  const ArmorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;
    return SheetCard(
      title: 'Armor',
      actions: addButtons(context, bindingKey: 'armor', onBlank: ctrl.addBlankArmor),
      child: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 140,
            child: IntBinding(
                label: 'Armor HP', value: c.armorHp, onChanged: (v) => ctrl.edit((_) => c.armorHp = v)),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < c.armor.length; i++)
          Builder(key: ObjectKey(c.armor[i]), builder: (context) {
            final a = c.armor[i];
            return SheetTile(
              index: i,
              onDelete: () => ctrl.edit((ch) => ch.armor.remove(a)),
              children: [
                TextBinding(label: 'Armor name', value: a.name, onChanged: (v) => ctrl.edit((_) => a.name = v)),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(width: 80, child: IntBinding(label: 'Rating', value: a.rating, onChanged: (v) => ctrl.edit((_) => a.rating = v))),
                  SizedBox(width: 80, child: IntBinding(label: 'HP', value: a.hp, onChanged: (v) => ctrl.edit((_) => a.hp = v))),
                  SizedBox(width: 80, child: IntBinding(label: 'Max HP', value: a.hpMax, onChanged: (v) => ctrl.edit((_) => a.hpMax = v))),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: a.equipped, onChanged: (v) => ctrl.edit((_) => a.equipped = v)),
                    const Text('Equipped'),
                  ]),
                ]),
                TextBinding(label: 'Properties', value: a.properties, onChanged: (v) => ctrl.edit((_) => a.properties = v)),
                EffectsField(effects: a.effects, onChanged: (e) => ctrl.edit((_) => a.effects = e)),
              ],
            );
          }),
      ]),
    );
  }
}
