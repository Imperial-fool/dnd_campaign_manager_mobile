import 'dart:math';

import 'package:dnd_campaign_manager/logic/rules.dart';
import 'package:dnd_campaign_manager/models/ability.dart';
import 'package:dnd_campaign_manager/models/character.dart';

/// Resolves a variable name to a number, or null when unknown.
typedef VariableResolver = num? Function(String name);

/// Small, safe expression language for data-driven calculations.
///
///  - numbers, `+ - * / %`, parentheses, comparisons (`< > <= >= == !=`)
///  - dice literals like `1d6` (rolled when evaluated)
///  - functions: floor ceil round abs min max clamp if(cond, a, b)
///  - variables supplied by a [VariableResolver] (e.g. `str_mod`, `level`)
///
/// Dice templates embed expressions in braces: `{1d6}d8+{str_mod}` rolls a
/// d6 to decide how many d8 are rolled (the "bullet die" pattern).
class FormulaEngine {
  FormulaEngine({required this.resolve, int Function(int sides)? rollDie})
      : _rollDie = rollDie ?? ((sides) => Random().nextInt(sides) + 1);

  final VariableResolver resolve;
  final int Function(int sides) _rollDie;

  static const _maxDice = 1000;

  /// Evaluates [source] and rounds down to an integer.
  int evaluate(String source) {
    final parser = _Parser(source, this);
    final value = parser.parse();
    if (value.isNaN || value.isInfinite) {
      throw const FormatException('Formula did not produce a number.');
    }
    return value.floor();
  }

