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
