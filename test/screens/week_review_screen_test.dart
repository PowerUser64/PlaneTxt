import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/screens/week_review_screen.dart';
import 'package:planetxt/services/file_store/io_file_store.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;
  late DailyFileProvider provider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('planetxt_week_');
    final root = Directory('${tempDir.path}/Org')..createSync();
    final dailies = Directory('${root.path}/dailies')..createSync();
    File('${dailies.path}/20261005.md').writeAsStringSync('- [ ] call the bank');
    File('${dailies.path}/20261007.md').writeAsStringSync('- [ ] call the bank');
    final private = Directory('${tempDir.path}/private')..createSync();
    StorageService().useStoreForTesting(IoFileStore(root), private);
    provider = DailyFileProvider();
  });

  tearDown(() {
    provider.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('shows the week and opens a day in the calendar',
      (tester) async {
    await tester.runAsync(() => provider.loadDailyFiles());
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WeekReviewScreen(day: DateTime(2026, 10, 8)))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('5 Oct to 11 Oct 2026'), findsOneWidget);
    expect(find.text('Carried over'), findsOneWidget);
    expect(find.text('on 2 days'), findsOneWidget);

    await tester.tap(find.text('Wed 7 Oct'));
    await tester.pumpAndSettle();
    expect(provider.selectedDate, '20261007');
    expect(find.byType(WeekReviewScreen), findsNothing);
  });
}
