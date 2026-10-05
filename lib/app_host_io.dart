import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

void launchCampaignApp({
  required Widget app,
  required Widget Function(Widget child) globalScope,
}) {
  if (Platform.isWindows) {
    runMultiApp(
      home: (_, __) => app,
      globalScope: globalScope,
    );
    return;
  }
  runApp(globalScope(app));
}

bool get supportsNativePopout => Platform.isWindows;
