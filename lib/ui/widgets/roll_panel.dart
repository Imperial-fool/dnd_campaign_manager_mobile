import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dnd_campaign_manager/logic/character_controller.dart';
import 'package:dnd_campaign_manager/logic/dice.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';

/// Pops a snackbar with the result of a roll (the log panel keeps history).
void showRoll(BuildContext context, RollEntry e) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(e.snackText),
    duration: const Duration(seconds: 5),
    showCloseIcon: true,
  ));
}

class RollPanel extends StatefulWidget {
  const RollPanel({super.key});

  @override
  State<RollPanel> createState() => _RollPanelState();
}

class _RollPanelState extends State<RollPanel> {
  final TextEditingController _expr = TextEditingController(text: 'd20');

  @override
  void dispose() {
    _expr.dispose();
    super.dispose();
  }

  void _roll(CharacterController ctrl) =>
      showRoll(context, ctrl.rollText(_expr.text));

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CharacterController>();
    return SheetCard(
      title: 'Dice',
      actions: [
        IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: ctrl.clearLog),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<RollMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: RollMode.disadvantage, label: Text('Disadv.')),
            ButtonSegment(value: RollMode.normal, label: Text('Normal')),
            ButtonSegment(value: RollMode.advantage, label: Text('Adv.')),
          ],
          selected: {ctrl.rollMode},
          onSelectionChanged: (s) => ctrl.setRollMode(s.first),
        ),
        const SizedBox(height: 4),
        Text('Applies to skill, save, attack and fire rolls.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _expr,
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(labelText: 'Roll (e.g. 2d6+3)'),
              onSubmitted: (_) => _roll(ctrl),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => _roll(ctrl), child: const Text('Roll')),
        ]),
        const SizedBox(height: 10),
        if (ctrl.rollLog.isEmpty) const Text('No rolls yet.'),
        for (final e in ctrl.rollLog.take(15))
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: e.crit
                  ? Colors.green.withValues(alpha: 0.18)
                  : e.fumble
                      ? Colors.red.withValues(alpha: 0.18)
                      : Colors.white10,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (e.total != null)
                SizedBox(
                  width: 44,
                  child: Text('${e.total}',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      for (final l in e.lines)
                        Text(l, style: Theme.of(context).textTheme.bodySmall),
                    ]),
              ),
            ]),
          ),
      ]),
    );
  }
}
