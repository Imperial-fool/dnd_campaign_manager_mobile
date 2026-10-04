import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_campaign_manager/logic/content_importer.dart';
import 'package:dnd_campaign_manager/models/catalog.dart';
import 'package:dnd_campaign_manager/models/class_definition.dart';

void main() {
  test('Tarkov pack imports from its standalone JSON file', () {
    final json =
        File('content/tarkov_character_options.json').readAsStringSync();
    final catalog = Catalog();
    final result =
        ContentImporter(ContentRegistry.standard()).importJson(json, catalog);

    expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    final classes =
        catalog.items('classes').whereType<ClassDefinition>().toList();
    expect(classes, hasLength(4));
    expect(catalog.items('backgrounds'), hasLength(15));
    expect(catalog.items('weapons'), hasLength(34));
    expect(catalog.items('armor'), hasLength(9));
    expect(catalog.items('items'), hasLength(32));

    final juggernaut =
        classes.singleWhere((definition) => definition.id == 'juggernaut');
    expect(
      juggernaut.featuresAtLevel(1).map((feature) => feature['name']),
      containsAll(['Strong Arm', 'Suppressive Fire']),
    );
    expect(
      juggernaut.featuresAtLevel(14).map((feature) => feature['name']),
      contains('Kaban option'),
    );

    final scout = classes.singleWhere((definition) => definition.id == 'scout');
    final unarmoredDefense = scout
        .featuresAtLevel(1)
        .singleWhere((feature) => feature['name'] == 'Unarmored Defense');
    expect(unarmoredDefense['effects'], [
      {
        'target': 'ac',
        'value': 10,
        'components': [
          {'ability': 'dex', 'calculation': 'modifier'},
          {'ability': 'wis', 'calculation': 'modifier'},
        ],
        'condition': 'noBallisticProtection',
        'operation': 'setBase',
      }
    ]);

    final cqb = classes.singleWhere((definition) => definition.id == 'cqb');
    final virtuoso =
        cqb.subclasses.singleWhere((subclass) => subclass['id'] == 'virtuoso');
    final choices = virtuoso['choices'] as List;
    expect(choices, hasLength(5));
    expect(
      choices.map((choice) => (choice as Map)['options'] as List),
      everyElement(hasLength(3)),
    );
    final enforcer =
        cqb.subclasses.singleWhere((subclass) => subclass['id'] == 'enforcer');
    expect(
      ClassSubclass(enforcer)
          .featuresAtLevel(6)
          .map((feature) => feature['name']),
      containsAll(['Weapon Jam Aura', 'Martial Artist']),
    );
  });

  test('legacy affiliation sections import as backgrounds', () {
    final catalog = Catalog();
    final result = ContentImporter(ContentRegistry.standard()).importJson(
      '{"affiliations":[{"id":"fsb","name":"FSB"}]}',
      catalog,
    );

    expect(result.errors, isEmpty, reason: result.errors.join('\n'));
    expect(catalog.items('backgrounds'), hasLength(1));
    expect(catalog.toJson().containsKey('backgrounds'), isTrue);
    expect(catalog.toJson().containsKey('affiliations'), isFalse);
  });
}
