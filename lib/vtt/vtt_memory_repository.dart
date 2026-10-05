import 'dart:async';
import 'dart:typed_data';

import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:dnd_campaign_manager/vtt/vtt_repository.dart';

VttMap _cloneMap(VttMap map) => VttMap.fromJson(map.toJson());
VttToken _cloneToken(VttToken token) => VttToken.fromJson(token.toJson());
VttCombat _cloneCombat(VttCombat combat) => VttCombat.fromJson(combat.toJson());

class MemoryVttStore {
  final Map<String, VttMap> maps = <String, VttMap>{};
  final Map<String, VttToken> tokens = <String, VttToken>{};
  final Map<String, Set<String>> doorStates = <String, Set<String>>{};
  final Map<String, Uint8List> mapImages = <String, Uint8List>{};
  VttCombat combat = const VttCombat();

  final StreamController<void> _changes =
      StreamController<void>.broadcast(sync: true);

  Stream<void> get changes => _changes.stream;

  void notifyChanged() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  void dispose() {
    _changes.close();
  }
}

class MemoryVttRepository implements VttRepository {
  MemoryVttRepository({
    required this.isOwner,
    required this.userId,
    MemoryVttStore? store,
  }) : _store = store ?? MemoryVttStore();

  final MemoryVttStore _store;

  @override
  final bool isOwner;

  @override
  final String userId;

  @override
  Stream<List<VttMap>> watchMaps() => _replay<List<VttMap>>(
        () => _store.maps.values.map(_cloneMap).toList(growable: false),
      );

  @override
  Stream<List<VttToken>> watchTokens() => _replay<List<VttToken>>(
        () => _store.tokens.values
            .where((token) => isOwner || !token.hidden)
            .map(_cloneToken)
            .toList(growable: false),
      );

  @override
  Stream<VttCombat> watchCombat() => _replay<VttCombat>(
        () => _cloneCombat(_store.combat),
      );

  @override
  Stream<Map<String, Set<String>>> watchDoorStates() =>
      _replay<Map<String, Set<String>>>(
        () => <String, Set<String>>{
          for (final entry in _store.doorStates.entries)
            entry.key: Set<String>.from(entry.value),
        },
      );

  @override
  Future<void> saveMap(VttMap map) async {
    _requireDm();
    _store.maps[map.id] = _cloneMap(map);
    _store.notifyChanged();
  }

  @override
  Future<void> deleteMap(String mapId) async {
    _requireDm();
    _store.maps.remove(mapId);
    _store.tokens.removeWhere((_, token) => token.mapId == mapId);
    _store.doorStates.remove(mapId);
    _store.mapImages.remove(mapId);
    _store.notifyChanged();
  }

  @override
  Future<void> saveToken(VttToken token) async {
    _requireDm();
    _store.tokens[token.id] = _cloneToken(token);
    _store.notifyChanged();
  }

  @override
  Future<void> deleteToken(String tokenId) async {
    _requireDm();
    _store.tokens.remove(tokenId);
    _store.notifyChanged();
  }

  @override
  Future<void> saveCombat(VttCombat combat) async {
    _requireDm();
    _store.combat = _cloneCombat(combat);
    _store.notifyChanged();
  }

  @override
  Future<void> saveMapImage(String mapId, Uint8List jpegBytes) async {
    _requireDm();
    _store.mapImages[mapId] = Uint8List.fromList(jpegBytes);
    _store.notifyChanged();
  }

  @override
  Future<Uint8List?> loadMapImage(String mapId) async {
    final bytes = _store.mapImages[mapId];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> deleteMapImage(String mapId) async {
    _requireDm();
    _store.mapImages.remove(mapId);
    _store.notifyChanged();
  }

  @override
  Future<void> moveToken(String tokenId, String mapId, int col, int row) async {
    final existing = _store.tokens[tokenId];
    if (existing == null) {
      throw StateError('Token not found.');
    }
    _requireTokenOwner(existing);
    final updated = _cloneToken(existing)
      ..mapId = mapId
      ..col = col
      ..row = row;
    _store.tokens[tokenId] = updated;
    _store.notifyChanged();
  }

  @override
  Future<void> setInitiative(String tokenId, int? initiative) async {
    final existing = _store.tokens[tokenId];
    if (existing == null) {
      throw StateError('Token not found.');
    }
    _requireTokenOwner(existing);
    final updated = _cloneToken(existing)..initiative = initiative;
    _store.tokens[tokenId] = updated;
    _store.notifyChanged();
  }

  @override
  Future<void> setDoorOpen(String mapId, String edgeKey, bool open) async {
    final openSet = Set<String>.from(_store.doorStates[mapId] ?? const <String>{});
    if (open) {
      openSet.add(edgeKey);
    } else {
      openSet.remove(edgeKey);
    }
    if (openSet.isEmpty) {
      _store.doorStates.remove(mapId);
    } else {
      _store.doorStates[mapId] = openSet;
    }
    _store.notifyChanged();
  }

  Stream<T> _replay<T>(T Function() snapshot) {
    return Stream<T>.multi(
      (controller) {
        controller.add(snapshot());
        final subscription = _store.changes.listen(
          (_) => controller.add(snapshot()),
          onError: controller.addError,
        );
        controller.onCancel = subscription.cancel;
      },
      isBroadcast: true,
    );
  }

  void _requireDm() {
    if (!isOwner) {
      throw StateError('Only the DM can perform this action.');
    }
  }

  void _requireTokenOwner(VttToken token) {
    if (isOwner) return;
    if (token.ownerUid != userId) {
      throw StateError('You do not control this token.');
    }
  }
}
