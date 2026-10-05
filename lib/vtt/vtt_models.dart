/// Plain data models for the VTT-lite board. No Flutter or Firebase imports.
int _int(dynamic v, int fallback) => v is num ? v.toInt() : fallback;
String _str(dynamic v, [String fallback = '']) => v is String ? v : fallback;
bool _bool(dynamic v, [bool fallback = false]) => v is bool ? v : fallback;

enum VttEdgeType { wall, door, window }

enum VttDiagonalRule { simple, alternating, euclidean }

VttEdgeType _edgeType(dynamic raw) {
  if (raw is String) {
    for (final value in VttEdgeType.values) {
      if (value.name == raw) return value;
    }
  }
  final index = _int(raw, 0);
  if (index >= 0 && index < VttEdgeType.values.length) {
    return VttEdgeType.values[index];
  }
  return VttEdgeType.wall;
}

VttDiagonalRule _diagonalRule(dynamic raw) {
  if (raw is String) {
    for (final value in VttDiagonalRule.values) {
      if (value.name == raw) return value;
    }
  }
  final index = _int(raw, 0);
  if (index >= 0 && index < VttDiagonalRule.values.length) {
    return VttDiagonalRule.values[index];
  }
  return VttDiagonalRule.simple;
}

List<String> _normalizeTerrain(
  dynamic rawTerrain,
  int cols,
  int rows,
) {
  final source = rawTerrain is List ? rawTerrain : const <dynamic>[];
  return List<String>.generate(rows, (row) {
    final raw = row < source.length && source[row] is String
        ? source[row] as String
        : '';
    final buffer = StringBuffer();
    for (var col = 0; col < cols; col++) {
      final char = col < raw.length ? raw[col] : '.';
      final isPalette = char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 55;
      buffer.write(char == '.' || isPalette ? char : '.');
    }
    return buffer.toString();
  });
}

/// A tile that moves a token to [targetMapId] at ([targetCol], [targetRow]).
class VttPortal {
  const VttPortal({
    required this.col,
    required this.row,
    required this.targetMapId,
    this.targetCol = 0,
    this.targetRow = 0,
    this.label = '',
  });

  final int col;
  final int row;
  final String targetMapId;
  final int targetCol;
  final int targetRow;
  final String label;

  factory VttPortal.fromJson(Map<String, dynamic> j) => VttPortal(
        col: _int(j['col'], 0),
        row: _int(j['row'], 0),
        targetMapId: _str(j['targetMapId']),
        targetCol: _int(j['targetCol'], 0),
        targetRow: _int(j['targetRow'], 0),
        label: _str(j['label']),
      );

  Map<String, dynamic> toJson() => {
        'col': col,
        'row': row,
        'targetMapId': targetMapId,
        'targetCol': targetCol,
        'targetRow': targetRow,
        'label': label,
      };
}

class VttEdge {
  VttEdge({
    required this.col,
    required this.row,
    required this.horizontal,
    this.type = VttEdgeType.wall,
    this.locked = false,
  });

  final int col;
  final int row;
  final bool horizontal;
  VttEdgeType type;
  bool locked;

  String get key => '${horizontal ? 'h' : 'v'}:$col:$row';

  factory VttEdge.fromJson(Map<String, dynamic> j) => VttEdge(
        col: _int(j['col'] ?? j['c'], 0),
        row: _int(j['row'] ?? j['r'], 0),
        horizontal: _bool(j['horizontal'] ?? j['h']),
        type: _edgeType(j['type'] ?? j['t']),
        locked: _bool(j['locked'] ?? j['l']),
      );

  Map<String, dynamic> toJson() => {
        'col': col,
        'row': row,
        'horizontal': horizontal,
        'type': type.index,
        'locked': locked,
      };
}

/// A square-grid map layer. An overworld is simply a (usually larger) map whose
/// portals lead to smaller local maps, which may portal back.
class VttMap {
  VttMap({
    required this.id,
    this.name = 'Map',
    this.cols = 20,
    this.rows = 20,
    this.isOverworld = false,
    List<VttPortal>? portals,
    List<VttEdge>? edges,
    List<String>? terrain,
    this.feetPerCell = 5,
    this.showGrid = true,
    this.hasImage = false,
    this.imageVersion = 0,
    this.diagonalRule = VttDiagonalRule.simple,
  })  : portals = portals ?? <VttPortal>[],
        edges = edges ?? <VttEdge>[],
        terrain = _normalizeTerrain(terrain, cols, rows);

  static const int maxDimension = 100;
  static const int maxPortals = 100;
  static const int maxEdges = 5000;
  static const List<int> terrainPalette = <int>[
    0xFF7A756F,
    0xFF7B5B3A,
    0xFF4F8A3C,
    0xFF2B6CB0,
    0xFFDDBA75,
    0xFFF3F6FB,
    0xFFD94A1E,
    0xFF111317,
  ];

