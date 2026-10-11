import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/gear_panels.dart';

class SpellsPanel extends StatelessWidget {
  const SpellsPanel({super.key});

  static const _fields = [
    ('level', 'Level'),
    ('school', 'School'),
    ('castingTime', 'Casting time'),
    ('range', 'Range'),
    ('components', 'Components'),
    ('duration', 'Duration'),
  ];

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final raw = ctrl.character.extras['spells'];
    final spells = raw is List ? raw : const <dynamic>[];
    final invalidContainer = raw != null && raw is! List;
    final invalidEntries =
        raw is List ? raw.where((entry) => entry is! Map).length : 0;

    return SheetCard(
      title: 'Spells',
      actions: [
        IconButton(
          tooltip: 'Add blank spell',
          icon: const Icon(Icons.add),
          onPressed: invalidContainer
              ? null
              : () => ctrl.edit((character) {
                    final current = character.extras['spells'];
                    final entries = current is List
                        ? List<dynamic>.from(current)
                        : <dynamic>[];
                    entries.add({
                      'name': 'New Spell',
                      'level': '',
                      'school': '',
                      'castingTime': '',
                      'range': '',
                      'components': '',
                      'duration': '',
                      'description': '',
                    });
                    character.extras['spells'] = entries;
                  }),
        ),
        if (!invalidContainer)
          catalogButton(context, 'spells', tooltip: 'Add spell from catalog'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (spells.isEmpty && invalidEntries == 0)
            const Text(
                'No spells yet. Add one or import spells to the catalog.'),
          if (invalidEntries > 0)
            Text(
              '$invalidEntries spell entr${invalidEntries == 1 ? 'y is' : 'ies are'} '
              'not an object and cannot be displayed.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (invalidContainer)
            Text(
              'Stored spells data is not a list and cannot be edited.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (var index = 0; index < spells.length; index++)
            if (spells[index] is Map)
              _spell(context, ctrl, index,
                  Map<String, dynamic>.from(spells[index] as Map)),
        ],
      ),
    );
  }

  Widget _spell(BuildContext context, CharacterController ctrl, int index,
      Map<String, dynamic> spell) {
    Widget field(String key, String label) => TextBinding(
          key: ValueKey('spell-$index-$key'),
          label: label,
          value: '${spell[key] ?? ''}',
          onChanged: (value) => _update(ctrl, index, key, value),
        );

    return Container(
      key: ValueKey('spell-$index'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: field('name', 'Spell name')),
              IconButton(
                tooltip: 'Remove spell',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => ctrl.edit((character) {
                  final entries =
                      List<dynamic>.from(character.extras['spells'] as List);
                  entries.removeAt(index);
                  character.extras['spells'] = entries;
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (key, label) in _fields) ...[
            field(key, label),
            const SizedBox(height: 8),
          ],
          field('description', 'Description'),
        ],
      ),
    );
  }

  void _update(CharacterController ctrl, int index, String key, String value) {
    ctrl.edit((character) {
      final entries = List<dynamic>.from(character.extras['spells'] as List);
      final spell = Map<String, dynamic>.from(entries[index] as Map);
      spell[key] = value;
      entries[index] = spell;
      character.extras['spells'] = entries;
    });
  }
}
