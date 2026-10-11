import 'package:planetxt/models/calendar_event.dart';
import 'package:planetxt/utils/logger.dart';

/// Single source of truth for the regular expressions used to recognise
/// task and event lines in daily markdown. Keeping these as `static final`
/// avoids re-compiling the patterns on every parse and also keeps the
/// recognition rules consistent across the parser, the content helpers,
/// and the notification service.
class MarkdownParser {
  /// Matches the shape of a todo line (with or without text after `]`).
  /// Used for "is this line part of the tasks section" detection.
  static final RegExp todoLine =
      RegExp(r'^\s*[-*+]\s*\[\s*[xX\s]\s*\]');

  /// Matches a todo line that has text. Group 1 is the checkbox content
  /// (`x`, `X` or whitespace), group 2 is the task text.
  static final RegExp _todoLineWithText =
      RegExp(r'^\s*[-*+]\s*\[\s*([xX\s])\s*\]\s+(.+)$');

  /// Matches an event line: bullet followed by `@HH:MM` (24h).
  /// Group 1 is hours (1-2 digits), group 2 is minutes (2 digits).
  static final RegExp eventLine =
      RegExp(r'^\s*[-*+]\s*@(\d{1,2}):(\d{2})\b\s*(.*)$');

  /// Matches any header (level 1-6).
  static final RegExp headerLine = RegExp(r'^\s*#{1,6}\s+');

  /// Matches a non-task bullet line (used by parseNotes).
  static final RegExp _bulletLine = RegExp(r'^\s*[-*+]\s+');

  static final RegExp _lineBreak = RegExp(r'\r?\n');

  /// Split [content] into lines, accepting CRLF as well as LF: files edited
  /// on Windows keep a trailing `\r` on every line otherwise, and none of
  /// the `...$` patterns above would match.
  static List<String> splitLines(String content) => content.split(_lineBreak);

  /// True if [line] is a markdown todo (checked or unchecked).
  static bool isTodoLine(String line) => todoLine.hasMatch(line);

  /// True if [line] is an event line — a bullet followed by `@HH:MM`.
  static bool isEventLine(String line) => eventLine.hasMatch(line);

  /// Parse tasks from markdown content.
  static List<TaskItem> parseTasks(String content) {
    final tasks = <TaskItem>[];
    final lines = splitLines(content);
    for (var i = 0; i < lines.length; i++) {
      final m = _todoLineWithText.firstMatch(lines[i]);
      if (m == null) continue;
      tasks.add(TaskItem(
        text: m.group(2)!.trim(),
        isCompleted: m.group(1)!.toLowerCase() == 'x',
        line: i,
      ));
    }
    return tasks;
  }

  /// Parse "free text" notes from markdown — everything that isn't a task,
  /// an event or its description, a header, or (with [logHeaderRegex]) a
  /// line of the logs section. Bullet markers are stripped.
  static List<String> parseNotes(String content, {String? logHeaderRegex}) =>
      parseFreeText(content, logHeaderRegex: logHeaderRegex).notes;

  /// Split the free text of [content] between the logs section - the one
  /// under the first header matching [logHeaderRegex], up to the next
  /// header - and the notes, i.e. everything else. Bullet markers are
  /// stripped.
  static ({List<String> notes, List<String> logs}) parseFreeText(
    String content, {
    String? logHeaderRegex,
  }) {
    final notes = <String>[];
    final logs = <String>[];
    final logHeader = _headerRegex(logHeaderRegex);
    final lines = splitLines(content);
    final kinds = _classify(lines);
    var inLogs = false;
    var logsSeen = false;
    for (var i = 0; i < lines.length; i++) {
      if (kinds[i] == _LineKind.header) {
        // Only the first matching section holds the logs, as for inserts.
        inLogs = !logsSeen && logHeader != null && logHeader.hasMatch(lines[i]);
        logsSeen |= inLogs;
        continue;
      }
      if (kinds[i] != _LineKind.text) continue;
      final trimmed = lines[i].trim();
      final clean = _bulletLine.hasMatch(trimmed)
          ? trimmed.replaceFirst(_bulletLine, '').trim()
          : trimmed;
      if (clean.isEmpty) continue;
      (inLogs ? logs : notes).add(clean);
    }
    return (notes: notes, logs: logs);
  }

