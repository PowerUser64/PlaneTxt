import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/utils/daily_content_helper.dart';
import 'package:planetxt/utils/markdown_parser.dart';

const todoHeader = r'^#{1,2}\s+.*Tasks?';
const eventHeader = r'^#{1,2}\s+.*Events?';

void main() {
  group('DailyContentHelper.insertAfterLastTodo', () {
    test('inserts after the last todo in the section', () {
      const content = '''
## Tasks
- [ ] first
- [x] second

## Notes
something''';
      final result = DailyContentHelper.insertAfterLastTodo(
          content, '- [ ] third', todoHeader);
      final lines = result.split('\n');
      final idx = lines.indexOf('- [ ] third');
      expect(idx, greaterThan(lines.indexOf('- [x] second')));
      expect(idx, lessThan(lines.indexOf('## Notes')));
    });

    test('inserts right after the header when the section is empty', () {
      const content = '''
## Tasks

## Notes''';
      final result = DailyContentHelper.insertAfterLastTodo(
          content, '- [ ] new', todoHeader);
      final lines = result.split('\n');
      expect(lines[lines.indexOf('## Tasks') + 1], '- [ ] new');
    });

    test('appends at end when no header matches', () {
      final result = DailyContentHelper.insertAfterLastTodo(
          'just text', '- [ ] new', todoHeader);
      expect(result.trim().endsWith('- [ ] new'), isTrue);
    });

    test('appends at end when regex is empty', () {
      final result =
          DailyContentHelper.insertAfterLastTodo('text', '- [ ] new', '');
      expect(result.contains('- [ ] new'), isTrue);
    });
  });

  group('DailyContentHelper.insertAfterLastEvent', () {
    test('inserts after the last event of the section', () {
      const content = '''
## Events
- @09:00 standup

## Tasks''';
      final result = DailyContentHelper.insertAfterLastEvent(
          content, '- @10:00 review', eventHeader);
      final lines = result.split('\n');
      expect(lines.indexOf('- @10:00 review'),
          lines.indexOf('- @09:00 standup') + 1);
    });
  });

  group('DailyContentHelper.insertEventsChronologically', () {
    test('merges new events sorted by time, skipping duplicates', () {
      const content = '''
## Events
- @12:00 lunch
''';
      final result = DailyContentHelper.insertEventsChronologically(
        content,
        ['- @15:00 coffee', '- @08:00 gym', '- @12:00 lunch'],
        eventHeader,
      );
      final lines =
          result.split('\n').where((l) => l.startsWith('- @')).toList();
      // Existing events are preserved first, new ones merged in time order;
      // the duplicate lunch is not added twice.
      expect(lines.where((l) => l.contains('lunch')).length, 1);
      expect(lines.indexWhere((l) => l.contains('gym')),
          lessThan(lines.indexWhere((l) => l.contains('coffee'))));
    });

    test('appends a fresh block when no events section exists', () {
      final result = DailyContentHelper.insertEventsChronologically(
          'notes only', ['- @08:00 gym'], eventHeader);
      expect(result.contains('- @08:00 gym'), isTrue);
    });
  });

  group('DailyContentHelper.insertAtEndOfSection', () {
    test('inserts before the next header', () {
      const content = '''
## Log
first entry

## Notes
note''';
      final result = DailyContentHelper.insertAtEndOfSection(
          content, '- 10:00 did things', r'^#{1,2}\s+.*Log');
      final lines = result.split('\n');
      expect(lines.indexOf('- 10:00 did things'),
          lines.indexOf('first entry') + 1);
    });
  });

  group('DailyContentHelper.insertAfterHeader', () {
    test('inserts right after the matching header', () {
      const content = '''
## Tasks
- [ ] existing''';
      final result = DailyContentHelper.insertAfterHeader(
          content, '- [ ] new', todoHeader);
      final lines = result.split('\n');
      expect(lines[lines.indexOf('## Tasks') + 1], '- [ ] new');
    });

    test('falls back to append on invalid regex', () {
      final result =
          DailyContentHelper.insertAfterHeader('text', 'new', r'([');
      expect(result.contains('new'), isTrue);
    });
  });

  group('CRLF line endings', () {
    const crlf = '## Tasks\r\n- [ ] first\r\n\r\n## Events\r\n'
        '- @10:00 Late\r\n\r\n## Notes\r\nsomething\r\n';

    void expectOnlyCrlf(String result) {
      expect(result.replaceAll('\r\n', '').contains('\n'), isFalse,
          reason: 'mixed line endings in:\n$result');
    }

    test('inserts a todo without mixing line endings', () {
      final result = DailyContentHelper.insertAfterLastTodo(
          crlf, '- [ ] second', todoHeader);
      expect(result, contains('- [ ] first\r\n- [ ] second\r\n'));
      expectOnlyCrlf(result);
    });

    test('finds the events section and keeps chronological order', () {
      final result = DailyContentHelper.insertEventsChronologically(
          crlf, ['- @08:00 Early'], eventHeader);
      expect(result, contains('## Events\r\n'));
      expect(result.indexOf('Early'), lessThan(result.indexOf('Late')));
      expectOnlyCrlf(result);
    });

    test('leaves LF files untouched', () {
      final result = DailyContentHelper.insertAfterLastTodo(
          '## Tasks\n- [ ] first', '- [ ] second', todoHeader);
      expect(result, '## Tasks\n- [ ] first\n- [ ] second');
    });
  });

  group('DailyContentHelper.removeUndoneTodos', () {
    test('matches the task text whatever the bullet and spacing', () {
      const content = '## Tasks\n* [ ] star bullet\n-  [ ]  wide spaces\n'
          '- [ ] stays';
      final result = DailyContentHelper.removeUndoneTodos(
          content, ['star bullet', 'wide spaces']);
      expect(result, '## Tasks\n- [ ] stays');
    });

    test('leaves a checked todo with the same text alone', () {
      const content = '- [x] call mom\n- [ ] call mom';
      expect(DailyContentHelper.removeUndoneTodos(content, ['call mom']),
          '- [x] call mom');
    });

    test('removes only as many occurrences as requested', () {
      const content = '- [ ] water plants\n- [ ] water plants';
      expect(DailyContentHelper.removeUndoneTodos(content, ['water plants']),
          '- [ ] water plants');
    });

    test('keeps CRLF line endings', () {
      const content = '- [ ] a\r\n- [ ] b\r\n';
      expect(DailyContentHelper.removeUndoneTodos(content, ['a']),
          '- [ ] b\r\n');
    });
  });
  group('DailyContentHelper.setTodoDone', () {
    TaskItem taskAt(String content, int index) =>
        MarkdownParser.parseTasks(content)[index];

    test('checks the todo at its line, keeping its bullet', () {
      const content = '# Todos\n* [ ] a\n- [ ] b';
      final updated =
          DailyContentHelper.setTodoDone(content, taskAt(content, 0), true);
      expect(updated, '# Todos\n* [x] a\n- [ ] b');
    });

    test('unchecks a todo checked with an uppercase X', () {
      const content = '- [X] a';
      expect(DailyContentHelper.setTodoDone(content, taskAt(content, 0), false),
          '- [ ] a');
    });

    test('picks the right one among identical todos', () {
      const content = '- [ ] call\n- [ ] call';
      expect(DailyContentHelper.setTodoDone(content, taskAt(content, 1), true),
          '- [ ] call\n- [x] call');
    });

    test('follows the todo when lines moved since it was read', () {
      const before = '- [ ] a\n- [ ] b';
      final task = taskAt(before, 1);
      const now = '# Synced meanwhile\n- [ ] a\n- [ ] b';
      expect(DailyContentHelper.setTodoDone(now, task, true),
          '# Synced meanwhile\n- [ ] a\n- [x] b');
    });

    test('leaves the file alone when the todo is gone', () {
      final task = taskAt('- [ ] a', 0);
      expect(DailyContentHelper.setTodoDone('- [x] a', task, true), '- [x] a');
    });

    test('keeps CRLF line endings', () {
      const content = '- [ ] a\r\n- [ ] b\r\n';
      expect(DailyContentHelper.setTodoDone(content, taskAt(content, 1), true),
          '- [ ] a\r\n- [x] b\r\n');
    });
  });
}
