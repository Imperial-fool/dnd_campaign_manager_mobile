import 'package:dnd_campaign_manager/app_host.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/campaign_controller.dart';
import 'package:dnd_campaign_manager/logic/google_drive_service.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/logic/firebase_campaign_service.dart';
import 'package:dnd_campaign_manager/logic/prefs_repository.dart';
import 'package:dnd_campaign_manager/ui/screens/character_list_screen.dart';
import 'package:dnd_campaign_manager/ui/theme.dart';
import 'package:dnd_campaign_manager/vtt/ui/vtt_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await PrefsCampaignRepository.create();
  final googleDrive = GoogleDriveService();
  await googleDrive.initialize();
  final sharedCampaign = await FirebaseCampaignService.initialize();
  await sharedCampaign.restoreSession();

  // To support a new content type, register a binding, e.g.:
  //   ..registerGeneric('spells', 'Spells')
  final registry = ContentRegistry.standard();

  final campaign = CampaignController(
    repository: repo,
    sharedCampaign: sharedCampaign,
    registry: registry,
  );
  await campaign.load();

  final startOnBoard = Uri.base.queryParameters['vttBoard'] == '1';

  launchCampaignApp(
    app: CampaignApp(startOnBoard: startOnBoard),
    globalScope: (child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: campaign),
        ChangeNotifierProvider.value(value: googleDrive),
        ChangeNotifierProvider.value(value: sharedCampaign),
      ],
      child: child,
    ),
  );
}

class CampaignApp extends StatelessWidget {
  const CampaignApp({
    super.key,
    required this.startOnBoard,
  });

  final bool startOnBoard;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Campaign Sheets',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: startOnBoard
            ? VttScreen(
                characters: context.watch<CampaignController>().characters,
              )
            : const CharacterListScreen(),
      );
}
