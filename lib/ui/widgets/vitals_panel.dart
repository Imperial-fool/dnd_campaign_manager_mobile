import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';

class VitalsPanel extends StatelessWidget {
  const VitalsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;

    Widget num_(String label, int value, void Function(int) set, {String? hint}) => SizedBox(
          width: 110,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IntBinding(label: label, value: value, onChanged: (v) => ctrl.edit((_) => set(v))),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4),
                child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
              ),
          ]),
        );

    final ac = Rules.armorClass(c);
    final spd = Rules.speed(c);
    final init = Rules.initiative(c);
    final maxHp = Rules.maxHp(c);

    Widget boxes(int count, int filled, void Function(int) set) => Row(children: [
          for (var i = 0; i < count; i++)
            Checkbox(
              value: i < filled,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => ctrl.edit((_) => set(i + 1 == filled ? i : i + 1)),
            ),
        ]);

    return SheetCard(
      title: 'Combat',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          num_('Armor class', c.armorClass, (v) => c.armorClass = v,
              hint: ac != c.armorClass ? 'effective $ac' : null),
          num_('Initiative bonus', c.initiativeBonus, (v) => c.initiativeBonus = v,
              hint: 'total ${signed(init)}'),
          num_('Speed (ft)', c.speed, (v) => c.speed = v,
              hint: spd != c.speed ? 'effective $spd' : null),
          num_('HP current', c.hpCurrent, (v) => c.hpCurrent = v),
          num_('HP max', c.hpMax, (v) => c.hpMax = v,
              hint: maxHp != c.hpMax ? 'effective $maxHp' : null),
          num_('Hit dice total', c.hitDiceTotal, (v) => c.hitDiceTotal = v),
          num_('Hit dice used', c.hitDiceUsed, (v) => c.hitDiceUsed = v),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Inspiration'),
          Switch(value: c.inspiration, onChanged: (v) => ctrl.edit((_) => c.inspiration = v)),
        ]),
        const Text('Death saves', style: TextStyle(fontWeight: FontWeight.w700)),
        Row(children: [
          const SizedBox(width: 80, child: Text('Successes')),
          boxes(3, c.deathSuccesses, (n) => c.deathSuccesses = n),
        ]),
        Row(children: [
          const SizedBox(width: 80, child: Text('Failures')),
          boxes(3, c.deathFailures, (n) => c.deathFailures = n),
        ]),
        const SizedBox(height: 8),
        const Text('Exhaustion', style: TextStyle(fontWeight: FontWeight.w700)),
        boxes(6, c.exhaustion, (n) => c.exhaustion = n),
      ]),
    );
  }
}
