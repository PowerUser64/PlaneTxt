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
}
