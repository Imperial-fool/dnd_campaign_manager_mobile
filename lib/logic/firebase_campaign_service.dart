import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dnd_campaign_manager/firebase_options.dart';
import 'package:dnd_campaign_manager/models/character.dart';

class CampaignMember {
  const CampaignMember({required this.uid, required this.playerName});

  final String uid;
  final String playerName;
}

class CampaignAssignment {
  const CampaignAssignment({
    required this.characterId,
    required this.characterName,
    this.playerUid,
  });

  final String characterId;
  final String characterName;
  final String? playerUid;
}

/// Optional realtime campaign transport. Firebase Auth uses anonymous
/// identities; the DM's unguessable campaign code acts as the invitation.
class FirebaseCampaignService extends ChangeNotifier {
  FirebaseCampaignService._({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    this.configurationError,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final String? configurationError;
  String? lastError;
  String? joinCode;
  String? playerName;
  bool isOwner = false;

  bool get isConfigured => _auth != null && _firestore != null;
  bool get isConnected => isConfigured && joinCode != null;
  String? get userId => _auth?.currentUser?.uid;

  static const _codeKey = 'dnd.sharedCampaign.code';
  static const _nameKey = 'dnd.sharedCampaign.playerName';
  static const _ownerKey = 'dnd.sharedCampaign.owner';

  static Future<FirebaseCampaignService> initialize() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return FirebaseCampaignService._(
        configurationError:
            'Firebase sharing is not supported on Linux. Local mode is still available.',
      );
    }
    final options = DefaultFirebaseOptions.currentPlatform;
    if (options.apiKey.isEmpty ||
        options.appId.isEmpty ||
        options.projectId.isEmpty) {
      return FirebaseCampaignService._(
        configurationError:
            'Firebase is not configured for ${_currentPlatformName()}. '
            'Run flutterfire configure --project=dnd-character-manager-80981 '
            '--platforms=${_currentPlatformName()} and rebuild the app. '
            'Firebase may already be active for another platform.',
      );
    }
    try {
      final app = Firebase.apps.isEmpty
          ? await Firebase.initializeApp(options: options)
          : Firebase.app();
      return FirebaseCampaignService._(
        auth: FirebaseAuth.instanceFor(app: app),
        firestore: FirebaseFirestore.instanceFor(app: app),
      );
    } on FirebaseException catch (error) {
      return FirebaseCampaignService._(
        configurationError: 'Firebase could not start: ${error.message}',
      );
    } on PlatformException catch (error) {
      return FirebaseCampaignService._(
        configurationError:
            'Firebase could not start on this device: ${error.message ?? error.code}',
      );
    } on MissingPluginException catch (error) {
      return FirebaseCampaignService._(
        configurationError:
            'Firebase is unavailable on this build: ${error.message ?? error}',
      );
    } on StateError catch (error) {
      return FirebaseCampaignService._(
        configurationError: 'Firebase could not start: ${error.message}',
      );
    }
  }

