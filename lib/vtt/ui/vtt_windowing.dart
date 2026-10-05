import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:flutter/widgets.dart';

import 'vtt_windowing_stub.dart'
    if (dart.library.io) 'vtt_windowing_io.dart'
    if (dart.library.js_interop) 'vtt_windowing_web.dart' as impl;

bool get supportsBoardPopout => impl.supportsBoardPopout;

Future<bool> openBoardPopoutWindow({
  required BuildContext context,
  required Widget Function() childBuilder,
  required VttController controller,
  required List<Character> characters,
}) {
  return impl.openBoardPopoutWindow(
    context: context,
    childBuilder: childBuilder,
    controller: controller,
    characters: characters,
  );
}

Future<bool> toggleBoardFullscreen(BuildContext context) {
  return impl.toggleBoardFullscreen(context);
}

bool get supportsNativeFullscreen => impl.supportsNativeFullscreen;
