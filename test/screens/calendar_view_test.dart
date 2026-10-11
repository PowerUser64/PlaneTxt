import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/screens/calendar_view.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;
  late DailyFileProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_calendar_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    Directory('${root.path}/dailies').createSync();
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    provider = DailyFileProvider();
  });

  tearDown(() {
    provider.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget calendar() => ChangeNotifierProvider<DailyFileProvider>.value(
        value: provider,
        child: const MaterialApp(home: Scaffold(body: CalendarView())),
      );

  testWidgets('shows a day selected from outside, like an ICS import',
      (tester) async {
    await tester.pumpWidget(calendar());

    provider.setSelectedDate('20271225');
    await tester.pumpAndSettle();

    expect(find.text('December 2027'), findsOneWidget);
  });

  testWidgets('opens on the day selected before it was built',
      (tester) async {
    provider.setSelectedDate('20271225');

    await tester.pumpWidget(calendar());
    await tester.pumpAndSettle();

    expect(find.text('December 2027'), findsOneWidget);
  });
  testWidgets('ignores a day the calendar cannot show', (tester) async {
    await tester.pumpWidget(calendar());
    final shown = find.textContaining(RegExp(r'\d{4}$'));
    final before = (tester.widget(shown.first) as Text).data;

    provider.setSelectedDate('21500101'); // past the calendar's last day
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect((tester.widget(shown.first) as Text).data, before);
  });
  testWidgets('a swipe on the day moves to the next or previous day',
      (tester) async {
    provider.setSelectedDate('20271015');
    await tester.pumpWidget(calendar());
    await tester.pumpAndSettle();

    await tester.fling(find.text('Fri 15 Oct'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(provider.selectedDate, '20271016');

    await tester.fling(find.text('Sat 16 Oct'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    await tester.fling(find.text('Fri 15 Oct'), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(provider.selectedDate, '20271014');
  });

  testWidgets('Today brings the calendar back to today', (tester) async {
    provider.setSelectedDate('20271015');
    await tester.pumpWidget(calendar());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(provider.selectedDate,
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}');
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('an empty day offers to start it', (tester) async {
    await tester.pumpWidget(calendar());
    await tester.pumpAndSettle();

    expect(find.text('Nothing planned yet today'), findsOneWidget);
    expect(find.text('Start the day'), findsOneWidget);
  });
  group('carry-over prompt', () {
    String dateOf(DateTime d) => '${d.year}'
        '${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

    Future<void> withYesterday(WidgetTester tester, String content) async {
      final now = DateTime.now();
      final yesterday = dateOf(DateTime(now.year, now.month, now.day - 1));
      File('${tempDir.path}/Org/dailies/$yesterday.md')
          .writeAsStringSync(content);
      await tester.runAsync(() => provider.loadDailyFiles());
    }

    testWidgets('offers yesterday\'s undone todos, until dismissed',
        (tester) async {
      await withYesterday(tester, '- [ ] call the bank\n- [x] done');
      await tester.pumpWidget(calendar());
      await tester.pumpAndSettle();

      expect(find.textContaining('1 todo left undone'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.textContaining('left undone'), findsNothing);
    });

    testWidgets('opens the carry-over with those todos ticked',
        (tester) async {
      await withYesterday(tester, '- [ ] call the bank');
      await tester.pumpWidget(calendar());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Carry over'));
      await tester.pumpAndSettle();

      final tile = tester.widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, 'call the bank'));
      expect(tile.value, isTrue);
    });
  });
}
