import 'package:flutter/widgets.dart';

void launchCampaignApp({
  required Widget app,
  required Widget Function(Widget child) globalScope,
}) {
  runApp(globalScope(app));
}

const bool supportsNativePopout = false;
