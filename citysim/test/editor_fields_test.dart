import 'package:citysim/editor/edit_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DoubleSliderField commits typed values, clamped to range', (
    tester,
  ) async {
    double? committed;
    var value = 0.5;
    late StateSetter setOuterState;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setOuterState = setState;
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: DoubleSliderField(
                  label: 'Anchor X',
                  value: value,
                  min: 0,
                  max: 1,
                  onChanged: (v) => setState(() {
                    value = v;
                    committed = v;
                  }),
                ),
              ),
            ),
          );
        },
      ),
    );

    // Typing an exact value commits it.
    await tester.enterText(find.byType(TextFormField), '0.75');
    await tester.pump();
    expect(committed, 0.75);

    // Out-of-range input clamps instead of rejecting.
    await tester.enterText(find.byType(TextFormField), '5');
    await tester.pump();
    expect(committed, 1.0);

    // Unparsable mid-typing input commits nothing.
    await tester.enterText(find.byType(TextFormField), '0..');
    await tester.pump();
    expect(committed, 1.0);

    // An external value change (slider drag, revert) re-syncs the box.
    await tester.enterText(find.byType(TextFormField), '0.6');
    await tester.pump();
    expect(committed, 0.6);
    setOuterState(() => value = 0.25);
    await tester.pump();
    final field =
        find.byType(TextFormField).evaluate().single.widget as TextFormField;
    expect(field.controller!.text, '0.250');
  });
}
