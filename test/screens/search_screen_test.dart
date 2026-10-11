import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/screens/search_screen.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;
  late DailyFileProvider dailies;
  late NoteFileProvider notes;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_search_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    Directory('${root.path}/dailies').createSync();
    Directory('${root.path}/notes').createSync();
    File('${root.path}/dailies/20261010.md')
        .writeAsStringSync('- @09:00 Réunion budget');
    File('${root.path}/notes/Budget.md').writeAsStringSync('2027');
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    dailies = DailyFileProvider();
    notes = NoteFileProvider();
  });

  tearDown(() {
    dailies.dispose();
    notes.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('finds days and notes, and opens a day in the calendar',
      (tester) async {
    await tester.runAsync(() async {
      await dailies.loadDailyFiles();
      await notes.loadNoteFiles();
    });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dailies),
        ChangeNotifierProvider.value(value: notes),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchScreen())),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'budget');
    await tester.pump();
    expect(find.text('Sat 10 Oct 2026'), findsOneWidget);
    expect(find.text('Budget'), findsOneWidget);

    await tester.tap(find.text('Sat 10 Oct 2026'));
    await tester.pumpAndSettle();
    expect(dailies.selectedDate, '20261010');
    expect(find.byType(SearchScreen), findsNothing);
  });
}