  /// Parse events from markdown content. Only lines shaped like
  /// `- @HH:MM <title>` (with bullet) are considered events; a stray
  /// `@9:00` mention inside a note or description is ignored.
  static List<CalendarEvent> parseEvents(String date, String content) {
    final events = <CalendarEvent>[];
    final lines = splitLines(content);

    int year, month, day;
    try {
      year = int.parse(date.substring(0, 4));
      month = int.parse(date.substring(4, 6));
      day = int.parse(date.substring(6, 8));
    } catch (e) {
      Log.e('MarkdownParser: invalid date "$date"', error: e);
      return events;
    }

    final kinds = _classify(lines);
    for (var i = 0; i < lines.length; i++) {
      if (kinds[i] != _LineKind.event) continue;
      final m = eventLine.firstMatch(lines[i])!;

      try {
        final hour = int.parse(m.group(1)!);
        final minute = int.parse(m.group(2)!);
        final title = m.group(3)!.trim();
        final description = [
          for (var j = i + 1;
              j < lines.length && kinds[j] == _LineKind.eventDescription;
              j++)
            lines[j].trim(),
        ].join('\n');
        events.add(CalendarEvent(
          title: title,
          time: DateTime(year, month, day, hour, minute),
          description: description,
          date: date,
        ));
      } catch (e) {
        Log.e('MarkdownParser: error parsing event on line ${i + 1}', error: e);
      }
    }
    return events;
  }

  /// Index just past the description of the event at [eventIndex] in
  /// [lines]: where a line written after that event must go.
  static int eventBlockEnd(List<String> lines, int eventIndex) {
    final kinds = _classify(lines);
    var end = eventIndex + 1;
    while (end < lines.length && kinds[end] == _LineKind.eventDescription) {
      end++;
    }
    return end;
  }

  /// Lines after an event, indented no deeper than it, that still count as
  /// its description. Deeper lines always do, however many: the ICS import
  /// writes them.
  static const int _maxLooseDescriptionLines = 4;

  static int _indentOf(String line) => line.length - line.trimLeft().length;

  /// What each of [lines] is. The lines after an event are its description
  /// until a blank line, a header, a todo, another event, or a bullet at
  /// the event's own level (a sibling item, not a description).
  static List<_LineKind> _classify(List<String> lines) {
    final kinds = List.filled(lines.length, _LineKind.text);
    var descriptionLines = -1; // -1: not right after an event
    var eventIndent = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      final kind = trimmed.isEmpty
          ? _LineKind.blank
          : headerLine.hasMatch(trimmed)
              ? _LineKind.header
              : isTodoLine(trimmed)
                  ? _LineKind.todo
                  : isEventLine(trimmed)
                      ? _LineKind.event
                      : _LineKind.text;
      if (kind == _LineKind.text && descriptionLines >= 0) {
        final deeper = _indentOf(line) > eventIndent;
        if (deeper ||
            (!_bulletLine.hasMatch(trimmed) &&
                descriptionLines < _maxLooseDescriptionLines)) {
          kinds[i] = _LineKind.eventDescription;
          descriptionLines++;
          continue;
        }
      }
      kinds[i] = kind;
      descriptionLines = kind == _LineKind.event ? 0 : -1;
      if (kind == _LineKind.event) eventIndent = _indentOf(line);
    }
    return kinds;
  }

  /// [pattern] compiled, or null when empty or invalid (it comes from the
  /// user's settings).
  static RegExp? _headerRegex(String? pattern) {
    if (pattern == null || pattern.isEmpty) return null;
    try {
      return RegExp(pattern, multiLine: true);
    } on FormatException catch (e) {
      Log.w('MarkdownParser: invalid header pattern "$pattern"', error: e);
      return null;
    }
  }
}

enum _LineKind { blank, header, todo, event, eventDescription, text }

class TaskItem {
  final String text;
  final bool isCompleted;

  /// Index of the task's line in the parsed content, -1 if unknown.
  final int line;

  TaskItem({required this.text, required this.isCompleted, this.line = -1});
}
