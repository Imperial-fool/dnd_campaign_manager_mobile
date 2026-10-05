import 'dart:collection';
import 'dart:math' as math;

import 'package:dnd_campaign_manager/vtt/vtt_models.dart';

bool edgeBlocks(VttEdge edge, Set<String> openDoors) {
  if (edge.type == VttEdgeType.door) {
    return !openDoors.contains(edge.key);
  }
  return true;
}

bool canStep(
  VttMap map,
  Set<String> openDoors,
  int c1,
  int r1,
  int c2,
  int r2,
) {
  if (!map.contains(c1, r1) || !map.contains(c2, r2)) return false;
  final dc = c2 - c1;
  final dr = r2 - r1;
  if (dc == 0 && dr == 0) return true;
  if (dc.abs() > 1 || dr.abs() > 1) return false;
  if (dc == 0 || dr == 0) {
    return !_sharedEdgeBlocks(map, openDoors, c1, r1, c2, r2);
  }
  final horizontalFirst = !_sharedEdgeBlocks(map, openDoors, c1, r1, c1 + dc, r1) &&
      !_sharedEdgeBlocks(map, openDoors, c1 + dc, r1, c2, r2);
  final verticalFirst = !_sharedEdgeBlocks(map, openDoors, c1, r1, c1, r1 + dr) &&
      !_sharedEdgeBlocks(map, openDoors, c1, r1 + dr, c2, r2);
  return horizontalFirst && verticalFirst;
}

List<({int col, int row})>? findPath(
  VttMap map,
  Set<String> openDoors,
  int sc,
  int sr,
  int ec,
  int er,
) {
  if (!map.contains(sc, sr) || !map.contains(ec, er)) return null;
  if (sc == ec && sr == er) return <({int col, int row})>[];

  final queue = Queue<({int col, int row})>()
    ..add((col: sc, row: sr));
  final previous = <String, ({int col, int row})?>{'$sc,$sr': null};
  const deltas = <(int, int)>[
    (-1, -1),
    (0, -1),
    (1, -1),
    (-1, 0),
    (1, 0),
    (-1, 1),
    (0, 1),
    (1, 1),
  ];

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    for (final (dc, dr) in deltas) {
      final nextCol = current.col + dc;
      final nextRow = current.row + dr;
      final nextKey = '$nextCol,$nextRow';
      if (previous.containsKey(nextKey)) continue;
      if (!canStep(map, openDoors, current.col, current.row, nextCol, nextRow)) {
        continue;
      }
      previous[nextKey] = current;
      if (nextCol == ec && nextRow == er) {
        return _reconstructPath(previous, ec, er);
      }
      queue.add((col: nextCol, row: nextRow));
    }
  }
  return null;
}

double gridDistance(int dc, int dr, VttDiagonalRule rule) {
  final absDc = dc.abs();
  final absDr = dr.abs();
  final diagonal = math.min(absDc, absDr);
  final straight = math.max(absDc, absDr) - diagonal;
  switch (rule) {
    case VttDiagonalRule.simple:
      return (straight + diagonal).toDouble();
    case VttDiagonalRule.alternating:
      return (straight + (diagonal ~/ 2) * 3 + (diagonal.isOdd ? 1 : 0))
          .toDouble();
    case VttDiagonalRule.euclidean:
      return straight + diagonal * math.sqrt2;
  }
}

List<VttEdge> edgesOnLine(
  int c1,
  int r1,
  int c2,
  int r2, {
  required VttEdgeType type,
}) {
  final edges = <VttEdge>[];
  if (c1 == c2) {
    final start = math.min(r1, r2);
    final end = math.max(r1, r2);
    for (var row = start; row < end; row++) {
      edges.add(
        VttEdge(
          col: c1,
          row: row,
          horizontal: false,
          type: type,
        ),
      );
    }
    return edges;
  }
  if (r1 == r2) {
    final start = math.min(c1, c2);
    final end = math.max(c1, c2);
    for (var col = start; col < end; col++) {
      edges.add(
        VttEdge(
          col: col,
          row: r1,
          horizontal: true,
          type: type,
        ),
      );
    }
  }
  return edges;
}

List<({int col, int row})> _reconstructPath(
  Map<String, ({int col, int row})?> previous,
  int endCol,
  int endRow,
) {
  final path = <({int col, int row})>[];
  ({int col, int row})? current = (col: endCol, row: endRow);
  while (current != null) {
    path.add(current);
    current = previous['${current.col},${current.row}'];
  }
  return path.reversed.skip(1).toList(growable: false);
}

bool _sharedEdgeBlocks(
  VttMap map,
  Set<String> openDoors,
  int c1,
  int r1,
  int c2,
  int r2,
) {
  final dc = c2 - c1;
  final dr = r2 - r1;
  String? key;
  if (dc == 1 && dr == 0) key = 'v:${c1 + 1}:$r1';
  if (dc == -1 && dr == 0) key = 'v:$c1:$r1';
  if (dc == 0 && dr == 1) key = 'h:$c1:${r1 + 1}';
  if (dc == 0 && dr == -1) key = 'h:$c1:$r1';
  if (key == null) return true;
  final edge = map.edgeAt(key);
  return edge != null && edgeBlocks(edge, openDoors);
}
