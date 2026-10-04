import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/gear_panels.dart';

class IdentityPanel extends StatelessWidget {
  const IdentityPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;
    Widget box(Widget w) => SizedBox(width: 230, child: w);
    return SheetCard(
      title: 'Character',
      child: Wrap(spacing: 10, runSpacing: 10, children: [
        box(TextBinding(
            label: 'Character name',
            value: c.name,
            onChanged: (v) => ctrl.edit((c) => c.name = v))),
        box(TextBinding(
            label: 'Player',
            value: c.player,
            onChanged: (v) => ctrl.edit((c) => c.player = v))),
        box(TextBinding(
            label: 'Race',
            value: c.race,
            onChanged: (v) => ctrl.edit((c) => c.race = v))),
        box(TextBinding(
            label: 'Affiliation',
            value: c.affiliation,
            onChanged: (v) => ctrl.edit((c) => c.affiliation = v))),
        box(TextBinding(
            label: 'Alignment',
            value: c.alignment,
            onChanged: (v) => ctrl.edit((c) => c.alignment = v))),
        box(Row(children: [
          Expanded(
            child: TextBinding(
              label: 'Background',
              value: c.background,
              onChanged: (v) => ctrl.edit((c) => c.background = v),
            ),
          ),
          catalogButton(
            context,
            'backgrounds',
            tooltip: 'Apply background from catalog (adds its features)',
          ),
        ])),
        SizedBox(
            width: 120,
            child: IntBinding(
                label: 'XP',
                value: c.xp,
                onChanged: (v) => ctrl.edit((c) => c.xp = v))),
        _LevelTracker(),
      ]),
    );
  }
}

class _LevelTracker extends StatelessWidget {
  Future<void> _levelUp(BuildContext context, CharacterController ctrl) async {
    final campaign = context.read<CampaignController>();
    final classes =
        campaign.catalog.items('classes').whereType<ClassDefinition>().toList();
    if (classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Import class definitions from the Catalog first.')),
      );
      return;
    }

    final character = ctrl.character;
    ClassDefinition? selectedClass;
    for (final definition in classes) {
      if (definition.id == character.classId) selectedClass = definition;
    }
    var selectedSubclassId = character.subclassId;
    final selections = <String, Set<String>>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final targetLevel =
              character.classId.isEmpty ? character.level : character.level + 1;
          final chosenClass = selectedClass;
          final subclasses =
              chosenClass?.subclasses.map(ClassSubclass.new).toList() ??
                  <ClassSubclass>[];
          final needsSubclass = chosenClass != null &&
              subclasses.isNotEmpty &&
              targetLevel >= chosenClass.subclassLevel;
          if (!subclasses
              .any((subclass) => subclass.id == selectedSubclassId)) {
            selectedSubclassId = '';
          }
          final hitDie = chosenClass?.hitDie ?? 0;
          final hpGain = hitDie == 0
              ? 0
              : (hitDie ~/ 2 +
                  1 +
                  Rules.modifier(character.abilityScores[Ability.con] ?? 10));
          final firstClassLevel = character.classId.isEmpty ? 1 : targetLevel;
          final choices = <Map<String, dynamic>>[];
          if (chosenClass != null) {
            for (var level = firstClassLevel; level <= targetLevel; level++) {
              choices.addAll(chosenClass.choicesAtLevel(
                level,
                availableFeats: campaign.catalog.items('feats'),
              ));
              if (selectedSubclassId.isNotEmpty &&
                  level >= chosenClass.subclassLevel) {
                final subclass = subclassById(chosenClass, selectedSubclassId);
                if (subclass != null) {
                  choices.addAll(
                    subclass.choicesAtLevel(level, chosenClass.id),
                  );
                }
              }
            }
          }
          final choicesComplete = choices.every((choice) {
            final selected =
                selections[asStr(choice['selectionKey'])] ?? const <String>{};
            return selected.length == asInt(choice['count'], 1);
          });
          final nextXp = Rules.xpForNextLevel(character);
          final xpEligible = character.classId.isEmpty ||
              !campaign.requireXpForLevelUp ||
              (nextXp != null && character.xp >= nextXp);

