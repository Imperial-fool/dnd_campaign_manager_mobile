import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';

class ActionsPanel extends StatelessWidget {
  const ActionsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = context
        .watch<CampaignController>()
        .catalog
        .items('actions')
        .whereType<GenericItem>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    const actionOrder = ['action', 'bonus', 'reaction'];
    return SheetCard(
      title: 'Combat Actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final type in actionOrder) ...[
            Text(
              switch (type) {
                'bonus' => 'Bonus Actions',
                'reaction' => 'Reactions',
                _ => 'Actions',
              },
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final action in actions.where(
              (action) => action.data['actionType'] == type,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(action.name),
                subtitle: Text(action.summary),
              ),
          ],
        ],
      ),
    );
  }
}
