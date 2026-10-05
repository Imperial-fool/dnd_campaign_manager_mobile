import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:flutter/widgets.dart';

const bool supportsBoardPopout = false;
const bool supportsNativeFullscreen = false;

Future<bool> openBoardPopoutWindow({
  required BuildContext context,
  required Widget Function() childBuilder,
  required VttController controller,
  required List<Character> characters,
}) async {
  return false;
}

Future<bool> toggleBoardFullscreen(BuildContext context) async {
  return false;
}
