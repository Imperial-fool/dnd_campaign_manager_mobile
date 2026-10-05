import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/models/sheet_template.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';

/// Renders the DM-designed components attached to this character and lets
/// the player attach more from the catalog.
class CustomSheetPanel extends StatelessWidget {
  const CustomSheetPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final campaign = context.watch<CampaignController>();
    final available = campaign.catalog
        .items('sheetTemplates')
        .whereType<SheetTemplate>()
        .toList();
    final ids = SheetEvaluator.componentIds(ctrl.character);
    if (available.isEmpty && ids.isEmpty) return const SizedBox.shrink();
    SheetTemplate? find(String id) {
      for (final t in available) {
        if (t.id == id) return t;
      }
      return null;
    }

    final addable = [
      for (final t in available)
        if (!ids.contains(t.id)) t
    ];
    return SheetCard(
      title: 'Components',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final id in ids) _component(context, ctrl, id, find(id)),
          if (addable.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                tooltip: 'Add a component',
                onSelected: (id) =>
                    ctrl.edit((c) => SheetEvaluator.addComponent(c, id)),
                itemBuilder: (_) => [
                  for (final t in addable)
                    PopupMenuItem(
                      value: t.id,
                      child: Text(t.name),
                    ),
                ],
                child: const Chip(
                  avatar: Icon(Icons.add, size: 18),
                  label: Text('Add component'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _component(BuildContext context, CharacterController ctrl, String id,
      SheetTemplate? template) {
    final header = Row(children: [
      Expanded(
        child: Text(template?.name ?? id,
            style: Theme.of(context).textTheme.titleSmall),
      ),
      IconButton(
        tooltip: 'Move up',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.arrow_upward, size: 18),
        onPressed: () =>
            ctrl.edit((c) => SheetEvaluator.moveComponent(c, id, -1)),
      ),
      IconButton(
        tooltip: 'Move down',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.arrow_downward, size: 18),
        onPressed: () =>
            ctrl.edit((c) => SheetEvaluator.moveComponent(c, id, 1)),
      ),
      IconButton(
        tooltip: 'Remove component',
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.close, size: 18),
        onPressed: () =>
            ctrl.edit((c) => SheetEvaluator.removeComponent(c, id)),
      ),
    ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        if (template == null)
          const Text('This component is not in the loaded catalog.')
        else
          ..._sections(ctrl, template),
      ]),
    );
  }

  List<Widget> _sections(CharacterController ctrl, SheetTemplate template) {
    final evaluator = SheetEvaluator(ctrl.character, template);
    final sections = template.sections;
    return [
      for (final section in sections) ...[
        if (sections.length > 1 || section != 'General')
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(section,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        for (final f in template.fields.where((f) => f.section == section))
          _fieldRow(ctrl, template, evaluator, f),
      ],
    ];
  }

  Widget _fieldRow(CharacterController ctrl, SheetTemplate template,
      SheetEvaluator evaluator, SheetField f) {
    switch (f.type) {
      case SheetFieldType.calc:
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          trailing: Text(evaluator.calcText(f),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        );
      case SheetFieldType.roll:
        return Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.casino_outlined),
            label: Text(f.label),
            onPressed: () => ctrl.rollSheetField(template, f),
          ),
        );
      case SheetFieldType.toggle:
        final raw = evaluator.rawValue(f);
        return CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: raw == true || raw == 'true' || raw == 1,
          onChanged: (v) => ctrl
              .edit((c) => SheetEvaluator(c, template).setValue(f, v ?? false)),
        );
      case SheetFieldType.number:
      case SheetFieldType.text:
        final isNumber = f.type == SheetFieldType.number;
        return TextBinding(
          key: ValueKey('${template.id}.${f.key}'),
          label: f.label,
          value: '${evaluator.rawValue(f) ?? ''}',
          onChanged: (v) => ctrl.edit((c) => SheetEvaluator(c, template)
              .setValue(f, isNumber ? (num.tryParse(v) ?? 0) : v)),
        );
    }
  }
}
