import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/widgets/daily_content_view.dart';
import 'package:planetxt/widgets/inline_markdown.dart';

void main() {
  late Directory tempDir;
  late DailyFileProvider provider;
  late List<({String text, bool done})> toggles;
  late int editorOpenings;

  const date = '20261011';
  const logHeader = r'^#{1,2}\s+.*(Journal|Logs?)';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_day_view_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    Directory('${root.path}/dailies').createSync();
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    File('${root.path}/dailies/$date.md').writeAsStringSync(
        '# Todos\n- [ ] buy milk\n- [x] call mom\n\n# Logs\nran 5 km\n\n'
        '# Notes\nidea');
    provider = DailyFileProvider();
    toggles = [];
    editorOpenings = 0;
  });

  tearDown(() {
    provider.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpDay(WidgetTester tester) async {
    await tester.runAsync(() => provider.ensureDailyFileLoaded(date));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DailyContentView(
            dailyFileProvider: provider,
            dateString: date,
            logHeaderRegex: logHeader,
            onOpenEditor: () => editorOpenings++,
            onToggleTask: (task, done) =>
                toggles.add((text: task.text, done: done)),
          ),
        ),
      ),
    ));
  }

  testWidgets('a tap on a todo toggles it at once', (tester) async {
    await pumpDay(tester);

    await tester.tap(find.text('buy milk'));
    await tester.pump(); // no wait for a double-tap timeout
    await tester.tap(find.text('call mom'));
    await tester.pump();

    expect(toggles, [
      (text: 'buy milk', done: true),
      (text: 'call mom', done: false),
    ]);
    expect(editorOpenings, 0);
  });

  testWidgets('a todo being saved shows its new state and a spinner',
      (tester) async {
    await tester.runAsync(() => provider.ensureDailyFileLoaded(date));
    final line = provider.getTasks(date).first.line;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyContentView(
          dailyFileProvider: provider,
          dateString: date,
          logHeaderRegex: logHeader,
          pendingTasks: {line: true},
        ),
      ),
    ));

    final icons = tester
        .widgetList<Icon>(find.byType(Icon))
        .map((i) => i.icon)
        .where((i) => i == Icons.check_box || i == Icons.check_box_outline_blank);
    expect(icons, [Icons.check_box, Icons.check_box]); // buy milk, call mom
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a double tap outside the todos opens the editor',
      (tester) async {
    await pumpDay(tester);

    await tester.tap(find.text('idea'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('idea'));
    await tester.pumpAndSettle();

    expect(editorOpenings, 1);
    expect(toggles, isEmpty);
  });

  testWidgets('shows the logs apart from the notes', (tester) async {
    await pumpDay(tester);

    expect(find.text('Logs'), findsOneWidget);
    expect(find.text('ran 5 km'), findsOneWidget);
    expect(find.text('idea'), findsOneWidget);
  });

  testWidgets('renders the markdown of an event and of its description',
      (tester) async {
    File('${tempDir.path}/Org/dailies/$date.md').writeAsStringSync(
        '# Events\n- @09:00 **Standup** with [the team](https://example.org)\n'
        '  read the *agenda* first\n');
    await pumpDay(tester);

    final markdown = find.byType(InlineMarkdown);
    expect(markdown, findsNWidgets(2)); // title, description

    TextSpan spanOf(int index) => tester
        .widget<Text>(find.descendant(
            of: markdown.at(index), matching: find.byType(Text)))
        .textSpan! as TextSpan;

    final title = spanOf(0);
    // The syntax is gone from the text; the words are all still there.
    expect(title.toPlainText(), 'Standup with the team');
    expect(_styleOf(title, 'Standup')?.fontWeight, FontWeight.bold);
    expect(_styleOf(title, 'the team')?.decoration, TextDecoration.underline);

    final description = spanOf(1);
    expect(description.toPlainText(), 'read the agenda first');
    expect(_styleOf(description, 'agenda')?.fontStyle, FontStyle.italic);
  });
}

/// Style the span holding exactly [text] is drawn with, if there is one.
TextStyle? _styleOf(InlineSpan span, String text) {
  TextStyle? found;
  span.visitChildren((child) {
    if (child is TextSpan && child.text == text) {
      found = child.style;
      return false;
    }
    return true;
  });
  return found;
}
