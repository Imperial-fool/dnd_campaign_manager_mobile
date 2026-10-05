import 'dart:convert';
import 'dart:typed_data';

import 'package:dnd_campaign_manager/vtt/vtt_controller.dart';
import 'package:dnd_campaign_manager/vtt/vtt_image.dart';
import 'package:dnd_campaign_manager/vtt/vtt_map_io.dart';
import 'package:dnd_campaign_manager/vtt/vtt_memory_repository.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Uint8List _png({int width = 120, int height = 80}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('vtt map io', () {
    test('native export/import round-trips image, edges, terrain, portals, tokens, and door states', () async {
      final store = MemoryVttStore();
      final controller = VttController(
        MemoryVttRepository(isOwner: true, userId: 'dm', store: store),
      )..start();
      addTearDown(() {
        controller.dispose();
        store.dispose();
      });
      await _flush();

      final root = await controller.createMap(name: 'Root', cols: 4, rows: 4);
      final linked = await controller.createMap(name: 'Linked', cols: 3, rows: 3);
      await controller.addPortal(
        root.id,
        VttPortal(
          col: 0,
          row: 0,
          targetMapId: linked.id,
          targetCol: 1,
          targetRow: 1,
        ),
      );
      await controller.setEdges(
        root.id,
        add: <VttEdge>[
          VttEdge(col: 1, row: 1, horizontal: false, type: VttEdgeType.door),
        ],
      );
      await controller.toggleDoor(root.id, 'v:1:1');
      await controller.paintTerrain(root.id, [(col: 1, row: 2)], 3);
      await controller.setMapImage(root.id, _png());
      await controller.addToken(mapId: root.id, name: 'Hero', ownerUid: 'player');
      await _flush();

      final exported = await controller.exportMaps(
        controller.linkedMapIds(root.id),
        includeTokens: true,
      );

      final importStore = MemoryVttStore();
      final importer = VttController(
        MemoryVttRepository(isOwner: true, userId: 'dm2', store: importStore),
      )..start();
      addTearDown(() {
        importer.dispose();
        importStore.dispose();
      });
      await _flush();

      final result = await importer.importFile(exported, fileName: 'bundle.vttmap.json');
      await _flush();

      expect(result.maps, hasLength(2));
      expect(result.tokensImported, 1);
      final importedRoot = result.maps.firstWhere((m) => m.name == 'Root');
      expect(importedRoot.terrain[2][1], '3');
      expect(importedRoot.edges.single.type, VttEdgeType.door);
      expect(importedRoot.portals.single.targetMapId, isNot(linked.id));
      expect(importedRoot.hasImage, isTrue);
      expect(importer.openDoorsFor(importedRoot.id), contains('v:1:1'));
      expect(await importer.imageFor(importedRoot.id), isNotNull);
      expect(importer.tokens.single.ownerUid, isNull);
      expect(importer.tokens.single.characterId, isNull);
    });

    test('dd2vtt import snaps geometry and export merges collinear walls', () async {
      final payload = <String, dynamic>{
        'resolution': {
          'map_size': {'x': 4, 'y': 4},
          'pixels_per_grid': 50,
        },
        'line_of_sight': [
          [
            {'x': 0, 'y': 0},
            {'x': 100, 'y': 100},
          ]
        ],
        'portals': [
          {
            'bounds': [
              {'x': 50, 'y': 0},
              {'x': 50, 'y': 50},
            ],
            'closed': false,
          }
        ],
        'image': base64Encode(_png(width: 200, height: 200)),
      };
      final parsed = await parseImportedVttData(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        fileName: 'import.dd2vtt',
      );
      expect(parsed.maps.single.map.edges, isNotEmpty);
      expect(parsed.maps.single.openDoors, contains('v:1:0'));
      expect(parsed.warnings.join(' '), contains('Approximated'));

      final store = MemoryVttStore();
      final controller = VttController(
        MemoryVttRepository(isOwner: true, userId: 'dm', store: store),
      )..start();
      addTearDown(() {
        controller.dispose();
        store.dispose();
      });
      await _flush();

      final map = await controller.createMap(name: 'Export', cols: 4, rows: 4);
      await controller.setEdges(
        map.id,
        add: <VttEdge>[
          VttEdge(col: 0, row: 1, horizontal: true, type: VttEdgeType.wall),
          VttEdge(col: 1, row: 1, horizontal: true, type: VttEdgeType.wall),
          VttEdge(col: 2, row: 0, horizontal: false, type: VttEdgeType.door),
        ],
      );
      await controller.setMapImage(map.id, _png(width: 280, height: 140));
      final dd2vtt = jsonDecode(utf8.decode(await controller.exportDd2vtt(map.id)))
          as Map<String, dynamic>;
      expect((dd2vtt['line_of_sight'] as List).length, 1);
      expect((dd2vtt['portals'] as List).length, 1);
    });

    test('dd2vtt import skips out-of-bounds geometry, caps edges, and validates resolution', () async {
      final hugeSegments = List<List<Map<String, int>>>.generate(
        100,
        (row) => <Map<String, int>>[
          {'x': 0, 'y': row * 10},
          {'x': 1000, 'y': row * 10},
        ],
      );
      final payload = <String, dynamic>{
        'resolution': {
          'map_size': {'x': 100, 'y': 100},
          'pixels_per_grid': 10,
        },
        'line_of_sight': [
          [
            {'x': -50, 'y': 0},
            {'x': 10, 'y': 0},
          ],
          ...hugeSegments,
        ],
      };
      final parsed = await parseImportedVttData(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
        fileName: 'bounded.dd2vtt',
      );
      expect(parsed.maps.single.map.edges.length, VttMap.maxEdges);
      expect(parsed.warnings.join(' '), contains('out-of-bounds'));
      expect(parsed.warnings.join(' '), contains('maximum number of edges'));

      final badPayload = <String, dynamic>{
        'resolution': {
          'map_size': {'x': '4', 'y': 4},
          'pixels_per_grid': 0,
        },
      };
      await expectLater(
        () => parseImportedVttData(
          Uint8List.fromList(utf8.encode(jsonEncode(badPayload))),
          fileName: 'bad.dd2vtt',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('image dimension prechecks reject oversized images in helpers and imports', () async {
      final giant = _png(width: 17000, height: 1);
      await expectLater(
        () => prepareMapImage(giant),
        throwsA(isA<FormatException>()),
      );
      expect(() => imageSize(giant), throwsA(isA<FormatException>()));

      final nativePayload = <String, dynamic>{
        'format': 'dnd_campaign_manager.vttmap',
        'version': 1,
        'maps': [
          {
            'map': VttMap(id: 'map-1', cols: 2, rows: 2).toJson(),
            'image': {'mime': 'image/png', 'data': base64Encode(giant)},
          },
        ],
      };
      await expectLater(
        () => parseImportedVttData(
          Uint8List.fromList(utf8.encode(jsonEncode(nativePayload))),
          fileName: 'huge.vttmap.json',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('controller import rejects duplicate map ids and drops duplicate token ids with a warning', () async {
      final store = MemoryVttStore();
      final controller = VttController(
        MemoryVttRepository(isOwner: true, userId: 'dm', store: store),
      )..start();
      addTearDown(() {
        controller.dispose();
        store.dispose();
      });
      await _flush();

      final duplicateMapPayload = <String, dynamic>{
        'format': 'dnd_campaign_manager.vttmap',
        'version': 1,
        'maps': [
          {'map': VttMap(id: 'same-id', cols: 2, rows: 2).toJson(), 'image': null},
          {'map': VttMap(id: 'same-id', cols: 2, rows: 2).toJson(), 'image': null},
        ],
      };
      await expectLater(
        () => controller.importFile(
          Uint8List.fromList(utf8.encode(jsonEncode(duplicateMapPayload))),
          fileName: 'dupe-maps.vttmap.json',
        ),
        throwsA(isA<FormatException>()),
      );

      final duplicateTokenPayload = <String, dynamic>{
        'format': 'dnd_campaign_manager.vttmap',
        'version': 1,
        'maps': [
          {'map': VttMap(id: 'map-1', cols: 2, rows: 2).toJson(), 'image': null},
        ],
        'tokens': [
          VttToken(id: 'token-1', mapId: 'map-1', name: 'Hero').toJson(),
          VttToken(id: 'token-1', mapId: 'map-1', name: 'Hero clone').toJson(),
        ],
      };
      final result = await controller.importFile(
        Uint8List.fromList(utf8.encode(jsonEncode(duplicateTokenPayload))),
        fileName: 'dupe-tokens.vttmap.json',
      );
      await _flush();

      expect(result.tokensImported, 1);
      expect(result.warnings.join(' '), contains('duplicate token id'));
      expect(controller.tokens, hasLength(1));
    });

    test('malformed and oversized imports are rejected', () async {
      await expectLater(
        () => parseImportedVttData(Uint8List.fromList(utf8.encode('nope'))),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        () => parseImportedVttData(Uint8List(25 * 1024 * 1024 + 1)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
