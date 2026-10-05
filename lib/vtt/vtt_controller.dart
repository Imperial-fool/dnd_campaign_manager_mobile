import 'dart:async';
import 'dart:math';

import 'package:dnd_campaign_manager/vtt/vtt_geometry.dart';
import 'package:dnd_campaign_manager/vtt/vtt_image.dart';
import 'package:dnd_campaign_manager/vtt/vtt_map_io.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:dnd_campaign_manager/vtt/vtt_repository.dart';
import 'package:flutter/foundation.dart';

class VttMoveResult {
  const VttMoveResult({
    required this.moved,
    this.portal,
    this.reason,
  });

  final bool moved;
  final VttPortal? portal;
  final String? reason;
}

class _ImageCacheEntry {
  _ImageCacheEntry({required this.version, this.bytes, this.future});

  int version;
  Uint8List? bytes;
  Future<Uint8List?>? future;
}

class VttController extends ChangeNotifier {
  VttController(this._repository, {Random? random})
      : _random = random ?? Random();

  final VttRepository _repository;
  final Random _random;

  static int _idCounter = 0;

  final List<VttMap> _maps = <VttMap>[];
  final List<VttToken> _tokens = <VttToken>[];
  final Map<String, Set<String>> _doorStates = <String, Set<String>>{};
  final Map<String, _ImageCacheEntry> _imageCache = <String, _ImageCacheEntry>{};
  VttCombat _combat = const VttCombat();

  StreamSubscription<List<VttMap>>? _mapsSub;
  StreamSubscription<List<VttToken>>? _tokensSub;
  StreamSubscription<VttCombat>? _combatSub;
  StreamSubscription<Map<String, Set<String>>>? _doorStatesSub;

  bool _started = false;
  bool _disposed = false;
  bool _gotMaps = false;
  bool _gotTokens = false;
  bool _gotCombat = false;
  bool _gotDoorStates = false;
  bool _initialOwnedMapSelectionPending = true;
  bool _loading = true;
  String? _error;
  String? _currentMapId;

  List<VttMap> get maps => List<VttMap>.unmodifiable(_maps);
  List<VttToken> get tokens => List<VttToken>.unmodifiable(_tokens);
  VttCombat get combat => _combat;
  String? get currentMapId => _currentMapId;
  VttMap? get currentMap => _mapById(_currentMapId);
  bool get isDm => _repository.isOwner;
  String get userId => _repository.userId;
  String? get error => _error;
  bool get loading => _loading;
  Map<String, Set<String>> get doorStates => <String, Set<String>>{
        for (final entry in _doorStates.entries)
          entry.key: Set<String>.unmodifiable(entry.value),
      };

  List<VttToken> get tokensOnCurrentMap {
    final mapId = _currentMapId;
    if (mapId == null) return const <VttToken>[];
    return List<VttToken>.unmodifiable(
      _tokens.where((token) => token.mapId == mapId),
    );
  }

  List<VttToken> get initiativeOrder {
    final ordered = _tokens
        .where((token) => token.initiative != null)
        .map(_cloneToken)
        .toList(growable: false);
    ordered.sort((a, b) {
      final initiativeCompare = b.initiative!.compareTo(a.initiative!);
      if (initiativeCompare != 0) return initiativeCompare;
      final nameCompare = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (nameCompare != 0) return nameCompare;
      return a.id.compareTo(b.id);
    });
    return ordered;
  }

  VttToken? get currentTurnToken {
    final turnTokenId = _combat.turnTokenId;
    if (turnTokenId == null) return null;
    return _tokenById(turnTokenId);
  }

  bool canMove(VttToken token) {
    if (isDm) return true;
    if (token.ownerUid != userId) return false;
    return !_combat.active || _combat.turnTokenId == token.id;
  }

  Set<String> openDoorsFor(String mapId) =>
      Set<String>.unmodifiable(_doorStates[mapId] ?? const <String>{});

