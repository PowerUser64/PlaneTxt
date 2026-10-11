import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/services/ics_parser_service.dart';

const _calendarHeader = 'BEGIN:VCALENDAR\nVERSION:2.0\n';
const _calendarFooter = 'END:VCALENDAR\n';

String _wrap(String vevents) => '$_calendarHeader$vevents$_calendarFooter';

void main() {
  group('IcsParserService.parseIcsContent', () {
    test('parses a simple local-time event', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART:20261225T103000
SUMMARY:Christmas brunch
DESCRIPTION:Bring gifts
END:VEVENT
''');
      final events = IcsParserService.parseIcsContent(ics);
      expect(events.length, 1);
      expect(events[0].title, 'Christmas brunch');
      expect(events[0].description, 'Bring gifts');
      expect(events[0].time, DateTime(2026, 12, 25, 10, 30));
      expect(events[0].date, '20261225');
    });

    test('converts UTC timestamps (Z suffix) to local time', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART:20261225T100000Z
SUMMARY:UTC event
END:VEVENT
''');
      final events = IcsParserService.parseIcsContent(ics);
      expect(events.length, 1);
      expect(events[0].time, DateTime.utc(2026, 12, 25, 10, 0).toLocal());
    });

    test('date-only DTSTART defaults to 09:00', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART:20261225
SUMMARY:All day
END:VEVENT
''');
      final events = IcsParserService.parseIcsContent(ics);
      expect(events.length, 1);
      expect(events[0].time, DateTime(2026, 12, 25, 9, 0));
    });

    test('handles property parameters like DTSTART;TZID=...', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART;TZID=Europe/Paris:20261225T103000
SUMMARY:With TZID
END:VEVENT
''');
      final events = IcsParserService.parseIcsContent(ics);
      expect(events.length, 1);
      expect(events[0].title, 'With TZID');
    });

    test('skips VEVENTs missing DTSTART or SUMMARY', () {
      final ics = _wrap('''
BEGIN:VEVENT
SUMMARY:No date
END:VEVENT
BEGIN:VEVENT
DTSTART:20261225T103000
END:VEVENT
''');
      expect(IcsParserService.parseIcsContent(ics), isEmpty);
    });

    test('parses multiple VEVENTs and survives one malformed block', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART:20261225T090000
SUMMARY:First
END:VEVENT
BEGIN:VEVENT
DTSTART:garbage
SUMMARY:Broken
END:VEVENT
BEGIN:VEVENT
DTSTART:20261226T090000
SUMMARY:Second
END:VEVENT
''');
      final events = IcsParserService.parseIcsContent(ics);
      expect(events.map((e) => e.title), ['First', 'Second']);
    });

    test('handles CRLF line endings', () {
      final ics = _wrap('BEGIN:VEVENT\r\n'
          'DTSTART:20261225T103000\r\n'
          'SUMMARY:CRLF event\r\n'
          'END:VEVENT\r\n');
      final events = IcsParserService.parseIcsContent(ics);
      expect(events.length, 1);
      expect(events[0].title, 'CRLF event');
    });
  });

  group('IcsParserService real-world calendars', () {
    test('converts a TZID time to the device time', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART;TZID=America/New_York:20261225T100000
SUMMARY:Call with New York
END:VEVENT
''');
      final event = IcsParserService.parseIcsContent(ics).single;
      expect(event.time, DateTime.utc(2026, 12, 25, 15, 0).toLocal());
    });

    test('keeps the written time for an unknown zone', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART;TZID="Romance Standard Time":20261225T100000
SUMMARY:Outlook meeting
END:VEVENT
''');
      final event = IcsParserService.parseIcsContent(ics).single;
      expect(event.time, DateTime(2026, 12, 25, 10, 0));
    });

    test('unfolds long lines and unescapes text', () {
      final ics = _wrap('BEGIN:VEVENT\r\n'
          'DTSTART:20261225T103000\r\n'
          'SUMMARY:Review\\, part 1\r\n'
          'DESCRIPTION:Join on Zo\r\n'
          ' om\\nRoom 4\\; floor 2\r\n'
          'END:VEVENT\r\n');
      final event = IcsParserService.parseIcsContent(ics).single;
      expect(event.title, 'Review, part 1');
      expect(event.description, 'Join on Zoom\nRoom 4; floor 2');
    });

    test('ignores the description of a reminder', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART:20261225T103000
SUMMARY:Dentist
DESCRIPTION:Bring the card
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:Reminder
END:VALARM
END:VEVENT
''');
      final event = IcsParserService.parseIcsContent(ics).single;
      expect(event.description, 'Bring the card');
    });

    test('keeps a multi-line title on one line', () {
      final ics = _wrap('''
BEGIN:VEVENT
DTSTART:20261225T103000
SUMMARY:Team\\nlunch
END:VEVENT
''');
      expect(IcsParserService.parseIcsContent(ics).single.title, 'Team lunch');
    });
  });

  group('IcsParserService.isValidIcsContent', () {
    test('accepts a minimal valid calendar', () {
      expect(IcsParserService.isValidIcsContent(_wrap('')), isTrue);
    });

    test('rejects empty and non-ICS content', () {
      expect(IcsParserService.isValidIcsContent(''), isFalse);
      expect(IcsParserService.isValidIcsContent('hello world'), isFalse);
      expect(
          IcsParserService.isValidIcsContent(
              'BEGIN:VCALENDAR\nEND:VCALENDAR'),
          isFalse); // missing VERSION
    });
  });
}
