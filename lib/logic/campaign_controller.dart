import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

/// App-level state: the character roster and the campaign catalog.
class CampaignController extends ChangeNotifier {
  CampaignController({required this.repository, ContentRegistry? registry})
      : registry = registry ?? ContentRegistry.standard() {
    importer = ContentImporter(this.registry);
  }

  final CampaignRepository repository;
  final ContentRegistry registry;
  late final ContentImporter importer;

  List<Character> characters = [];
  Catalog catalog = Catalog();
  bool loading = true;
  bool requireXpForLevelUp = false;

  static const _pretty = JsonEncoder.withIndent('  ');

  Future<void> load() async {
    loading = true;
    notifyListeners();
    characters = await repository.loadCharacters();
    catalog = Catalog();
    importer.loadInto(await repository.loadCatalogJson(), catalog);
    requireXpForLevelUp = await repository.loadRequireXpForLevelUp();
    loading = false;
    notifyListeners();
  }

  // ---- characters (Create / Read / Update / Delete) -------------------------
  Future<Character> createCharacter([String name = 'New Character']) async {
    final c = Character(id: newId())..name = name;
    characters.add(c);
    await repository.saveCharacter(c);
    notifyListeners();
    return c;
  }

  Future<void> deleteCharacter(Character c) async {
    characters.remove(c);
    await repository.deleteCharacter(c.id);
    notifyListeners();
  }

  Future<Character> duplicateCharacter(Character c) async {
    final copy = Character.fromJson({...c.toJson(), 'id': newId()});
    copy.name = '${c.name} (copy)';
    characters.add(copy);
    await repository.saveCharacter(copy);
    notifyListeners();
    return copy;
  }

  CharacterController editorFor(Character c) => CharacterController(
        character: c,
        repository: repository,
        onSaved: notifyListeners,
      );

  // ---- JSON in / out ---------------------------------------------------------
  String exportCharacter(Character c) => _pretty.convert(c.toJson());

  /// Throws [FormatException] on bad JSON. Always assigns a fresh id.
  Future<Character> importCharacter(String jsonText) async {
    final data = jsonDecode(jsonText);
    if (data is! Map) throw const FormatException('Expected a JSON object.');
    final c =
        Character.fromJson({...Map<String, dynamic>.from(data), 'id': newId()});
    characters.add(c);
    await repository.saveCharacter(c);
    notifyListeners();
    return c;
  }

  // ---- catalog / content packs ------------------------------------------------
  Future<ImportResult> importContent(String jsonText) async {
    final result = importer.importJson(jsonText, catalog);
    if (result.added + result.updated > 0) {
      await repository.saveCatalogJson(catalog.toJson());
    }
    notifyListeners();
    return result;
  }

  Future<void> removeCatalogItem(String key, String id) async {
    catalog.remove(key, id);
    await repository.saveCatalogJson(catalog.toJson());
    notifyListeners();
  }

  Future<void> setRequireXpForLevelUp(bool value) async {
    await repository.saveRequireXpForLevelUp(value);
    requireXpForLevelUp = value;
    notifyListeners();
  }

  String exportCatalog() => _pretty.convert(catalog.toJson());
}
