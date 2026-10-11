import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_campaign_manager/ui/widgets/common.dart';

void main() {
  testWidgets('tapping outside blurs the field and applies external updates',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _TextBindingHarness()));

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, 'local edit');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('update')));
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, 'external update');
  });

  testWidgets('numeric binding keeps a partial draft until focus is lost',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _IntBindingHarness()));

    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.enterText(field, '-');
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, '-');
    expect(tester.binding.focusManager.primaryFocus, isNotNull);

    await tester.tap(find.byKey(const ValueKey('blur')));
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, '0');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
  });
}

class _TextBindingHarness extends StatefulWidget {
  const _TextBindingHarness();

  @override
  State<_TextBindingHarness> createState() => _TextBindingHarnessState();
}

class _TextBindingHarnessState extends State<_TextBindingHarness> {
  String value = 'initial';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            TextBinding(
              label: 'Text',
              value: value,
              onChanged: (text) => setState(() => value = text),
            ),
            ElevatedButton(
              key: const ValueKey('update'),
              onPressed: () => setState(() => value = 'external update'),
              child: const Text('Update elsewhere'),
            ),
          ],
        ),
      );
}

class _IntBindingHarness extends StatefulWidget {
  const _IntBindingHarness();

  @override
  State<_IntBindingHarness> createState() => _IntBindingHarnessState();
}

class _IntBindingHarnessState extends State<_IntBindingHarness> {
  int value = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          children: [
            IntBinding(
              label: 'Number',
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
            ElevatedButton(
              key: const ValueKey('blur'),
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: const Text('Blur'),
            ),
          ],
        ),
      );
}
