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
    test('taps on several todos of a day all land', () async {
      daily('20261011').writeAsStringSync(
          List.generate(6, (i) => '- [ ] task $i').join('\n'));
      await provider.ensureDailyFileLoaded('20261011');
      final tasks = provider.getTasks('20261011');

      // Not awaited one by one: taps arrive while the first write runs.
      await Future.wait(
          [for (final task in tasks) provider.setTodoDone('20261011', task, true)]);

      expect(daily('20261011').readAsStringSync(),
          List.generate(6, (i) => '- [x] task $i').join('\n'));
    });

    test('checks the todo in the file', () async {
      daily('20261011').writeAsStringSync('# Todos\n- [ ] a\n- [ ] b');
      await provider.ensureDailyFileLoaded('20261011');
      final task = provider.getTasks('20261011')[1];

      await provider.setTodoDone('20261011', task, true);

      expect(daily('20261011').readAsStringSync(), '# Todos\n- [ ] a\n- [x] b');
      expect(provider.getTasks('20261011')[1].isCompleted, isTrue);
    });
  });
  group('DailyFileProvider merged notes', () {
    File nested(String date, String name) {
      final year = date.substring(0, 4);
      final month = date.substring(4, 6);
      final day = date.substring(6, 8);
      final file = File('${tempDir.path}/Org/cal/$year/$month/$day/$name');
      file.parent.createSync(recursive: true);
      return file;
    }

    setUp(() {
      StorageService.applyDailyPathFormat('cal/%Y/%m/%d', 'daily.md');
      Directory('${tempDir.path}/Org/cal').createSync();
    });

    tearDown(() {
      StorageService.applyDailyPathFormat('dailies', '%Y%m%d.md');
    });

    test('parses tasks, events and notes across every note of the day',
        () async {
      nested('20261011', 'daily.md').writeAsStringSync(
          '# Todos\n- [ ] in daily\n\n# Notes\nprimary idea');
      nested('20261011', 'reading_list.md').writeAsStringSync(
          '- [ ] in note\nnote idea\n- @09:00 meeting');

      await provider.ensureDailyFileLoaded('20261011');

      expect(provider.getTasks('20261011').map((t) => t.text),
          ['in daily', 'in note']);
      expect(provider.getCalendarEvents('20261011').map((e) => e.title),
          ['meeting']);
      expect(provider.getNotes('20261011'), ['primary idea', 'note idea']);
    });

    test('an edit writes the primary file and keeps the other note',
        () async {
      nested('20261011', 'daily.md').writeAsStringSync('- [ ] mine');
      nested('20261011', 'reading_list.md').writeAsStringSync('- [ ] list');

      await provider.ensureDailyFileLoaded('20261011');
      final task = provider.getTasks('20261011')[0];
      await provider.setTodoDone('20261011', task, true);

      expect(nested('20261011', 'daily.md').readAsStringSync(),
          '- [x] mine');
      expect(nested('20261011', 'reading_list.md').readAsStringSync(),
          '- [ ] list');
      // The merged view still parses both notes.
      expect(provider.getTasks('20261011').map((t) => t.text),
          ['mine', 'list']);
    });

    test('a todo from an additional note is checked in that note', () async {
      nested('20261011', 'daily.md').writeAsStringSync('- [ ] mine');
      nested('20261011', 'reading_list.md').writeAsStringSync('- [ ] list');

      await provider.ensureDailyFileLoaded('20261011');
      // The second task lives in reading_list.md.
      final task = provider.getTasks('20261011')[1];
      await provider.setTodoDone('20261011', task, true);

      expect(nested('20261011', 'daily.md').readAsStringSync(), '- [ ] mine');
      expect(nested('20261011', 'reading_list.md').readAsStringSync(),
          '- [x] list');
      expect(provider.getTasks('20261011').map((t) => t.text),
          ['mine', 'list']);
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
