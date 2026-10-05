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

    Widget num_(String label, int value, void Function(int) set,
            {String? hint, bool enabled = true}) =>
        SizedBox(
          width: 110,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IntBinding(
                label: label,
                value: value,
                onChanged: (v) => ctrl.edit((_) => set(v)),
                enabled: enabled),
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

    Widget boxes(int count, int filled, void Function(int) set) =>
        Row(children: [
          for (var i = 0; i < count; i++)
            Checkbox(
              value: i < filled,
              visualDensity: VisualDensity.compact,
              onChanged: (_) =>
                  ctrl.edit((_) => set(i + 1 == filled ? i : i + 1)),
            ),
        ]);

    final prominentColor = Theme.of(context).colorScheme.secondaryContainer;
    final prominentTextColor =
        Theme.of(context).colorScheme.onSecondaryContainer;

    Widget prominentStatCard({
      required String title,
      required Widget child,
      required double width,
    }) =>
        Container(
          width: width,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: prominentColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: prominentTextColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        );

    return SheetCard(
      title: 'Combat',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              prominentStatCard(
                title: 'Armor Class',
                width: constraints.maxWidth < 215 ? constraints.maxWidth : 215,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '$ac',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: prominentTextColor,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 88,
                      child: IntBinding(
                        label: 'Base',
                        value: c.armorClass,
                        onChanged: (value) =>
                            ctrl.edit((_) => c.armorClass = value),
                      ),
                    ),
                  ],
                ),
              ),
              prominentStatCard(
                title: 'Hit Points',
                width: constraints.maxWidth < 280 ? constraints.maxWidth : 280,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Decrease current HP by 1',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 34, height: 44),
                      onPressed: () => ctrl.edit((_) => c.hpCurrent--),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Expanded(
                      child: IntBinding(
                        label: 'Current',
                        value: c.hpCurrent,
                        onChanged: (value) =>
                            ctrl.edit((_) => c.hpCurrent = value),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Increase current HP by 1',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 34, height: 44),
                      onPressed: () => ctrl.edit((_) => c.hpCurrent++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: IntBinding(
                        label: 'Max',
                        value: c.hpMax,
                        onChanged: (value) => ctrl.edit((_) => c.hpMax = value),
                        enabled: !ctrl.isPlayerMode,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          num_('Initiative', c.initiativeBonus, (v) => c.initiativeBonus = v,
              hint: 'Total ${signed(init)}'),
          num_('Speed', c.speed, (v) => c.speed = v,
              hint: spd != c.speed ? 'Total $spd ft' : 'ft'),
          num_('Hit dice', c.hitDiceTotal, (v) => c.hitDiceTotal = v,
              enabled: !ctrl.isPlayerMode),
          num_('Used', c.hitDiceUsed, (v) => c.hitDiceUsed = v),
          if (maxHp != c.hpMax)
            Padding(
              padding: const EdgeInsets.only(top: 25),
              child: Text('Maximum HP with effects: $maxHp'),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Inspiration'),
          Switch(
              value: c.inspiration,
              onChanged: (v) => ctrl.edit((_) => c.inspiration = v)),
        ]),
        const Text('Death saves',
            style: TextStyle(fontWeight: FontWeight.w700)),
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
