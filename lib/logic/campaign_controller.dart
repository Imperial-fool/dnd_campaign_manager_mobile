import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/character_repository.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/logic/dice.dart';
import 'package:dnd_campaign_manager/logic/firebase_campaign_service.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

/// App-level state: the character roster and the campaign catalog.
class CampaignController extends ChangeNotifier {
  CampaignController({
    required this.repository,
    this.sharedCampaign,
    ContentRegistry? registry,
    AssetBundle? assetBundle,
  })  : registry = registry ?? ContentRegistry.standard(),
        assetBundle = assetBundle ?? rootBundle {
    importer = ContentImporter(this.registry);
  }

  final CampaignRepository repository;
  final FirebaseCampaignService? sharedCampaign;
  final ContentRegistry registry;
  final AssetBundle assetBundle;
  late final ContentImporter importer;

  List<Character> characters = [];
  Catalog catalog = Catalog();
  final Map<String, List<Map<String, dynamic>>> _playerStashes = {};
  bool loading = true;
  bool requireXpForLevelUp = false;
  bool allowPlayerCharacterCreation = false;
  Map<String, dynamic> creationRules = const {};
  List<Character>? _localCharactersBeforeSharing;
  StreamSubscription<List<Character>>? _sharedCharactersSubscription;
  StreamSubscription<Map<String, dynamic>>? _sharedConfigurationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _sharedStashesSubscription;

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
    creationRules = Map<String, dynamic>.from(
      jsonDecode(
        await assetBundle.loadString('content/character_creation.json'),
      ) as Map,
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
    if (sharedCampaign?.isConnected == true) {
      await _restoreSharedCampaign();
    }
    loading = false;
    notifyListeners();
  }

  // ---- characters (Create / Read / Update / Delete) -------------------------
  Future<Character> createCharacter([String name = 'New Character']) async {
    final c = Character(id: newId())..name = name;
    return createCharacterFromSheet(c);
  }

  Future<Character> createCharacterFromSheet(Character c) async {
    final isPlayer =
        sharedCampaign?.isConnected == true && sharedCampaign?.isOwner == false;
    if (isPlayer && !allowPlayerCharacterCreation) {
      throw StateError('The DM has not enabled player character creation.');
    }
    if (isPlayer) {
      c
        ..player = sharedCampaign!.playerName ?? ''
        ..xp = 0
        ..level = 1
        ..hpMax = c.hpMax.clamp(1, 100)
        ..hpCurrent = c.hpCurrent.clamp(0, c.hpMax)
        ..hitDiceTotal = c.hitDiceTotal.clamp(0, 1)
        ..weapons.clear()
        ..armor.clear()
        ..items.clear()
        ..weaponHp = 0
        ..armorHp = 0;
    }
    final definitions = catalog.items('skills').whereType<GenericItem>();
    if (definitions.isNotEmpty) {
      for (final definition in definitions) {
        if (c.skills.any((skill) => skill.key == slug(definition.name))) {
          continue;
        }
        c.skills.add(Skill(
          name: definition.name,
          ability: Ability.fromKey(asStr(definition.data['ability'], 'str')),
        ));
      }
    }
    if (isPlayer) {
      await sharedCampaign!.createPlayerCharacter(c);
    }
    characters.add(c);
    await repository.saveCharacter(c);
    if (!isPlayer) _publishCharacter(c);
    notifyListeners();
    return c;
  }

  Future<void> deleteCharacter(Character c) async {
    _ensureDmCanEdit();
    characters.remove(c);
    await repository.deleteCharacter(c.id);
    _publishCloud(sharedCampaign?.deleteCharacter(c.id));
    notifyListeners();
  }

  Future<void> _ensureSkillDefinitionsOnCharacters() async {
    if (sharedCampaign?.isConnected == true &&
        sharedCampaign?.isOwner == false) {
      return;
    }
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
    _ensureDmCanEdit();
    final copy = Character.fromJson({...c.toJson(), 'id': newId()});
    copy.name = '${c.name} (copy)';
    characters.add(copy);
    await repository.saveCharacter(copy);
    _publishCharacter(copy);
    notifyListeners();
    return copy;
  }

