import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/utils/daily_file_naming.dart';

void main() {
  tearDown(() => DailyFileNaming.useTemplate(DailyFileNaming.defaultTemplate));

  group('the default naming', () {
    test('names a day after it', () {
      expect(DailyFileNaming.current.fileName('20261020'), '20261020.md');
    });

    test('reads the day back from a name or a path', () {
      expect(DailyFileNaming.current.dateOf('20261020.md'), '20261020');
      expect(DailyFileNaming.current.dateOf('dailies/20261020.md'),
          '20261020');
    });

    test('takes no file that is not a day', () {
      for (final name in [
        'notes.md',
        '2026102.md',
        '202610201.md',
        '20261320.md', // no 13th month
        '20261032.md', // no 32nd day
        '20261020.txt',
        'meeting 20261020.md',
        '20261020.sync-conflict-20261021-093000-ABCDEF.md',
        '20261020 (conflict 2026-10-21 09:30).md',
      ]) {
        expect(DailyFileNaming.current.dateOf(name), isNull, reason: name);
      }
    });
  });

  group('a configured template', () {
    test('names a day after it', () {
      DailyFileNaming.useTemplate('YYYY-MM-DD-Agenda');
      expect(DailyFileNaming.current.fileName('20261020'),
          '2026-10-20-Agenda.md');
      expect(DailyFileNaming.current.dateOf('2026-10-20-Agenda.md'),
          '20261020');
    });

    test('takes the placeholders in any order', () {
      DailyFileNaming.useTemplate('DD.MM.YYYY');
      expect(DailyFileNaming.current.fileName('20261020'), '20.10.2026.md');
      expect(DailyFileNaming.current.dateOf('20.10.2026.md'), '20261020');
    });

    test('is written without its extension', () {
      DailyFileNaming.useTemplate(' YYYY-MM-DD.md ');
      expect(DailyFileNaming.current.template, 'YYYY-MM-DD');
      expect(DailyFileNaming.current.fileName('20261020'), '2026-10-20.md');
    });

    test('still reads the days written before it', () {
      DailyFileNaming.useTemplate('YYYY-MM-DD');
      expect(DailyFileNaming.current.dateOf('20261020.md'), '20261020');
    });

    test('takes no file that is not a day', () {
      DailyFileNaming.useTemplate('YYYY-MM-DD');
      expect(DailyFileNaming.current.dateOf('2026-10-20-notes.md'), isNull);
      expect(DailyFileNaming.current.dateOf('journal.md'), isNull);
    });

    test('is refused when it cannot name every day apart', () {
      expect(DailyFileNaming.validate(''), isNotNull);
      expect(DailyFileNaming.validate('Agenda'), isNotNull);
      expect(DailyFileNaming.validate('YYYY-MM'), isNotNull);
      expect(DailyFileNaming.validate('YYYY-MM-DD-DD'), isNotNull);
      expect(DailyFileNaming.validate('dailies/YYYY-MM-DD'), isNotNull);
      expect(DailyFileNaming.validate('YYYY:MM:DD'), isNotNull);
      expect(DailyFileNaming.validate('.YYYY-MM-DD'), isNotNull);
      expect(DailyFileNaming.validate('YYYY-MM-DD'), isNull);
    });

    test('nothing configured is the default naming, quietly', () {
      DailyFileNaming.useTemplate('YYYY-MM-DD');
      DailyFileNaming.useTemplate(null);
      expect(DailyFileNaming.current.template, DailyFileNaming.defaultTemplate);
    });

    test('an invalid one falls back to the default naming', () {
      DailyFileNaming.useTemplate('Agenda');
      expect(DailyFileNaming.current.template, DailyFileNaming.defaultTemplate);
    });

    test('shows the name it would give before it is saved', () {
      expect(DailyFileNaming.nameFrom('YYYY_MM_DD', '20261020'),
          '2026_10_20.md');
      expect(DailyFileNaming.nameFrom('Agenda', '20261020'), isNull);
      // Previewing one does not configure it.
      expect(DailyFileNaming.current.template, DailyFileNaming.defaultTemplate);
    });
  });
}
