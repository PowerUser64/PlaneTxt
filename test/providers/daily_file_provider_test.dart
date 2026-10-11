import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DailyFileProvider provider;

  const todoHeader = r'^#{1,2}\s+.*(Todos?|Tasks?)';
  const template = '# Todos\n';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_provider_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    Directory('${root.path}/dailies').createSync();
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    provider = DailyFileProvider();
  });

  tearDown(() {
    provider.dispose(); // cancels the post-save timers
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File daily(String date) => File('${tempDir.path}/Org/dailies/$date.md');

  group('DailyFileProvider.refillTodos', () {
    test('moves the todos to the target day', () async {
      daily('20261009').writeAsStringSync('# Todos\n- [ ] a\n- [x] done');
      daily('20261010').writeAsStringSync('# Todos\n* [ ] b');

      await provider.refillTodos(
        '20261011',
        {
          '20261009': ['a'],
          '20261010': ['b'],
        },
        template: template,
        todoHeaderRegex: todoHeader,
      );

      expect(daily('20261011').readAsStringSync(),
          '# Todos\n\n- [ ] a\n- [ ] b');
      expect(daily('20261009').readAsStringSync(), '# Todos\n- [x] done');
      expect(daily('20261010').readAsStringSync(), '# Todos');
    });

    test('keeps the todos in place when the target cannot be written',
        () async {
      daily('20261009').writeAsStringSync('# Todos\n- [ ] a');
      // A directory where the target file should go: every write fails.
      Directory('${tempDir.path}/Org/dailies/20261011.md').createSync();

      await expectLater(
        provider.refillTodos(
          '20261011',
          {
            '20261009': ['a'],
          },
          template: template,
          todoHeaderRegex: todoHeader,
        ),
        throwsA(anything),
      );
      expect(daily('20261009').readAsStringSync(), '# Todos\n- [ ] a');
    });

    test('does not recreate a source day deleted meanwhile', () async {
      await provider.refillTodos(
        '20261011',
        {
          '20261009': ['a'],
        },
        template: template,
        todoHeaderRegex: todoHeader,
      );

      expect(daily('20261009').existsSync(), isFalse);
    });
  });
}
