import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/utils/note_names.dart';

void main() {
  group('sanitizeNoteName', () {
    test('keeps accented letters', () {
      expect(sanitizeNoteName('Réunion équipe'), 'Réunion_équipe');
      expect(sanitizeNoteName('Ça marche, ou pas ?'), 'Ça_marche_ou_pas');
    });

    test('drops path separators and symbols', () {
      expect(sanitizeNoteName(' a/b\\c '), 'a_b_c');
      expect(sanitizeNoteName('...'), '');
      expect(sanitizeNoteName('to-do_list 2'), 'to-do_list_2');
    });
  });

  group('sanitizeNoteFolder', () {
    test('cleans every segment and drops the empty ones', () {
      expect(sanitizeNoteFolder('Travail/Réunions'), 'Travail/Réunions');
      expect(sanitizeNoteFolder('/a//../b\\c/'), 'a/b/c');
    });
  });
}
