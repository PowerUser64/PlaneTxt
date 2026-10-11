import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/repositories/daily_repository.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/utils/exceptions.dart';

void main() {
  late Directory tempDir;
  late DailyRepository repository;

  // Latin-1 "Réunion": the "é" byte is not valid UTF-8.
  const latin1Bytes = [0x52, 0xE9, 0x75, 0x6E, 0x69, 0x6F, 0x6E];

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_dailies_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    Directory('${root.path}/dailies').createSync();
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    repository = DailyRepository(StorageService());
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File daily(String date) => File('${tempDir.path}/Org/dailies/$date.md');

  group('DailyRepository with an unreadable file', () {
    test('loadByDate throws instead of reporting the file as missing',
        () async {
      daily('20261011').writeAsBytesSync(latin1Bytes);

      await expectLater(repository.loadByDate('20261011'), throwsA(anything));
      expect(daily('20261011').readAsBytesSync(), latin1Bytes);
    });

    test('loadAll still loads the readable files', () async {
      daily('20261010').writeAsStringSync('- [ ] readable');
      daily('20261011').writeAsBytesSync(latin1Bytes);

      final files = await repository.loadAll();

      expect(files.map((f) => f.date), ['20261010']);
    });

    test('a file fixed after a failed read is picked up', () async {
      daily('20261011').writeAsBytesSync(latin1Bytes);
      final mtime = daily('20261011').lastModifiedSync();
      await repository.loadAll();

      // Sync tools like Syncthing keep the source mtime: the fixed file can
      // carry the very mtime the failed read saw.
      daily('20261011')
        ..writeAsStringSync('- [ ] fixed')
        ..setLastModifiedSync(mtime);
      final files = await repository.loadIncremental();

      expect(files.single.content, '- [ ] fixed');
    });
  });

  group('DailyRepository.save with an expected content', () {
    DailyFile file(String content) => DailyFile(
        path: StorageService.dailyPath('20261011'),
        date: '20261011',
        content: content);

    test('successive saves build on each other', () async {
      await repository.save(file('v1'), expected: const ExpectedContent(null));
      await repository.save(file('v2'), expected: const ExpectedContent('v1'));
      expect(daily('20261011').readAsStringSync(), 'v2');
    });

    test('refuses to overwrite an external change', () async {
      await repository.save(file('v1'), expected: const ExpectedContent(null));
      daily('20261011').writeAsStringSync('from the PC');

      await expectLater(
        repository.save(file('mine'), expected: const ExpectedContent('v1')),
        throwsA(isA<FileConflictException>()
            .having((e) => e.diskContent, 'diskContent', 'from the PC')),
      );
      expect(daily('20261011').readAsStringSync(), 'from the PC');
    });

    test('detects a synced change carrying an older mtime', () async {
      await repository.save(file('v1'), expected: const ExpectedContent(null));
      final ourWrite = daily('20261011').lastModifiedSync();
      daily('20261011')
        ..writeAsStringSync('edited on the PC earlier')
        ..setLastModifiedSync(ourWrite.subtract(const Duration(hours: 1)));

      await expectLater(
        repository.save(file('mine'), expected: const ExpectedContent('v1')),
        throwsA(isA<FileConflictException>()),
      );
    });

    test('detects a change landing in the same mtime tick as our write',
        () async {
      await repository.save(file('v1'), expected: const ExpectedContent(null));
      final ourWrite = daily('20261011').lastModifiedSync();
      daily('20261011')
        ..writeAsStringSync('same tick')
        ..setLastModifiedSync(ourWrite);

      await expectLater(
        repository.save(file('mine'), expected: const ExpectedContent('v1')),
        throwsA(isA<FileConflictException>()),
      );
    });

    test('refuses to create over a file that appeared meanwhile', () async {
      daily('20261011').writeAsStringSync('created elsewhere');

      await expectLater(
        repository.save(file('mine'), expected: const ExpectedContent(null)),
        throwsA(isA<FileConflictException>()),
      );
    });

    test('reports a file deleted meanwhile', () async {
      await repository.save(file('v1'), expected: const ExpectedContent(null));
      daily('20261011').deleteSync();

      await expectLater(
        repository.save(file('mine'), expected: const ExpectedContent('v1')),
        throwsA(isA<FileConflictException>()
            .having((e) => e.diskContent, 'diskContent', isNull)),
      );
    });
  });

  group('DailyRepository conflict copies', () {
    test('a scan reports the copies Syncthing left aside', () async {
      daily('20261011').writeAsStringSync('- [ ] mine');
      File('${tempDir.path}/Org/dailies/'
              '20261011.sync-conflict-20261011-153045-ABCDEFG.md')
          .writeAsStringSync('- [ ] theirs');

      final files = await repository.loadAll();

      expect(files.map((f) => f.date), ['20261011']);
      expect(repository.conflictFiles,
          {'dailies/20261011.sync-conflict-20261011-153045-ABCDEFG.md'});
    });
  });
}