  final String id;
  String name;
  int cols;
  int rows;
  bool isOverworld;
  List<VttPortal> portals;
  List<VttEdge> edges;
  List<String> terrain;
  int feetPerCell;
  bool showGrid;
  bool hasImage;
  int imageVersion;
  VttDiagonalRule diagonalRule;

  bool contains(int col, int row) =>
      col >= 0 && row >= 0 && col < cols && row < rows;

  VttPortal? portalAt(int col, int row) {
    for (final portal in portals) {
      if (portal.col == col && portal.row == row) return portal;
    }
    return null;
  }

  VttEdge? edgeAt(String key) {
    for (final edge in edges) {
      if (edge.key == key) return edge;
    }
    return null;
  }

  factory VttMap.fromJson(Map<String, dynamic> j) {
    final cols = _int(j['cols'], 20).clamp(1, maxDimension);
    final rows = _int(j['rows'], 20).clamp(1, maxDimension);
    return VttMap(
      id: _str(j['id']),
      name: _str(j['name'], 'Map'),
      cols: cols,
      rows: rows,
      isOverworld: j['isOverworld'] == true,
      portals: [
        if (j['portals'] is List)
          for (final p in (j['portals'] as List))
            if (p is Map) VttPortal.fromJson(Map<String, dynamic>.from(p)),
      ],
      edges: [
        if (j['edges'] is List)
          for (final e in (j['edges'] as List))
            if (e is Map) VttEdge.fromJson(Map<String, dynamic>.from(e)),
      ],
      terrain: _normalizeTerrain(j['terrain'], cols, rows),
      feetPerCell: _int(j['feetPerCell'], 5).clamp(1, 100),
      showGrid: j['showGrid'] is bool ? j['showGrid'] as bool : true,
      hasImage: j['hasImage'] == true,
      imageVersion: _int(j['imageVersion'], 0).clamp(0, 1 << 30),
      diagonalRule: _diagonalRule(j['diagonalRule']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cols': cols,
        'rows': rows,
        'isOverworld': isOverworld,
        'portals': portals.map((p) => p.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'terrain': _normalizeTerrain(terrain, cols, rows),
        'feetPerCell': feetPerCell,
        'showGrid': showGrid,
        'hasImage': hasImage,
        'imageVersion': imageVersion,
        'diagonalRule': diagonalRule.index,
      };
}

class VttToken {
  VttToken({
    required this.id,
    required this.mapId,
    this.name = 'Token',
    this.col = 0,
    this.row = 0,
    this.kind = 'npc',
    this.color = 0xFF8D6E63,
    this.characterId,
    this.ownerUid,
    this.hidden = false,
    this.initiative,
  });

  final String id;
  String mapId;
  String name;
  int col;
  int row;

  /// 'pc' or 'npc'.
  String kind;

  /// ARGB colour value.
  int color;
  String? characterId;

  /// Firebase uid of the player allowed to move this token (null = DM only).
  String? ownerUid;

  /// Hidden tokens are never delivered to players.
  bool hidden;

  /// Null means "not in the initiative order".
  int? initiative;

  factory VttToken.fromJson(Map<String, dynamic> j) => VttToken(
        id: _str(j['id']),
        mapId: _str(j['mapId']),
        name: _str(j['name'], 'Token'),
        col: _int(j['col'], 0),
        row: _int(j['row'], 0),
        kind: _str(j['kind'], 'npc'),
        color: _int(j['color'], 0xFF8D6E63),
        characterId:
            j['characterId'] is String ? j['characterId'] as String : null,
        ownerUid: j['ownerUid'] is String ? j['ownerUid'] as String : null,
        hidden: j['hidden'] == true,
        initiative:
            j['initiative'] is num ? (j['initiative'] as num).toInt() : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'mapId': mapId,
        'name': name,
        'col': col,
        'row': row,
        'kind': kind,
        'color': color,
        'characterId': characterId,
        'ownerUid': ownerUid,
        'hidden': hidden,
        'initiative': initiative,
      };
}

/// Shared combat/turn state. The order itself is derived from token
/// initiatives (see `VttController.initiativeOrder`).
class VttCombat {
  const VttCombat({this.active = false, this.round = 1, this.turnTokenId});

  final bool active;
  final int round;
  final String? turnTokenId;

  factory VttCombat.fromJson(Map<String, dynamic> j) => VttCombat(
        active: j['active'] == true,
        round: _int(j['round'], 1),
        turnTokenId:
            j['turnTokenId'] is String ? j['turnTokenId'] as String : null,
      );

  Map<String, dynamic> toJson() => {
        'active': active,
        'round': round,
        'turnTokenId': turnTokenId,
      };
}
