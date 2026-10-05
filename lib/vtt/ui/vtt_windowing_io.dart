import 'dart:io';

import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

bool get supportsBoardPopout => Platform.isWindows;
bool get supportsNativeFullscreen => Platform.isWindows;

Future<bool> openBoardPopoutWindow({
  required BuildContext context,
  required Widget Function() childBuilder,
  required VttController controller,
  required List<Character> characters,
}) async {
  if (!Platform.isWindows) {
    return false;
  }
  await openWindow(
    (_, __) => childBuilder(),
    parentContext: context,
    options: const WindowOptions(
      title: 'Campaign board',
      size: Size(1600, 960),
    ),
  );
  return true;
}

Future<bool> toggleBoardFullscreen(BuildContext context) async {
  if (!Platform.isWindows) {
    return false;
  }
  final window = MultiViewDesktop.of(context);
  window.setFullScreen(!window.isFullScreen());
  return true;
}
