import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/utils/conflict_files.dart';

void main() {
  group('isConflictCopy', () {
    test('recognises the copies sync tools write', () {
      expect(
          isConflictCopy(
              'dailies/20261011.sync-conflict-20261011-153045-ABCDEFG.md'),
          isTrue); // Syncthing
      expect(isConflictCopy('notes/Plan (conflicted copy 2026-10-11 153045).md'),
          isTrue); // Nextcloud
      expect(
          isConflictCopy("notes/Plan (Ben's conflicted copy 2026-10-11).md"),
          isTrue); // Dropbox
      expect(isConflictCopy('notes/conflicts/daily 20261011 '
              '(conflict 2026-10-11 153045).md'),
          isTrue); // PlaneTxt
    });

    test('ignores ordinary files', () {
      expect(isConflictCopy('dailies/20261011.md'), isFalse);
      expect(isConflictCopy('notes/Conflict resolution.md'), isFalse);
      // Only the file name counts, not the folder.
      expect(isConflictCopy('notes/conflicts/notes.md'), isFalse);
    });
  });

  group('originalPathOf', () {
    test('takes the marker back out of the name', () {
      expect(
          originalPathOf(
              'dailies/20261011.sync-conflict-20261011-153045-ABCDEFG.md'),
          'dailies/20261011.md');
      expect(
          originalPathOf('notes/Plan (conflicted copy 2026-10-11 153045).md'),
          'notes/Plan.md');
      expect(originalPathOf("notes/Plan (Ben's conflicted copy 2026-10-11).md"),
          'notes/Plan.md');
      expect(
          originalPathOf('notes/conflicts/daily 20261011 '
              '(conflict 2026-10-11 153045).md'),
          'notes/conflicts/daily 20261011.md');
    });

    test('keeps the folder and the extension', () {
      expect(
          originalPathOf('notes/a/b/Plan (conflicted copy 2026-10-11).txt'),
          'notes/a/b/Plan.txt');
    });

    test('leaves a name holding several markers resolvable once', () {
      // Two devices in a row: the outer marker goes, the inner one stays,
      // and resolving the result settles the rest.
      expect(
          originalPathOf('notes/Plan (conflicted copy 2026-10-11)'
              ' (conflicted copy 2026-10-12).md'),
          'notes/Plan (conflicted copy 2026-10-11).md');
    });

    test('has nothing to give for an ordinary file', () {
      expect(originalPathOf('dailies/20261011.md'), isNull);
      expect(originalPathOf('notes/Conflict resolution.md'), isNull);
    });
  });
}
