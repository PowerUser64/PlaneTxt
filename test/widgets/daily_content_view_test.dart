import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/widgets/daily_content_view.dart';

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
}
