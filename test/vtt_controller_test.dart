import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:dnd_campaign_manager/vtt/vtt_geometry.dart';
import 'package:dnd_campaign_manager/vtt/vtt_memory_repository.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:dnd_campaign_manager/vtt/vtt_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _Rig {
  _Rig._(this.store, this.dm, this.player);

  factory _Rig.shared() {
    final sharedStore = MemoryVttStore();
    final rig = _Rig._(
      sharedStore,
      VttController(
        MemoryVttRepository(
          isOwner: true,
          userId: 'dm',
          store: sharedStore,
        ),
      ),
      VttController(
        MemoryVttRepository(
          isOwner: false,
          userId: 'player-1',
          store: sharedStore,
        ),
      ),
    );
    rig.dm.start();
    rig.player.start();
    return rig;
  }

  final MemoryVttStore store;
  final VttController dm;
  final VttController player;

  void dispose() {
    dm.dispose();
    player.dispose();
    store.dispose();
  }
}

class _FixedRandom implements Random {
  _FixedRandom(this._values);

  final List<int> _values;
  int _index = 0;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1000) / 1000;

  @override
  int nextInt(int max) {
    final value = _values[_index % _values.length];
    _index += 1;
    return value % max;
  }
}

class _DelayedMoveRepository implements VttRepository {
  _DelayedMoveRepository(this._delegate);

  final VttRepository _delegate;
  Completer<void>? _nextMoveCompleter;

  void delayNextMove() {
    _nextMoveCompleter = Completer<void>();
  }

  void failNextMove(Object error) {
    final completer = _nextMoveCompleter!;
    _nextMoveCompleter = null;
    completer.completeError(error);
  }

  @override
  bool get isOwner => _delegate.isOwner;

  @override
  String get userId => _delegate.userId;

  @override
  Future<void> deleteMap(String mapId) => _delegate.deleteMap(mapId);

  @override
  Future<void> deleteMapImage(String mapId) => _delegate.deleteMapImage(mapId);

  @override
  Future<void> deleteToken(String tokenId) => _delegate.deleteToken(tokenId);

  @override
  Future<Uint8List?> loadMapImage(String mapId) => _delegate.loadMapImage(mapId);

  @override
  Future<void> moveToken(String tokenId, String mapId, int col, int row) {
    final completer = _nextMoveCompleter;
    if (completer != null) {
      return completer.future;
    }
    return _delegate.moveToken(tokenId, mapId, col, row);
  }

  @override
  Future<void> saveCombat(VttCombat combat) => _delegate.saveCombat(combat);

  @override
  Future<void> saveMap(VttMap map) => _delegate.saveMap(map);

  @override
  Future<void> saveMapImage(String mapId, Uint8List jpegBytes) =>
      _delegate.saveMapImage(mapId, jpegBytes);

  @override
  Future<void> saveToken(VttToken token) => _delegate.saveToken(token);

  @override
  Future<void> setDoorOpen(String mapId, String edgeKey, bool open) =>
      _delegate.setDoorOpen(mapId, edgeKey, open);

  @override
  Future<void> setInitiative(String tokenId, int? initiative) =>
      _delegate.setInitiative(tokenId, initiative);

  @override
  Stream<VttCombat> watchCombat() => _delegate.watchCombat();

  @override
  Stream<Map<String, Set<String>>> watchDoorStates() =>
      _delegate.watchDoorStates();

  @override
  Stream<List<VttMap>> watchMaps() => _delegate.watchMaps();