  static String _currentPlatformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  Future<void> restoreSession() async {
    if (!isConfigured) return;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    if (code == null) return;
    lastError = null;
    try {
      await _ensureAnonymousUser();
    } on FirebaseException catch (error) {
      _reportRestoreError(error.message ?? error.toString());
    } on PlatformException catch (error) {
      _reportRestoreError(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      _reportRestoreError(error.message ?? error.toString());
    } on StateError catch (error) {
      _reportRestoreError(error.message);
    }
    if (lastError != null) return;
    joinCode = code;
    playerName = prefs.getString(_nameKey);
    isOwner = prefs.getBool(_ownerKey) ?? false;
    notifyListeners();
  }

  void _reportRestoreError(String error) {
    lastError = 'Could not restore Firebase session: $error';
    notifyListeners();
  }

  Future<String> createCampaign({
    required Map<String, dynamic> catalog,
    required bool requireXpForLevelUp,
    required bool allowPlayerCharacterCreation,
    required Map<String, dynamic> creationRules,
    required List<Character> characters,
  }) async {
    final firestore = _requireFirestore();
    final uid = await _ensureAnonymousUser();
    final code = _newJoinCode();
    final campaign = firestore.collection('campaigns').doc(code);
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(campaign);
      if (existing.exists) {
        throw StateError('Could not create a unique campaign join code.');
      }
      transaction.set(campaign, {
        'ownerUid': uid,
        'joinOpen': true,
        'catalog': catalog,
        'rules': {
          'requireXpForLevelUp': requireXpForLevelUp,
          'allowPlayerCharacterCreation': allowPlayerCharacterCreation,
        },
        'creationRules': creationRules,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    for (var start = 0; start < characters.length; start += 450) {
      final batch = firestore.batch();
      final end = min(start + 450, characters.length);
      for (final character in characters.sublist(start, end)) {
        batch.set(campaign.collection('characters').doc(character.id), {
          'assignedUid': null,
          'character': character.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    await _activate(code, owner: true);
    return code;
  }

  Future<Map<String, dynamic>> joinCampaign({
    required String code,
    required String playerName,
  }) async {
    final firestore = _requireFirestore();
    final uid = await _ensureAnonymousUser();
    final normalizedCode = code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z2-9]{16}$').hasMatch(normalizedCode)) {
      throw const FormatException('Enter the 16-character campaign join code.');
    }
    final campaign = firestore.collection('campaigns').doc(normalizedCode);
    final member = campaign.collection('members').doc(uid);
    if (!(await member.get()).exists) {
      await member.set({
        'uid': uid,
        'playerName': playerName.trim(),
        'role': 'player',
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }
    final snapshot = await campaign.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('That campaign could not be loaded.');
    }
    await _activate(normalizedCode, owner: false, name: playerName.trim());
    return data;
  }

  Future<Map<String, dynamic>> loadCampaign() async {
    final code = joinCode;
    if (code == null) throw StateError('No shared campaign is active.');
    final snapshot =
        await _requireFirestore().collection('campaigns').doc(code).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('The shared campaign no longer exists.');
    }
    return data;
  }

  Stream<List<Character>> watchCharacters() {
    final code = joinCode;
    final uid = userId;
    if (code == null || uid == null) {
      throw StateError('Join a campaign before loading characters.');
    }
    Query<Map<String, dynamic>> query = _requireFirestore()
        .collection('campaigns')
        .doc(code)
        .collection('characters');
    if (!isOwner) query = query.where('assignedUid', isEqualTo: uid);
    return query.snapshots().map((snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          final json = data['character'];
          if (json is! Map) {
            throw FormatException(
                'Character document ${doc.id} does not contain a sheet.');
          }
          return _applyPlayerState(
            Character.fromJson(Map<String, dynamic>.from(json)),
            data['playerState'],
          );
        }).toList());
  }

  Stream<Map<String, dynamic>> watchConfiguration() {
    final code = joinCode;
    if (code == null || isOwner) {
      throw StateError(
          'Only players need the DM campaign configuration stream.');
    }
    return _requireFirestore()
        .collection('campaigns')
        .doc(code)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw StateError('The shared campaign no longer exists.');
      }
      return data;
    });
  }

  Stream<List<Map<String, dynamic>>> watchStashes() {
    final code = joinCode;
    final uid = userId;
    if (code == null || uid == null) {
      throw StateError('Join a campaign before loading stashes.');
    }
    final stashes = _requireFirestore()
        .collection('campaigns')
        .doc(code)
        .collection('stashes');
    if (isOwner) {
      return stashes.snapshots().map(
            (snapshot) => snapshot.docs.map((doc) => doc.data()).toList(),
          );
    }
    return stashes.doc(uid).snapshots().map(
          (snapshot) => snapshot.exists && snapshot.data() != null
              ? [snapshot.data()!]
              : <Map<String, dynamic>>[],
        );
  }

  Stream<List<CampaignMember>> watchMembers() {
    final code = joinCode;
    if (code == null || !isOwner) {
      throw StateError('Only the DM can view campaign players.');
    }
    return _requireFirestore()
        .collection('campaigns')
        .doc(code)
        .collection('members')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CampaignMember(
                  uid: doc.id,
                  playerName: doc.data()['playerName'] as String? ?? 'Player',
                ))
            .toList());
  }

  Stream<List<CampaignAssignment>> watchAssignments() {
    final code = joinCode;
    if (code == null || !isOwner) {
      throw StateError('Only the DM can view character assignments.');
    }
    return _requireFirestore()
        .collection('campaigns')
        .doc(code)
        .collection('characters')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final character = doc.data()['character'];
              final characterMap =
                  character is Map ? Map<String, dynamic>.from(character) : {};
              return CampaignAssignment(
                characterId: doc.id,
                characterName: characterMap['name'] as String? ?? 'Character',
                playerUid: doc.data()['assignedUid'] as String?,
              );
            }).toList());
  }

  Stream<List<Map<String, dynamic>>> watchRolls() {
    final code = joinCode;
    if (code == null || !isOwner) {
      throw StateError('Only the DM can view campaign rolls.');
    }
    return _requireFirestore()
        .collection('campaigns')
        .doc(code)
        .collection('rolls')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Future<String?> assignCharacter(
    String characterId,
    String? uid,
    Map<String, List<Map<String, dynamic>>> stashesByPlayer,
  ) async {
    if (!isOwner) throw StateError('Only the DM can assign characters.');
    final characterDocument =
        _campaignCollection('characters').doc(characterId);
    String? playerName;
    if (uid != null) {
      final member = await _campaignCollection('members').doc(uid).get();
      playerName = member.data()?['playerName'] as String?;
      if (playerName == null) {
        throw StateError('The selected player is no longer in this campaign.');
      }
    }
    await _requireFirestore().runTransaction((transaction) async {
      final characterSnapshot = await transaction.get(characterDocument);
      final rawCharacter = characterSnapshot.data()?['character'];
      if (rawCharacter is! Map) {
        throw StateError('The selected character could not be loaded.');
      }
      final character = Map<String, dynamic>.from(rawCharacter)
        ..['player'] = playerName ?? '';
      transaction.update(characterDocument, {
        'assignedUid': uid,
        'character': character,
        'playerState': {},
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    if (uid != null && playerName != null) {
      final playerKey = _playerKey(playerName);
      await _campaignCollection('members').doc(uid).update({
        'stashKey': playerKey,
      });
      final stashDocument = _campaignCollection('stashes').doc(uid);
      final oldStash = await stashDocument.get();
      final items = stashesByPlayer.containsKey(playerKey)
          ? stashesByPlayer[playerKey]!
          : (oldStash.data()?['items'] as List?)
                  ?.whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList() ??
              <Map<String, dynamic>>[];
      await stashDocument.set({
        'playerName': playerName,
        'playerKey': playerKey,
        'items': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return playerName;
  }

  Future<void> createPlayerCharacter(Character character) async {
    if (!isConnected || isOwner) {
      throw StateError('Join as a player before creating a character.');
    }
    final uid = await _ensureAnonymousUser();
    final member = await _campaignCollection('members').doc(uid).get();
    if (!member.exists) {
      throw StateError('Rejoin the campaign before creating a character.');
    }
    final playerName = member.data()?['playerName'] as String?;
    if (playerName == null || playerName.isEmpty) {
      throw StateError('Your campaign player name could not be loaded.');
    }
    character.player = playerName;
    try {
      await _campaignCollection('characters').doc(character.id).set({
        'assignedUid': uid,
        'createdByUid': uid,
        'character': character.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError(
          'Firebase denied character creation. Ask the DM to enable '
          '“Allow players to create characters” and deploy the latest '
          'firestore.rules. Details: ${error.message ?? error.code}',
        );
      }
      rethrow;
    }
  }

  Future<void> syncStashForPlayer(
    String playerName,
    List<Map<String, dynamic>> items,
  ) async {
    if (!isOwner) throw StateError('Only the DM can update player stashes.');
    final playerKey = _playerKey(playerName);
    if (playerKey.isEmpty) return;
    final members = await _campaignCollection('members')
        .where('stashKey', isEqualTo: playerKey)
        .get();
    final batch = _requireFirestore().batch();
    for (final member in members.docs) {
      batch.set(_campaignCollection('stashes').doc(member.id), {
        'playerName': member.data()['playerName'] as String? ?? playerName,
        'playerKey': playerKey,
        'items': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (members.docs.isNotEmpty) await batch.commit();
  }

  static String _playerKey(String name) => name.trim().toLowerCase();

  Future<void> syncCharacter(Character character) async {
    if (!isOwner) throw StateError('Only the DM can update character data.');
    final document = _campaignCollection('characters').doc(character.id);
    final nextCharacter = character.toJson();
    await _requireFirestore().runTransaction((transaction) async {
      final existing = await transaction.get(document);
      final data = existing.data() ?? const <String, dynamic>{};
      final oldCharacter = data['character'];
      final oldCharacterMap =
          oldCharacter is Map ? Map<String, dynamic>.from(oldCharacter) : {};
      final state = data['playerState'];
      final playerState =
          state is Map ? Map<String, dynamic>.from(state) : <String, dynamic>{};
      playerState.removeWhere((key, value) =>
          nextCharacter.containsKey(key) &&
          jsonEncode(oldCharacterMap[key]) != jsonEncode(nextCharacter[key]));
      for (final entry in const {
        'weapons': ['weaponState', 'weaponHp'],
        'armor': ['armorState', 'armorHp'],
        'items': ['itemState'],
      }.entries) {
        if (jsonEncode(oldCharacterMap[entry.key]) !=
            jsonEncode(nextCharacter[entry.key])) {
          for (final stateKey in entry.value) {
            playerState.remove(stateKey);
          }
        }
      }
      transaction.set(
        document,
        {
          'character': nextCharacter,
          'playerState': playerState,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> syncPlayerCharacterState(Character character) async {
    if (!isConnected || isOwner) {
      throw StateError('Only a joined player can update player-owned fields.');
    }
    await _ensureAnonymousUser();
    await _campaignCollection('characters').doc(character.id).update({
      'playerState': _playerStateFor(character),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Map<String, dynamic> _playerStateFor(Character character) {
    final json = character.toJson();
    return {
      for (final key in const [
        'name',
        'race',
        'affiliation',
        'alignment',
        'background',
        'backgroundId',
        'abilityScores',
        'saveProficiencies',
        'skills',
        'traits',
        'initiativeBonus',
        'speed',
        'armorClass',
        'hpCurrent',
        'inspiration',
        'hitDiceUsed',
        'deathSuccesses',
        'deathFailures',
        'exhaustion',
        'equipment',
        'proficiencies',
        'notes',
      ])
        key: json[key],
      'weaponHp': character.weaponHp,
      'armorHp': character.armorHp,
      'weaponState': {
        for (final weapon in character.weapons)
          weapon.id: {'ammo': weapon.ammo, 'hp': weapon.hp},
      },
      'armorState': {
        for (final armor in character.armor)
          armor.id: {'hp': armor.hp, 'equipped': armor.equipped},
      },
      'itemState': {
        for (final item in character.items)
          item.id: {'quantity': item.quantity, 'uses': item.uses},
      },
    };
  }

  Character _applyPlayerState(Character character, dynamic value) {
    if (value is! Map) return character;
    final state = Map<String, dynamic>.from(value);
    final merged = character.toJson();
    for (final key in const [
      'name',
      'race',
      'affiliation',
      'alignment',
      'background',
      'backgroundId',
      'abilityScores',
      'saveProficiencies',
      'skills',
      'traits',
      'initiativeBonus',
      'speed',
      'armorClass',
      'hpCurrent',
      'inspiration',
      'hitDiceUsed',
      'deathSuccesses',
      'deathFailures',
      'exhaustion',
      'equipment',
      'proficiencies',
      'notes',
    ]) {
      if (state.containsKey(key)) merged[key] = state[key];
    }
    final result = Character.fromJson(merged);
    result.hpCurrent = result.hpCurrent.clamp(0, result.hpMax).toInt();
    result.weaponHp =
        _boundedState(state['weaponHp'], result.weaponHp, 0, 9999);
    result.armorHp = _boundedState(state['armorHp'], result.armorHp, 0, 9999);

    final weaponState = state['weaponState'];
    if (weaponState is Map) {
      for (final weapon in result.weapons) {
        final saved = weaponState[weapon.id];
        if (saved is! Map) continue;
        weapon.ammo = _boundedState(
          saved['ammo'],
          weapon.ammo,
          0,
          weapon.ammoMax > 0 ? weapon.ammoMax : 9999,
        );
        weapon.hp = _boundedState(
          saved['hp'],
          weapon.hp,
          0,
          weapon.hpMax > 0 ? weapon.hpMax : 9999,
        );
      }
    }
    final armorState = state['armorState'];
    if (armorState is Map) {
      for (final armor in result.armor) {
        final saved = armorState[armor.id];
        if (saved is! Map) continue;
        armor.hp = _boundedState(
          saved['hp'],
          armor.hp,
          0,
          armor.hpMax > 0 ? armor.hpMax : 9999,
        );
        if (saved['equipped'] is bool) {
          armor.equipped = saved['equipped'] as bool;
        }
      }
    }
    final itemState = state['itemState'];
    if (itemState is Map) {
      for (final item in result.items) {
        final saved = itemState[item.id];
        if (saved is! Map) continue;
        item.quantity =
            _boundedState(saved['quantity'], item.quantity, 0, 9999);
        item.uses = _boundedState(
          saved['uses'],
          item.uses,
          0,
          item.usesMax > 0 ? item.usesMax : 9999,
        );
      }
    }
    return result;
  }

  int _boundedState(dynamic value, int fallback, int minValue, int maxValue) =>
      value is num ? value.toInt().clamp(minValue, maxValue).toInt() : fallback;

  Future<void> deleteCharacter(String id) async {
    if (!isOwner) throw StateError('Only the DM can delete character data.');
    await _campaignCollection('characters').doc(id).delete();
  }

  Future<void> syncConfiguration({
    required Map<String, dynamic> catalog,
    required bool requireXpForLevelUp,
    required bool allowPlayerCharacterCreation,
    required Map<String, dynamic> creationRules,
  }) async {
    if (!isOwner) throw StateError('Only the DM can update campaign rules.');
    await _requireFirestore().collection('campaigns').doc(joinCode).update({
      'catalog': catalog,
      'rules': {
        'requireXpForLevelUp': requireXpForLevelUp,
        'allowPlayerCharacterCreation': allowPlayerCharacterCreation,
      },
      'creationRules': creationRules,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> publishRoll({
    required Character character,
    required String title,
    required int? total,
    required List<String> lines,
    required bool crit,
    required bool fumble,
  }) async {
    if (isOwner || !isConnected) return;
    final uid = await _ensureAnonymousUser();
    await _campaignCollection('rolls').add({
      'playerUid': uid,
      'playerName': playerName ?? character.player,
      'characterId': character.id,
      'characterName': character.name,
      'title': title.substring(0, min(200, title.length)),
      'total': total,
      'lines': lines
          .take(30)
          .map((line) => line.substring(0, min(1000, line.length)))
          .toList(),
      'crit': crit,
      'fumble': fumble,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> leaveCampaign({bool removeMember = true}) async {
    final code = joinCode;
    final uid = userId;
    if (removeMember && code != null && uid != null && !isOwner) {
      await _requireFirestore()
          .collection('campaigns')
          .doc(code)
          .collection('members')
          .doc(uid)
          .delete();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_codeKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_ownerKey);
    joinCode = null;
    playerName = null;
    isOwner = false;
    lastError = null;
    notifyListeners();
  }

  void reportError(Object error) {
    lastError = error.toString();
    notifyListeners();
  }

  Future<void> _activate(String code,
      {required bool owner, String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, code);
    await prefs.setBool(_ownerKey, owner);
    if (name != null) {
      await prefs.setString(_nameKey, name);
    } else {
      await prefs.remove(_nameKey);
    }
    joinCode = code;
    isOwner = owner;
    playerName = name;
    lastError = null;
    notifyListeners();
  }

  Future<String> _ensureAnonymousUser() async {
    final auth = _auth;
    if (auth == null) {
      throw StateError(configurationError ?? 'Firebase is off.');
    }
    final current = auth.currentUser ?? (await auth.signInAnonymously()).user;
    if (current == null) {
      throw StateError('Anonymous sign-in did not complete.');
    }
    return current.uid;
  }

  CollectionReference<Map<String, dynamic>> _campaignCollection(String name) {
    final code = joinCode;
    if (code == null) throw StateError('No shared campaign is active.');
    return _requireFirestore()
        .collection('campaigns')
        .doc(code)
        .collection(name);
  }

  FirebaseFirestore _requireFirestore() =>
      _firestore ??
      (throw StateError(configurationError ?? 'Firebase is off.'));

  String _newJoinCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }
}
