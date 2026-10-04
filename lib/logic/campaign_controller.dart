import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

/// App-level state: the character roster and the campaign catalog.
class CampaignController extends ChangeNotifier {
  CampaignController({
    required this.repository,
    ContentRegistry? registry,
    AssetBundle? assetBundle,
  })  : registry = registry ?? ContentRegistry.standard(),
        assetBundle = assetBundle ?? rootBundle {
    importer = ContentImporter(this.registry);
  }

  final CampaignRepository repository;
  final ContentRegistry registry;
  final AssetBundle assetBundle;
  late final ContentImporter importer;

  List<Character> characters = [];
  Catalog catalog = Catalog();
  final Map<String, List<Map<String, dynamic>>> _playerStashes = {};
  bool loading = true;
  bool requireXpForLevelUp = false;

  static const _pretty = JsonEncoder.withIndent('  ');

  Future<void> load() async {
    WidgetsFlutterBinding.ensureInitialized();
    loading = true;
    notifyListeners();
    characters = await repository.loadCharacters();
    catalog = Catalog();
    final bundledSkills = await assetBundle.loadString('content/skills.json');
    importer.loadInto(
      Map<String, dynamic>.from(jsonDecode(bundledSkills) as Map),
      catalog,
    );
    final bundledMechanics = Map<String, dynamic>.from(
      jsonDecode(await assetBundle.loadString('content/tarkov_mechanics.json'))
          as Map,
    );
    importer.loadInto({'actions': bundledMechanics['actions']}, catalog);
    importer.loadInto(
      Map<String, dynamic>.from(
        jsonDecode(await assetBundle.loadString('content/tarkov_armory.json'))
            as Map,
      ),
      catalog,
    );
    final catalogJson = await repository.loadCatalogJson();
    _playerStashes
      ..clear()
      ..addAll(_decodeStashes(catalogJson.remove('playerStashes')));
    importer.loadInto(catalogJson, catalog);
    await _ensureSkillDefinitionsOnCharacters();
    requireXpForLevelUp = await repository.loadRequireXpForLevelUp();
    loading = false;
    notifyListeners();
  }

  // ---- characters (Create / Read / Update / Delete) -------------------------
  Future<Character> createCharacter([String name = 'New Character']) async {
    final c = Character(id: newId())..name = name;
    final definitions = catalog.items('skills').whereType<GenericItem>();
    if (definitions.isNotEmpty) {
      c.skills = definitions
          .map((definition) => Skill(
                name: definition.name,
                ability:
                    Ability.fromKey(asStr(definition.data['ability'], 'str')),
              ))
          .toList();
    }
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

  Future<void> _ensureSkillDefinitionsOnCharacters() async {
    final definitions = catalog.items('skills').whereType<GenericItem>();
    for (final character in characters) {
      var changed = false;
      for (final definition in definitions) {
        if (character.skills
            .any((skill) => skill.key == slug(definition.name))) {
          continue;
        }
        character.skills.add(Skill(
          name: definition.name,
          ability: Ability.fromKey(asStr(definition.data['ability'], 'str')),
        ));
        changed = true;
      }
      if (changed) await repository.saveCharacter(character);
    }
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
      await _saveCatalog();
    }
    notifyListeners();
    return result;
  }

  Future<void> removeCatalogItem(String key, String id) async {
    catalog.remove(key, id);
    await _saveCatalog();
    notifyListeners();
  }

  List<Map<String, dynamic>> stashForPlayer(String player) =>
      List.unmodifiable(_playerStashes[_playerKey(player)] ?? const []);

  Future<bool> moveToStash(
      Character character, String kind, CatalogItem item) async {
    final key = _playerKey(character.player);
    if (key.isEmpty) return false;
    final removed = switch (kind) {
      'weapons' => character.weapons.remove(item),
      'armor' => character.armor.remove(item),
      'items' => character.items.remove(item),
      _ => false,
    };
    if (!removed) return false;
    _playerStashes.putIfAbsent(key, () => []).add({
      'kind': kind,
      'item': item.toJson(),
    });
    await repository.saveCharacter(character);
    await _saveCatalog();
    notifyListeners();
    return true;
  }

  Future<bool> moveFromStash(Character character, int index) async {
    final key = _playerKey(character.player);
    final stash = _playerStashes[key];
    if (key.isEmpty || stash == null || index < 0 || index >= stash.length) {
      return false;
    }
    final stored = stash[index];
    final raw = stored['item'];
    if (raw is! Map) {
      throw const FormatException('Stashed item is not a JSON object.');
    }
    final json = Map<String, dynamic>.from(raw);
    switch (stored['kind']) {
      case 'weapons':
        character.weapons.add(Weapon.fromJson(json));
        break;
      case 'armor':
        character.armor.add(Armor.fromJson(json));
        break;
      case 'items':
        character.items.add(InventoryItem.fromJson(json));
        break;
      default:
        throw FormatException(
            'Unsupported stashed item type "${stored['kind']}".');
    }
    stash.removeAt(index);
    if (stash.isEmpty) _playerStashes.remove(key);
    await repository.saveCharacter(character);
    await _saveCatalog();
    notifyListeners();
    return true;
  }

  static String _playerKey(String player) => player.trim().toLowerCase();

  Map<String, List<Map<String, dynamic>>> _decodeStashes(dynamic value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        if (entry.value is List)
          entry.key.toString(): (entry.value as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
    };
  }

  Future<void> _saveCatalog() => repository.saveCatalogJson({
        ...catalog.toJson(),
        if (_playerStashes.isNotEmpty)
          'playerStashes': {
            for (final entry in _playerStashes.entries) entry.key: entry.value,
          },
      });

  Future<void> setRequireXpForLevelUp(bool value) async {
    await repository.saveRequireXpForLevelUp(value);
    requireXpForLevelUp = value;
    notifyListeners();
  }

  String exportCatalog() => _pretty.convert(catalog.toJson());
}
