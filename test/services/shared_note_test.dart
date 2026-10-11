import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/intent_handler_service.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/widgets/quick_add_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late NoteFileProvider notes;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_shared_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    notes = NoteFileProvider();
  });

  tearDown(() {
    notes.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File note(String name) => File('${tempDir.path}/Org/notes/$name');

  test('keeps the whole shared text, line breaks included', () async {
    const text = 'Recette\n- 200 g farine\n- 3 œufs';

    await IntentHandlerService.saveSharedNote(notes, 'Recette crêpes', text);

    expect(note('Recette_crêpes.md').readAsStringSync(), text);
  });

  test('numbers a name already taken and shortens a long one', () async {
    await IntentHandlerService.saveSharedNote(notes, 'Idée', 'a');
    final second = await IntentHandlerService.saveSharedNote(notes, 'Idée', 'b');
    final long = await IntentHandlerService.saveSharedNote(
        notes, List.filled(30, 'mot').join(' '), 'c');

    expect(second.relativePath, 'Idée_2.md');
    expect(note('Idée.md').readAsStringSync(), 'a');
    expect(long.fileName.length, 60);
  });

  testWidgets('the share sheet choice "Note" fits a phone and saves a note',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? savedAs;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuickAddModal(
          selectedDate: DateTime(2026, 10, 11),
          initialText: 'Recette crêpes',
          initialType: QuickAddType.todo,
          onAdd: (_, __) {},
          onAddNote: (name) => savedAs = name,
        ),
      ),
    ));
    await tester.tap(find.text('Note'));
    await tester.pump();
    await tester.tap(find.text('Save Note'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(savedAs, 'Recette crêpes');
  });
}
