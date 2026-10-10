import 'package:flutter/material.dart';
import 'package:dnd_campaign_manager/models/equipment_rule_effect.dart';

class EquipmentRuleEffectsField extends StatelessWidget {
  const EquipmentRuleEffectsField({
    super.key,
    required this.effects,
    required this.onChanged,
  });

  final List<EquipmentRuleEffect> effects;
  final ValueChanged<List<EquipmentRuleEffect>> onChanged;

  Future<EquipmentRuleEffect?> _addRicochet(BuildContext context) async {
    final controller = TextEditingController(text: '0');
    String? error;
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Ricochet chance'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Chance (%)',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text);
                if (parsed == null || parsed < 0 || parsed > 100) {
                  setState(() => error = 'Enter a whole number from 0 to 100.');
                  return;
                }
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return value == null ? null : EquipmentRuleEffect.ricochetChance(value);
  }

  Future<EquipmentRuleEffect?> _addFactionDisposition(
      BuildContext context) async {
    final controller = TextEditingController();
    var disposition = 'friendly';
    String? error;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Faction disposition'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Faction',
                  errorText: error,
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: disposition,
                decoration: const InputDecoration(labelText: 'Disposition'),
                items: const [
                  DropdownMenuItem(value: 'friendly', child: Text('Friendly')),
                  DropdownMenuItem(value: 'neutral', child: Text('Neutral')),
                  DropdownMenuItem(value: 'hostile', child: Text('Hostile')),
                ],
                onChanged: (value) =>
                    setState(() => disposition = value ?? 'friendly'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  setState(() => error = 'Enter a faction name.');
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  (controller.text.trim(), disposition),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null) return null;
    return EquipmentRuleEffect.factionDisposition(
      faction: result.$1,
      disposition: result.$2,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Equipment rules'),
          for (var index = 0; index < effects.length; index++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(effects[index].summary),
              trailing: IconButton(
                tooltip: 'Remove equipment rule',
                icon: const Icon(Icons.close),
                onPressed: () {
                  final next = [...effects]..removeAt(index);
                  onChanged(next);
                },
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final effect = await _addRicochet(context);
                  if (effect != null) onChanged([...effects, effect]);
                },
                child: const Text('Add ricochet rule'),
              ),
              OutlinedButton(
                onPressed: () async {
                  final effect = await _addFactionDisposition(context);
                  if (effect != null) onChanged([...effects, effect]);
                },
                child: const Text('Add faction rule'),
              ),
            ],
          ),
        ],
      );
}
