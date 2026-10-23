import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/screens/conflict_screen.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;
  late Directory root;
  late DailyFileProvider daily;
  late NoteFileProvider notes;

  const copyName = '20261011.sync-conflict-20261011-153045-ABCDEFG.md';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_conflict_screen_');
    root = Directory('${tempDir.path}/Org')..createSync();
    final dailies = Directory('${root.path}/dailies')..createSync();
    Directory('${root.path}/notes').createSync();
    File('${dailies.path}/20261011.md')
        .writeAsStringSync('## Todos\n- [ ] call Ana\n');
    File('${dailies.path}/$copyName')
        .writeAsStringSync('## Todos\n- [ ] call Ana\n- [ ] pay rent\n');
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    daily = DailyFileProvider();
    notes = NoteFileProvider();
  });

  tearDown(() {
    daily.dispose();
    notes.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File file(String relPath) => File('${root.path}/$relPath');

  /// Pumps until [target] is on screen, letting the real file reads behind
  /// the screen run: they are outside the test's fake async, and the spinner
  /// shown meanwhile never lets `pumpAndSettle` return.
  Future<void> pumpUntil(WidgetTester tester, Finder target) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
      if (target.evaluate().isNotEmpty) return;
    }
    fail('$target never showed up');
  }

  Future<void> pumpConflicts(WidgetTester tester) async {
    await tester.runAsync(() => daily.loadDailyFiles());
    await tester.runAsync(() => notes.loadNoteFiles());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<DailyFileProvider>.value(value: daily),
        ChangeNotifierProvider<NoteFileProvider>.value(value: notes),
      ],
      child: const MaterialApp(home: ConflictScreen()),
    ));
    await tester.pump();
  }

  /// Opens the only conflict and waits for both versions to be read.
  Future<void> openTheConflict(WidgetTester tester) async {
    await tester.tap(find.text(copyName));
    await pumpUntil(tester, find.text('Keep both'));
  }

  /// Taps one of the three ways out and waits for the screen to pop back.
  Future<void> resolveWith(WidgetTester tester, String action) async {
    await tester.tap(find.text(action));
    await pumpUntil(tester, find.text('No conflicting versions left.'));
  }

  testWidgets('lists the copies left to resolve', (tester) async {
    await pumpConflicts(tester);

    expect(find.text(copyName), findsOneWidget);
    expect(find.textContaining('changed in two places at once'),
        findsOneWidget);
  });

  testWidgets('marks the lines only the copy has', (tester) async {
    await pumpConflicts(tester);
    await openTheConflict(tester);

    expect(find.text('  ## Todos'), findsOneWidget);
    expect(find.text('+ - [ ] pay rent'), findsOneWidget);
    expect(find.text('dailies/20261011.md'), findsOneWidget);
  });

  testWidgets('keeping the copy writes it over the day and drops it',
      (tester) async {
    await pumpConflicts(tester);
    await openTheConflict(tester);

    await resolveWith(tester, 'Keep the copy');

    expect(file('dailies/20261011.md').readAsStringSync(),
        '## Todos\n- [ ] call Ana\n- [ ] pay rent\n');
    expect(file('dailies/$copyName').existsSync(), isFalse);
  });

  testWidgets('keeping the current file only drops the copy', (tester) async {
    await pumpConflicts(tester);
    await openTheConflict(tester);

    await resolveWith(tester, 'Keep the current file');

    expect(file('dailies/20261011.md').readAsStringSync(),
        '## Todos\n- [ ] call Ana\n');
    expect(file('dailies/$copyName').existsSync(), isFalse);
  });

  testWidgets('keeping both files the copy among the notes', (tester) async {
    await pumpConflicts(tester);
    await openTheConflict(tester);

    await resolveWith(tester, 'Keep both');

    expect(file('notes/conflicts/20261011 (copy).md').readAsStringSync(),
        '## Todos\n- [ ] call Ana\n- [ ] pay rent\n');
    expect(file('dailies/20261011.md').readAsStringSync(),
        '## Todos\n- [ ] call Ana\n');
    expect(file('dailies/$copyName').existsSync(), isFalse);
  });
}
