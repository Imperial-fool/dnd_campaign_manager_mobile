import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Campaign Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            value: campaign.requireXpForLevelUp,
            title: const Text('Require XP to level up'),
            subtitle: Text(
              campaign.requireXpForLevelUp
                  ? 'Characters must meet the standard XP threshold before advancing.'
                  : 'Level-ups are manual; XP thresholds are informational only.',
            ),
            onChanged: campaign.setRequireXpForLevelUp,
          ),
        ],
      ),
    );
  }
}
