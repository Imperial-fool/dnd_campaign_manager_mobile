import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ContentAssetBundle extends CachingAssetBundle {
  static const _assets = {
    'content/skills.json',
    'content/tarkov_mechanics.json',
    'content/tarkov_armory.json',
    'content/tarkov_character_options.json',
    'content/character_creation.json',
  };

  final loadedAssets = <String>{};

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (!_assets.contains(key)) {
      throw FlutterError('Unexpected asset: $key');
    }
    loadedAssets.add(key);
    return File(key).readAsStringSync();
  }

  @override
  Future<ByteData> load(String key) async {
    if (!_assets.contains(key)) {
      throw FlutterError('Unexpected asset: $key');
    }
    loadedAssets.add(key);
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
