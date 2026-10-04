/// Tolerant JSON readers so hand-edited or partial files never crash the app.
int asInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

String asStr(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

List<Map<String, dynamic>> asMapList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

/// "Sleight of Hand" -> "sleight_of_hand". Used for ids and effect targets.
String slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

String idFor(Map<String, dynamic> json, String name) {
  final id = asStr(json['id']);
  return id.isEmpty ? slug(name) : id;
}
