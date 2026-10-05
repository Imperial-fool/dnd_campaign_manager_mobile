import 'package:dnd_campaign_manager/logic/formula.dart';
import 'package:dnd_campaign_manager/models/character.dart';
import 'package:dnd_campaign_manager/models/sheet_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FormulaEngine engine({Map<String, num> vars = const {}, int Function(int)? die}) =>
      FormulaEngine(resolve: (n) => vars[n], rollDie: die ?? (s) => s);

  test('arithmetic and functions', () {
    final e = engine(vars: {'str_mod': 3});
    expect(e.evaluate('2 + 3 * 4'), 14);
    expect(e.evaluate('floor((str_mod + 1) / 3)'), 1);
    expect(e.evaluate('if(str_mod > 2, 10, 0)'), 10);
    expect(e.evaluate('-max(1, 4) + 10'), 6);
  });

  test('bullet die template rolls count then damage dice', () {
    final e = engine(vars: {'str_mod': 2}, die: (s) => 3);
    expect(e.resolveTemplate('{1d6}d8+{str_mod}'), '3d8+2');
  });

  test('errors are FormatExceptions', () {
    final e = engine();
    expect(() => e.evaluate('foo + 1'), throwsFormatException);
    expect(() => e.evaluate('1 / 0'), throwsFormatException);
    expect(() => e.evaluate('1 +'), throwsFormatException);
    expect(() => e.resolveTemplate('{1'), throwsFormatException);
  });

  test('sheet calc fields reference other fields and detect cycles', () {
    final c = Character(id: 'x');
    final t = SheetTemplate.fromJson({
      'name': 'T',
      'fields': [
        {'key': 'base', 'type': 'number', 'default': '4'},
        {'key': 'double', 'type': 'calc', 'formula': 'base * 2 + prof'},
        {'key': 'a', 'type': 'calc', 'formula': 'b'},
        {'key': 'b', 'type': 'calc', 'formula': 'a'},
      ],
    });
    final ev = SheetEvaluator(c, t);
    expect(ev.calc(t.fields[1]), 10);
    expect(() => ev.calc(t.fields[2]), throwsFormatException);
    expect(ev.validate(), isNotNull);
    ev.setValue(t.fields[0], 10);
    expect(ev.calc(t.fields[1]), 22);
  });
}
