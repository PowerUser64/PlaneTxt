import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/screens/notes_view.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;
  late NoteFileProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_notes_view_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    final notes = Directory('${root.path}/notes')..createSync();
    Directory('${notes.path}/Travail').createSync();
    File('${notes.path}/Courses.md').writeAsStringSync('- [ ] lait');
    File('${notes.path}/Travail/Réunion.md').writeAsStringSync('ordre du jour');
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    provider = NoteFileProvider();
  });

  tearDown(() {
    provider.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpNotes(WidgetTester tester) async {
    await tester.runAsync(() => provider.loadNoteFiles());
    await tester.pumpWidget(ChangeNotifierProvider<NoteFileProvider>.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: NotesView())),
    ));
  }

  testWidgets('folders start folded and unfold on a tap', (tester) async {
    await pumpNotes(tester);

    expect(find.text('Courses'), findsOneWidget);
    expect(find.text('Travail'), findsOneWidget);
    expect(find.text('Réunion'), findsNothing);

    await tester.tap(find.text('Travail'));
    await tester.pump();
    expect(find.text('Réunion'), findsOneWidget);

    await tester.tap(find.text('Travail'));
    await tester.pump();
    expect(find.text('Réunion'), findsNothing);
  });

  testWidgets('a search finds notes inside folded folders', (tester) async {
    await pumpNotes(tester);

    await tester.enterText(find.byType(TextField), 'ordre');
    await tester.pump();

    expect(find.text('Réunion'), findsOneWidget);
    expect(find.text('Courses'), findsNothing);
  });
}
