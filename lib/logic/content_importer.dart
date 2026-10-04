import 'dart:convert';

import 'package:dnd_campaign_manager/logic/backgrounds.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/gear.dart';

/// Binds a top-level JSON key (e.g. "weapons") to:
///  - [parse]: how to turn one JSON object into a catalog item
///  - [apply]: how to add a (cloned) item to a character
///
/// Registering a new binding is all it takes to support a new content type.
class ContentBinding {
  const ContentBinding({
    required this.key,
    required this.label,
    required this.parse,
    required this.apply,
  });

  final String key;
  final String label;
  final CatalogItem Function(Map<String, dynamic> json) parse;
  final void Function(Character character, CatalogItem item) apply;
}

class ContentRegistry {
  final Map<String, ContentBinding> _bindings = {};

  void register(ContentBinding binding) => _bindings[binding.key] = binding;

  /// Registers a schema-less type. Items are stored verbatim and, when added
  /// to a character, appended to `character.extras[key]`.
  void registerGeneric(String key, String label) => register(ContentBinding(
        key: key,
        label: label,
        parse: GenericItem.new,
        apply: (c, item) {
          final list = (c.extras[key] is List)
              ? List<dynamic>.from(c.extras[key])
              : <dynamic>[];
          list.add(item.toJson());
          c.extras[key] = list;
        },
      ));

  ContentBinding? operator [](String key) => _bindings[key];
  List<ContentBinding> get bindings => _bindings.values.toList();
  Iterable<String> get keys => _bindings.keys;
  ContentRegistry();
  factory ContentRegistry.standard() {
    final r = ContentRegistry();
    r.register(ContentBinding(
      key: 'weapons',
      label: 'Weapons',
      parse: Weapon.fromJson,
      apply: (c, i) => c.weapons.add(i as Weapon),
    ));
    r.register(ContentBinding(
      key: 'armor',
      label: 'Armor',
      parse: Armor.fromJson,
      apply: (c, i) => c.armor.add(i as Armor),
    ));
    r.register(ContentBinding(
      key: 'items',
      label: 'Items',
      parse: InventoryItem.fromJson,
      apply: (c, i) => c.items.add(i as InventoryItem),
    ));
    r.register(ContentBinding(
      key: 'traits',
      label: 'Traits',
      parse: (j) => Trait.fromJson(j, defaultCategory: 'trait'),
      apply: (c, i) => c.traits.add(i as Trait),
    ));
    r.register(ContentBinding(
      key: 'features',
      label: 'Features',
      parse: (j) => Trait.fromJson(j, defaultCategory: 'feature'),
      apply: (c, i) => c.traits.add(i as Trait),
    ));
    r.register(ContentBinding(
      key: 'feats',
      label: 'Feats',
      parse: (j) => Trait.fromJson(j, defaultCategory: 'feat'),
      apply: (c, i) => c.traits.add(i as Trait),
    ));
    r.register(ContentBinding(
      key: 'backgrounds',
      label: 'Backgrounds',
      parse: BackgroundDefinition.fromJson,
      apply: (c, i) => applyBackground(c, i as BackgroundDefinition),
    ));
    r.register(ContentBinding(
      key: 'classes',
      label: 'Classes',
      parse: ClassDefinition.new,
      apply: (_, __) => throw UnsupportedError(
        'Classes must be selected through the character level-up flow.',
      ),
    ));
    r.registerGeneric('skills', 'Skills');
    r.registerGeneric('actions', 'Actions');
    r.registerGeneric('ammunitionByCaliber', 'Ammunition by caliber');
    return r;
  }
}

class ImportResult {
  int added = 0;
  int updated = 0;
  final List<String> errors = [];
  final List<String> warnings = [];

  bool get ok => errors.isEmpty;
  String get summary {
    final parts = ['$added added', '$updated updated'];
    if (warnings.isNotEmpty) parts.add('${warnings.length} warning(s)');
    if (errors.isNotEmpty) parts.add('${errors.length} error(s)');
    return parts.join(', ');
  }
}

/// Reads a "content pack" JSON document and merges it into a [Catalog].
///
///   {
///     "pack": "Core Armory",            // optional metadata
///     "weapons":  [ {...}, {...} ],
///     "armor":    [ {...} ],
///     "traits":   [ {...} ],
///     "features": [ {...} ],
///     "backgrounds": [ {...} ]
///   }
class ContentImporter {
  ContentImporter(this.registry);

  final ContentRegistry registry;
  static const _metaKeys = {'schemaVersion', 'pack', 'description', 'author'};

  ImportResult importJson(String text, Catalog catalog) {
    final result = ImportResult();
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      result.errors.add('Invalid JSON: ${e.message}');
      return result;
    }
    if (decoded is! Map) {
      result.errors.add('Top level must be a JSON object.');
      return result;
    }
    loadInto(Map<String, dynamic>.from(decoded), catalog, result);
    return result;
  }

  /// Also used to rebuild the catalog from catalog.json.
  void loadInto(Map<String, dynamic> json, Catalog catalog,
      [ImportResult? result]) {
    final res = result ?? ImportResult();
    for (final entry in json.entries) {
      // Older packs used "affiliations" for the same bundled definition.
      final key = entry.key == 'affiliations' ? 'backgrounds' : entry.key;
      final binding = registry[key];
      if (binding == null) {
        if (!_metaKeys.contains(entry.key)) {
          res.warnings.add('Unknown section "${entry.key}" ignored.');
        }
        continue;
      }
      if (entry.value is! List) {
        res.errors.add('"$key" must be a list.');
        continue;
      }
      final list = entry.value as List;
      for (var i = 0; i < list.length; i++) {
        final raw = list[i];
        if (raw is! Map) {
          res.errors.add('$key[$i] is not an object.');
          continue;
        }
        try {
          final item = binding.parse(Map<String, dynamic>.from(raw));
          if (item.name.trim().isEmpty) {
            res.errors.add('$key[$i] has no "name".');
            continue;
          }
          catalog.upsert(key, item) ? res.updated++ : res.added++;
        } catch (e) {
          res.errors.add('$key[$i]: $e');
        }
      }
    }
  }
}