  bool isDoorOpen(String mapId, String key) =>
      _doorStates[mapId]?.contains(key) ?? false;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _loading = true;
    _mapsSub = _repository.watchMaps().listen(_onMaps, onError: _onStreamError);
    _tokensSub =
        _repository.watchTokens().listen(_onTokens, onError: _onStreamError);
    _combatSub =
        _repository.watchCombat().listen(_onCombat, onError: _onStreamError);
    _doorStatesSub = _repository
        .watchDoorStates()
        .listen(_onDoorStates, onError: _onStreamError);
  }

  void selectMap(String id) {
    if (_mapById(id) == null || _currentMapId == id) return;
    _currentMapId = id;
    notifyListeners();
  }

  Future<VttMap> createMap({
    String name = 'Map',
    int cols = 20,
    int rows = 20,
    bool isOverworld = false,
  }) async {
    _ensureDm();
    final map = VttMap(
      id: _newId('map'),
      name: name,
      cols: cols.clamp(1, VttMap.maxDimension),
      rows: rows.clamp(1, VttMap.maxDimension),
      isOverworld: isOverworld,
    );
    await _runAction(() => _repository.saveMap(map));
    if (_currentMapId == null) {
      _currentMapId = map.id;
      notifyListeners();
    }
    return _cloneMap(map);
  }

  Future<void> updateMap(VttMap map) async {
    _ensureDm();
    _validateMap(map);
    await _runAction(() => _repository.saveMap(_cloneMap(map)));
  }

  Future<void> deleteMap(String id) async {
    _ensureDm();
    final existing = _mapById(id);
    if (existing == null) {
      throw _setAndThrow('Map not found.');
    }
    final inboundMaps = _maps
        .where(
          (map) => map.id != id && map.portals.any((p) => p.targetMapId == id),
        )
        .map(_cloneMap)
        .toList(growable: false);
    await _runAction(() async {
      for (final map in inboundMaps) {
        map.portals.removeWhere((portal) => portal.targetMapId == id);
        await _repository.saveMap(map);
      }
      await _repository.deleteMap(id);
    });
    _doorStates.remove(id);
    _imageCache.remove(id);
  }

  Future<void> addPortal(String mapId, VttPortal portal) async {
    _ensureDm();
    final map = _cloneRequiredMap(mapId);
    final targetMap = _mapById(portal.targetMapId);
    if (targetMap == null) {
      throw _setAndThrow('Portal target map not found.');
    }
    if (!map.contains(portal.col, portal.row)) {
      throw _setAndThrow('Portal must be placed within the map bounds.');
    }
    if (!targetMap.contains(portal.targetCol, portal.targetRow)) {
      throw _setAndThrow('Portal destination must be within the target map.');
    }
    final replacementIndex = map.portals.indexWhere(
      (existing) => existing.col == portal.col && existing.row == portal.row,
    );
    if (replacementIndex >= 0) {
      map.portals[replacementIndex] = portal;
    } else {
      if (map.portals.length >= VttMap.maxPortals) {
        throw _setAndThrow('This map already has the maximum number of portals.');
      }
      map.portals.add(portal);
    }
    await _runAction(() => _repository.saveMap(map));
  }

  Future<void> removePortal(String mapId, int col, int row) async {
    _ensureDm();
    final map = _cloneRequiredMap(mapId);
    map.portals.removeWhere((portal) => portal.col == col && portal.row == row);
    await _runAction(() => _repository.saveMap(map));
  }

  Future<VttToken> addToken({
    required String mapId,
    required String name,
    int col = 0,
    int row = 0,
    String kind = 'npc',
    int color = 0xFF8D6E63,
    String? characterId,
    String? ownerUid,
    bool hidden = false,
  }) async {
    _ensureDm();
    final map = _cloneRequiredMap(mapId);
    if (!map.contains(col, row)) {
      throw _setAndThrow('Token must be placed within the map bounds.');
    }
    final token = VttToken(
      id: _newId('token'),
      mapId: mapId,
      name: name,
      col: col,
      row: row,
      kind: kind,
      color: color,
      characterId: characterId,
      ownerUid: ownerUid,
      hidden: hidden,
    );
    await _runAction(() => _repository.saveToken(token));
    return _cloneToken(token);
  }

  Future<void> updateToken(VttToken token) async {
    _ensureDm();
    _validateToken(token);
    await _runAction(() => _repository.saveToken(_cloneToken(token)));
  }

  Future<void> removeToken(String id) async {
    _ensureDm();
    if (_tokenById(id) == null) {
      throw _setAndThrow('Token not found.');
    }
    await _runAction(() => _repository.deleteToken(id));
  }

  Future<void> startCombat() async {
    _ensureDm();
    final order = initiativeOrder;
    if (order.isEmpty) {
      throw _setAndThrow('Set initiative for at least one token first.');
    }
    await _runAction(
      () => _repository.saveCombat(
        VttCombat(active: true, round: 1, turnTokenId: order.first.id),
      ),
    );
  }

  Future<void> nextTurn() async {
    _ensureDm();
    if (!_combat.active) {
      throw _setAndThrow('Combat is not active.');
    }
    final order = initiativeOrder;
    if (order.isEmpty) {
      throw _setAndThrow('No tokens are in the initiative order.');
    }
    final currentIndex =
        order.indexWhere((token) => token.id == _combat.turnTokenId);
    if (currentIndex < 0) {
      await _runAction(
        () => _repository.saveCombat(
          VttCombat(
            active: true,
            round: _combat.round,
            turnTokenId: order.first.id,
          ),
        ),
      );
      return;
    }
    final nextIndex = (currentIndex + 1) % order.length;
    final nextRound = nextIndex == 0 ? _combat.round + 1 : _combat.round;
    await _runAction(
      () => _repository.saveCombat(
        VttCombat(
          active: true,
          round: nextRound,
          turnTokenId: order[nextIndex].id,
        ),
      ),
    );
  }

  Future<void> endCombat() async {
    _ensureDm();
    await _runAction(() => _repository.saveCombat(const VttCombat()));
  }

  Future<VttMoveResult> moveToken(
    String tokenId,
    int col,
    int row, {
    bool? ignoreWalls,
  }) async {
    final token = _tokenById(tokenId);
    if (token == null) {
      return _moveFailure('Token not found.');
    }
    if (!canMove(token)) {
      return _moveFailure('You cannot move this token right now.');
    }
    final map = _mapById(token.mapId);
    if (map == null) {
      return _moveFailure('Map not found for this token.');
    }
    if (!map.contains(col, row)) {
      return _moveFailure('Destination is outside the map bounds.');
    }
    final shouldIgnoreWalls = ignoreWalls ?? isDm;
    if (!shouldIgnoreWalls) {
      final path = findPath(map, openDoorsFor(map.id), token.col, token.row, col, row);
      if (path == null) {
        return _moveFailure('Blocked by a wall or closed door.');
      }
    }
    final portal = map.portalAt(col, row);
    final original = _cloneToken(token);
    final updated = _cloneToken(token)
      ..col = col
      ..row = row;
    _upsertLocalToken(updated);
    try {
      await _repository.moveToken(token.id, token.mapId, col, row);
      _clearError();
      return VttMoveResult(moved: true, portal: portal);
    } catch (error) {
      _rollbackOptimisticTokenIfUnchanged(original, updated);
      return _moveFailure(_messageFor(error), portal: null, notify: false);
    }
  }

  Future<void> usePortal(String tokenId) async {
    final token = _tokenById(tokenId);
    if (token == null) {
      throw _setAndThrow('Token not found.');
    }
    if (!canMove(token)) {
      throw _setAndThrow('You cannot move this token right now.');
    }
    final map = _mapById(token.mapId);
    if (map == null) {
      throw _setAndThrow('Map not found for this token.');
    }
    final portal = map.portalAt(token.col, token.row);
    if (portal == null) {
      throw _setAndThrow('Token is not standing on a portal.');
    }
    final targetMap = _mapById(portal.targetMapId);
    if (targetMap == null) {
      throw _setAndThrow('Portal target map not found.');
    }
    if (!targetMap.contains(portal.targetCol, portal.targetRow)) {
      throw _setAndThrow('Portal destination is outside the target map.');
    }
    final original = _cloneToken(token);
    final originalMapId = _currentMapId;
    final updated = _cloneToken(token)
      ..mapId = targetMap.id
      ..col = portal.targetCol
      ..row = portal.targetRow;
    _upsertLocalToken(updated);
    if (isDm || token.ownerUid == userId) {
      _currentMapId = targetMap.id;
      notifyListeners();
    }
    try {
      await _repository.moveToken(
        token.id,
        targetMap.id,
        portal.targetCol,
        portal.targetRow,
      );
      _clearError();
    } catch (error) {
      final rolledBack = _rollbackOptimisticTokenIfUnchanged(original, updated);
      if (rolledBack && _currentMapId == updated.mapId) {
        _currentMapId = originalMapId;
        notifyListeners();
      }
      _setError(_messageFor(error), notify: !rolledBack);
      rethrow;
    }
  }

  Future<void> setInitiative(String tokenId, int? value) async {
    final token = _tokenById(tokenId);
    if (token == null) {
      throw _setAndThrow('Token not found.');
    }
    if (!isDm && token.ownerUid != userId) {
      throw _setAndThrow('You can only change initiative for your own token.');
    }
    if (value != null && (value < -20 || value > 100)) {
      throw _setAndThrow('Initiative must be between -20 and 100.');
    }
    await _runAction(() => _repository.setInitiative(tokenId, value));
  }

  Future<int> rollInitiative(String tokenId, int bonus) async {
    final roll = _random.nextInt(20) + 1 + bonus;
    await setInitiative(tokenId, roll);
    return roll;
  }

  Future<void> setEdges(
    String mapId, {
    List<VttEdge> add = const <VttEdge>[],
    List<String> removeKeys = const <String>[],
  }) async {
    _ensureDm();
    final map = _cloneRequiredMap(mapId);
    final edgeMap = <String, VttEdge>{
      for (final edge in map.edges) edge.key: _cloneEdge(edge),
    };
    for (final key in removeKeys) {
      edgeMap.remove(key);
    }
    for (final edge in add) {
      _validateEdgeBounds(map, edge);
      edgeMap[edge.key] = _cloneEdge(edge);
    }
    if (edgeMap.length > VttMap.maxEdges) {
      throw _setAndThrow('A map can have at most ${VttMap.maxEdges} edges.');
    }
    map.edges = edgeMap.values.toList(growable: false);
    await _runAction(() => _repository.saveMap(map));
  }

  Future<void> paintTerrain(
    String mapId,
    List<({int col, int row})> cells,
    int? paletteIndex,
  ) async {
    _ensureDm();
    if (paletteIndex != null &&
        (paletteIndex < 0 || paletteIndex >= VttMap.terrainPalette.length)) {
      throw _setAndThrow('Terrain palette index is out of range.');
    }
    final map = _cloneRequiredMap(mapId);
    final rows = map.terrain.map((row) => row.split('')).toList(growable: false);
    for (final cell in cells) {
      if (!map.contains(cell.col, cell.row)) continue;
      rows[cell.row][cell.col] = paletteIndex == null ? '.' : '$paletteIndex';
    }
    map.terrain = rows.map((row) => row.join()).toList(growable: false);
    await _runAction(() => _repository.saveMap(map));
  }

  Future<void> setMapSettings(
    String mapId, {
    String? name,
    int? cols,
    int? rows,
    int? feetPerCell,
    bool? showGrid,
    VttDiagonalRule? diagonalRule,
    bool? isOverworld,
  }) async {
    _ensureDm();
    final map = _cloneRequiredMap(mapId);
    map.name = name ?? map.name;
    map.cols = (cols ?? map.cols).clamp(1, VttMap.maxDimension);
    map.rows = (rows ?? map.rows).clamp(1, VttMap.maxDimension);
    map.feetPerCell = (feetPerCell ?? map.feetPerCell).clamp(1, 100);
    map.showGrid = showGrid ?? map.showGrid;
    map.diagonalRule = diagonalRule ?? map.diagonalRule;
    map.isOverworld = isOverworld ?? map.isOverworld;
    _normalizeMapShape(map);
    final updatedTokens = _clampTokensForMap(map);
    await _runAction(() async {
      await _repository.saveMap(map);
      for (final token in updatedTokens) {
        await _repository.saveToken(token);
      }
    });
  }

  Future<void> toggleDoor(String mapId, String edgeKey) async {
    final map = _cloneRequiredMap(mapId);
    final edge = map.edgeAt(edgeKey);
    if (edge == null || edge.type != VttEdgeType.door) {
      throw _setAndThrow('Door not found.');
    }
    if (!isDm) {
      if (edge.locked) {
        throw _setAndThrow('This door is locked.');
      }
      final nearby = _playerHasAdjacentTokenForDoor(map, edge);
      if (!nearby) {
        throw _setAndThrow('One of your tokens must be next to the door.');
      }
    }
    await _runAction(
      () => _repository.setDoorOpen(mapId, edgeKey, !isDoorOpen(mapId, edgeKey)),
    );
  }

  Future<void> setMapImage(
    String mapId,
    Uint8List raw, {
    bool fitGridToImage = false,
    int? pixelsPerGrid,
  }) async {
    _ensureDm();
    final map = _cloneRequiredMap(mapId);
    final prepared = await _runAction(() => prepareMapImage(raw));
    final size = imageSize(prepared);
    if (fitGridToImage) {
      final ppg = (pixelsPerGrid ?? 70).clamp(1, 4096);
      map.cols = (size.width / ppg).round().clamp(1, VttMap.maxDimension);
      map.rows = (size.height / ppg).round().clamp(1, VttMap.maxDimension);
      _normalizeMapShape(map);
    }
    map.hasImage = true;
    map.imageVersion += 1;
    final updatedTokens = _clampTokensForMap(map);
    await _runAction(() async {
      await _repository.saveMapImage(map.id, prepared);
      await _repository.saveMap(map);
      for (final token in updatedTokens) {
        await _repository.saveToken(token);
      }
    });
    _imageCache[map.id] = _ImageCacheEntry(
      version: map.imageVersion,
      bytes: Uint8List.fromList(prepared),
    );
    notifyListeners();
  }

  Future<void> clearMapImage(String mapId) async {
    _ensureDm();
    final map = _cloneRequiredMap(mapId);
    map.hasImage = false;
    map.imageVersion += 1;
    await _runAction(() async {
      await _repository.deleteMapImage(mapId);
      await _repository.saveMap(map);
    });
    _imageCache.remove(mapId);
    notifyListeners();
  }

  Future<Uint8List?> imageFor(String mapId) async {
    final map = _mapById(mapId);
    if (map == null || !map.hasImage) return null;
    final cached = _imageCache[mapId];
    if (cached != null && cached.version == map.imageVersion && cached.bytes != null) {
      return cached.bytes;
    }
    if (cached != null && cached.version == map.imageVersion && cached.future != null) {
      return cached.future!;
    }
    final future = _repository.loadMapImage(mapId).then((bytes) {
      if (bytes != null) {
        _imageCache[mapId] = _ImageCacheEntry(
          version: map.imageVersion,
          bytes: Uint8List.fromList(bytes),
        );
      } else {
        _imageCache.remove(mapId);
      }
      notifyListeners();
      return bytes;
    });
    _imageCache[mapId] = _ImageCacheEntry(version: map.imageVersion, future: future);
    return future;
  }

  Future<VttMap> duplicateMap(String mapId) async {
    _ensureDm();
    final source = _cloneRequiredMap(mapId);
    final duplicate = _cloneMap(source)
      ..name = '${source.name} Copy'
      ..portals = <VttPortal>[]
      ..edges = source.edges.map(_cloneEdge).toList(growable: false)
      ..terrain = List<String>.from(source.terrain)
      ..hasImage = source.hasImage
      ..imageVersion = source.hasImage ? 1 : 0;
    final newMap = VttMap.fromJson(duplicate.toJson())..name = duplicate.name;
    newMap.portals = <VttPortal>[];
    final created = VttMap(
      id: _newId('map'),
      name: newMap.name,
      cols: newMap.cols,
      rows: newMap.rows,
      isOverworld: newMap.isOverworld,
      portals: const <VttPortal>[],
      edges: newMap.edges.map(_cloneEdge).toList(growable: false),
      terrain: List<String>.from(newMap.terrain),
      feetPerCell: newMap.feetPerCell,
      showGrid: newMap.showGrid,
      hasImage: newMap.hasImage,
      imageVersion: newMap.imageVersion,
      diagonalRule: newMap.diagonalRule,
    );
    await _runAction(() => _repository.saveMap(created));
    if (source.hasImage) {
      final image = await imageFor(source.id);
      if (image != null) {
        await _runAction(() => _repository.saveMapImage(created.id, image));
      }
    }
    return _cloneMap(created);
  }

  List<String> linkedMapIds(String rootId) {
    final visited = <String>{};
    final queue = <String>[rootId];
    while (queue.isNotEmpty) {
      final mapId = queue.removeLast();
      if (!visited.add(mapId)) continue;
      final map = _mapById(mapId);
      if (map == null) continue;
      for (final portal in map.portals) {
        if (_mapById(portal.targetMapId) != null) {
          queue.add(portal.targetMapId);
        }
      }
    }
    return visited.toList(growable: false);
  }

  Future<Uint8List> exportMaps(
    List<String> mapIds, {
    bool includeTokens = false,
    bool includeDoorStates = true,
  }) async {
    final exportMaps = <VttMap>[];
    final seen = <String>{};
    for (final mapId in mapIds) {
      if (!seen.add(mapId)) continue;
      final map = _mapById(mapId);
      if (map != null) exportMaps.add(_cloneMap(map));
    }
    final images = <String, Uint8List?>{};
    for (final map in exportMaps) {
      images[map.id] = await imageFor(map.id);
    }
    final exportTokens = includeTokens
        ? _tokens
            .where((token) => seen.contains(token.mapId))
            .map((token) {
              final copy = _cloneToken(token)
                ..ownerUid = null
                ..characterId = null;
              return copy;
            })
            .toList(growable: false)
        : const <VttToken>[];
    return exportNativeVttMapBundle(
      maps: exportMaps,
      images: images,
      doorStates: _doorStates,
      tokens: exportTokens,
      includeTokens: includeTokens,
      includeDoorStates: includeDoorStates,
    );
  }

  Future<Uint8List> exportDd2vtt(String mapId) async {
    final map = _mapById(mapId);
    if (map == null) {
      throw _setAndThrow('Map not found.');
    }
    final image = await imageFor(mapId);
    return exportDd2vttMap(
      map: _cloneMap(map),
      openDoors: openDoorsFor(mapId),
      imageBytes: image,
    );
  }

  Future<VttImportResult> importFile(
    Uint8List bytes, {
    String? fileName,
  }) async {
    _ensureDm();
    final parsed = await _runAction(
      () => parseImportedVttData(bytes, fileName: fileName),
    );
    final idMap = <String, String>{};
    for (final entry in parsed.maps) {
      idMap[entry.map.id] = _newId('map');
    }
    final createdMaps = <VttMap>[];
    await _runAction(() async {
      for (final entry in parsed.maps) {
        final sourceMap = _cloneMap(entry.map);
        final newId = idMap[sourceMap.id]!;
        sourceMap.portals = sourceMap.portals
            .where((portal) => idMap.containsKey(portal.targetMapId))
            .map(
              (portal) => VttPortal(
                col: portal.col,
                row: portal.row,
                targetMapId: idMap[portal.targetMapId]!,
                targetCol: portal.targetCol,
                targetRow: portal.targetRow,
                label: portal.label,
              ),
            )
            .toList(growable: false);
        final created = VttMap(
          id: newId,
          name: sourceMap.name,
          cols: sourceMap.cols,
          rows: sourceMap.rows,
          isOverworld: sourceMap.isOverworld,
          portals: sourceMap.portals,
          edges: sourceMap.edges.map(_cloneEdge).toList(growable: false),
          terrain: List<String>.from(sourceMap.terrain),
          feetPerCell: sourceMap.feetPerCell,
          showGrid: sourceMap.showGrid,
          hasImage: sourceMap.hasImage && entry.imageBytes != null,
          imageVersion:
              sourceMap.hasImage && entry.imageBytes != null ? 1 : 0,
          diagonalRule: sourceMap.diagonalRule,
        );
        await _repository.saveMap(created);
        if (entry.openDoors.isNotEmpty) {
          for (final key in entry.openDoors) {
            await _repository.setDoorOpen(created.id, key, true);
          }
        }
        if (entry.imageBytes != null) {
          await _repository.saveMapImage(created.id, entry.imageBytes!);
        }
        createdMaps.add(created);
      }
      for (final token in parsed.tokens) {
        final targetMapId = idMap[token.mapId];
        if (targetMapId == null) continue;
        final created = VttToken(
          id: _newId('token'),
          mapId: targetMapId,
          name: token.name,
          col: token.col,
          row: token.row,
          kind: token.kind,
          color: token.color,
          hidden: token.hidden,
          initiative: token.initiative,
        );
        final map = createdMaps.firstWhere((m) => m.id == targetMapId);
        created.col = created.col.clamp(0, map.cols - 1);
        created.row = created.row.clamp(0, map.rows - 1);
        await _repository.saveToken(created);
      }
    });
    return VttImportResult(
      maps: createdMaps.map(_cloneMap).toList(growable: false),
      tokensImported: parsed.tokens.length,
      warnings: List<String>.from(parsed.warnings),
    );
  }

  Future<VttMap> importMapFile(Uint8List bytes, {String? fileName}) async {
    final result = await importFile(bytes, fileName: fileName);
    if (result.maps.isEmpty) {
      throw _setAndThrow('The imported file did not contain any maps.');
    }
    return result.maps.first;
  }

  @override
  void dispose() {
    _disposed = true;
    _mapsSub?.cancel();
    _tokensSub?.cancel();
    _combatSub?.cancel();
    _doorStatesSub?.cancel();
    super.dispose();
  }

  void _onMaps(List<VttMap> maps) {
    _maps
      ..clear()
      ..addAll(maps.map(_cloneMap));
    _gotMaps = true;
    _applyInitialOwnedMapSelection();
    _syncImageCacheWithMaps();
    _ensureCurrentMapSelection();
    _updateLoadingState();
    notifyListeners();
  }

  void _onTokens(List<VttToken> tokens) {
    final previousById = <String, VttToken>{
      for (final token in _tokens) token.id: _cloneToken(token),
    };
    _tokens
      ..clear()
      ..addAll(tokens.map(_cloneToken));
    _gotTokens = true;
    _followOwnedTokenIfNeeded(previousById);
    _updateLoadingState();
    notifyListeners();
  }

  void _onCombat(VttCombat combat) {
    _combat = _cloneCombat(combat);
    _gotCombat = true;
    _updateLoadingState();
    notifyListeners();
  }

  void _onDoorStates(Map<String, Set<String>> doorStates) {
    _doorStates
      ..clear()
      ..addAll({
        for (final entry in doorStates.entries)
          entry.key: Set<String>.from(entry.value),
      });
    _gotDoorStates = true;
    _updateLoadingState();
    notifyListeners();
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _setError(_messageFor(error));
    if (_loading) {
      _loading = false;
    }
  }

  void _followOwnedTokenIfNeeded(Map<String, VttToken> previousById) {
    if (isDm) return;
    _applyInitialOwnedMapSelection();
    for (final token in _tokens) {
      if (token.ownerUid != userId) continue;
      final previous = previousById[token.id];
      if (previous != null && previous.mapId != token.mapId) {
        _currentMapId = token.mapId;
        return;
      }
    }
    _ensureCurrentMapSelection();
  }

  void _applyInitialOwnedMapSelection() {
    if (isDm || !_initialOwnedMapSelectionPending) return;
    for (final token in _tokens) {
      if (token.ownerUid != userId) continue;
      if (_mapById(token.mapId) == null) continue;
      _currentMapId = token.mapId;
      _initialOwnedMapSelectionPending = false;
      return;
    }
    if (_gotTokens && _gotMaps) {
      _initialOwnedMapSelectionPending = false;
    }
  }

  void _ensureCurrentMapSelection() {
    if (_maps.isEmpty) {
      _currentMapId = null;
      return;
    }
    final currentId = _currentMapId;
    if (currentId != null && _mapById(currentId) != null) {
      return;
    }
    _currentMapId = _preferredMap()?.id;
  }

  VttMap? _preferredMap() {
    for (final map in _maps) {
      if (map.isOverworld) return map;
    }
    return _maps.isEmpty ? null : _maps.first;
  }

  Future<T> _runAction<T>(Future<T> Function() action) async {
    try {
      final result = await action();
      _clearError();
      return result;
    } catch (error) {
      _setError(_messageFor(error));
      rethrow;
    }
  }

  VttMoveResult _moveFailure(
    String reason, {
    VttPortal? portal,
    bool notify = true,
  }) {
    _setError(reason, notify: notify);
    return VttMoveResult(moved: false, portal: portal, reason: reason);
  }

  void _updateLoadingState() {
    final nextLoading =
        !(_gotMaps && _gotTokens && _gotCombat && _gotDoorStates);
    if (_loading != nextLoading) {
      _loading = nextLoading;
    }
  }

  VttMap _cloneRequiredMap(String mapId) {
    final map = _mapById(mapId);
    if (map == null) {
      throw _setAndThrow('Map not found.');
    }
    return _cloneMap(map);
  }

  void _validateMap(VttMap map) {
    if (map.cols < 1 || map.cols > VttMap.maxDimension) {
      throw _setAndThrow(
        'Map columns must be between 1 and ${VttMap.maxDimension}.',
      );
    }
    if (map.rows < 1 || map.rows > VttMap.maxDimension) {
      throw _setAndThrow(
        'Map rows must be between 1 and ${VttMap.maxDimension}.',
      );
    }
    if (map.portals.length > VttMap.maxPortals) {
      throw _setAndThrow(
        'A map can have at most ${VttMap.maxPortals} portals.',
      );
    }
    if (map.edges.length > VttMap.maxEdges) {
      throw _setAndThrow('A map can have at most ${VttMap.maxEdges} edges.');
    }
    if (map.feetPerCell < 1 || map.feetPerCell > 100) {
      throw _setAndThrow('Feet per cell must be between 1 and 100.');
    }
    map.terrain = _normalizeTerrain(map.terrain, map.cols, map.rows);
    for (final portal in map.portals) {
      if (!map.contains(portal.col, portal.row)) {
        throw _setAndThrow('All portals must be within the map bounds.');
      }
      final targetMap = _mapById(portal.targetMapId);
      if (targetMap != null &&
          !targetMap.contains(portal.targetCol, portal.targetRow)) {
        throw _setAndThrow(
          'All portal destinations must be within their target maps.',
        );
      }
    }
    for (final edge in map.edges) {
      _validateEdgeBounds(map, edge);
    }
  }

  void _validateToken(VttToken token) {
    final map = _mapById(token.mapId);
    if (map == null) {
      throw _setAndThrow('Map not found for this token.');
    }
    if (!map.contains(token.col, token.row)) {
      throw _setAndThrow('Token must be placed within the map bounds.');
    }
    if (token.initiative != null &&
        (token.initiative! < -20 || token.initiative! > 100)) {
      throw _setAndThrow('Initiative must be between -20 and 100.');
    }
  }

  void _validateEdgeBounds(VttMap map, VttEdge edge) {
    final inBounds = edge.horizontal
        ? edge.col >= 0 &&
            edge.col < map.cols &&
            edge.row >= 0 &&
            edge.row <= map.rows
        : edge.col >= 0 &&
            edge.col <= map.cols &&
            edge.row >= 0 &&
            edge.row < map.rows;
    if (!inBounds) {
      throw _setAndThrow('An edge lies outside the map bounds.');
    }
  }

  List<VttToken> _clampTokensForMap(VttMap map) {
    final changed = <VttToken>[];
    for (final token in _tokens.where((token) => token.mapId == map.id)) {
      final nextCol = token.col.clamp(0, map.cols - 1);
      final nextRow = token.row.clamp(0, map.rows - 1);
      if (nextCol == token.col && nextRow == token.row) continue;
      final updated = _cloneToken(token)
        ..col = nextCol
        ..row = nextRow;
      changed.add(updated);
    }
    return changed;
  }

  void _normalizeMapShape(VttMap map) {
    map.terrain = _normalizeTerrain(map.terrain, map.cols, map.rows);
    map.portals = map.portals
        .where((portal) {
          if (!map.contains(portal.col, portal.row)) return false;
          final targetMap = _mapById(portal.targetMapId);
          return targetMap == null ||
              targetMap.contains(portal.targetCol, portal.targetRow);
        })
        .toList(growable: false);
    map.edges = map.edges
        .where((edge) {
          try {
            _validateEdgeBounds(map, edge);
            return true;
          } catch (_) {
            return false;
          }
        })
        .toList(growable: false);
  }

  bool _playerHasAdjacentTokenForDoor(VttMap map, VttEdge edge) {
    final adjacentCells = _cellsTouchingEdge(map, edge);
    for (final token in _tokens) {
      if (token.ownerUid != userId || token.mapId != map.id) continue;
      for (final cell in adjacentCells) {
        if ((token.col - cell.col).abs() <= 1 && (token.row - cell.row).abs() <= 1) {
          return true;
        }
      }
    }
    return false;
  }

  List<({int col, int row})> _cellsTouchingEdge(VttMap map, VttEdge edge) {
    final cells = <({int col, int row})>[];
    if (edge.horizontal) {
      if (map.contains(edge.col, edge.row)) {
        cells.add((col: edge.col, row: edge.row));
      }
      if (map.contains(edge.col, edge.row - 1)) {
        cells.add((col: edge.col, row: edge.row - 1));
      }
    } else {
      if (map.contains(edge.col, edge.row)) {
        cells.add((col: edge.col, row: edge.row));
      }
      if (map.contains(edge.col - 1, edge.row)) {
        cells.add((col: edge.col - 1, row: edge.row));
      }
    }
    return cells;
  }

  void _syncImageCacheWithMaps() {
    final validIds = _maps.map((map) => map.id).toSet();
    _imageCache.removeWhere((key, _) => !validIds.contains(key));
    for (final map in _maps) {
      if (!map.hasImage) {
        _imageCache.remove(map.id);
        continue;
      }
      final entry = _imageCache[map.id];
      if (entry == null || entry.version != map.imageVersion) {
        imageFor(map.id);
      }
    }
  }

  void _upsertLocalToken(VttToken token) {
    final index = _tokens.indexWhere((existing) => existing.id == token.id);
    if (index >= 0) {
      _tokens[index] = _cloneToken(token);
      notifyListeners();
    }
  }

  bool _rollbackOptimisticTokenIfUnchanged(VttToken original, VttToken optimistic) {
    final current = _tokenById(original.id);
    if (current == null) return false;
    final sameOptimisticPosition = current.mapId == optimistic.mapId &&
        current.col == optimistic.col &&
        current.row == optimistic.row;
    if (!sameOptimisticPosition) {
      return false;
    }
    _upsertLocalToken(original);
    return true;
  }

  VttMap? _mapById(String? mapId) {
    if (mapId == null) return null;
    for (final map in _maps) {
      if (map.id == mapId) return map;
    }
    return null;
  }

  VttToken? _tokenById(String id) {
    for (final token in _tokens) {
      if (token.id == id) return token;
    }
    return null;
  }

  void _ensureDm() {
    if (!isDm) {
      throw _setAndThrow('Only the DM can perform this action.');
    }
  }

  StateError _setAndThrow(String message) {
    _setError(message);
    return StateError(message);
  }

  void _clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void _setError(String message, {bool notify = true}) {
    _error = message;
    if (notify) {
      notifyListeners();
    }
  }

  String _messageFor(Object error) {
    if (error is StateError) return error.message;
    if (error is FormatException) return error.message;
    return error.toString();
  }

  String _newId(String prefix) {
    _idCounter += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }
}

VttMap _cloneMap(VttMap map) => VttMap.fromJson(map.toJson());
VttToken _cloneToken(VttToken token) => VttToken.fromJson(token.toJson());
VttCombat _cloneCombat(VttCombat combat) => VttCombat.fromJson(combat.toJson());
VttEdge _cloneEdge(VttEdge edge) => VttEdge.fromJson(edge.toJson());
List<String> _normalizeTerrain(List<String> terrain, int cols, int rows) =>
    VttMap.fromJson(<String, dynamic>{
      'id': 'tmp',
      'cols': cols,
      'rows': rows,
      'terrain': terrain,
    }).terrain;
