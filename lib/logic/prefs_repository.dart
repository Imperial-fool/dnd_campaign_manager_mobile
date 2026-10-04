import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/models/character.dart';

/// Cross-platform JSON storage (web localStorage, Windows/macOS/Linux/mobile
/// preferences store). Every value is a JSON string:
///   dnd.index        -> ["id1","id2"]
///   dnd.char.<id>    -> character JSON
///   dnd.catalog      -> catalog JSON
/// Use "View JSON" / import in the app to move data in and out as text.
class PrefsCampaignRepository implements CampaignRepository {
  PrefsCampaignRepository(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsCampaignRepository> create() async =>
      PrefsCampaignRepository(await SharedPreferences.getInstance());

  static const _indexKey = 'dnd.index';
  static const _catalogKey = 'dnd.catalog';
  static const _requireXpKey = 'dnd.settings.requireXpForLevelUp';
  String _charKey(String id) => 'dnd.char.$id';

  List<String> get _ids => _prefs.getStringList(_indexKey) ?? <String>[];

  @override
  Future<List<Character>> loadCharacters() async {
    final out = <Character>[];
    for (final id in _ids) {
      final raw = _prefs.getString(_charKey(id));
      if (raw == null) continue;
      try {
        final data = jsonDecode(raw);
        if (data is Map)
          out.add(Character.fromJson(Map<String, dynamic>.from(data)));
      } catch (_) {
        // Skip unreadable entries rather than blocking the whole campaign.
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  @override
  Future<void> saveCharacter(Character c) async {
    await _prefs.setString(_charKey(c.id), jsonEncode(c.toJson()));
    final ids = _ids;
    if (!ids.contains(c.id))
      await _prefs.setStringList(_indexKey, [...ids, c.id]);
  }

  @override
  Future<void> deleteCharacter(String id) async {
    await _prefs.remove(_charKey(id));
    await _prefs.setStringList(_indexKey, _ids.where((e) => e != id).toList());
  }

  @override
  Future<Map<String, dynamic>> loadCatalogJson() async {
    final raw = _prefs.getString(_catalogKey);
    if (raw == null) return {};
    try {
      final data = jsonDecode(raw);
      return data is Map ? Map<String, dynamic>.from(data) : {};
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveCatalogJson(Map<String, dynamic> json) =>
      _prefs.setString(_catalogKey, jsonEncode(json));

  @override
  Future<bool> loadRequireXpForLevelUp() async =>
      _prefs.getBool(_requireXpKey) ?? false;

  @override
  Future<void> saveRequireXpForLevelUp(bool requireXp) =>
      _prefs.setBool(_requireXpKey, requireXp);
}
