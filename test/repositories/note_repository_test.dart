import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/models/expected_content.dart';
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

  group('NoteRepository conflict detection', () {
    test('loadByRelativePath returns what is on disk', () async {
      await repository.create('Plan.md', 'v1');
      noteFile('Plan.md').writeAsStringSync('edited elsewhere');

      final fresh = await repository.loadByRelativePath('Plan.md');
      expect(fresh!.content, 'edited elsewhere');
      expect(await repository.loadByRelativePath('Missing.md'), isNull);
    });

    test('a save refuses to overwrite an external change', () async {
      await repository.create('Plan.md', 'v1');
      noteFile('Plan.md').writeAsStringSync('edited elsewhere');

      await expectLater(
        repository.create('Plan.md', 'mine',
            expected: const ExpectedContent('v1')),
        throwsA(isA<FileConflictException>()),
      );
      expect(noteFile('Plan.md').readAsStringSync(), 'edited elsewhere');
    });

    test('a change in the same mtime tick as our write is caught', () async {
      await repository.create('Plan.md', 'v1');
      final ourWrite = noteFile('Plan.md').lastModifiedSync();
      noteFile('Plan.md')
        ..writeAsStringSync('same tick')
        ..setLastModifiedSync(ourWrite);

      await expectLater(
        repository.create('Plan.md', 'mine',
            expected: const ExpectedContent('v1')),
        throwsA(isA<FileConflictException>()),
      );
    });
  });
  group('NoteRepository archives', () {
    File archived(String relPath) =>
        File('${tempDir.path}/Org/archives/$relPath');

    test('moves a note to archives/, keeping its folder', () async {
      final note = await repository.create('work/Plan.md', 'keep me');

      final target = await repository.archive(note);

      expect(target, 'archives/work/Plan.md');
      expect(noteFile('work/Plan.md').existsSync(), isFalse);
      expect(archived('work/Plan.md').readAsStringSync(), 'keep me');
    });

    test('numbers a name already taken in the archives', () async {
      archived('Plan.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('older');
      final note = await repository.create('Plan.md', 'newer');

      expect(await repository.archive(note), 'archives/Plan (2).md');
      expect(archived('Plan.md').readAsStringSync(), 'older');
    });

    test('brings an archived note back', () async {
      final note = await repository.create('Plan.md', 'keep me');
      final target = await repository.archive(note);

      final restored = await repository.unarchive(target, 'Plan.md');

      expect(restored!.content, 'keep me');
      expect(noteFile('Plan.md').readAsStringSync(), 'keep me');
      expect(archived('Plan.md').existsSync(), isFalse);
    });
  });
}
