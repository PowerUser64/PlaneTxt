/// One additional `.md` note found in a day's directory, scanned alongside
/// the day's primary file.
///
/// Its content is merged into the day's view for parsing (todos, events,
/// notes) and reminders, but it is never edited in place: edits go to the
/// day's primary file ([DailyFile.content]), so a note stays a separate
/// file on disk.
class DailyNote {
  final String path;
  final String content;

  const DailyNote({required this.path, required this.content});
}

class DailyFile {
  /// Store path of the day's primary (editable) file.
  final String path;

  final String date;

  /// Content of the day's primary file - what editing and saving write back.
  final String content;

  /// Other `.md` notes in the same day directory, merged into the day's view.
  final List<DailyNote> notes;

  DailyFile({
    required this.path,
    required this.date,
    required this.content,
    this.notes = const [],
  });

  /// The day's content for display and parsing: the primary file plus every
  /// additional note merged in order. Tasks, events, notes and reminders all
  /// parse this combined content, so clicking a date returns every note of
  /// that day's directory.
  String get mergedContent {
    if (notes.isEmpty) return content;
    final buf = StringBuffer();
    var first = true;
    for (final part in [content, ...notes.map((n) => n.content)]) {
      if (!first) buf.write('\n');
      buf.write(part);
      first = false;
    }
    return buf.toString();
  }

  DateTime get dateTime {
    final year = int.parse(date.substring(0, 4));
    final month = int.parse(date.substring(4, 6));
    final day = int.parse(date.substring(6, 8));
    return DateTime(year, month, day);
  }

  String get formattedDate {
    final dt = dateTime;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  DailyFile copyWith({
    String? path,
    String? date,
    String? content,
    List<DailyNote>? notes,
  }) {
    return DailyFile(
      path: path ?? this.path,
      date: date ?? this.date,
      content: content ?? this.content,
      notes: notes ?? this.notes,
    );
  }
}