  @override
  Stream<List<VttToken>> watchTokens() => _delegate.watchTokens();
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Uint8List _rawPng({int width = 40, int height = 20}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('VttController', () {
    late _Rig rig;

    setUp(() async {
      rig = _Rig.shared();
      await _flush();
    });

    tearDown(() {
      rig.dispose();
    });

    test('player sees filtered tokens, can move own token, and can use portals', () async {
      final overworld = await rig.dm.createMap(
        name: 'Overworld',
        cols: 8,
        rows: 8,
        isOverworld: true,
      );
      final dungeon = await rig.dm.createMap(name: 'Dungeon', cols: 6, rows: 6);
      await rig.dm.addPortal(
        overworld.id,
        VttPortal(
          col: 2,
          row: 2,
          targetMapId: dungeon.id,
          targetCol: 1,
          targetRow: 1,
          label: 'Trapdoor',
        ),
      );
      final hero = await rig.dm.addToken(
        mapId: overworld.id,
        name: 'Hero',
        ownerUid: 'player-1',
      );
      await rig.dm.addToken(
        mapId: overworld.id,
        name: 'Secret',
        hidden: true,
      );
      await _flush();

      expect(rig.player.tokens.map((t) => t.name), ['Hero']);

      final portalMove = await rig.player.moveToken(hero.id, 2, 2, ignoreWalls: true);
      await _flush();

      expect(portalMove.moved, isTrue);
      expect(portalMove.portal?.label, 'Trapdoor');

      await rig.player.usePortal(hero.id);
      await _flush();

      expect(rig.player.currentMapId, dungeon.id);
      expect(rig.player.tokens.single.mapId, dungeon.id);
      expect(rig.player.tokens.single.col, 1);
      expect(rig.player.tokens.single.row, 1);
    });

    test('player initially selects owned token map instead of overworld', () async {
      final store = MemoryVttStore();
      final dm = VttController(
        MemoryVttRepository(isOwner: true, userId: 'dm', store: store),
      )..start();
      addTearDown(() {
        dm.dispose();
        store.dispose();
      });
      await _flush();

      final overworld = await dm.createMap(
        name: 'Overworld',
        cols: 8,
        rows: 8,
        isOverworld: true,
      );
      final dungeon = await dm.createMap(name: 'Dungeon', cols: 6, rows: 6);
      await dm.addToken(mapId: dungeon.id, name: 'Hero', ownerUid: 'player-1');
      await _flush();

      final player = VttController(
        MemoryVttRepository(isOwner: false, userId: 'player-1', store: store),
      )..start();
      addTearDown(player.dispose);
      await _flush();

      expect(player.currentMapId, isNot(overworld.id));
      expect(player.currentMapId, dungeon.id);
    });

    test('combat enforces turn order and initiative sorting', () async {
      final controller = VttController(
        MemoryVttRepository(isOwner: true, userId: 'dm', store: rig.store),
        random: _FixedRandom(<int>[9]),
      )..start();
      addTearDown(controller.dispose);
      await _flush();

      final map = await rig.dm.createMap(name: 'Arena', cols: 5, rows: 5);
      final hero =
          await rig.dm.addToken(mapId: map.id, name: 'Hero', ownerUid: 'player-1');
      final goblin = await rig.dm.addToken(mapId: map.id, name: 'Goblin');
      final archer = await rig.dm.addToken(mapId: map.id, name: 'Archer');
      await rig.dm.setInitiative(hero.id, 12);
      await rig.dm.setInitiative(goblin.id, 12);
      await rig.dm.setInitiative(archer.id, 8);
      await _flush();

      expect(
        rig.dm.initiativeOrder.map((t) => t.name).toList(),
        ['Goblin', 'Hero', 'Archer'],
      );

      await rig.dm.startCombat();
      await _flush();
      expect(rig.dm.currentTurnToken?.name, 'Goblin');

      final blockedMove = await rig.player.moveToken(hero.id, 1, 0, ignoreWalls: true);
      expect(blockedMove.moved, isFalse);

      await rig.dm.nextTurn();
      await _flush();
      expect(rig.dm.currentTurnToken?.id, hero.id);

      final allowedMove = await rig.player.moveToken(hero.id, 1, 0, ignoreWalls: true);
      expect(allowedMove.moved, isTrue);

      await rig.dm.nextTurn();
      await rig.dm.nextTurn();
      await _flush();
      expect(rig.dm.combat.round, 2);

      final rolled = await controller.rollInitiative(archer.id, 3);
      expect(rolled, 13);
      expect(rig.dm.initiativeOrder.first.name, 'Archer');
    });

    test('player cannot path through walls but DM can ignore them', () async {
      final map = await rig.dm.createMap(name: 'Hall', cols: 4, rows: 4);
      await rig.dm.setEdges(
        map.id,
        add: edgesOnLine(1, 0, 1, 4, type: VttEdgeType.wall),
      );
      final hero = await rig.dm.addToken(
        mapId: map.id,
        name: 'Hero',
        col: 0,
        row: 1,
        ownerUid: 'player-1',
      );
      await _flush();

      final blocked = await rig.player.moveToken(hero.id, 2, 1);
      expect(blocked.moved, isFalse);
      expect(blocked.reason, 'Blocked by a wall or closed door.');

      final moved = await rig.dm.moveToken(hero.id, 2, 1);
      expect(moved.moved, isTrue);
    });

    test('players can toggle nearby unlocked doors but not locked or distant ones', () async {
      final map = await rig.dm.createMap(name: 'Doors', cols: 4, rows: 4);
      await rig.dm.setEdges(
        map.id,
        add: <VttEdge>[
          VttEdge(
            col: 1,
            row: 1,
            horizontal: false,
            type: VttEdgeType.door,
          ),
          VttEdge(
            col: 3,
            row: 1,
            horizontal: false,
            type: VttEdgeType.door,
            locked: true,
          ),
        ],
      );
      final hero = await rig.dm.addToken(
        mapId: map.id,
        name: 'Hero',
        col: 1,
        row: 1,
        ownerUid: 'player-1',
      );
      await _flush();

      await rig.player.toggleDoor(map.id, 'v:1:1');
      await _flush();
      expect(rig.player.isDoorOpen(map.id, 'v:1:1'), isTrue);

      final moved = await rig.player.moveToken(hero.id, 2, 1);
      expect(moved.moved, isTrue);

      expect(
        () => rig.player.toggleDoor(map.id, 'v:3:1'),
        throwsA(isA<StateError>()),
      );

      final farToken = VttToken.fromJson(hero.toJson())
        ..col = 0
        ..row = 3;
      await rig.dm.updateToken(farToken);
      await _flush();
      expect(
        () => rig.player.toggleDoor(map.id, 'v:1:1'),
        throwsA(isA<StateError>()),
      );
    });

    test('player cannot move other tokens and remote moves auto-follow maps', () async {
      final overworld = await rig.dm.createMap(
        name: 'Overworld',
        cols: 6,
        rows: 6,
        isOverworld: true,
      );
      final cave = await rig.dm.createMap(name: 'Cave', cols: 6, rows: 6);
      await rig.dm.addPortal(
        overworld.id,
        VttPortal(
          col: 1,
          row: 1,
          targetMapId: cave.id,
          targetCol: 3,
          targetRow: 3,
        ),
      );
      final hero =
          await rig.dm.addToken(mapId: overworld.id, name: 'Hero', ownerUid: 'player-1');
      final npc = await rig.dm.addToken(mapId: overworld.id, name: 'NPC');
      await _flush();

      final denied = await rig.player.moveToken(npc.id, 2, 1, ignoreWalls: true);
      expect(denied.moved, isFalse);

      await rig.dm.moveToken(hero.id, 1, 1, ignoreWalls: true);
      await rig.dm.usePortal(hero.id);
      await _flush();

      final playerHero =
          rig.player.tokens.firstWhere((token) => token.ownerUid == 'player-1');
      expect(rig.player.currentMapId, cave.id);
      expect(playerHero.mapId, cave.id);
      expect(playerHero.col, 3);
      expect(playerHero.row, 3);
    });

    test('stale move failure does not roll back newer snapshot state', () async {
      final store = MemoryVttStore();
      final dm = VttController(
        MemoryVttRepository(isOwner: true, userId: 'dm', store: store),
      )..start();
      final delayedRepo = _DelayedMoveRepository(
        MemoryVttRepository(isOwner: false, userId: 'player-1', store: store),
      );
      final player = VttController(delayedRepo)..start();
      addTearDown(() {
        player.dispose();
        dm.dispose();
        store.dispose();
      });
      await _flush();

      final map = await dm.createMap(name: 'Arena', cols: 6, rows: 6);
      final hero = await dm.addToken(mapId: map.id, name: 'Hero', ownerUid: 'player-1');
      await _flush();

      delayedRepo.delayNextMove();
      final moveFuture = player.moveToken(hero.id, 1, 1, ignoreWalls: true);
      await _flush();

      final remoteHero = VttToken.fromJson(hero.toJson())
        ..col = 4
        ..row = 2;
      await dm.updateToken(remoteHero);
      await _flush();

      delayedRepo.failNextMove(StateError('move rejected'));
      final result = await moveFuture;
      await _flush();

      expect(result.moved, isFalse);
      expect(player.tokens.single.col, 4);
      expect(player.tokens.single.row, 2);
      expect(player.error, contains('move rejected'));
    });

    test('stale portal failure does not roll back newer snapshot state', () async {
      final store = MemoryVttStore();
      final dm = VttController(
        MemoryVttRepository(isOwner: true, userId: 'dm', store: store),
      )..start();
      final delayedRepo = _DelayedMoveRepository(
        MemoryVttRepository(isOwner: false, userId: 'player-1', store: store),
      );
      final player = VttController(delayedRepo)..start();
      addTearDown(() {
        player.dispose();
        dm.dispose();
        store.dispose();
      });
      await _flush();

      final overworld = await dm.createMap(
        name: 'Overworld',
        cols: 6,
        rows: 6,
        isOverworld: true,
      );
      final cave = await dm.createMap(name: 'Cave', cols: 6, rows: 6);
      await dm.addPortal(
        overworld.id,
        VttPortal(
          col: 1,
          row: 1,
          targetMapId: cave.id,
          targetCol: 2,
          targetRow: 2,
        ),
      );
      final hero = await dm.addToken(
        mapId: overworld.id,
        name: 'Hero',
        col: 1,
        row: 1,
        ownerUid: 'player-1',
      );
      await _flush();

      delayedRepo.delayNextMove();
      final portalFuture = player.usePortal(hero.id).catchError((_) {});
      await _flush();

      final remoteHero = VttToken.fromJson(hero.toJson())
        ..mapId = cave.id
        ..col = 4
        ..row = 4;
      await dm.updateToken(remoteHero);
      await _flush();

      delayedRepo.failNextMove(StateError('portal rejected'));
      await portalFuture;
      await _flush();

      final currentHero =
          player.tokens.firstWhere((token) => token.ownerUid == 'player-1');
      expect(player.currentMapId, cave.id);
      expect(currentHero.mapId, cave.id);
      expect(currentHero.col, 4);
      expect(currentHero.row, 4);
    });

    test('setMapImage caches image and duplicateMap copies it without portals', () async {
      final map = await rig.dm.createMap(name: 'Art', cols: 2, rows: 2);
      await rig.dm.addPortal(
        map.id,
        VttPortal(
          col: 0,
          row: 0,
          targetMapId: map.id,
          targetCol: 1,
          targetRow: 1,
        ),
      );
      await rig.dm.setMapImage(map.id, _rawPng(width: 140, height: 70));
      await _flush();

      final bytes = await rig.player.imageFor(map.id);
      expect(bytes, isNotNull);

      final copy = await rig.dm.duplicateMap(map.id);
      await _flush();
      final duplicate = rig.dm.maps.firstWhere((m) => m.id == copy.id);
      expect(duplicate.portals, isEmpty);
      expect(duplicate.hasImage, isTrue);
      expect(await rig.dm.imageFor(copy.id), isNotNull);
    });

    test('importFile is DM-only', () async {
      final map = await rig.dm.createMap(name: 'Export', cols: 3, rows: 3);
      final bytes = await rig.dm.exportMaps([map.id]);
      await expectLater(
        () => rig.player.importFile(bytes),
        throwsA(isA<StateError>()),
      );
    });

    test('deleteMap removes inbound portals and tokens', () async {
      final overworld = await rig.dm.createMap(
        name: 'Overworld',
        cols: 6,
        rows: 6,
        isOverworld: true,
      );
      final cave = await rig.dm.createMap(name: 'Cave', cols: 6, rows: 6);
      await rig.dm.addPortal(
        overworld.id,
        VttPortal(
          col: 1,
          row: 1,
          targetMapId: cave.id,
          targetCol: 0,
          targetRow: 0,
        ),
      );
      final hero = await rig.dm.addToken(mapId: cave.id, name: 'Hero', ownerUid: 'player-1');
      await _flush();

      await rig.dm.deleteMap(cave.id);
      await _flush();

      expect(rig.dm.maps.map((m) => m.id), [overworld.id]);
      expect(rig.dm.maps.single.portals, isEmpty);
      expect(rig.dm.tokens.where((t) => t.id == hero.id), isEmpty);
    });
  });

  test('VTT model JSON round-trips', () {
    final map = VttMap(
      id: 'map-1',
      name: 'Town',
      cols: 12,
      rows: 9,
      isOverworld: true,
      portals: <VttPortal>[
        const VttPortal(
          col: 1,
          row: 2,
          targetMapId: 'map-2',
          targetCol: 3,
          targetRow: 4,
          label: 'Gate',
        ),
      ],
      edges: <VttEdge>[
        VttEdge(
          col: 2,
          row: 3,
          horizontal: true,
          type: VttEdgeType.window,
          locked: true,
        ),
      ],
      terrain: const <String>['0..', '.1.', '..2'],
      feetPerCell: 10,
      showGrid: false,
      hasImage: true,
      imageVersion: 2,
      diagonalRule: VttDiagonalRule.alternating,
    );
    final token = VttToken(
      id: 'token-1',
      mapId: 'map-1',
      name: 'Hero',
      col: 2,
      row: 3,
      kind: 'pc',
      color: 0xFF336699,
      characterId: 'char-1',
      ownerUid: 'player-1',
      hidden: true,
      initiative: 15,
    );
    const combat = VttCombat(active: true, round: 3, turnTokenId: 'token-1');

    expect(VttMap.fromJson(map.toJson()).toJson(), map.toJson());
    expect(VttToken.fromJson(token.toJson()).toJson(), token.toJson());
    expect(VttCombat.fromJson(combat.toJson()).toJson(), combat.toJson());
  });
}
