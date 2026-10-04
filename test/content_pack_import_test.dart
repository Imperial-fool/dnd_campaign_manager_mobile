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
    expect(catalog.items('affiliations'), hasLength(15));
    expect(catalog.items('weapons'), hasLength(34));
    expect(catalog.items('armor'), hasLength(9));
    expect(catalog.items('items'), hasLength(32));

    final juggernaut =
        classes.singleWhere((definition) => definition.id == 'juggernaut');
    expect(
      juggernaut.featuresAtLevel(1).map((feature) => feature['name']),
      contains('Level 1 Juggernaut progression'),
    );
    expect(
      juggernaut.featuresAtLevel(14).map((feature) => feature['name']),
      contains('Kaban option'),
    );
  });
}
