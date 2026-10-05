import 'package:flutter/material.dart';
import 'package:dnd_campaign_manager/logic/dice.dart';
import 'package:dnd_campaign_manager/logic/formula.dart';
import 'package:dnd_campaign_manager/models/character.dart';

class LibraryEntry {
  const LibraryEntry(this.title, this.description,
      {this.formula, this.dice, this.category = 'Character'});

  final String title;
  final String description;

  /// Snippet when building a plain calculation; null if not applicable.
  final String? formula;

  /// Snippet when building a dice expression; null if not applicable.
  final String? dice;
  final String category;
}

/// Plain-language catalog of the functions a DM can drop into fields.
final List<LibraryEntry> functionLibrary = [
  for (final a in const ['str', 'dex', 'con', 'int', 'wis', 'cha'])
    LibraryEntry(
      '${a.toUpperCase()} modifier',
      'The character\'s ${a.toUpperCase()} modifier (score 14 = +2).',
      formula: '${a}_mod',
      dice: '{${a}_mod}',
    ),
  const LibraryEntry('Proficiency bonus', 'Grows with level (+2 at level 1).',
      formula: 'prof', dice: '{prof}'),
  const LibraryEntry('Character level', 'The character\'s current level.',
      formula: 'level', dice: '{level}'),
  const LibraryEntry('Armor class', 'Current AC including effects.',
      formula: 'ac', dice: '{ac}'),
  const LibraryEntry('Skill bonus', 'Replace "stealth" with any skill key.',
      formula: 'skill_stealth', dice: '{skill_stealth}'),
  const LibraryEntry(
    'Variable dice count (bullet die)',
    'Roll one die to decide HOW MANY damage dice to roll. '
        'Here a d6 picks the number of d8.',
    dice: '{1d6}d8',
    formula: '1d6',
    category: 'Dice tricks',
  ),
  const LibraryEntry(
    'Scale dice with level',
    'One extra die every 4 levels: 1d6 at level 1, 2d6 at level 4...',
    dice: '{1+floor(level/4)}d6',
    formula: '1 + floor(level / 4)',
    category: 'Dice tricks',
  ),
  const LibraryEntry(
    'Half level (round down)',
    'Handy for small scaling bonuses.',
    formula: 'floor(level / 2)',
    dice: '{floor(level/2)}',
    category: 'Math',
  ),
  const LibraryEntry(
    'At least 1',
    'Never lets a value drop below 1.',
    formula: 'max(1, str_mod)',
    dice: '{max(1, str_mod)}',
    category: 'Math',
  ),
  const LibraryEntry(
    'If / else',
    'Pick between two values: more dice when STR modifier is 3 or more.',
    formula: 'if(str_mod >= 3, 2, 1)',
    dice: '{if(str_mod >= 3, 2, 1)}d6',
    category: 'Math',
  ),
  const LibraryEntry(
    'Clamp between limits',
    'Keeps a value between a minimum and a maximum.',
    formula: 'clamp(str_mod, 0, 5)',
    dice: '{clamp(str_mod, 0, 5)}',
    category: 'Math',
  ),
  const LibraryEntry('Add a flat bonus', 'Plain +2 on the end.',
      dice: '+2', formula: '+ 2', category: 'Math'),
];

