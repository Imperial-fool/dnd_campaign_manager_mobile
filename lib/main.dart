import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/logic/prefs_repository.dart';
import 'package:dnd_campaign_manager/ui/screens/character_list_screen.dart';
import 'package:dnd_campaign_manager/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await PrefsCampaignRepository.create();

  // To support a new content type, register a binding, e.g.:
  //   ..registerGeneric('spells', 'Spells')
  final registry = ContentRegistry.standard();

  final campaign = CampaignController(repository: repo, registry: registry);
  await campaign.load();

  runApp(ChangeNotifierProvider.value(value: campaign, child: const CampaignApp()));
}

class CampaignApp extends StatelessWidget {
  const CampaignApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Campaign Sheets',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const CharacterListScreen(),
      );
}
