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
}
