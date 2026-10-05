import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dnd_campaign_manager/vtt/vtt_geometry.dart';
import 'package:dnd_campaign_manager/vtt/vtt_image.dart';
import 'package:dnd_campaign_manager/vtt/vtt_models.dart';

class VttImportResult {
  const VttImportResult({
    required this.maps,
    required this.tokensImported,
    required this.warnings,
  });

  final List<VttMap> maps;
  final int tokensImported;
  final List<String> warnings;
}

class VttImportedMapData {
  const VttImportedMapData({
    required this.map,
    this.imageBytes,
    this.openDoors = const <String>{},
  });

  final VttMap map;
  final Uint8List? imageBytes;
  final Set<String> openDoors;
}

class VttParsedImport {
  const VttParsedImport({
    required this.maps,
    required this.tokens,
    required this.warnings,
  });

  final List<VttImportedMapData> maps;
  final List<VttToken> tokens;
  final List<String> warnings;
}

Future<Uint8List> exportNativeVttMapBundle({
  required List<VttMap> maps,
  required Map<String, Uint8List?> images,
  Map<String, Set<String>> doorStates = const <String, Set<String>>{},
  List<VttToken> tokens = const <VttToken>[],
  bool includeTokens = false,
  bool includeDoorStates = true,
}) async {
  final encodedMaps = <Map<String, dynamic>>[];
  for (final map in maps) {
    final imageBytes = images[map.id];
    encodedMaps.add(<String, dynamic>{
      'map': map.toJson(),
      if (includeDoorStates) 'doorStates': doorStates[map.id]?.toList() ?? <String>[],
      'image': imageBytes == null
          ? null
          : <String, dynamic>{
              'mime': 'image/jpeg',
              'data': base64Encode(imageBytes),
            },
    });
  }
  final payload = <String, dynamic>{
    'format': 'dnd_campaign_manager.vttmap',
    'version': 1,
    'maps': encodedMaps,
    if (includeTokens)
      'tokens': tokens
          .map(
            (token) => <String, dynamic>{
              ...token.toJson(),
              'ownerUid': null,
              'characterId': null,
            },
          )
          .toList(),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
}

Future<VttParsedImport> parseImportedVttData(
  Uint8List bytes, {
  String? fileName,
}) async {
  if (bytes.lengthInBytes > 25 * 1024 * 1024) {
    throw const FormatException('Import files must be 25 MB or smaller.');
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    throw const FormatException('That file is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('That file does not contain a valid map bundle.');
  }
  if (decoded['format'] == 'dnd_campaign_manager.vttmap') {
    return _parseNativeBundle(decoded);
  }
  return _parseDd2vtt(decoded, fileName: fileName);
}

Future<Uint8List> exportDd2vttMap({
  required VttMap map,
  required Set<String> openDoors,
  Uint8List? imageBytes,
}) async {
  final pixelsPerGrid = imageBytes == null
      ? 70
      : math.max(1, (imageSize(imageBytes).width / math.max(1, map.cols)).round());
  final lineOfSight = <List<Map<String, num>>>[];
  for (final type in <VttEdgeType>[VttEdgeType.wall, VttEdgeType.window]) {
    lineOfSight.addAll(
      _mergeEdgesForExport(
        map.edges.where((edge) => edge.type == type).toList(growable: false),
        pixelsPerGrid,
      ),
    );
  }
  final portals = <Map<String, dynamic>>[];
  for (final edge in map.edges.where((edge) => edge.type == VttEdgeType.door)) {
    final bounds = edge.horizontal
        ? [
            {'x': edge.col * pixelsPerGrid, 'y': edge.row * pixelsPerGrid},
            {'x': (edge.col + 1) * pixelsPerGrid, 'y': edge.row * pixelsPerGrid},
          ]
        : [
            {'x': edge.col * pixelsPerGrid, 'y': edge.row * pixelsPerGrid},
            {'x': edge.col * pixelsPerGrid, 'y': (edge.row + 1) * pixelsPerGrid},
          ];
    portals.add(<String, dynamic>{
      'bounds': bounds,
      'closed': !openDoors.contains(edge.key),
    });
  }
  final payload = <String, dynamic>{
    'format': 0.3,
    'resolution': <String, dynamic>{
      'map_size': <String, int>{'x': map.cols, 'y': map.rows},
      'pixels_per_grid': pixelsPerGrid,
    },
    'line_of_sight': lineOfSight,
    'portals': portals,
    if (imageBytes != null) 'image': base64Encode(imageBytes),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
}

Future<VttParsedImport> _parseNativeBundle(Map<String, dynamic> decoded) async {
  final rawMaps = decoded['maps'];
  if (rawMaps is! List || rawMaps.isEmpty) {
    throw const FormatException('The map bundle does not contain any maps.');
  }
  if (rawMaps.length > 20) {
    throw const FormatException('A single import can contain at most 20 maps.');
  }
  final maps = <VttImportedMapData>[];
  final mapIds = <String>{};
  final warnings = <String>[];
  for (final raw in rawMaps) {
    if (raw is! Map) continue;
    final entry = Map<String, dynamic>.from(raw);
    final mapJson = entry['map'];
    if (mapJson is! Map) {
      throw const FormatException('One of the maps in this bundle is malformed.');
    }
    final rawMapId = mapJson['id'];
    if (rawMapId is! String || rawMapId.isEmpty) {
      throw const FormatException('One of the maps in this bundle is missing its id.');
    }
    if (!mapIds.add(rawMapId)) {
      throw FormatException('The map bundle contains a duplicate map id: $rawMapId');
    }
    final map = VttMap.fromJson(Map<String, dynamic>.from(mapJson));
    _validateImportedMap(map);
    Uint8List? imageBytes;
    final image = entry['image'];
    if (image is Map && image['data'] is String) {
      imageBytes = await prepareMapImage(
        Uint8List.fromList(base64Decode(image['data'] as String)),
      );
    }
    final openDoors = <String>{
      if (entry['doorStates'] is List)
        for (final value in entry['doorStates'] as List)
          if (value is String) value,
    };
    maps.add(
      VttImportedMapData(
        map: map,
        imageBytes: imageBytes,
        openDoors: openDoors,
      ),
    );
  }
  for (final entry in maps) {
    entry.map.portals.removeWhere((portal) => !mapIds.contains(portal.targetMapId));
  }

  final tokens = <VttToken>[];
  final seenTokenIds = <String>{};
  final rawTokens = decoded['tokens'];
  if (rawTokens is List) {
    for (final raw in rawTokens) {
      if (raw is! Map) continue;
      final token = VttToken.fromJson(Map<String, dynamic>.from(raw));
      if (!seenTokenIds.add(token.id)) {
        warnings.add('Dropped duplicate token id "${token.id}" from the import bundle.');
        continue;
      }
      token.ownerUid = null;
      token.characterId = null;
      if (mapIds.contains(token.mapId)) {
        tokens.add(token);
      }
    }
  }
  return VttParsedImport(maps: maps, tokens: tokens, warnings: warnings);
}

Future<VttParsedImport> _parseDd2vtt(
  Map<String, dynamic> decoded, {
  String? fileName,
}) async {
  final resolution = decoded['resolution'];
  if (resolution is! Map) {
    throw const FormatException('The dd2vtt file is missing its resolution block.');
  }
  final mapSize = resolution['map_size'];
  final cols = mapSize is Map ? _validatedPositiveInt(mapSize['x']) : null;
  final rows = mapSize is Map ? _validatedPositiveInt(mapSize['y']) : null;
  final pixelsPerGrid = _validatedPositiveInt(resolution['pixels_per_grid']);
  if (cols == null || rows == null || pixelsPerGrid == null) {
    throw const FormatException('The dd2vtt resolution block is invalid.');
  }
  if (cols < 1 || rows < 1 || cols > VttMap.maxDimension || rows > VttMap.maxDimension) {
    throw const FormatException('The dd2vtt grid size is out of range.');
  }
  if (pixelsPerGrid < 1 || pixelsPerGrid > 4096) {
    throw const FormatException('The dd2vtt pixels-per-grid value is out of range.');
  }
  final map = VttMap(
    id: 'imported-map',
    name: fileName ?? 'Imported map',
    cols: cols,
    rows: rows,
  );
  final warnings = <String>[];
  var approximations = 0;

  final rawLos = decoded['line_of_sight'];
  if (rawLos is List) {
    for (final polyline in rawLos) {
      final points = _readDd2vttPoints(polyline);
      for (var i = 0; i + 1 < points.length; i++) {
        final start = points[i];
        final end = points[i + 1];
        final startCorner = _snapCorner(start, pixelsPerGrid);
        final endCorner = _snapCorner(end, pixelsPerGrid);
        if (!_cornerInBounds(startCorner, cols, rows) ||
            !_cornerInBounds(endCorner, cols, rows)) {
          warnings.add('Skipped an out-of-bounds line-of-sight segment.');
          continue;
        }
        final exact = edgesOnLine(
          startCorner.col,
          startCorner.row,
          endCorner.col,
          endCorner.row,
          type: VttEdgeType.wall,
        );
        if (exact.isNotEmpty) {
          if (!_addEdgesWithCap(map.edges, exact, warnings)) {
            break;
          }
        } else {
          final stair = _staircaseEdges(startCorner, endCorner);
          approximations += stair.length;
          if (!_addEdgesWithCap(map.edges, stair, warnings)) {
            break;
          }
        }
      }
      if (map.edges.length >= VttMap.maxEdges) {
        break;
      }
    }
  }

  final openDoors = <String>{};
  final rawPortals = decoded['portals'];
  if (rawPortals is List) {
    for (final raw in rawPortals) {
      if (raw is! Map) continue;
      final bounds = _readDd2vttPoints(raw['bounds']);
      if (bounds.length < 2) continue;
      final startCorner = _snapCorner(bounds.first, pixelsPerGrid);
      final endCorner = _snapCorner(bounds.last, pixelsPerGrid);
      if (!_cornerInBounds(startCorner, cols, rows) ||
          !_cornerInBounds(endCorner, cols, rows)) {
        warnings.add('Skipped an out-of-bounds door segment.');
        continue;
      }
      final edges = edgesOnLine(
        startCorner.col,
        startCorner.row,
        endCorner.col,
        endCorner.row,
        type: VttEdgeType.door,
      );
      if (edges.isEmpty) continue;
      final originalLength = map.edges.length;
      final allAdded = _addEdgesWithCap(map.edges, edges, warnings);
      final addedEdges = map.edges.skip(originalLength);
      if (raw['closed'] != true) {
        for (final edge in addedEdges) {
          openDoors.add(edge.key);
        }
      }
      if (!allAdded) break;
    }
  }

  _dedupeEdges(map);
  _validateImportedMap(map);

  Uint8List? imageBytes;
  if (decoded['image'] is String) {
    imageBytes = await prepareMapImage(
      Uint8List.fromList(base64Decode(decoded['image'] as String)),
    );
  }
  if (approximations > 0) {
    warnings.add('Approximated $approximations diagonal line-of-sight segments.');
  }
  warnings.add('dd2vtt lights are ignored.');
  return VttParsedImport(
    maps: <VttImportedMapData>[
      VttImportedMapData(
        map: map,
        imageBytes: imageBytes,
        openDoors: openDoors,
      ),
    ],
    tokens: const <VttToken>[],
    warnings: warnings,
  );
}

List<Map<String, num>> _readDd2vttPoints(dynamic raw) {
  if (raw is! List) return const <Map<String, num>>[];
  final points = <Map<String, num>>[];
  for (final entry in raw) {
    if (entry is Map && entry['x'] is num && entry['y'] is num) {
      final x = (entry['x'] as num).toDouble();
      final y = (entry['y'] as num).toDouble();
      if (x.isFinite && y.isFinite) {
        points.add({'x': x, 'y': y});
      }
    }
  }
  return points;
}

({int col, int row}) _snapCorner(Map<String, num> point, int pixelsPerGrid) {
  final x = (point['x'] ?? 0).toDouble() / pixelsPerGrid;
  final y = (point['y'] ?? 0).toDouble() / pixelsPerGrid;
  return (col: x.round(), row: y.round());
}

List<VttEdge> _staircaseEdges(
  ({int col, int row}) start,
  ({int col, int row}) end,
) {
  final edges = <VttEdge>[];
  var current = start;
  final dx = end.col - start.col;
  final dy = end.row - start.row;
  final steps = math.max(dx.abs(), dy.abs());
  for (var i = 0; i < steps; i++) {
    final target = (
      col: start.col + ((i + 1) * dx / steps).round(),
      row: start.row + ((i + 1) * dy / steps).round(),
    );
    if (current.col != target.col) {
      edges.addAll(
        edgesOnLine(
          current.col,
          current.row,
          target.col,
          current.row,
          type: VttEdgeType.wall,
        ),
      );
      current = (col: target.col, row: current.row);
    }
    if (current.row != target.row) {
      edges.addAll(
        edgesOnLine(
          current.col,
          current.row,
          current.col,
          target.row,
          type: VttEdgeType.wall,
        ),
      );
      current = (col: current.col, row: target.row);
    }
  }
  return edges;
}

void _validateImportedMap(VttMap map) {
  if (map.cols < 1 || map.cols > VttMap.maxDimension) {
    throw const FormatException('A map in this file has too many columns.');
  }
  if (map.rows < 1 || map.rows > VttMap.maxDimension) {
    throw const FormatException('A map in this file has too many rows.');
  }
  if (map.edges.length > VttMap.maxEdges) {
    throw const FormatException('A map in this file has too many edges.');
  }
}

void _dedupeEdges(VttMap map) {
  final byKey = <String, VttEdge>{};
  for (final edge in map.edges) {
    byKey[edge.key] = edge;
  }
  map.edges = byKey.values.toList(growable: false);
}

List<List<Map<String, num>>> _mergeEdgesForExport(
  List<VttEdge> edges,
  int pixelsPerGrid,
) {
  final result = <List<Map<String, num>>>[];
  final horizontal = <int, List<VttEdge>>{};
  final vertical = <int, List<VttEdge>>{};
  for (final edge in edges) {
    if (edge.horizontal) {
      horizontal.putIfAbsent(edge.row, () => <VttEdge>[]).add(edge);
    } else {
      vertical.putIfAbsent(edge.col, () => <VttEdge>[]).add(edge);
    }
  }
  for (final entry in horizontal.entries) {
    entry.value.sort((a, b) => a.col.compareTo(b.col));
    var start = entry.value.first.col;
    var last = start;
    for (var i = 1; i < entry.value.length; i++) {
      final edge = entry.value[i];
      if (edge.col == last + 1) {
        last = edge.col;
        continue;
      }
      result.add(_polylineHorizontal(start, last + 1, entry.key, pixelsPerGrid));
      start = edge.col;
      last = edge.col;
    }
    result.add(_polylineHorizontal(start, last + 1, entry.key, pixelsPerGrid));
  }
  for (final entry in vertical.entries) {
    entry.value.sort((a, b) => a.row.compareTo(b.row));
    var start = entry.value.first.row;
    var last = start;
    for (var i = 1; i < entry.value.length; i++) {
      final edge = entry.value[i];
      if (edge.row == last + 1) {
        last = edge.row;
        continue;
      }
      result.add(_polylineVertical(entry.key, start, last + 1, pixelsPerGrid));
      start = edge.row;
      last = edge.row;
    }
    result.add(_polylineVertical(entry.key, start, last + 1, pixelsPerGrid));
  }
  return result;
}

List<Map<String, num>> _polylineHorizontal(
  int startCol,
  int endCol,
  int row,
  int pixelsPerGrid,
) {
  return <Map<String, num>>[
    {'x': startCol * pixelsPerGrid, 'y': row * pixelsPerGrid},
    {'x': endCol * pixelsPerGrid, 'y': row * pixelsPerGrid},
  ];
}

List<Map<String, num>> _polylineVertical(
  int col,
  int startRow,
  int endRow,
  int pixelsPerGrid,
) {
  return <Map<String, num>>[
    {'x': col * pixelsPerGrid, 'y': startRow * pixelsPerGrid},
    {'x': col * pixelsPerGrid, 'y': endRow * pixelsPerGrid},
  ];
}

bool _cornerInBounds(({int col, int row}) corner, int cols, int rows) =>
    corner.col >= 0 &&
    corner.row >= 0 &&
    corner.col <= cols &&
    corner.row <= rows;

bool _addEdgesWithCap(
  List<VttEdge> destination,
  List<VttEdge> source,
  List<String> warnings,
) {
  final remaining = VttMap.maxEdges - destination.length;
  if (remaining <= 0) {
    if (!warnings.contains('Reached the maximum number of edges; extra geometry was skipped.')) {
      warnings.add('Reached the maximum number of edges; extra geometry was skipped.');
    }
    return false;
  }
  if (source.length > remaining) {
    destination.addAll(source.take(remaining));
    _addEdgeCapWarning(warnings);
    return false;
  }
  destination.addAll(source);
  if (destination.length >= VttMap.maxEdges) {
    _addEdgeCapWarning(warnings);
    return false;
  }
  return true;
}

void _addEdgeCapWarning(List<String> warnings) {
  const message = 'Reached the maximum number of edges; extra geometry was skipped.';
  if (!warnings.contains(message)) {
    warnings.add(message);
  }
}

int? _validatedPositiveInt(dynamic value) {
  if (value is! num) return null;
  final asDouble = value.toDouble();
  if (!asDouble.isFinite) return null;
  if (asDouble != asDouble.roundToDouble()) return null;
  return asDouble.toInt();
}
