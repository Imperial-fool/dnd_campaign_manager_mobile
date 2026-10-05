import 'package:dnd_campaign_manager/vtt/vtt_geometry.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vtt geometry', () {
    test('walls and closed doors block paths while open doors pass', () {
      final wallMap = VttMap(
        id: 'wall-map',
        cols: 2,
        rows: 1,
        edges: <VttEdge>[
          VttEdge(col: 1, row: 0, horizontal: false, type: VttEdgeType.wall),
        ],
      );
      final doorMap = VttMap(
        id: 'door-map',
        cols: 2,
        rows: 1,
        edges: <VttEdge>[
          VttEdge(col: 1, row: 0, horizontal: false, type: VttEdgeType.door),
        ],
      );

      expect(canStep(wallMap, const <String>{}, 0, 0, 1, 0), isFalse);
      expect(canStep(doorMap, const <String>{}, 0, 0, 1, 0), isFalse);
      expect(canStep(doorMap, const <String>{'v:1:0'}, 0, 0, 1, 0), isTrue);
      expect(findPath(doorMap, const <String>{}, 0, 0, 1, 0), isNull);
      expect(findPath(doorMap, const <String>{'v:1:0'}, 0, 0, 1, 0), isNotNull);
    });

    test('diagonals require both corner routes to stay open', () {
      final map = VttMap(
        id: 'map',
        cols: 3,
        rows: 3,
        edges: <VttEdge>[
          VttEdge(col: 1, row: 0, horizontal: false, type: VttEdgeType.wall),
        ],
      );
      expect(canStep(map, const <String>{}, 0, 0, 1, 1), isFalse);
      expect(canStep(map, const <String>{}, 1, 1, 2, 2), isTrue);
    });

    test('bounds, edgesOnLine, and distance rules work', () {
      final map = VttMap(id: 'map', cols: 2, rows: 2);
      expect(canStep(map, const <String>{}, 0, 0, -1, 0), isFalse);
      expect(findPath(map, const <String>{}, 0, 0, 0, 0), isEmpty);

      final horizontal = edgesOnLine(0, 1, 3, 1, type: VttEdgeType.wall);
      expect(horizontal.map((e) => e.key), ['h:0:1', 'h:1:1', 'h:2:1']);
      final vertical = edgesOnLine(2, 0, 2, 2, type: VttEdgeType.window);
      expect(vertical.map((e) => e.key), ['v:2:0', 'v:2:1']);
      expect(edgesOnLine(0, 0, 1, 1, type: VttEdgeType.wall), isEmpty);

      expect(gridDistance(3, 1, VttDiagonalRule.simple), 3);
      expect(gridDistance(3, 3, VttDiagonalRule.alternating), 4);
      expect(
        gridDistance(1, 1, VttDiagonalRule.euclidean),
        closeTo(1.414, 0.01),
      );
    });
  });
}
