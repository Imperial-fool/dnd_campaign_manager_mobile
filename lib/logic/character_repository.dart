import 'dart:convert';
import 'dart:io';

import 'package:dnd_campaign_manager/models/character.dart';

/// Storage contract. The UI/controllers only know this interface, so the
/// backing store (files, SQLite, cloud) can be swapped without touching them.
abstract class CampaignRepository {
  Future<List<Character>> loadCharacters();
  Future<void> saveCharacter(Character character);
  Future<void> deleteCharacter(String id);
  Future<Map<String, dynamic>> loadCatalogJson();
  Future<void> saveCatalogJson(Map<String, dynamic> json);
  Future<bool> loadRequireXpForLevelUp();
  Future<void> saveRequireXpForLevelUp(bool requireXp);
  Future<bool> loadPullAmmoFromInventory();
  Future<void> savePullAmmoFromInventory(bool pullAmmo);
}

/// One pretty-printed JSON file per character plus catalog.json:
///   <root>/characters/<id>.json
///   <root>/catalog.json
class FileCampaignRepository implements CampaignRepository {
  FileCampaignRepository(this.root);

  final Directory root;
  static const _encoder = JsonEncoder.withIndent('  ');

  Directory get _charDir => Directory('${root.path}/characters');
  File get _catalogFile => File('${root.path}/catalog.json');
  File get _settingsFile => File('${root.path}/settings.json');

  Future<void> _writeAtomic(File file, Map<String, dynamic> json) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(_encoder.convert(json), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<List<Character>> loadCharacters() async {
    if (!await _charDir.exists()) return [];
    final out = <Character>[];
    await for (final f in _charDir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await f.readAsString());
        if (data is Map)
          out.add(Character.fromJson(Map<String, dynamic>.from(data)));
      } catch (_) {
        // Skip unreadable files rather than blocking the whole campaign.
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  @override
  Future<void> saveCharacter(Character c) =>
      _writeAtomic(File('${_charDir.path}/${c.id}.json'), c.toJson());

  @override
  Future<void> deleteCharacter(String id) async {
    final f = File('${_charDir.path}/$id.json');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<Map<String, dynamic>> loadCatalogJson() async {
    if (!await _catalogFile.exists()) return {};
    try {
      final data = jsonDecode(await _catalogFile.readAsString());
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveCatalogJson(Map<String, dynamic> json) =>
      _writeAtomic(_catalogFile, json);

  @override
  Future<bool> loadRequireXpForLevelUp() async {
    if (!await _settingsFile.exists()) return false;
    try {
      final data = jsonDecode(await _settingsFile.readAsString());
      return data is Map && data['requireXpForLevelUp'] == true;
    } on FormatException {
      return false;
    }
  }

  @override
  Future<void> saveRequireXpForLevelUp(bool requireXp) async {
    final settings = await _loadSettings();
    settings['requireXpForLevelUp'] = requireXp;
    await _writeAtomic(_settingsFile, settings);
  }

  Future<Map<String, dynamic>> _loadSettings() async {
    if (!await _settingsFile.exists()) return {};
    try {
      final data = jsonDecode(await _settingsFile.readAsString());
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } on FormatException {
      return {};
    }
  }

  @override
  Future<bool> loadPullAmmoFromInventory() async {
    final settings = await _loadSettings();
    return settings['pullAmmoFromInventory'] == true;
  }

  @override
  Future<void> savePullAmmoFromInventory(bool pullAmmo) async {
    final settings = await _loadSettings();
    settings['pullAmmoFromInventory'] = pullAmmo;
    await _writeAtomic(_settingsFile, settings);
  }
}
