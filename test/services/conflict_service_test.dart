import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/services/conflict_service.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';

void main() {
  late Directory tempDir;
  late Directory root;
  late ConflictService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_conflicts_');
    root = Directory('${tempDir.path}/Org')..createSync();
    Directory('${root.path}/dailies').createSync();
    Directory('${root.path}/notes').createSync();
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    service = ConflictService(StorageService());
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File file(String relPath) => File('${root.path}/$relPath');

  void write(String relPath, String content) {
    final target = file(relPath);
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(content);
  }

  const syncthingCopy =
      'dailies/20261011.sync-conflict-20261011-153045-ABCDEFG.md';

  group('ConflictService.read', () {
    test('pairs a copy with the file it was made from', () async {
      write('dailies/20261011.md', '- [ ] mine');
      write(syncthingCopy, '- [ ] theirs');

      final versions = await service.read(syncthingCopy);

      expect(versions.originalPath, 'dailies/20261011.md');
      expect(versions.current, '- [ ] mine');
      expect(versions.copy, '- [ ] theirs');
      expect(versions.currentIsGone, isFalse);
      expect(versions.versionsMatch, isFalse);
    });

    test('reports a file that is gone rather than failing', () async {
      write(syncthingCopy, '- [ ] theirs');

      final versions = await service.read(syncthingCopy);

      expect(versions.currentIsGone, isTrue);
      expect(versions.copy, '- [ ] theirs');
    });

    test('finds the day behind a copy PlaneTxt wrote', () async {
      write('dailies/20261011.md', '- [ ] mine');
      write('notes/conflicts/daily 20261011 (conflict 2026-10-11 153045).md',
          '- [ ] theirs');

      final versions = await service.read(
          'notes/conflicts/daily 20261011 (conflict 2026-10-11 153045).md');

      expect(versions.originalPath, 'dailies/20261011.md');
      expect(versions.current, '- [ ] mine');
    });

    test('throws on a file that is not a copy', () async {
      write('dailies/20261011.md', '- [ ] mine');

      expect(service.read('dailies/20261011.md'), throwsA(anything));
    });
  });

  group('ConflictService.resolve', () {
    test('keeping the current file drops the copy', () async {
      write('dailies/20261011.md', '- [ ] mine');
      write(syncthingCopy, '- [ ] theirs');

      final kept = await service.resolve(
          await service.read(syncthingCopy), ConflictChoice.keepCurrent);

      expect(kept, isNull);
      expect(file(syncthingCopy).existsSync(), isFalse);
      expect(file('dailies/20261011.md').readAsStringSync(), '- [ ] mine');
    });

    test('keeping the copy makes it the file', () async {
      write('dailies/20261011.md', '- [ ] mine');
      write(syncthingCopy, '- [ ] theirs');

      final kept = await service.resolve(
          await service.read(syncthingCopy), ConflictChoice.keepCopy);

      expect(kept, 'dailies/20261011.md');
      expect(file(syncthingCopy).existsSync(), isFalse);
      expect(file('dailies/20261011.md').readAsStringSync(), '- [ ] theirs');
    });

    test('keeping the copy puts back a file that was gone', () async {
      write(syncthingCopy, '- [ ] theirs');

      await service.resolve(
          await service.read(syncthingCopy), ConflictChoice.keepCopy);

      expect(file('dailies/20261011.md').readAsStringSync(), '- [ ] theirs');
    });

    test("keeping both files a day's copy among the notes", () async {
      write('dailies/20261011.md', '- [ ] mine');
      write(syncthingCopy, '- [ ] theirs');

      final kept = await service.resolve(
          await service.read(syncthingCopy), ConflictChoice.keepBoth);

      // A day is addressed by its file name, so the copy cannot stay in
      // dailies/ without passing for another day.
      expect(kept, 'notes/conflicts/20261011 (copy).md');
      expect(file(kept!).readAsStringSync(), '- [ ] theirs');
      expect(file('dailies/20261011.md').readAsStringSync(), '- [ ] mine');
      expect(file(syncthingCopy).existsSync(), isFalse);
    });

    test('keeping both leaves a note beside the note it came from', () async {
      write('notes/work/Plan.md', 'mine');
      write('notes/work/Plan (conflicted copy 2026-10-11 153045).md', 'theirs');

      final kept = await service.resolve(
          await service
              .read('notes/work/Plan (conflicted copy 2026-10-11 153045).md'),
          ConflictChoice.keepBoth);

      expect(kept, 'notes/work/Plan (copy).md');
      expect(file(kept!).readAsStringSync(), 'theirs');
      expect(file('notes/work/Plan.md').readAsStringSync(), 'mine');
    });

    test('keeping both twice does not overwrite the first copy', () async {
      write('notes/Plan.md', 'mine');
      write('notes/Plan (copy).md', 'kept earlier');
      write("notes/Plan (Ben's conflicted copy 2026-10-11).md", 'theirs');

      final kept = await service.resolve(
          await service.read("notes/Plan (Ben's conflicted copy 2026-10-11).md"),
          ConflictChoice.keepBoth);

      expect(kept, 'notes/Plan (copy 2).md');
      expect(file('notes/Plan (copy).md').readAsStringSync(), 'kept earlier');
      expect(file(kept!).readAsStringSync(), 'theirs');
    });
  });
}
