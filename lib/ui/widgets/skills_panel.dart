import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/dialogs.dart';
import 'package:dnd_campaign_manager/ui/widgets/roll_panel.dart';

class SkillsPanel extends StatelessWidget {
  const SkillsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;
    return SheetCard(
      title: 'Skills',
      actions: [
        IconButton(
          tooltip: 'Add custom skill',
          icon: const Icon(Icons.add),
          onPressed: () async {
            final skill = await promptNewSkill(context);
            if (skill != null) ctrl.addSkill(skill);
          },
        ),
      ],
      child: Column(children: [
        for (final s in c.skills)
          Row(key: ObjectKey(s), children: [
            IconButton(
              tooltip: s.hasExpertise
                  ? 'Expertise (tap to clear)'
                  : s.isProficient
                      ? 'Proficient (tap for expertise)'
                      : 'Not proficient (tap for proficiency)',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                s.hasExpertise
                    ? Icons.stars
                    : s.isProficient
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                color: s.hasExpertise ? Colors.amber : null,
              ),
              onPressed: () => ctrl.edit((_) {
                if (!s.isProficient) {
                  s.proficient = true;
                } else if (!s.hasExpertise) {
                  s.expertise = true;
                } else {
                  s.expertise = false;
                  s.proficient = false;
                }
              }),
            ),
            SizedBox(width: 34, child: Text(signed(Rules.skillBonus(c, s)))),
            Expanded(child: Text('${s.name}  (${s.ability.label})')),
            IconButton(
              tooltip: 'Roll ${s.name}',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.casino_outlined),
              onPressed: () => showRoll(context,
                  ctrl.rollCheck('${s.name} check', Rules.skillBonus(c, s))),
            ),
            IconButton(
              tooltip: 'Remove skill',
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              icon: const Icon(Icons.close),
              onPressed: () => ctrl.edit((ch) => ch.skills.remove(s)),
            ),
          ]),
        const Divider(),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Passive Perception: ${Rules.passivePerception(c)}'),
        ),
      ]),
    );
  }
}
