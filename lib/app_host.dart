import 'package:flutter/widgets.dart';

import 'app_host_stub.dart'
    if (dart.library.io) 'app_host_io.dart'
    if (dart.library.js_interop) 'app_host_stub.dart' as impl;

void launchCampaignApp({
  required Widget app,
  required Widget Function(Widget child) globalScope,
}) {
  impl.launchCampaignApp(app: app, globalScope: globalScope);
}

bool get supportsNativePopout => impl.supportsNativePopout;
