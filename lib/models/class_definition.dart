import 'package:dnd_campaign_manager/models/gear.dart';
import 'package:dnd_campaign_manager/models/json_utils.dart';

class ClassDefinition implements CatalogItem {
  ClassDefinition(this.data) {
    if (name.trim().isEmpty) {
      throw const FormatException('Class has no "name".');
    }
    if (hitDie < 1 || hitDie > 20) {
      throw const FormatException('"hitDie" must be between 1 and 20.');
    }
    if (subclassLevel < 1 || subclassLevel > 20) {
      throw const FormatException('"subclassLevel" must be between 1 and 20.');
    }
    if (savingThrows.any(
      (key) => !{'str', 'dex', 'con', 'int', 'wis', 'cha'}.contains(key),
    )) {
      throw const FormatException(
          '"savingThrows" entries must be ability keys.');
    }
    _validateLevels(data['levels'], 'levels');
    final featLevels = data['featLevels'];
    if (featLevels != null &&
        (featLevels is! List ||
            featLevels
                .any((level) => level is! int || level < 1 || level > 20))) {
      throw const FormatException('"featLevels" must contain levels 1-20.');
    }
    if (featLevels != null &&
        ![4, 8, 12].every((level) => (featLevels as List).contains(level))) {
      throw const FormatException(
          'Standard feat progression must include levels 4, 8, and 12.');
    }
    final feats = data['feats'];
    if (feats != null && feats is! List) {
      throw const FormatException('"feats" must be a list.');
    }
    for (final feat in feats as List? ?? const []) {
      if (feat is! Map ||
          asStr(feat['id']).trim().isEmpty ||
          asStr(feat['name']).trim().isEmpty) {
        throw const FormatException(
            'Each class feat needs an "id" and "name".');
      }
    }
    for (final level in asMapList(data['levels'])) {
      _validateChoices(level['choices']);
    }
    final rawSubclasses = data['subclasses'];
    if (rawSubclasses != null && rawSubclasses is! List) {
      throw const FormatException('"subclasses" must be a list.');
    }
    for (final subclass in rawSubclasses as List? ?? const []) {
      if (subclass is! Map) {
        throw const FormatException('Each subclass must be an object.');
      }
      final subclassData = Map<String, dynamic>.from(subclass);
      if (asStr(subclassData['name']).trim().isEmpty) {
        throw const FormatException('Each subclass needs a "name".');
      }
      _validateLevels(subclassData['features'], 'subclass features');
      _validateChoices(subclassData['choices'], requireLevel: true);
    }
  }

  final Map<String, dynamic> data;

  @override
  String get id => idFor(data, name);
  @override
  String get name => asStr(data['name'], 'Unnamed');
  int get hitDie => asInt(data['hitDie']);
  int get subclassLevel => asInt(data['subclassLevel'], 3);
  List<String> get savingThrows => _strings(data['savingThrows']);
  List<Map<String, dynamic>> get subclasses => asMapList(data['subclasses']);

  @override
  String get summary => 'd$hitDie hit die · ${subclasses.length} subclass(es)';

  List<Map<String, dynamic>> featuresAtLevel(int level) =>
      asMapList(data['levels'])
          .where((entry) => asInt(entry['level']) == level)
          .expand((entry) => asMapList(entry['features']))
          .toList();

  List<Map<String, dynamic>> choicesAtLevel(
    int level, {
    List<CatalogItem> availableFeats = const [],
  }) {
    final choices = asMapList(data['levels'])
        .where((entry) => asInt(entry['level']) == level)
        .expand((entry) => asMapList(entry['choices']))
        .map((choice) => {
              ...choice,
              'level': level,
              'selectionKey': 'class:$id:level:$level:${asStr(choice['id'])}',
              'selectionOrigin':
                  'class:$id:level:$level:choice:${asStr(choice['id'])}',
            })
        .toList();
    if (_strings(data['featLevels']).contains('$level')) {
      choices.add({
        'id': 'feat',
        'prompt': 'Choose a feat',
        'count': 1,
        'options': [
          for (final feat in availableFeats)
            {
              ...feat.toJson(),
              'id': feat.id,
              'name': feat.name,
              'grantType': 'feat',
              'featId': feat.id,
            }
        ],
        'level': level,
        'selectionKey': 'class:$id:level:$level:feat',
        'selectionOrigin': 'class:$id:level:$level:choice:feat',
      });
    }
    return choices;
  }