  CharacterController editorFor(
    Character c, {
    bool forceReadOnly = false,
    bool allowReadOnlyEditToggle = false,
  }) =>
      CharacterController(
        character: c,
        repository: repository,
        isReadOnly: forceReadOnly,
        isPlayerMode: sharedCampaign?.isConnected == true &&
            sharedCampaign?.isOwner == false,
        allowReadOnlyEditToggle: allowReadOnlyEditToggle,
        onSaved: (savedCharacter) {
          final isPlayer = sharedCampaign?.isConnected == true &&
              sharedCampaign?.isOwner == false;
          if (!isPlayer) notifyListeners();
          if (sharedCampaign?.isOwner == true) {
            _publishCharacter(savedCharacter);
          } else if (isPlayer) {
            _publishCloud(
                sharedCampaign!.syncPlayerCharacterState(savedCharacter));
          }
        },
        onRoll: (entry) => _publishRoll(c, entry),
      );

  Future<String> createSharedCampaign() async {
    final service = _requireSharedService();
    _localCharactersBeforeSharing ??= List.of(characters);
    final code = await service.createCampaign(
      catalog: catalog.toJson(),
      requireXpForLevelUp: requireXpForLevelUp,
      allowPlayerCharacterCreation: allowPlayerCharacterCreation,
      creationRules: creationRules,
      characters: characters,
    );
    _watchSharedCharacters();
    notifyListeners();
    return code;
  }

  Future<void> joinSharedCampaign({
    required String code,
    required String playerName,
  }) async {
    final service = _requireSharedService();
    _localCharactersBeforeSharing ??= List.of(characters);
    final config = await service.joinCampaign(
      code: code,
      playerName: playerName,
    );
    _playerStashes.clear();
    _applySharedConfiguration(config);
    _watchSharedCharacters();
    notifyListeners();
  }

  Future<void> assignCharacterToPlayer(
      String characterId, String? playerUid) async {
    final service = _requireSharedService();
    if (!service.isOwner) {
      throw StateError('Only the DM can assign characters.');
    }
    final character = characters.firstWhere(
      (candidate) => candidate.id == characterId,
      orElse: () => throw StateError('Character not found.'),
    );
    character.player = await service.assignCharacter(
          characterId,
          playerUid,
          _playerStashes,
        ) ??
        '';
    await repository.saveCharacter(character);
    notifyListeners();
  }

  Future<void> _restoreSharedCampaign() async {
    final service = sharedCampaign!;
    _localCharactersBeforeSharing ??= List.of(characters);
    try {
      if (!service.isOwner) _playerStashes.clear();
      _applySharedConfiguration(await service.loadCampaign());
      _watchSharedCharacters();
    } catch (error) {
      await service.leaveCampaign(removeMember: false);
      service.reportError(error);
    }
  }

  Future<void> leaveSharedCampaign() async {
    final service = _requireSharedService();
    await _sharedCharactersSubscription?.cancel();
    await _sharedConfigurationSubscription?.cancel();
    await _sharedStashesSubscription?.cancel();
    _sharedCharactersSubscription = null;
    _sharedConfigurationSubscription = null;
    _sharedStashesSubscription = null;
    await service.leaveCampaign();
    characters = _localCharactersBeforeSharing ?? characters;
    _localCharactersBeforeSharing = null;
    await load();
  }

  Future<void> refreshSharedCampaign() async {
    final service = sharedCampaign;
    if (service?.isConnected != true) return;
    final config = await service!.loadCampaign();
    _applySharedConfiguration(config);
    notifyListeners();
  }

