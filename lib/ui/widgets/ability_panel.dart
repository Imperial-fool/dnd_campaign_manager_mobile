import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/roll_panel.dart';

class AbilityPanel extends StatelessWidget {
  const AbilityPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;
    return SheetCard(
      title: 'Ability Scores',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'Ability modifier (tap to roll) · save (tick = proficient, die = roll)',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final a in Ability.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                  width: 32,
                  child: Text(a.label,
                      style: const TextStyle(fontWeight: FontWeight.w800))),
              SizedBox(
                width: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IntBinding(
                      label: 'Score',
                      value: c.abilityScores[a] ?? 10,
                      onChanged: (v) =>
                          ctrl.edit((ch) => ch.abilityScores[a] = v),
                    ),
                    if (Rules.effectTotal(c, 'ability.${a.key}') != 0)
                      Tooltip(
                        message:
                            'Base score ${c.abilityScores[a] ?? 10} ${signed(Rules.effectTotal(c, 'ability.${a.key}'))} bonus = ${Rules.abilityScore(c, a)}',
                        child: Text(
                          '${signed(Rules.effectTotal(c, 'ability.${a.key}'))} bonus\nTotal ${Rules.abilityScore(c, a)}',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showRoll(context,
                    ctrl.rollCheck('${a.label} check', Rules.abilityMod(c, a))),
                child: Container(
                  width: 40,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white12,
                  ),
                  alignment: Alignment.center,
                  child: Text(signed(Rules.abilityMod(c, a)),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const Spacer(),
              Checkbox(
                visualDensity: VisualDensity.compact,
                value: c.saveProficiencies.contains(a),
                onChanged: (on) => ctrl.edit((ch) => on == true
                    ? ch.saveProficiencies.add(a)
                    : ch.saveProficiencies.remove(a)),
              ),
              SizedBox(width: 26, child: Text(signed(Rules.saveBonus(c, a)))),
              IconButton(
                tooltip: 'Roll ${a.label} save',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.casino_outlined),
                onPressed: () => showRoll(context,
                    ctrl.rollCheck('${a.label} save', Rules.saveBonus(c, a))),
              ),
            ]),
          ),
      ]),
    );
  }
}
