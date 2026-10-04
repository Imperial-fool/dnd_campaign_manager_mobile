import 'gear.dart';
import 'json_utils.dart';

/// Campaign-wide library of weapons, armor, traits, features (and anything
/// else a content binding registers). Stored as one JSON file:
///   { "weapons": [...], "armor": [...], "traits": [...], "features": [...] }
class Catalog {
  final Map<String, List<CatalogItem>> _items = {};

  List<CatalogItem> items(String key) => List.unmodifiable(_items[key] ?? const []);

  String _idOf(CatalogItem i) => i.id.isEmpty ? slug(i.name) : i.id;

  /// Inserts or replaces by id. Returns true if an existing item was replaced.
  bool upsert(String key, CatalogItem item) {
    final list = _items.putIfAbsent(key, () => []);
    final i = list.indexWhere((e) => _idOf(e) == _idOf(item));
    if (i >= 0) {
      list[i] = item;
      return true;
    }
    list.add(item);
    return false;
  }

  void remove(String key, String id) =>
      _items[key]?.removeWhere((e) => _idOf(e) == id);

  Map<String, dynamic> toJson() => {
        for (final e in _items.entries) e.key: e.value.map((i) => i.toJson()).toList(),
      };
}
