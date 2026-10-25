import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/note_file.dart';

/// One day or note matching a search, with the lines that matched.
class SearchHit {
  /// The day (`yyyyMMdd`) for a daily file, null for a note.
  final String? date;
  final NoteFile? note;
  final List<String> lines;

  const SearchHit.day(String this.date, this.lines) : note = null;
  const SearchHit.note(NoteFile this.note, this.lines) : date = null;
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a', //
  'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i', 'ñ': 'n', //
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', //
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', 'ÿ': 'y', //
  'œ': 'oe', 'æ': 'ae', 'ß': 'ss',
};

/// [text] lowercased without accents: "Réunion" and "reunion" match.
String foldForSearch(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_accents[char] ?? char);
  }
  return buffer.toString();
}

/// The days and notes containing [query], ignoring case and accents: days
/// newest first, then notes whose name matches, then notes whose text
/// does. Each hit keeps at most [maxLines] matching lines.
List<SearchHit> searchAll(
  String query, {
  required Iterable<DailyFile> dailies,
  required Iterable<NoteFile> notes,
  int maxLines = 3,
}) {
  final folded = foldForSearch(query.trim());
  if (folded.isEmpty) return const [];

  List<String> matchingLines(String content) => content
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => foldForSearch(line).contains(folded))
      .take(maxLines)
      .toList();

  final days = <SearchHit>[];
  for (final daily in dailies) {
    final lines = matchingLines(daily.mergedContent);
    if (lines.isNotEmpty) days.add(SearchHit.day(daily.date, lines));
  }
  days.sort((a, b) => b.date!.compareTo(a.date!));

  final byName = <SearchHit>[];
  final byText = <SearchHit>[];
  for (final note in notes) {
    final lines = matchingLines(note.content);
    if (foldForSearch(note.displayName).contains(folded)) {
      byName.add(SearchHit.note(note, lines));
    } else if (lines.isNotEmpty) {
      byText.add(SearchHit.note(note, lines));
    }
  }
  return [...days, ...byName, ...byText];
}
