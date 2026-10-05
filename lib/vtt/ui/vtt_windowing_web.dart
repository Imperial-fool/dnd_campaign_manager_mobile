import 'dart:js_interop';

import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

const bool supportsBoardPopout = true;
const bool supportsNativeFullscreen = true;

Future<bool> openBoardPopoutWindow({
  required BuildContext context,
  required Widget Function() childBuilder,
  required VttController controller,
  required List<Character> characters,
}) async {
  final uri = Uri.base.replace(
    queryParameters: <String, String>{
      ...Uri.base.queryParameters,
      'vttBoard': '1',
    },
  );
  web.window.open(uri.toString(), '_blank', 'popup,width=1600,height=960');
  return true;
}

Future<bool> toggleBoardFullscreen(BuildContext context) async {
  final document = web.document;
  if (document.fullscreenElement != null) {
    await document.exitFullscreen().toDart;
    return true;
  }
  final element = document.documentElement;
  if (element == null) return false;
  await element.requestFullscreen().toDart;
  return true;
}
