import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/utils/line_diff.dart';

void main() {
  String render(List<DiffLine>? lines) =>
      lines!.map((l) => l.toString()).join('\n');

  group('diffLines', () {
    test('marks nothing when the two versions match', () {
      final diff = diffLines('- [ ] call Ana\n- [ ] pay rent',
          '- [ ] call Ana\n- [ ] pay rent');
      expect(diff!.every((l) => l.kind == DiffKind.same), isTrue);
    });

    test('marks a line only the copy has', () {
      final diff = diffLines(
        '## Todos\n- [ ] call Ana\n',
        '## Todos\n- [ ] call Ana\n- [ ] pay rent\n',
      );
      expect(
          render(diff),
          ' ## Todos\n'
          ' - [ ] call Ana\n'
          '+- [ ] pay rent\n'
          ' ');
    });

    test('marks a line only the current file has', () {
      final diff = diffLines('a\nb\nc', 'a\nc');
      expect(render(diff), ' a\n-b\n c');
    });

    test('marks an edited line on both sides', () {
      final diff = diffLines('- [ ] call Ana', '- [x] call Ana');
      expect(render(diff), '-- [ ] call Ana\n+- [x] call Ana');
    });

    test('keeps the lines around a change untouched', () {
      final before = List.generate(50, (i) => 'line $i').join('\n');
      final after = before.replaceFirst('line 25', 'line 25 edited');

      final diff = diffLines(before, after)!;

      expect(diff.where((l) => l.kind != DiffKind.same).map((l) => l.text),
          ['line 25', 'line 25 edited']);
      expect(diff.length, 51);
    });

    test('gives up on versions too far apart to line up', () {
      final before = List.generate(900, (i) => 'mine $i').join('\n');
      final after = List.generate(900, (i) => 'theirs $i').join('\n');

      expect(diffLines(before, after), isNull);
    });

    test('still lines up long files that differ by one line', () {
      final before = List.generate(5000, (i) => 'line $i').join('\n');
      final after = before.replaceFirst('line 4999', 'line 4999 edited');

      final diff = diffLines(before, after);

      expect(diff, isNotNull);
      expect(diff!.where((l) => l.kind == DiffKind.added).single.text,
          'line 4999 edited');
    });
  });
}
