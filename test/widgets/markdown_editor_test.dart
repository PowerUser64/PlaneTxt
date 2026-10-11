import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/widgets/markdown_editor.dart';

void main() {
  late List<String> autoSaves;

  setUp(() {
    autoSaves = [];
  });

  Widget editor() {
    return MaterialApp(
      home: MarkdownEditor(
        initialContent: '',
        onSave: (_) async {},
        onAutoSave: (content) async => autoSaves.add(content),
        title: 'Test',
        hintText: '',
        mode: EditorMode.fullscreen,
      ),
    );
  }

  group('MarkdownEditor autosave', () {
    testWidgets('saves pending text when closed before the debounce',
        (tester) async {
      await tester.pumpWidget(editor());
      await tester.enterText(find.byType(TextField), 'last words');

      // Close the editor 100ms later, well before the 500ms autosave.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(autoSaves, ['last words']);
    });

    testWidgets('does not save again on close when nothing is pending',
        (tester) async {
      await tester.pumpWidget(editor());
      await tester.enterText(find.byType(TextField), 'saved already');
      await tester.pump(const Duration(milliseconds: 600));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(autoSaves, ['saved already']);
    });

    testWidgets('saves pending text when the app goes to the background',
        (tester) async {
      await tester.pumpWidget(editor());
      await tester.enterText(find.byType(TextField), 'before pause');
      await tester.pump(const Duration(milliseconds: 100));

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(autoSaves, ['before pause']);
    });
  });
}