Future<String?> showFunctionLibrary(BuildContext context,
    {required bool dice}) {
  final entries = functionLibrary
      .where((e) => (dice ? e.dice : e.formula) != null)
      .toList();
  final categories = <String>[];
  for (final e in entries) {
    if (!categories.contains(e.category)) categories.add(e.category);
  }
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Function library'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: ListView(children: [
          for (final cat in categories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(cat,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final e in entries.where((e) => e.category == cat))
              ListTile(
                dense: true,
                title: Text(e.title),
                subtitle:
                    Text('${e.description}\n${dice ? e.dice : e.formula}'),
                isThreeLine: true,
                onTap: () => Navigator.pop(ctx, dice ? e.dice : e.formula),
              ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

/// Text box for a dice expression or calculation, with a function-library
/// button and a live example result.
class FormulaTextField extends StatefulWidget {
  const FormulaTextField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.dice = true,
    this.help,
    this.extraNames = const [],
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool dice;
  final String? help;

  /// Extra names to suggest, e.g. other fields in a sheet template.
  final List<String> extraNames;

  @override
  State<FormulaTextField> createState() => _FormulaTextFieldState();
}

class _FormulaTextFieldState extends State<FormulaTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _insert() async {
    final snippet = await showFunctionLibrary(context, dice: widget.dice);
    if (snippet == null) return;
    final sel = _controller.selection;
    final text = _controller.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, snippet),
      selection: TextSelection.collapsed(offset: start + snippet.length),
    );
    widget.onChanged(_controller.text);
    setState(() {});
  }

  static const _functions = [
    'floor(',
    'ceil(',
    'round(',
    'abs(',
    'min(',
    'max(',
    'clamp(',
    'if(',
  ];
  static const _variables = [
    'str',
    'dex',
    'con',
    'int',
    'wis',
    'cha',
    'str_mod',
    'dex_mod',
    'con_mod',
    'int_mod',
    'wis_mod',
    'cha_mod',
    'level',
    'prof',
    'ac',
    'speed',
    'initiative',
    'hp',
    'hp_max',
    'skill_',
  ];

  /// The identifier being typed at the cursor, as (start, end, text).
  (int, int, String)? _currentWord() {
    final sel = _controller.selection;
    final text = _controller.text;
    if (!sel.isValid || !sel.isCollapsed) return null;
    var start = sel.start;
    while (start > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(text[start - 1])) {
      start--;
    }
    final word = text.substring(start, sel.start);
    if (word.isEmpty || RegExp(r'^\d').hasMatch(word)) return null;
    return (start, sel.start, word);
  }

  List<String> _suggestions() {
    final word = _currentWord();
    if (word == null) return const [];
    final lower = word.$3.toLowerCase();
    return [..._variables, ...widget.extraNames, ..._functions]
        .where((n) => n.toLowerCase().startsWith(lower) && n != word.$3)
        .take(8)
        .toList();
  }

  void _accept(String name) {
    final word = _currentWord();
    if (word == null) return;
    final text = _controller.text.replaceRange(word.$1, word.$2, name);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: word.$1 + name.length),
    );
    widget.onChanged(text);
    setState(() {});
  }

  /// (text, isError) for a sample character with every score at 10, level 1.
  (String, bool)? _preview() {
    final src = _controller.text.trim();
    if (src.isEmpty) return null;
    final sample = Character(id: 'sample');
    final dice = DiceRoller();
    final engine = FormulaEngine(
      resolve: (n) => FormulaEngine.characterVariable(sample, n),
      rollDie: dice.die,
    );
    try {
      if (widget.dice) {
        final resolved = engine.resolveTemplate(src);
        final r = dice.roll(resolved);
        return ('Example roll: $resolved = ${r.total}', false);
      }
      return ('Example result: ${engine.evaluate(src)}', false);
    } on FormatException catch (e) {
      return (e.message, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview();
    final suggestions = _suggestions();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.help,
                helperMaxLines: 3,
              ),
              onChanged: (v) {
                widget.onChanged(v);
                setState(() {});
              },
            ),
          ),
          IconButton(
            tooltip: 'How to write formulas',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showFormulaGuide(context, dice: widget.dice),
          ),
          OutlinedButton.icon(
            onPressed: _insert,
            icon: const Icon(Icons.functions),
            label: const Text('Functions'),
          ),
        ]),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final s in suggestions)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(s),
                  onPressed: () => _accept(s),
                ),
            ]),
          ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              preview.$1,
              style: TextStyle(
                fontSize: 12,
                color: preview.$2
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
      ]),
    );
  }
}

void showFormulaGuide(BuildContext context, {required bool dice}) {
  const heading = TextStyle(fontWeight: FontWeight.bold);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('How to write formulas'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (dice) ...[
              const Text('Dice expressions', style: heading),
              const Text('Write normal dice: 2d6+3, d8, 1d10-1+2d4.\n'),
              const Text('Calculated parts go in { } braces', style: heading),
              const Text('2d6+{str_mod} adds the STR modifier.\n'
                  '{1d6}d8 rolls a d6 first, then rolls that many d8 '
                  '(the "bullet die" trick).\n'
                  '{1+floor(level/4)}d6 adds a die every 4 levels.\n'),
            ] else ...[
              const Text('Calculations', style: heading),
              const Text('Use numbers, + - * / %, brackets, and names.\n'
                  'Example: floor((str + dex) / 2) + prof\n'),
            ],
            const Text('Names you can use', style: heading),
            const Text('str dex con int wis cha - ability scores\n'
                'str_mod ... cha_mod - ability modifiers\n'
                'level, prof, ac, speed, initiative, hp, hp_max\n'
                'skill_<name> - a skill bonus, e.g. skill_stealth\n'
                "In a sheet designer, any other field's key too.\n"),
            const Text('Functions', style: heading),
            const Text('floor(x) ceil(x) round(x) abs(x)\n'
                'min(a, b) max(a, b) clamp(x, low, high)\n'
                'if(condition, then, else) e.g. if(str_mod >= 3, 2, 1)\n'
                'Comparisons: < > <= >= == !=\n'),
            const Text('Tips', style: heading),
            const Text('Start typing a name and tap a suggestion chip.\n'
                'The line under the box shows an example result using a '
                'blank character (all scores 10, level 1); errors show in '
                'red.\n'
                'The Functions button inserts ready-made patterns.'),
          ]),
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Got it')),
      ],
    ),
  );
}
