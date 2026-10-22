import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/utils/daily_path_format.dart';

void main() {
  group('DailyPathFormat.pathForDate', () {
    test('flat default layout', () {
      var fmt = DailyPathFormat('dailies/%Y%m%d.md');
      expect(fmt.pathForDate('20260713'), 'dailies/20260713.md');
      expect(fmt.pathForDate('20241228'), 'dailies/20241228.md');
    });

    test('nested Notes-style layout', () {
      var fmt = DailyPathFormat('cal/%Y/%m/%d/daily.md');
      expect(fmt.pathForDate('20260713'), 'cal/2026/07/13/daily.md');
    });

    test('wildcard layout writes the canonical daily.md', () {
      var fmt = DailyPathFormat('cal/%Y/%m/%d/*.md');
      expect(fmt.pathForDate('20260713'), 'cal/2026/07/13/daily.md');
    });
  });

  group('DailyPathFormat.scanDir / recursive', () {
    test('flat layout scans dailies non-recursively', () {
      var fmt = DailyPathFormat('dailies/%Y%m%d.md');
      expect(fmt.scanDir, 'dailies');
      expect(fmt.recursive, isFalse);
    });

    test('nested layout scans the prefix recursively', () {
      var fmt = DailyPathFormat('cal/%Y/%m/%d/daily.md');
      expect(fmt.scanDir, 'cal');
      expect(fmt.recursive, isTrue);
    });

    test('layout starting at the root', () {
      var fmt = DailyPathFormat('%Y/%m/%d/daily.md');
      expect(fmt.scanDir, '');
      expect(fmt.recursive, isTrue);
    });
  });

  group('DailyPathFormat.directoryForDate', () {
    test('nested layout returns the day directory', () {
      var fmt = DailyPathFormat('cal/%Y/%m/%d/daily.md');
      expect(fmt.directoryForDate('20260713'), 'cal/2026/07/13');
    });

    test('flat layout returns the dailies directory', () {
      var fmt = DailyPathFormat('dailies/%Y%m%d.md');
      expect(fmt.directoryForDate('20260713'), 'dailies');
    });
  });

  group('DailyPathFormat.dateFromPath', () {
    test('flat layout parses the file name', () {
      var fmt = DailyPathFormat('dailies/%Y%m%d.md');
      expect(fmt.dateFromPath('dailies/20260713.md'), '20260713');
      expect(fmt.dateFromPath('dailies/20241228.md'), '20241228');
      expect(fmt.dateFromPath('notes/foo.md'), isNull);
    });

    test('nested layout parses the directory segments', () {
      var fmt = DailyPathFormat('cal/%Y/%m/%d/daily.md');
      expect(fmt.dateFromPath('cal/2026/07/13/daily.md'), '20260713');
      expect(fmt.dateFromPath('cal/2026/07/13/other.md'), isNull);
    });

    test('wildcard layout accepts any file name', () {
      var fmt = DailyPathFormat('cal/%Y/%m/%d/*.md');
      expect(fmt.dateFromPath('cal/2026/07/13/daily.md'), '20260713');
      expect(fmt.dateFromPath('cal/2026/07/13/reading_list.md'), '20260713');
    });

    test('handles tokens in a non-standard order', () {
      var fmt = DailyPathFormat('cal/%Y/%m/%d/daily.md');
      var reordered = DailyPathFormat('cal/%d/%m/%Y.md');
      expect(reordered.dateFromPath('cal/13/07/2026.md'), '20260713');
      expect(fmt.dateFromPath('cal/2026/07/13/daily.md'), '20260713');
    });

    test('rejects impossible dates', () {
      var fmt = DailyPathFormat('dailies/%Y%m%d.md');
      expect(fmt.dateFromPath('dailies/20260231.md'), isNull); // Feb 31
      expect(fmt.dateFromPath('dailies/20261301.md'), isNull); // month 13
    });

    test('skips conflict copies', () {
      var fmt = DailyPathFormat('cal/%Y/%m/%d/*.md');
      expect(
        fmt.dateFromPath('cal/2026/07/13/daily.sync-conflict-20260713-x.md'),
        isNull,
      );
    });
  });
}
