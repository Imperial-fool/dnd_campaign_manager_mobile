import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';

enum SheetText { equipment, proficiencies, notes }

class FreeTextPanel extends StatelessWidget {
  const FreeTextPanel({super.key, required this.title, required this.field});

  final String title;
  final SheetText field;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;
    final value = switch (field) {
      SheetText.equipment => c.equipment,
      SheetText.proficiencies => c.proficiencies,
      SheetText.notes => c.notes,
    };
    return SheetCard(
      title: title,
      child: TextBinding(
        label: title,
        value: value,
        minLines: 5,
        maxLines: 14,
        onChanged: (v) => ctrl.edit((ch) {
          switch (field) {
            case SheetText.equipment:
              ch.equipment = v;
            case SheetText.proficiencies:
              ch.proficiencies = v;
            case SheetText.notes:
              ch.notes = v;
          }
        }),
      ),
    );
  }
}
