import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';

class StashPanel extends StatelessWidget {
  const StashPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    final editor = context.watch<CharacterController>();
    final character = editor.character;
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
            Builder(builder: (context) {
              final entry = items[index];
              final rawItem = entry['item'];
              final item =
                  rawItem is Map ? Map<String, dynamic>.from(rawItem) : {};
              final kind = asStr(entry['kind']);
              final quantity = kind == 'items' ? asInt(item['quantity'], 1) : 1;
              final typeLabel = switch (kind) {
                'weapons' => 'Weapon',
                'armor' => 'Armor',
                'items' => item['kind'] == 'ammo' ? 'Ammunition' : 'Item',
                _ => 'Unknown',
              };
              final details = switch (kind) {
                'weapons' => [
                    asStr(item['ammoType']),
                    asStr(item['damage']),
                    if (asInt(item['ammoMax']) > 0)
                      'Magazine ${asInt(item['ammo'])}/${asInt(item['ammoMax'])}',
                  ].where((part) => part.isNotEmpty).join(' · '),
                'armor' =>
                  'Rating ${asInt(item['rating'])} · HP ${asInt(item['hp'])}/${asInt(item['hpMax'])}',
                'items' => asStr(item['description']).isNotEmpty
                    ? asStr(item['description'])
                    : asStr(item['ammoType']),
                _ => '',
              };
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(asStr(item['name'], 'Unnamed item')),
                subtitle: Text([
                  typeLabel,
                  if (details.isNotEmpty) details,
                ].join(' · ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('x$quantity'),
                    IconButton(
                      tooltip: 'Transfer to this character',
                      icon: const Icon(Icons.move_to_inbox_outlined),
                      onPressed: character.player.trim().isEmpty
                          ? null
                          : () async {
                              try {
                                await editor.flush();
                                final moved = await campaign.moveFromStash(
                                  character,
                                  index,
                                );
                                if (!context.mounted) return;
                                if (moved) {
                                  editor.notifyExternalMutation();
                                }
                              } catch (error) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Could not retrieve item from stash: $error',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
