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
  group('DailyFileProvider free text', () {
    const logHeader = r'^#{1,2}\s+.*(Journal|Logs?)';

    test('splits logs from notes and follows the pattern', () async {
      daily('20261011')
          .writeAsStringSync('# Logs\n- 08:10 run\n\n# Notes\nidea');
      await provider.ensureDailyFileLoaded('20261011');

      expect(provider.getLogs('20261011', logHeader), ['08:10 run']);
      expect(provider.getNotes('20261011', logHeaderRegex: logHeader),
          ['idea']);
      // Another pattern (the user edited it): parsed again.
      expect(provider.getNotes('20261011', logHeaderRegex: r'^# Nothing'),
          ['08:10 run', 'idea']);
    });
  });
  group('DailyFileProvider.setTodoDone', () {
    test('checks the todo in the file', () async {
      daily('20261011').writeAsStringSync('# Todos\n- [ ] a\n- [ ] b');
      await provider.ensureDailyFileLoaded('20261011');
      final task = provider.getTasks('20261011')[1];

      await provider.setTodoDone('20261011', task, true);

      expect(daily('20261011').readAsStringSync(), '# Todos\n- [ ] a\n- [x] b');
      expect(provider.getTasks('20261011')[1].isCompleted, isTrue);
    });
  });
  group('DailyFileProvider carry over', () {
    test('a copy leaves the todos in their day', () async {
      daily('20261009').writeAsStringSync('# Todos\n- [ ] a');

      await provider.refillTodos(
        '20261011',
        {
          '20261009': ['a'],
        },
        template: template,
        todoHeaderRegex: todoHeader,
        move: false,
      );

      expect(daily('20261011').readAsStringSync(), '# Todos\n\n- [ ] a');
      expect(daily('20261009').readAsStringSync(), '# Todos\n- [ ] a');
    });

    test('finds the latest earlier day with undone todos', () async {
      daily('20261008').writeAsStringSync('- [ ] old');
      daily('20261009').writeAsStringSync('- [x] all done');
      daily('20261011').writeAsStringSync('- [ ] today');
      await provider.loadDailyFiles();

      final latest = provider.latestUndoneBefore('20261011');
      expect(latest?.date, '20261008');
      expect(latest?.todos.map((t) => t.text), ['old']);
      expect(provider.latestUndoneBefore('20261008'), isNull);
    });
  });
}
