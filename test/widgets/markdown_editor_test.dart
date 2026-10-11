import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/utils/exceptions.dart';
import 'package:planetxt/widgets/markdown_editor.dart';

/// One save the editor attempted: the text and the base it was checked
/// against.
typedef SaveCall = ({String content, String? expected});

void main() {
  late List<SaveCall> saves;
  late List<String> copies;
  late ValueNotifier<String?> disk;

  /// When set, the next save fails with a conflict: the file now holds this.
  String? conflictWith;
  bool conflictDeleted = false;

  setUp(() {
    saves = [];
    copies = [];
    disk = ValueNotifier<String?>('');
    conflictWith = null;
    conflictDeleted = false;
  });

  Future<void> save(String content, ExpectedContent expected) async {
    saves.add((content: content, expected: expected.content));
    if (conflictWith != null || conflictDeleted) {
      final theirs = conflictDeleted ? null : conflictWith;
      conflictWith = null;
      conflictDeleted = false;
      throw FileConflictException('changed', diskContent: theirs);
    }
  }

  Widget editor({String initial = ''}) {
    disk.value = initial;
    return MaterialApp(
      home: ValueListenableBuilder<String?>(
        valueListenable: disk,
        builder: (context, diskContent, _) => MarkdownEditor(
          initialContent: initial,
          diskContent: diskContent,
          onSave: save,
          onAutoSave: save,
          onSaveCopy: (content) async => copies.add(content),
          title: 'Test',
          hintText: '',
          mode: EditorMode.fullscreen,
        ),
      ),
    );
  }

  String editorText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  group('MarkdownEditor autosave', () {
    testWidgets('saves pending text when closed before the debounce',
        (tester) async {
      await tester.pumpWidget(editor());
      await tester.enterText(find.byType(TextField), 'last words');

      // Close the editor 100ms later, well before the 500ms autosave.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(saves.map((s) => s.content), ['last words']);
    });

    testWidgets('does not save again on close when nothing is pending',
        (tester) async {
      await tester.pumpWidget(editor());
      await tester.enterText(find.byType(TextField), 'saved already');
      await tester.pump(const Duration(milliseconds: 600));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(saves.map((s) => s.content), ['saved already']);
    });

    testWidgets('saves pending text when the app goes to the background',
        (tester) async {
      await tester.pumpWidget(editor());
      await tester.enterText(find.byType(TextField), 'before pause');
      await tester.pump(const Duration(milliseconds: 100));

      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(saves.map((s) => s.content), ['before pause']);
    });
  });

  group('MarkdownEditor conflict detection', () {
    testWidgets('checks each save against the previous one', (tester) async {
      await tester.pumpWidget(editor(initial: 'v1'));

      await tester.enterText(find.byType(TextField), 'v2');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byType(TextField), 'v3');
      await tester.pump(const Duration(milliseconds: 600));

      expect(saves, [
        (content: 'v2', expected: 'v1'),
        (content: 'v3', expected: 'v2'),
      ]);
    });

    testWidgets('reloads an external change when nothing is pending',
        (tester) async {
      await tester.pumpWidget(editor(initial: 'mine'));

      disk.value = 'changed by Syncthing';
      await tester.pump();

      expect(editorText(tester), 'changed by Syncthing');
      expect(saves, isEmpty);

      // The next save builds on the reloaded content.
      await tester.enterText(find.byType(TextField), 'edited after reload');
      await tester.pump(const Duration(milliseconds: 600));
      expect(saves.single.expected, 'changed by Syncthing');
    });

    testWidgets('keeps local typing over an external change', (tester) async {
      await tester.pumpWidget(editor(initial: 'v1'));
      await tester.enterText(find.byType(TextField), 'typing');

      disk.value = 'changed by Syncthing';
      conflictWith = 'changed by Syncthing'; // what the repository will see
      await tester.pump();

      expect(editorText(tester), 'typing');
      await tester.pump(const Duration(milliseconds: 600));
      expect(saves.single, (content: 'typing', expected: 'v1'));
      expect(find.text('File changed outside PlaneTxt'), findsOneWidget);
    });

    testWidgets('"Load theirs" replaces the text with the disk version',
        (tester) async {
      await tester.pumpWidget(editor(initial: 'v1'));
      conflictWith = 'theirs';
      await tester.enterText(find.byType(TextField), 'mine');
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('File changed outside PlaneTxt'), findsOneWidget);
      await tester.tap(find.text('Load theirs'));
      await tester.pumpAndSettle();

      expect(editorText(tester), 'theirs');
      expect(copies, isEmpty);
    });

    testWidgets('"Keep mine" overwrites, checked against their version',
        (tester) async {
      await tester.pumpWidget(editor(initial: 'v1'));
      conflictWith = 'theirs';
      await tester.enterText(find.byType(TextField), 'mine');
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Keep mine'));
      await tester.pumpAndSettle();

      expect(saves.last, (content: 'mine', expected: 'theirs'));
      expect(editorText(tester), 'mine');
    });

    testWidgets('"Keep both" saves a copy, then loads their version',
        (tester) async {
      await tester.pumpWidget(editor(initial: 'v1'));
      conflictWith = 'theirs';
      await tester.enterText(find.byType(TextField), 'mine');
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(copies, ['mine']);
      expect(editorText(tester), 'theirs');
    });

    testWidgets('a file deleted meanwhile can be recreated', (tester) async {
      await tester.pumpWidget(editor(initial: 'v1'));
      conflictDeleted = true;
      await tester.enterText(find.byType(TextField), 'mine');
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Recreate with mine'));
      await tester.pumpAndSettle();

      expect(saves.last, (content: 'mine', expected: null));
    });

    testWidgets('a conflict found while closing keeps a copy',
        (tester) async {
      await tester.pumpWidget(editor(initial: 'v1'));
      conflictWith = 'theirs';
      await tester.enterText(find.byType(TextField), 'mine');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(copies, ['mine']);
    });
  });
  group('MarkdownEditor editing', () {
    /// Put [text] in the field with the cursor at [cursor] (default: end).
    Future<void> setValue(WidgetTester tester, String text,
        {int? cursor, int? selectionStart}) async {
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: selectionStart ?? cursor ?? text.length,
          extentOffset: cursor ?? text.length,
        ),
      ));
      await tester.pump();
    }

    /// Type Enter at the cursor of [text], as the keyboard sends it.
    Future<void> pressEnter(WidgetTester tester, String text,
        {int? cursor}) async {
      final at = cursor ?? text.length;
      await setValue(tester, text, cursor: at);
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: text.replaceRange(at, at, '\n'),
        selection: TextSelection.collapsed(offset: at + 1),
      ));
      await tester.pump();
    }

    testWidgets('Bold wraps the selection', (tester) async {
      await tester.pumpWidget(editor());
      await setValue(tester, 'a word', selectionStart: 2, cursor: 6);

      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();

      expect(editorText(tester), 'a **word**');
    });

    testWidgets('Bold without selection puts the cursor inside',
        (tester) async {
      await tester.pumpWidget(editor());
      await setValue(tester, 'a ');

      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();

      final controller =
          tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(editorText(tester), 'a ****');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
    });

    testWidgets('a list marker goes to the start of the line',
        (tester) async {
      await tester.pumpWidget(editor());
      await setValue(tester, 'first\nsecond', cursor: 9);

      await tester.tap(find.byTooltip('Bullet List'));
      await tester.pump();

      expect(editorText(tester), 'first\n- second');
    });

    testWidgets('Enter after a checked todo starts an unchecked one',
        (tester) async {
      await tester.pumpWidget(editor());
      await pressEnter(tester, '- [x] done');

      expect(editorText(tester), '- [x] done\n- [ ] ');
    });

    testWidgets('Enter on an empty item ends the list', (tester) async {
      await tester.pumpWidget(editor());
      await pressEnter(tester, '- milk\n- ');

      expect(editorText(tester), '- milk\n');
    });

    testWidgets('Enter on an empty todo ends the list', (tester) async {
      await tester.pumpWidget(editor());
      await pressEnter(tester, '- [ ] a\n- [ ] ');

      expect(editorText(tester), '- [ ] a\n');
    });

    testWidgets('Enter continues a numbered list', (tester) async {
      await tester.pumpWidget(editor());
      await pressEnter(tester, '1. one');

      expect(editorText(tester), '1. one\n2. ');
    });

    testWidgets('Enter in plain text adds a plain line break',
        (tester) async {
      await tester.pumpWidget(editor());
      await pressEnter(tester, 'hello');

      expect(editorText(tester), 'hello\n');
    });
  });
}
