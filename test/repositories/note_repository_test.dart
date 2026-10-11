import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/repositories/note_repository.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/utils/exceptions.dart';

void main() {
  late Directory tempDir;
  late NoteRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_notes_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    repository = NoteRepository(StorageService());
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File noteFile(String relPath) => File('${tempDir.path}/Org/notes/$relPath');

  group('NoteRepository.createNew', () {
    test('creates the note when the name is free', () async {
      final created = await repository.createNew('Groceries.md', '');
      expect(created.relativePath, 'Groceries.md');
      expect(noteFile('Groceries.md').existsSync(), isTrue);
    });

    test('refuses to overwrite an existing note', () async {
      await repository.create('Groceries.md', '- [ ] milk\n- [ ] eggs');

      await expectLater(
        repository.createNew('Groceries.md', ''),
        throwsA(isA<FileAlreadyExistsException>()),
      );
      expect(noteFile('Groceries.md').readAsStringSync(),
          '- [ ] milk\n- [ ] eggs');
    });

    test('detects the collision without the .md extension', () async {
      await repository.create('work/Plan.md', 'keep me');

      await expectLater(
        repository.createNew('work/Plan', ''),
        throwsA(isA<FileAlreadyExistsException>()),
      );
      expect(noteFile('work/Plan.md').readAsStringSync(), 'keep me');
    });
  });
}
