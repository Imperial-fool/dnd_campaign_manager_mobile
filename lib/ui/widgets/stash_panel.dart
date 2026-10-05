import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';

class StashPanel extends StatelessWidget {
  const StashPanel({super.key, this.isPlayerMode = false});

  final bool isPlayerMode;

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    final character = context.watch<CharacterController>().character;
    final items = campaign.stashForPlayer(character.player);
    return SheetCard(
      title: 'Player Stash',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            character.player.trim().isEmpty
                ? 'Assign a player to this character to use a shared stash.'
                : 'Shared by all characters assigned to ${character.player}.',
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('The player stash is empty.'),
            ),
          for (var index = 0; index < items.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                (items[index]['item'] as Map?)?['name']?.toString() ??
                    'Unnamed item',
              ),
              subtitle: Text(switch (items[index]['kind']) {
                'weapons' => 'Weapon',
                'armor' => 'Armor',
                _ => 'Item',
              }),
              trailing: isPlayerMode
                  ? null
                  : IconButton(
                      tooltip: 'Transfer to this character',
                      icon: const Icon(Icons.move_to_inbox_outlined),
                      onPressed: character.player.trim().isEmpty
                          ? null
                          : () => campaign.moveFromStash(character, index),
                    ),
            ),
        ],
      ),
    );
  }
}
