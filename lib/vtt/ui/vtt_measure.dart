import 'dart:math' as math;

import 'package:dnd_campaign_manager/vtt/vtt_geometry.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';

enum VttMeasureMode { none, ruler, circle, cone, line }

class VttGridPoint {
  const VttGridPoint(this.col, this.row);

  final int col;
  final int row;

  String get key => '$col,$row';
}

class VttMeasureOverlay {
  const VttMeasureOverlay({
    required this.mode,
    required this.start,
    required this.end,
    required this.affectedCells,
    required this.label,
    required this.distanceCells,
    required this.lineWidth,
  });

  final VttMeasureMode mode;
  final VttGridPoint start;
  final VttGridPoint end;
  final List<VttGridPoint> affectedCells;
  final String label;
  final double distanceCells;
  final int lineWidth;
}

VttMeasureOverlay? buildMeasureOverlay(
  VttMap map,
  VttMeasureMode mode,
  VttGridPoint? start,
  VttGridPoint? end, {
  int lineWidth = 1,
}) {
  if (mode == VttMeasureMode.none || start == null || end == null) return null;

  final distanceCells = gridDistance(
    end.col - start.col,
    end.row - start.row,
    map.diagonalRule,
  );
  final feet = (distanceCells * map.feetPerCell).toStringAsFixed(
    distanceCells % 1 == 0 ? 0 : 1,
  );
  final cellsLabel =
      distanceCells.toStringAsFixed(distanceCells % 1 == 0 ? 0 : 1);
  return VttMeasureOverlay(
    mode: mode,
    start: start,
    end: end,
    affectedCells: switch (mode) {
      VttMeasureMode.ruler => _rulerCells(map, start, end),
      VttMeasureMode.circle => _circleCells(map, start, end),
      VttMeasureMode.cone => _coneCells(map, start, end),
      VttMeasureMode.line => _lineCells(map, start, end, lineWidth),
      VttMeasureMode.none => const <VttGridPoint>[],
    },
    label: '$feet ft · $cellsLabel cells',
    distanceCells: distanceCells,
    lineWidth: lineWidth,
  );
}

List<VttGridPoint> _rulerCells(
  VttMap map,
  VttGridPoint start,
  VttGridPoint end,
) {
  final results = <VttGridPoint>[];
  final dx = end.col - start.col;
  final dy = end.row - start.row;
  final steps = math.max(dx.abs(), dy.abs());
  if (steps == 0) return <VttGridPoint>[start];
  for (var i = 0; i <= steps; i++) {
    final col = (start.col + dx * (i / steps)).round();
    final row = (start.row + dy * (i / steps)).round();
    if (_contains(map, col, row) &&
        results.every((cell) => cell.col != col || cell.row != row)) {
      results.add(VttGridPoint(col, row));
    }
  }
  return results;
}

List<VttGridPoint> _circleCells(
  VttMap map,
  VttGridPoint start,
  VttGridPoint end,
) {
  final radius = math.sqrt(
    math.pow(end.col - start.col, 2) + math.pow(end.row - start.row, 2),
  );
  final cells = <VttGridPoint>[];
  for (var row = 0; row < map.rows; row++) {
    for (var col = 0; col < map.cols; col++) {
      final dc = col - start.col;
      final dr = row - start.row;
      final distance = math.sqrt(dc * dc + dr * dr);
      if (distance <= radius + 0.5) cells.add(VttGridPoint(col, row));
    }
  }
  return cells;
}

List<VttGridPoint> _coneCells(
  VttMap map,
  VttGridPoint start,
  VttGridPoint end,
) {
  final dx = end.col - start.col;
  final dy = end.row - start.row;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length == 0) return <VttGridPoint>[start];
  const halfAngle =
      0.4636476090008061; // atan(0.5) ~ classic 5e cone half-angle
  final directionX = dx / length;
  final directionY = dy / length;
  final cells = <VttGridPoint>[];
  for (var row = 0; row < map.rows; row++) {
    for (var col = 0; col < map.cols; col++) {
      final cx = col - start.col;
      final cy = row - start.row;
      final distance = math.sqrt(cx * cx + cy * cy);
      if (distance > length + 0.5) continue;
      if (distance == 0) {
        cells.add(VttGridPoint(col, row));
        continue;
      }
      final dot = (cx / distance) * directionX + (cy / distance) * directionY;
      final angle = math.acos(dot.clamp(-1, 1));
      if (angle <= halfAngle) cells.add(VttGridPoint(col, row));
    }
  }
  return cells;
}

List<VttGridPoint> _lineCells(
  VttMap map,
  VttGridPoint start,
  VttGridPoint end,
  int width,
) {
  final dx = end.col - start.col;
  final dy = end.row - start.row;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length == 0) return <VttGridPoint>[start];
  final directionX = dx / length;
  final directionY = dy / length;
  final halfWidth = math.max(1, width) / 2;
  final cells = <VttGridPoint>[];
  for (var row = 0; row < map.rows; row++) {
    for (var col = 0; col < map.cols; col++) {
      final cx = col - start.col;
      final cy = row - start.row;
      final projection = cx * directionX + cy * directionY;
      if (projection < -0.5 || projection > length + 0.5) continue;
      final closestX = directionX * projection;
      final closestY = directionY * projection;
      final perpendicular = math.sqrt(
        math.pow(cx - closestX, 2) + math.pow(cy - closestY, 2),
      );
      if (perpendicular <= halfWidth) cells.add(VttGridPoint(col, row));
    }
  }
  return cells;
}

bool _contains(VttMap map, int col, int row) =>
    col >= 0 && row >= 0 && col < map.cols && row < map.rows;