  void _watchSharedCharacters() {
    _sharedCharactersSubscription?.cancel();
    _sharedConfigurationSubscription?.cancel();
    _sharedCharactersSubscription = sharedCampaign!.watchCharacters().listen(
      (remoteCharacters) {
        remoteCharacters.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        characters = remoteCharacters;
        notifyListeners();
      },
      onError: (Object error) => sharedCampaign!.reportError(error),
    );
    _watchSharedStashes();
    if (!sharedCampaign!.isOwner) {
      _sharedConfigurationSubscription =
          sharedCampaign!.watchConfiguration().listen(
        (configuration) {
          _applySharedConfiguration(configuration);
          notifyListeners();
        },
        onError: (Object error) => sharedCampaign!.reportError(error),
      );
    }
  }

  void _applySharedConfiguration(Map<String, dynamic> data) {
    final remoteCatalog = data['catalog'];
    if (remoteCatalog is Map) {
      final json = Map<String, dynamic>.from(remoteCatalog);
      if (json.containsKey('playerStashes')) {
        _playerStashes
          ..clear()
          ..addAll(_decodeStashes(json.remove('playerStashes')));
      }
      catalog = Catalog();
      importer.loadInto(json, catalog);
    }
    final rules = data['rules'];
    if (rules is Map) {
      requireXpForLevelUp = rules['requireXpForLevelUp'] == true;
      allowPlayerCharacterCreation =
          rules['allowPlayerCharacterCreation'] == true;
    }
    final remoteCreationRules = data['creationRules'];
    if (remoteCreationRules is Map) {
      creationRules = Map<String, dynamic>.from(remoteCreationRules);
    }
  }

  Map<String, dynamic> _sharedCatalogJson() => {
        ...catalog.toJson(),
        if (_playerStashes.isNotEmpty)
          'playerStashes': {
            for (final entry in _playerStashes.entries) entry.key: entry.value,
          },
      };

  void _watchSharedStashes() {
    _sharedStashesSubscription?.cancel();
    _sharedStashesSubscription = sharedCampaign!.watchStashes().listen(
      (stashes) {
        if (sharedCampaign!.isOwner) {
          for (final stash in stashes) {
            final playerName = asStr(stash['playerName']);
            final key = _playerKey(playerName);
            final items = stash['items'];
            if (key.isNotEmpty && items is List) {
              _playerStashes[key] = items
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList();
            }
          }
        } else {
          final key = _playerKey(sharedCampaign!.playerName ?? '');
          if (key.isNotEmpty) {
            if (stashes.isEmpty) {
              _playerStashes.remove(key);
            } else {
              final items = stashes.first['items'];
              _playerStashes[key] = items is List
                  ? items
                      .whereType<Map>()
                      .map((item) => Map<String, dynamic>.from(item))
                      .toList()
                  : <Map<String, dynamic>>[];
            }
          }
        }
        notifyListeners();
      },
      onError: (Object error) => sharedCampaign!.reportError(error),
    );
  }

  Future<void> _syncPlayerStash(String playerName) async {
    final service = sharedCampaign;
    if (service?.isOwner != true) return;
    await service!.syncStashForPlayer(
      playerName,
      _playerStashes[_playerKey(playerName)] ?? const [],
    );
  }

  void _publishCharacter(Character character) {
    final service = sharedCampaign;
    if (service?.isOwner == true) {
      _publishCloud(service!.syncCharacter(character));
    }
  }

  void _publishRoll(Character character, RollEntry entry) {
    final service = sharedCampaign;
    if (service?.isConnected == true && service?.isOwner == false) {
      _publishCloud(service!.publishRoll(
        character: character,
        title: entry.title,
        total: entry.total,
        lines: entry.lines,
        crit: entry.crit,
        fumble: entry.fumble,
      ));
    }
  }

  void _publishCloud(Future<void>? operation) {
    if (operation == null) return;
    unawaited(operation.catchError((Object error) {
      sharedCampaign?.reportError(error);
    }));
  }

  FirebaseCampaignService _requireSharedService() {
    final service = sharedCampaign;
    if (service == null || !service.isConfigured) {
      throw StateError(
          service?.configurationError ?? 'Firebase is unavailable.');
    }
    return service;
  }