          return AlertDialog(
            title:
                Text(character.classId.isEmpty ? 'Choose a class' : 'Level up'),
            content: SizedBox(
              width: 460,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (character.classId.isNotEmpty &&
                          selectedClass == null) ...[
                        Text(
                          'The ${character.className} class definition is missing. '
                          'Import it again to continue leveling.',
                        ),
                      ] else ...[
                        DropdownButtonFormField<String>(
                          initialValue: chosenClass?.id,
                          key: ValueKey(chosenClass?.id),
                          decoration: const InputDecoration(labelText: 'Class'),
                          items: [
                            for (final definition in classes)
                              DropdownMenuItem(
                                value: definition.id,
                                child: Text(definition.name),
                              ),
                          ],
                          onChanged: character.classId.isNotEmpty
                              ? null
                              : (id) => setState(() {
                                    selectedClass = classes
                                        .where(
                                            (definition) => definition.id == id)
                                        .first;
                                    selectedSubclassId = '';
                                    selections.clear();
                                  }),
                        ),
                        if (chosenClass != null) ...[
                          const SizedBox(height: 8),
                          Text(character.classId.isEmpty
                              ? 'Class features through level ${character.level} will be added.'
                              : 'Advancing to level $targetLevel grants the class features defined for that level.'),
                          if (character.classId.isNotEmpty)
                            Text(
                                'Average HP gain: $hpGain (hit die d$hitDie).'),
                          if (needsSubclass) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: selectedSubclassId.isEmpty
                                  ? null
                                  : selectedSubclassId,
                              key: ValueKey(selectedSubclassId),
                              decoration: InputDecoration(
                                labelText:
                                    'Subclass (unlocks at level ${chosenClass.subclassLevel})',
                              ),
                              items: [
                                for (final subclass in subclasses)
                                  DropdownMenuItem(
                                    value: subclass.id,
                                    child: Text(subclass.name),
                                  ),
                              ],
                              onChanged: character.subclassId.isNotEmpty
                                  ? null
                                  : (id) => setState(
                                        () {
                                          selectedSubclassId = id ?? '';
                                          selections.clear();
                                        },
                                      ),
                            ),
                            if (selectedSubclassId.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  subclasses
                                      .firstWhere(
                                          (s) => s.id == selectedSubclassId)
                                      .description,
                                ),
                              ),
                          ],
                        ],
                      ],
                      if (chosenClass != null)
                        for (final choice in choices) ...[
                          const Divider(),
                          Text(
                            asStr(choice['prompt']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (asMapList(choice['options']).isEmpty)
                            const Text(
                              'Import feats from the Catalog before advancing.',
                            ),
                          const SizedBox(height: 6),
                          if (asInt(choice['count'], 1) == 1)
                            DropdownButtonFormField<String>(
                              key: ValueKey(asStr(choice['selectionKey'])),
                              initialValue: (selections[
                                              asStr(choice['selectionKey'])] ??
                                          const <String>{})
                                      .isEmpty
                                  ? null
                                  : selections[asStr(choice['selectionKey'])]!
                                      .first,
                              decoration: const InputDecoration(
                                  labelText: 'Choose one'),
                              items: [
                                for (final option
                                    in asMapList(choice['options']))
                                  DropdownMenuItem(
                                    value: asStr(option['id']),
                                    child: Text(asStr(option['name'])),
                                  ),
                              ],
                              onChanged: (id) => setState(() {
                                if (id != null) {
                                  selections[asStr(choice['selectionKey'])] = {
                                    id
                                  };
                                }
                              }),
                            )
                          else
                            for (final option in asMapList(choice['options']))
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(asStr(option['name'])),
                                subtitle: asStr(option['description']).isEmpty
                                    ? null
                                    : Text(asStr(option['description'])),
                                value: (selections[
                                            asStr(choice['selectionKey'])] ??
                                        const <String>{})
                                    .contains(asStr(option['id'])),
                                onChanged: (checked) => setState(() {
                                  final key = asStr(choice['selectionKey']);
                                  final selected =
                                      selections.putIfAbsent(key, () => {});
                                  final id = asStr(option['id']);
                                  if (checked == true) {
                                    if (selected.length <
                                        asInt(choice['count'], 1)) {
                                      selected.add(id);
                                    }
                                  } else {
                                    selected.remove(id);
                                  }
                                }),
                              ),
                          if (asInt(choice['count'], 1) == 1)
                            Builder(builder: (context) {
                              final selected =
                                  selections[asStr(choice['selectionKey'])];
                              final selectedId =
                                  selected == null || selected.isEmpty
                                      ? ''
                                      : selected.first;
                              final found = asMapList(choice['options']).where(
                                  (item) => asStr(item['id']) == selectedId);
                              final description = found.isEmpty
                                  ? ''
                                  : asStr(found.first['description']);
                              return description.isEmpty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(description),
                                    );
                            }),
                        ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    chosenClass == null || !choicesComplete || !xpEligible
                        ? null
                        : () {
                            final subclass = selectedSubclassId.isEmpty
                                ? null
                                : subclasses.firstWhere(
                                    (item) => item.id == selectedSubclassId,
                                  );
                            final error = ctrl.advanceLevel(
                              chosenClass,
                              catalog: campaign.catalog,
                              subclass: subclass,
                              requireXp: campaign.requireXpForLevelUp,
                              selections: {
                                for (final entry in selections.entries)
                                  entry.key: entry.value.toList(),
                              },
                            );
                            if (error != null) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(error)),
                              );
                              return;
                            }
                            Navigator.pop(dialogContext);
                          },
                child: Text(
                    character.classId.isEmpty ? 'Select class' : 'Level up'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final campaign = context.watch<CampaignController>();
    final c = ctrl.character;
    final next = Rules.xpForNextLevel(c);
    final ready = next != null && c.xp >= next;
    final xpLocked =
        c.classId.isNotEmpty && campaign.requireXpForLevelUp && !ready;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Level down',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: c.level > 1 ? () => ctrl.changeLevel(-1) : null,
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('LEVEL ${c.level}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(
            'Proficiency ${signed(Rules.proficiency(c))}'
            '${next == null ? '' : ready ? '  ·  XP for level ${c.level + 1} reached' : '  ·  next at $next XP'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            c.className.isEmpty
                ? 'Class not selected'
                : '${c.className}${c.subclassName.isEmpty ? '' : ' · ${c.subclassName}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
        IconButton(
          tooltip: c.classId.isEmpty
              ? 'Choose class'
              : xpLocked
                  ? 'Requires $next XP to level up'
                  : 'Level up',
          icon: Icon(Icons.add_circle_outline,
              color: ready ? Colors.greenAccent : null),
          onPressed:
              c.level < 20 && !xpLocked ? () => _levelUp(context, ctrl) : null,
        ),
      ]),
    );
  }
}
