import 'dart:math';

enum RollMode { normal, advantage, disadvantage }

class D20Roll {
  D20Roll(this.rolls, this.chosen);

  final List<int> rolls;
  final int chosen;

  bool get crit => chosen == 20;
  bool get fumble => chosen == 1;

  String describe() => rolls.length == 1 ? '${rolls.first}' : '[${rolls.join(', ')}] -> $chosen';
}

class DiceResult {
  DiceResult(this.expression, this.total, this.parts);

  final String expression;
  final int total;
  final String parts; // e.g. "2d6[3,4] +2"
}

/// One line in the roll log.
class RollEntry {
  RollEntry({
    required this.title,
    this.total,
    this.lines = const [],
    this.crit = false,
    this.fumble = false,
  }) : time = DateTime.now();

  final String title;
  final int? total;
  final List<String> lines;
  final bool crit;
  final bool fumble;
  final DateTime time;

  String get headline => total == null ? title : '$title: $total';
  String get snackText => [headline, ...lines].join('  ·  ');
}

/// Dice engine. Pass a seeded [Random] in tests for deterministic results.
class DiceRoller {
  DiceRoller([Random? random]) : _random = random ?? Random();

  final Random _random;

  int die(int sides) => _random.nextInt(sides) + 1;

  D20Roll d20(RollMode mode) {
    final count = mode == RollMode.normal ? 1 : 2;
    final rolls = List.generate(count, (_) => die(20));
    final chosen = switch (mode) {
      RollMode.normal => rolls.first,
      RollMode.advantage => rolls.reduce(max),
      RollMode.disadvantage => rolls.reduce(min),
    };
    return D20Roll(rolls, chosen);
  }

  static final RegExp _term = RegExp(r'([+-]?)(?:(\d*)d(\d+)|(\d+))');

  /// Rolls things like "2d6+3", "d8", "1d10-1+2d4". [doubleDice] doubles the
  /// number of dice (critical hits) but not flat modifiers.
  /// Throws [FormatException] if the text isn't a valid expression.
  DiceResult roll(String expression, {bool doubleDice = false}) {
    final src = expression.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (src.isEmpty) throw const FormatException('Empty dice expression');

    var total = 0;
    var consumed = 0;
    final parts = <String>[];

    for (final m in _term.allMatches(src)) {
      if (m.start != consumed) throw FormatException('Cannot read "$expression"');
      consumed = m.end;
      final sign = m.group(1) == '-' ? -1 : 1;
      if (m.group(3) != null) {
        var count = int.tryParse(m.group(2) ?? '') ?? 1;
        final sides = int.parse(m.group(3)!);
        if (doubleDice) count *= 2;
        if (count < 1 || count > 100 || sides < 1 || sides > 1000) {
          throw FormatException('Unsupported dice "$expression"');
        }
        final rolls = List.generate(count, (_) => die(sides));
        total += sign * rolls.fold<int>(0, (a, b) => a + b);
        parts.add('${sign < 0 ? '-' : ''}${count}d$sides[${rolls.join(',')}]');
      } else {
        final v = int.parse(m.group(4)!);
        total += sign * v;
        parts.add('${sign < 0 ? '-' : '+'}$v');
      }
    }
    if (consumed != src.length) throw FormatException('Cannot read "$expression"');
    return DiceResult(expression.trim(), total, parts.join(' '));
  }
}
