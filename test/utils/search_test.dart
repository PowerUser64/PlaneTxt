import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/note_file.dart';
import 'package:planetxt/utils/search.dart';

void main() {
  DailyFile day(String date, String content) =>
      DailyFile(path: 'dailies/$date.md', date: date, content: content);
  NoteFile note(String relPath, String content) => NoteFile(
        path: 'notes/$relPath',
        relativePath: relPath,
        content: content,
        lastModified: DateTime(2026),
      );

  test('ignores case and accents', () {
    final hits = searchAll('REUNION',
        dailies: [day('20261010', '- @09:00 Réunion équipe')], notes: []);
    expect(hits.single.date, '20261010');
    expect(hits.single.lines, ['- @09:00 Réunion équipe']);
  });

  test('lists days newest first, then notes by name, then by text', () {
    final hits = searchAll('plan', dailies: [
      day('20261001', 'plan A'),
      day('20261005', 'plan B'),
    ], notes: [
      note('Ideas.md', 'a plan'),
      note('Plan.md', 'nothing here'),
    ]);
    expect(hits.map((h) => h.date ?? h.note!.relativePath),
        ['20261005', '20261001', 'Plan.md', 'Ideas.md']);
  });

  test('keeps a few matching lines per hit', () {
    final content = List.generate(10, (i) => 'call $i').join('\n');
    final hits = searchAll('call', dailies: [day('20261010', content)], notes: []);
    expect(hits.single.lines, ['call 0', 'call 1', 'call 2']);
  });

  test('an empty query finds nothing', () {
    expect(searchAll('  ', dailies: [day('20261010', 'x')], notes: []),
        isEmpty);
  });
}
