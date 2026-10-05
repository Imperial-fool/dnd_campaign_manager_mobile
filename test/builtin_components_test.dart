import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_campaign_manager/models/builtin_components.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/sheet_template.dart';

void main() {
  test('built-in components are valid and round-trip', () {
    for (final b in builtinComponents) {
      final t = SheetTemplate.fromJson(b.build().toJson());
      expect(t.fields, isNotEmpty, reason: b.name);
      expect(SheetEvaluator(Character(id: 'x'), t).validate(), isNull,
          reason: b.name);
    }
  });
}