  /// Replaces every `{expression}` in [template] with its integer result.
  String resolveTemplate(String template) {
    if (!template.contains('{')) return template;
    final out = StringBuffer();
    var i = 0;
    while (i < template.length) {
      final c = template[i];
      if (c == '{') {
        final end = template.indexOf('}', i + 1);
        if (end < 0) {
          throw FormatException('Missing "}" in "$template".');
        }
        out.write(evaluate(template.substring(i + 1, end)));
        i = end + 1;
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  int rollDice(int count, int sides) {
    if (count < 0 || count > _maxDice || sides < 1 || sides > _maxDice) {
      throw FormatException('Unsupported dice ${count}d$sides.');
    }
    var total = 0;
    for (var i = 0; i < count; i++) {
      total += _rollDie(sides);
    }
    return total;
  }

  /// Variables every sheet formula can use: `str`..`cha`, `str_mod`..`cha_mod`,
  /// `level`, `prof`, `ac`, `speed`, `initiative`, `hp`, `hp_max`, and
  /// `<ability>_save` and `skill_<key>` for each skill.
  static num? characterVariable(Character c, String name) {
    for (final a in Ability.values) {
      if (name == a.key) return Rules.abilityScore(c, a);
      if (name == '${a.key}_mod') return Rules.abilityMod(c, a);
      if (name == '${a.key}_save') return Rules.saveBonus(c, a);
    }
    switch (name) {
      case 'level':
        return c.level;
      case 'prof':
        return Rules.proficiency(c);
      case 'ac':
        return Rules.armorClass(c);
      case 'speed':
        return Rules.speed(c);
      case 'initiative':
        return Rules.initiative(c);
      case 'hp':
        return c.hpCurrent;
      case 'hp_max':
        return Rules.maxHp(c);
    }
    if (name.startsWith('skill_')) {
      final key = name.substring(6);
      for (final s in c.skills) {
        if (s.key == key) return Rules.skillBonus(c, s);
      }
    }
    return null;
  }
}

enum _T { num, dice, ident, op, lparen, rparen, comma, end }

class _Token {
  _Token(this.type, this.text);
  final _T type;
  final String text;
}

class _Parser {
  _Parser(String source, this.engine) : _tokens = _tokenize(source);

  final FormulaEngine engine;
  final List<_Token> _tokens;
  int _pos = 0;

  static final _re = RegExp(
      r'\s*(?:(\d*\.?\d+)d(\d+)|(\d*\.?\d+)|([A-Za-z_][A-Za-z0-9_.]*)|(<=|>=|==|!=|[-+*/%<>])|(\()|(\))|(,))');

  static List<_Token> _tokenize(String s) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < s.length) {
      if (s.substring(i).trim().isEmpty) break;
      final m = _re.matchAsPrefix(s, i);
      if (m == null) {
        throw FormatException(
            'Unexpected character near "${s.substring(i).trim()}".');
      }
      if (m.group(1) != null) {
        tokens.add(_Token(_T.dice, '${m.group(1)}d${m.group(2)}'));
      } else if (m.group(3) != null) {
        tokens.add(_Token(_T.num, m.group(3)!));
      } else if (m.group(4) != null) {
        tokens.add(_Token(_T.ident, m.group(4)!));
      } else if (m.group(5) != null) {
        tokens.add(_Token(_T.op, m.group(5)!));
      } else if (m.group(6) != null) {
        tokens.add(_Token(_T.lparen, '('));
      } else if (m.group(7) != null) {
        tokens.add(_Token(_T.rparen, ')'));
      } else {
        tokens.add(_Token(_T.comma, ','));
      }
      i = m.end;
    }
    tokens.add(_Token(_T.end, ''));
    return tokens;
  }

  _Token get _cur => _tokens[_pos];

  double parse() {
    if (_cur.type == _T.end) throw const FormatException('Empty formula.');
    final v = _comparison();
    if (_cur.type != _T.end) {
      throw FormatException('Unexpected "${_cur.text}".');
    }
    return v;
  }

  bool _isOp(Set<String> ops) => _cur.type == _T.op && ops.contains(_cur.text);

  double _comparison() {
    final left = _sum();
    if (_isOp(const {'<', '>', '<=', '>=', '==', '!='})) {
      final op = _tokens[_pos++].text;
      final right = _sum();
      final result = switch (op) {
        '<' => left < right,
        '>' => left > right,
        '<=' => left <= right,
        '>=' => left >= right,
        '==' => left == right,
        _ => left != right,
      };
      return result ? 1 : 0;
    }
    return left;
  }

  double _sum() {
    var v = _product();
    while (_isOp(const {'+', '-'})) {
      final op = _tokens[_pos++].text;
      final r = _product();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _product() {
    var v = _unary();
    while (_isOp(const {'*', '/', '%'})) {
      final op = _tokens[_pos++].text;
      final r = _unary();
      if (op != '*' && r == 0) {
        throw const FormatException('Division by zero.');
      }
      v = switch (op) { '*' => v * r, '/' => v / r, _ => v % r };
    }
    return v;
  }

  double _unary() {
    if (_isOp(const {'-'})) {
      _pos++;
      return -_unary();
    }
    return _primary();
  }

  double _primary() {
    final t = _tokens[_pos++];
    switch (t.type) {
      case _T.num:
        return double.parse(t.text);
      case _T.dice:
        final parts = t.text.split('d');
        final count = double.parse(parts[0].isEmpty ? '1' : parts[0]).floor();
        return engine.rollDice(count, int.parse(parts[1])).toDouble();
      case _T.lparen:
        final v = _comparison();
        _expect(_T.rparen, ')');
        return v;
      case _T.ident:
        if (_cur.type == _T.lparen) {
          _pos++;
          return _call(t.text);
        }
        final v = engine.resolve(t.text);
        if (v == null) throw FormatException('Unknown variable "${t.text}".');
        return v.toDouble();
      default:
        throw FormatException(t.type == _T.end
            ? 'Formula ended early.'
            : 'Unexpected "${t.text}".');
    }
  }

  void _expect(_T type, String label) {
    if (_cur.type != type) throw FormatException('Expected "$label".');
    _pos++;
  }

  double _call(String name) {
    final args = <double>[];
    if (_cur.type != _T.rparen) {
      args.add(_comparison());
      while (_cur.type == _T.comma) {
        _pos++;
        args.add(_comparison());
      }
    }
    _expect(_T.rparen, ')');
    void arity(int n) {
      if (args.length != n) {
        throw FormatException('$name() takes $n argument(s).');
      }
    }

    switch (name) {
      case 'floor':
        arity(1);
        return args[0].floorToDouble();
      case 'ceil':
        arity(1);
        return args[0].ceilToDouble();
      case 'round':
        arity(1);
        return args[0].roundToDouble();
      case 'abs':
        arity(1);
        return args[0].abs();
      case 'min':
        if (args.length < 2) {
          throw const FormatException('min() needs 2+ arguments.');
        }
        return args.reduce(min);
      case 'max':
        if (args.length < 2) {
          throw const FormatException('max() needs 2+ arguments.');
        }
        return args.reduce(max);
      case 'clamp':
        arity(3);
        if (args[1] > args[2]) {
          throw const FormatException('clamp() minimum exceeds maximum.');
        }
        return args[0].clamp(args[1], args[2]).toDouble();
      case 'if':
        arity(3);
        return args[0] != 0 ? args[1] : args[2];
      default:
        throw FormatException('Unknown function "$name".');
    }
  }
}