  static void _validateLevels(dynamic value, String label) {
    if (value == null) return;
    if (value is! List) throw FormatException('"$label" must be a list.');
    for (final entry in value) {
      if (entry is! Map) {
        throw FormatException('Each "$label" entry must be an object.');
      }
      final map = Map<String, dynamic>.from(entry);
      final level = asInt(map['level']);
      if (level < 1 || level > 20) {
        throw FormatException(
            'Each "$label" entry needs a level from 1 to 20.');
      }
      if (label == 'levels' &&
          map['features'] != null &&
          map['features'] is! List) {
        throw const FormatException('"features" must be a list.');
      }
      if (label == 'subclass features' &&
          map['features'] != null &&
          map['features'] is! List) {
        throw const FormatException('"features" must be a list.');
      }
      final featureList = label == 'levels' ? map['features'] : [map];
      for (final feature in featureList as List? ?? const []) {
        if (feature is! Map || asStr(feature['name']).trim().isEmpty) {
          throw const FormatException('Each class feature needs a "name".');
        }
        if (label == 'subclass features') {
          _validateChoices(feature['choices']);
        }
      }
    }
  }

  static void _validateChoices(dynamic value, {bool requireLevel = false}) {
    if (value == null) return;
    if (value is! List) {
      throw const FormatException('"choices" must be a list.');
    }
    for (final rawChoice in value) {
      if (rawChoice is! Map) {
        throw const FormatException('Each choice must be an object.');
      }
      final choice = Map<String, dynamic>.from(rawChoice);
      if (asStr(choice['id']).trim().isEmpty ||
          asStr(choice['prompt']).trim().isEmpty) {
        throw const FormatException('Each choice needs an "id" and "prompt".');
      }
      if (requireLevel) {
        final level = asInt(choice['level']);
        if (level < 1 || level > 20) {
          throw const FormatException(
              'Each subclass choice needs a level from 1 to 20.');
        }
      }
      final count = asInt(choice['count'], 1);
      final rawOptions = choice['options'];
      if (count < 1 || rawOptions is! List || rawOptions.length < count) {
        throw const FormatException(
            'A choice needs a positive count and at least that many options.');
      }
      final optionIds = <String>{};
      for (final rawOption in rawOptions) {
        if (rawOption is! Map) {
          throw const FormatException('Each choice option must be an object.');
        }
        final option = Map<String, dynamic>.from(rawOption);
        final id = asStr(option['id']);
        if (id.trim().isEmpty ||
            asStr(option['name']).trim().isEmpty ||
            !optionIds.add(id)) {
          throw const FormatException(
              'Choice options need unique, non-empty "id" and "name" fields.');
        }
        final grantType = asStr(option['grantType'], 'feature');
        if (!{'feature', 'feat', 'skill', 'catalog'}.contains(grantType)) {
          throw FormatException('Unsupported choice grantType "$grantType".');
        }
        if (grantType == 'skill' &&
            !{'str', 'dex', 'con', 'int', 'wis', 'cha'}
                .contains(asStr(option['skillAbility']))) {
          throw const FormatException(
              'Skill choice options need a "skillAbility".');
        }
        if (grantType == 'catalog' &&
            (!{'weapons', 'armor', 'items'}
                    .contains(asStr(option['catalogKey'])) ||
                asStr(option['itemId']).trim().isEmpty)) {
          throw const FormatException(
              'Catalog choices need a valid "catalogKey" and "itemId".');
        }
      }
    }
  }

  static List<String> _strings(dynamic value) =>
      value is List ? value.map((item) => item.toString()).toList() : [];

  @override
  Map<String, dynamic> toJson() => Map<String, dynamic>.from(data);
}

class ClassSubclass {
  ClassSubclass(this.data);

  final Map<String, dynamic> data;

  String get id => idFor(data, name);
  String get name => asStr(data['name'], 'Unnamed');
  String get description => asStr(data['description']);

  List<Map<String, dynamic>> featuresAtLevel(int level) =>
      asMapList(data['features'])
          .where((feature) => asInt(feature['level']) == level)
          .toList();

  List<Map<String, dynamic>> choicesAtLevel(int level, String classId) =>
      asMapList(data['choices'])
          .where((choice) => asInt(choice['level']) == level)
          .map((choice) => {
                ...choice,
                'selectionKey':
                    'subclass:$classId:$id:level:$level:${asStr(choice['id'])}',
                'selectionOrigin':
                    'subclass:$classId:$id:level:$level:choice:${asStr(choice['id'])}',
              })
          .toList();
}

ClassSubclass? subclassById(ClassDefinition classDefinition, String id) {
  for (final data in classDefinition.subclasses) {
    final subclass = ClassSubclass(data);
    if (subclass.id == id) return subclass;
  }
  return null;
}
