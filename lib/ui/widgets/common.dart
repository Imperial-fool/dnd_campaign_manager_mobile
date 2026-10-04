import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dnd_campaign_manager/models/effect.dart';
import 'package:dnd_campaign_manager/ui/theme.dart';

String signed(int n) => n >= 0 ? '+$n' : '$n';

class SheetCard extends StatelessWidget {
  const SheetCard(
      {super.key,
      required this.title,
      required this.child,
      this.actions = const []});

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
        color: kPanel,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(title.toUpperCase(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ),
                ...actions,
              ]),
              const Divider(height: 18),
              child,
            ],
          ),
        ),
      );
}

/// Text field that edits a string owned by the model. Keeps its own
/// TextEditingController so the cursor never jumps while typing.
class TextBinding extends StatefulWidget {
  const TextBinding({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.minLines,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final int? minLines;

  @override
  State<TextBinding> createState() => _TextBindingState();
}

class _TextBindingState extends State<TextBinding> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(TextBinding old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _focus,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        onTapOutside: (_) => _focus.unfocus(),
        decoration: InputDecoration(labelText: widget.label),
        onChanged: widget.onChanged,
      );
}

/// Integer field (negative allowed). Empty input is treated as 0.
class IntBinding extends StatefulWidget {
  const IntBinding(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<IntBinding> createState() => _IntBindingState();
}

class _IntBindingState extends State<IntBinding> {
  late final TextEditingController _c =
      TextEditingController(text: '${widget.value}');
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(IntBinding old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && int.tryParse(_c.text) != widget.value) {
      _c.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
        onTapOutside: (_) => _focus.unfocus(),
        decoration: InputDecoration(labelText: widget.label),
        onChanged: (s) => widget.onChanged(int.tryParse(s) ?? 0),
      );
}

/// "ac=1, ability.dex=2" <-> List<Effect>
class EffectsField extends StatelessWidget {
  const EffectsField(
      {super.key, required this.effects, required this.onChanged});

  final List<Effect> effects;
  final ValueChanged<List<Effect>> onChanged;

  @override
  Widget build(BuildContext context) => TextBinding(
        label: 'Effects  (e.g. ac=1, ability.dex=2, skill.stealth=-1)',
        value: Effect.toText(effects),
        onChanged: (s) => onChanged(Effect.parseText(s)),
      );
}

Widget gap([double w = 8, double h = 8]) => SizedBox(width: w, height: h);
