import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/widgets/refill_dialog.dart';

void main() {
  final todos = [
    RefillTodo(text: 'a', sourceDate: '20261010', sourceDateDisplay: 'Sat 10'),
    RefillTodo(text: 'b', sourceDate: '20261010', sourceDateDisplay: 'Sat 10'),
    RefillTodo(text: 'a', sourceDate: '20261009', sourceDateDisplay: 'Fri 9'),
  ];
  late List<String> refilled;
  late bool? moved;

  Future<void> pumpDialog(WidgetTester tester, {Set<int> selected = const {}}) {
    refilled = [];
    moved = null;
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RefillDialog(
          undoneTodos: todos,
          initiallySelected: selected,
          onRefill: (chosen, {required move}) {
            refilled = [for (final t in chosen) '${t.sourceDate}:${t.text}'];
            moved = move;
          },
        ),
      ),
    ));
  }

  testWidgets('groups the todos under their day', (tester) async {
    await pumpDialog(tester);

    expect(find.text('Sat 10'), findsOneWidget);
    expect(find.text('Fri 9'), findsOneWidget);
    expect(find.text('a'), findsNWidgets(2));
  });

  testWidgets('a day header selects all of its todos', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('Sat 10'));
    await tester.pump();
    await tester.tap(find.text('Move here'));

    expect(refilled, ['20261010:a', '20261010:b']);
    expect(moved, isTrue);
  });

  testWidgets('opens with a day ticked and can copy instead', (tester) async {
    await pumpDialog(tester, selected: {2});

    await tester.tap(find.text('Copy'));
    await tester.pump();
    await tester.tap(find.text('Copy here'));

    expect(refilled, ['20261009:a']);
    expect(moved, isFalse);
  });
}
