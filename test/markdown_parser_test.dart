import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/utils/markdown_parser.dart';

void main() {
  group('MarkdownParser.parseTasks', () {
    test('parses unchecked and checked todos', () {
      const content = '''
# Tasks
- [ ] buy milk
- [x] call mom
* [ ] star bullet
+ [x] plus bullet
''';
      final tasks = MarkdownParser.parseTasks(content);
      expect(tasks.length, 4);
      expect(tasks[0].text, 'buy milk');
      expect(tasks[0].isCompleted, isFalse);
      expect(tasks[1].text, 'call mom');
      expect(tasks[1].isCompleted, isTrue);
      expect(tasks[2].isCompleted, isFalse);
      expect(tasks[3].isCompleted, isTrue);
    });

    test('tolerates indentation and spaces inside brackets', () {
      const content = '  - [ x ] indented done\n\t- [  ] tab todo';
      final tasks = MarkdownParser.parseTasks(content);
      expect(tasks.length, 2);
      expect(tasks[0].isCompleted, isTrue);
      expect(tasks[1].isCompleted, isFalse);
    });

    test('ignores non-todo lines and empty checkboxes without text', () {
      const content = '''
just a note
- a bullet
- [ ]
# header
''';
      expect(MarkdownParser.parseTasks(content), isEmpty);
    });

    test('returns empty list for empty content', () {
      expect(MarkdownParser.parseTasks(''), isEmpty);
    });
  });

  group('MarkdownParser.parseEvents', () {
    test('parses event lines with @HH:MM', () {
      const content = '''
## Events
- @09:30 standup meeting
- @14:05 dentist
''';
      final events = MarkdownParser.parseEvents('20260710', content);
      expect(events.length, 2);
      expect(events[0].title, 'standup meeting');
      expect(events[0].time, DateTime(2026, 7, 10, 9, 30));
      expect(events[1].time, DateTime(2026, 7, 10, 14, 5));
    });

    test('accepts single-digit hour', () {
      final events =
          MarkdownParser.parseEvents('20260710', '- @9:00 breakfast');
      expect(events.length, 1);
      expect(events[0].time.hour, 9);
    });

    test('ignores @time mentions without a bullet', () {
      final events = MarkdownParser.parseEvents(
          '20260710', 'meet me at @9:00 tomorrow');
      expect(events, isEmpty);
    });

    test('collects following lines as description, stopping at blank/todo',
        () {
      const content = '''
- @10:00 review
  bring the notes
  room 4B

- @11:00 next
''';
      final events = MarkdownParser.parseEvents('20260710', content);
      expect(events.length, 2);
      expect(events[0].description, 'bring the notes\nroom 4B');
      expect(events[1].description, isEmpty);
    });

    test('returns empty list for an invalid date string', () {
      expect(MarkdownParser.parseEvents('not-a-date', '- @10:00 x'), isEmpty);
    });
  });

  group('MarkdownParser.parseNotes', () {
    test('keeps free text and plain bullets, strips markers', () {
      const content = '''
# Header
- [ ] a todo
- @10:00 an event
- plain bullet note
free text line
''';
      final notes = MarkdownParser.parseNotes(content);
      expect(notes, ['plain bullet note', 'free text line']);
    });
  });

  group('line classifiers', () {
    test('isTodoLine', () {
      expect(MarkdownParser.isTodoLine('- [ ] x'), isTrue);
      expect(MarkdownParser.isTodoLine('- [x] x'), isTrue);
      expect(MarkdownParser.isTodoLine('- x'), isFalse);
    });

    test('isEventLine', () {
      expect(MarkdownParser.isEventLine('- @10:00 x'), isTrue);
      expect(MarkdownParser.isEventLine('- 10:00 x'), isFalse);
      expect(MarkdownParser.isEventLine('@10:00 x'), isFalse);
    });
  });

  group('CRLF line endings', () {
    const crlf = '# Todos\r\n- [ ] buy milk\r\n- [x] call mom\r\n'
        '# Events\r\n- @09:30 Standup\r\n  room 4\r\n';

    test('parses tasks from a file edited on Windows', () {
      final tasks = MarkdownParser.parseTasks(crlf);
      expect(tasks.map((t) => t.text), ['buy milk', 'call mom']);
      expect(tasks.map((t) => t.isCompleted), [false, true]);
    });

    test('parses events and their descriptions', () {
      final events = MarkdownParser.parseEvents('20261011', crlf);
      expect(events.single.title, 'Standup');
      expect(events.single.time, DateTime(2026, 10, 11, 9, 30));
      expect(events.single.description, 'room 4');
    });

    test('keeps tasks and events out of the notes', () {
      final notes = MarkdownParser.parseNotes(crlf);
      expect(notes.where((n) => n.contains('milk') || n.contains('Standup')),
          isEmpty);
    });
  });
  group('uppercase X', () {
    test('a todo checked with [X] is done', () {
      final tasks = MarkdownParser.parseTasks('- [X] done\n- [ ] open');
      expect(tasks.map((t) => t.isCompleted), [true, false]);
      expect(MarkdownParser.isTodoLine('- [X] done'), isTrue);
    });

    test('a [X] todo stays out of the notes', () {
      expect(MarkdownParser.parseNotes('- [X] done'), isEmpty);
    });
  });

  group('MarkdownParser.parseTasks line index', () {
    test('records the line of each task', () {
      final tasks =
          MarkdownParser.parseTasks('# Todos\r\n- [ ] a\r\ntext\r\n- [x] b');
      expect(tasks.map((t) => t.line), [1, 3]);
    });
  });

  group('event descriptions', () {
    test('are not repeated in the notes', () {
      const content = '''
# Events
- @10:00 review
  bring the notes

# Notes
call the bank
''';
      expect(MarkdownParser.parseNotes(content), ['call the bank']);
    });

    test('stop at the next header', () {
      const content = '# Events\n- @10:00 review\n# Todos\n- [ ] a';
      final events = MarkdownParser.parseEvents('20261011', content);
      expect(events.single.description, isEmpty);
    });

    test('keep every indented line, but at most 4 loose ones', () {
      final indented = List.generate(6, (i) => '  line $i').join('\n');
      final loose = List.generate(6, (i) => 'line $i').join('\n');

      final long =
          MarkdownParser.parseEvents('20261011', '- @10:00 a\n$indented');
      final short = MarkdownParser.parseEvents('20261011', '- @10:00 a\n$loose');

      expect(long.single.description.split('\n'), hasLength(6));
      expect(short.single.description.split('\n'), hasLength(4));
      expect(MarkdownParser.parseNotes('- @10:00 a\n$loose'),
          ['line 4', 'line 5']);
    });

    test('eventBlockEnd points past the description', () {
      final lines = ['- @10:00 a', '  desc', '- @11:00 b', '', 'text'];
      expect(MarkdownParser.eventBlockEnd(lines, 0), 2);
      expect(MarkdownParser.eventBlockEnd(lines, 2), 3);
    });
  });

  group('MarkdownParser.parseFreeText', () {
    const logHeader = r'^#{1,2}\s+.*(Journal|Logs?)';
    const content = '''
# 📅 Events
- @09:30 Standup
  room 4

# ✅ Todos
- [ ] book train

# 📝 Logs
- 08:10 morning run
felt good

# 🗒️ Notes
idea: plain text
''';

    test('puts the logs section apart from the notes', () {
      final text =
          MarkdownParser.parseFreeText(content, logHeaderRegex: logHeader);
      expect(text.logs, ['08:10 morning run', 'felt good']);
      expect(text.notes, ['idea: plain text']);
    });

    test('without a logs pattern, everything is a note', () {
      final text = MarkdownParser.parseFreeText(content);
      expect(text.logs, isEmpty);
      expect(text.notes,
          ['08:10 morning run', 'felt good', 'idea: plain text']);
    });

    test('an invalid pattern falls back to notes only', () {
      final text = MarkdownParser.parseFreeText(content, logHeaderRegex: '(');
      expect(text.logs, isEmpty);
      expect(text.notes, hasLength(3));
    });
  });
}