  void _ensureDmCanEdit() {
    if (sharedCampaign?.isConnected == true &&
        sharedCampaign?.isOwner == false) {
      throw StateError('The DM controls character changes in shared mode.');
    }
  }

  // ---- JSON in / out ---------------------------------------------------------
  String exportCharacter(Character c) => _pretty.convert(c.toJson());

  /// Throws [FormatException] on bad JSON. Always assigns a fresh id.
  Future<Character> importCharacter(String jsonText) async {
    _ensureDmCanEdit();
    final data = jsonDecode(jsonText);
    if (data is! Map) throw const FormatException('Expected a JSON object.');
    final c =
        Character.fromJson({...Map<String, dynamic>.from(data), 'id': newId()});
    characters.add(c);
    await repository.saveCharacter(c);
    _publishCharacter(c);
    notifyListeners();
    return c;
  }

  // ---- catalog / content packs ------------------------------------------------
  Future<ImportResult> importContent(String jsonText) async {
    _ensureDmCanEdit();
    final result = importer.importJson(jsonText, catalog);
    if (result.added + result.updated > 0) {
      await _saveCatalog();
    }
    notifyListeners();
    return result;
  }

  Future<void> removeCatalogItem(String key, String id) async {
    _ensureDmCanEdit();
    catalog.remove(key, id);
    await _saveCatalog();
    notifyListeners();
  }

  List<Map<String, dynamic>> stashForPlayer(String player) =>
      List.unmodifiable(_playerStashes[_playerKey(player)] ?? const []);

  Future<bool> moveToStash(
      Character character, String kind, CatalogItem item) async {
    _ensureDmCanEdit();
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
    _publishCharacter(character);
    await _saveCatalog();
    await _syncPlayerStash(character.player);
    notifyListeners();
    return true;
  }

  Future<bool> moveFromStash(Character character, int index) async {
    _ensureDmCanEdit();
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
    _publishCharacter(character);
    await _saveCatalog();
    await _syncPlayerStash(character.player);
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

  Future<void> _saveCatalog() async {
    final json = _sharedCatalogJson();
    await repository.saveCatalogJson(json);
    final service = sharedCampaign;
    if (service?.isOwner == true) {
      await service!.syncConfiguration(
        catalog: catalog.toJson(),
        requireXpForLevelUp: requireXpForLevelUp,
        allowPlayerCharacterCreation: allowPlayerCharacterCreation,
        creationRules: creationRules,
      );
    }
  }

  Future<void> setRequireXpForLevelUp(bool value) async {
    _ensureDmCanEdit();
    await repository.saveRequireXpForLevelUp(value);
    requireXpForLevelUp = value;
    notifyListeners();
    final service = sharedCampaign;
    if (service?.isOwner == true) {
      try {
        await service!.syncConfiguration(
          catalog: catalog.toJson(),
          requireXpForLevelUp: value,
          allowPlayerCharacterCreation: allowPlayerCharacterCreation,
          creationRules: creationRules,
        );
      } catch (error) {
        service?.reportError(error);
      }
    }
  }

  Future<void> setAllowPlayerCharacterCreation(bool value) async {
    _ensureDmCanEdit();
    allowPlayerCharacterCreation = value;
    notifyListeners();
    final service = sharedCampaign;
    if (service?.isOwner == true) {
      try {
        await service!.syncConfiguration(
          catalog: catalog.toJson(),
          requireXpForLevelUp: requireXpForLevelUp,
          allowPlayerCharacterCreation: value,
          creationRules: creationRules,
        );
      } catch (error) {
        service?.reportError(error);
      }
    }
  }

  String exportCatalog() => _pretty.convert(catalog.toJson());

  @override
  void dispose() {
    unawaited(_sharedCharactersSubscription?.cancel());
    unawaited(_sharedConfigurationSubscription?.cancel());
    unawaited(_sharedStashesSubscription?.cancel());
    super.dispose();
  }
}
