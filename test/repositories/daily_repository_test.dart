import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/repositories/daily_repository.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';

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
}
