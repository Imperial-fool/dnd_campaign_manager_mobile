import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/ui/theme.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';
import 'package:dnd_campaign_manager/ui/widgets/gear_panels.dart';

enum TraitPanelFilter { all, feats, featuresAndTraits }

class TraitsPanel extends StatelessWidget {
  const TraitsPanel({
    super.key,
    this.filter = TraitPanelFilter.all,
  });

  final TraitPanelFilter filter;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    final c = ctrl.character;
    final traits = c.traits.where((trait) => switch (filter) {
          TraitPanelFilter.all => true,
          TraitPanelFilter.feats => trait.category == 'feat',
          TraitPanelFilter.featuresAndTraits => trait.category != 'feat',
        });
    return SheetCard(
      title: switch (filter) {
        TraitPanelFilter.all => 'Features & Traits',
        TraitPanelFilter.feats => 'Feats',
        TraitPanelFilter.featuresAndTraits => 'Features & Traits',
      },
      actions: [
        if (filter != TraitPanelFilter.feats) ...[
          IconButton(
            tooltip: 'Add blank feature',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => ctrl.addBlankTrait(category: 'feature'),
          ),
          IconButton(
            tooltip: 'Add blank trait',
            icon: const Icon(Icons.add),
            onPressed: () => ctrl.addBlankTrait(),
          ),
          catalogButton(context, 'features',
              tooltip: 'Add feature from catalog'),
          catalogButton(context, 'traits', tooltip: 'Add trait from catalog'),
        ],
        if (filter != TraitPanelFilter.featuresAndTraits) ...[
          if (filter == TraitPanelFilter.feats)
            IconButton(
              tooltip: 'Add blank feat',
              icon: const Icon(Icons.add),
              onPressed: () => ctrl.addBlankTrait(category: 'feat'),
            ),
          catalogButton(context, 'feats', tooltip: 'Add feat from catalog'),
        ],
      ],
      child: Column(children: [
        if (traits.isEmpty)
          Text(filter == TraitPanelFilter.feats
              ? 'No feats yet.'
              : 'No features or traits yet.'),
        for (final t in traits)
          Container(
            key: ObjectKey(t),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: kTan, borderRadius: BorderRadius.circular(8)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: TextBinding(
                          label: 'Name',
                          value: t.name,
                          onChanged: (v) => ctrl.edit((_) => t.name = v)),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: {'feature', 'feat'}.contains(t.category)
                          ? t.category
                          : 'trait',
                      items: const [
                        DropdownMenuItem(
                            value: 'feature', child: Text('Feature')),
                        DropdownMenuItem(value: 'feat', child: Text('Feat')),
                        DropdownMenuItem(value: 'trait', child: Text('Trait')),
                      ],
                      onChanged: (v) =>
                          ctrl.edit((_) => t.category = v ?? 'trait'),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => ctrl.edit((ch) => ch.traits.remove(t)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextBinding(
                    label: 'Description',
                    value: t.description,
                    maxLines: 6,
                    minLines: 2,
                    onChanged: (v) => ctrl.edit((_) => t.description = v),
                  ),
                  const SizedBox(height: 8),
                  TextBinding(
                      label: 'Source',
                      value: t.source,
                      onChanged: (v) => ctrl.edit((_) => t.source = v)),
                  const SizedBox(height: 8),
                  EffectsField(
                      effects: t.effects,
                      skills: ctrl.character.skills,
                      onChanged: (e) => ctrl.edit((_) => t.effects = e)),
                ]),
          ),
      ]),
    );
  }
}
