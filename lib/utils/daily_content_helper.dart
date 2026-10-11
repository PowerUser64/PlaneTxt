import 'package:planetxt/models/calendar_event.dart';
import 'package:planetxt/utils/logger.dart';
import 'package:planetxt/utils/markdown_parser.dart';

/// Bounds of a markdown section: the index of its `## Header` line and the
/// index just past the section's last line.
class _SectionRange {
  final int headerIndex;
  final int endExclusive; // points past last line of the section
  const _SectionRange(this.headerIndex, this.endExclusive);

  bool get found => headerIndex >= 0;
}

/// Utility functions for working with daily file content.
class DailyContentHelper {
  // ---- shared helpers ------------------------------------------------------

  static String _appendAtEnd(String content, String newContent) {
    if (content.isEmpty) return newContent;
    return content.endsWith('\n')
        ? '$content$newContent'
        : '$content\n\n$newContent';
  }

  /// Find the section identified by the first line matching [headerRegex].
  ///
  /// If [strictItemPredicate] is provided, the section ends at the first
  /// non-empty, non-header line that does not match the predicate (this is
  /// how task/event sections are bounded — a stray note ends the section).
  /// Otherwise the section runs until the next header (or end of file).
  static _SectionRange _findSection(
    List<String> lines,
    RegExp headerRegex, {
    bool Function(String trimmedLine)? strictItemPredicate,
  }) {
    int? headerIndex;
    for (var i = 0; i < lines.length; i++) {
      if (headerRegex.hasMatch(lines[i])) {
        headerIndex = i;
        break;
      }
    }
    if (headerIndex == null) return const _SectionRange(-1, -1);

    var end = headerIndex + 1;
    while (end < lines.length) {
      final t = lines[end].trim();
      if (t.isEmpty) {
        end++;
        continue;
      }
      if (t.startsWith('#')) break;
      if (strictItemPredicate != null && !strictItemPredicate(t)) break;
      end++;
    }
    return _SectionRange(headerIndex, end);
  }

  /// Run [edit] on [content] with LF line endings, then restore CRLF if the
  /// file used it, so an insertion never leaves a file with mixed endings.
  static String _keepingLineEndings(
    String content,
    String Function(String lfContent) edit,
  ) {
    if (!content.contains('\r\n')) return edit(content);
    final result = edit(content.replaceAll('\r\n', '\n'));
    return result.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
  }

  static bool _isEventLine(String line) => MarkdownParser.isEventLine(line);
  static bool _isTodoLine(String line) => MarkdownParser.isTodoLine(line);

  // ---- public API ----------------------------------------------------------

  /// Inserts content after the first header matching [headerRegex].
  /// If no matching header is found, appends the content to the end.
  static String insertAfterHeader(
    String content,
    String newContent,
    String headerRegex,
  ) =>
      _keepingLineEndings(
          content, (c) => _insertAfterHeader(c, newContent, headerRegex));

  static String _insertAfterHeader(
    String content,
    String newContent,
    String headerRegex,
  ) {
    if (headerRegex.isEmpty) return _appendAtEnd(content, newContent);

    try {
      final regex = RegExp(headerRegex, multiLine: true);
      final lines = content.split('\n');

      int? headerIndex;
      for (var i = 0; i < lines.length; i++) {
        if (regex.hasMatch(lines[i])) {
          headerIndex = i;
          break;
        }
      }
      if (headerIndex == null) return _appendAtEnd(content, newContent);

      var insertIndex = headerIndex + 1;
      while (insertIndex < lines.length && lines[insertIndex].trim().isEmpty) {
        insertIndex++;
      }

      final beforeInsert = lines.sublist(0, insertIndex).join('\n');
      final afterInsert = lines.sublist(insertIndex).join('\n');
      final nextLine = afterInsert.split('\n').firstOrNull?.trim() ?? '';
      final nextIsHeader = nextLine.startsWith('#');

      if (afterInsert.isNotEmpty) {
        return nextIsHeader
            ? '$beforeInsert\n$newContent\n\n$afterInsert'
            : '$beforeInsert\n$newContent\n$afterInsert';
      }
      return '$beforeInsert\n$newContent';
    } catch (e) {
      Log.e('DailyContentHelper: invalid regex "$headerRegex"', error: e);
      return _appendAtEnd(content, newContent);
    }
  }

  /// Inserts events into the events section in chronological order, creating
  /// the section at the end of the file if needed. Existing duplicate events
  /// (same time + title) are preserved; new ones are merged in.
  static String insertEventsChronologically(
    String content,
    List<String> eventLines,
    String eventHeaderRegex,
  ) =>
      _keepingLineEndings(content,
          (c) => _insertEventsChronologically(c, eventLines, eventHeaderRegex));

  static String _insertEventsChronologically(
    String content,
    List<String> eventLines,
    String eventHeaderRegex,
  ) {
    try {
      final regex = RegExp(eventHeaderRegex, multiLine: true);
      final lines = content.split('\n');
      final range =
          _findSection(lines, regex, strictItemPredicate: _isEventLine);
      final sortedNew = _sortEventLinesChronologically(eventLines);

      if (range.found) {
        final beforeEvents = lines.sublist(0, range.headerIndex + 1);
        final eventsBlock =
            lines.sublist(range.headerIndex + 1, range.endExclusive);
        final afterEventsSection = lines.sublist(range.endExclusive);

        final existingEvents =
            eventsBlock.where((l) => _isEventLine(l.trim())).toList();
        final newOnly = sortedNew.where((newE) => !existingEvents.any((e) =>
            _eventsAreSame(e.trim(), newE)));
        // Existing events must be re-inserted alongside the new ones —
        // they were stripped from eventsBlock above.
        final merged = _sortEventLinesChronologically(
            [...existingEvents, ...newOnly]);

        return [
          ...beforeEvents,
          ...eventsBlock.where((l) => !_isEventLine(l.trim())),
          ...merged,
          if (afterEventsSection.isNotEmpty) ...afterEventsSection,
        ].join('\n');
      }
      // No section header found — append a fresh block at the end.
      return _appendAtEnd(content, sortedNew.join('\n'));
    } catch (e) {
      Log.e('DailyContentHelper: error inserting events chronologically',
          error: e);
      return _appendAtEnd(content, eventLines.join('\n'));
    }
  }

  /// Sort event lines chronologically by their `@HH:MM` time.
  static List<String> _sortEventLinesChronologically(List<String> eventLines) {
    final withTimes = eventLines.map((line) {
      final m = MarkdownParser.eventLine.firstMatch(line);
      final t = m == null
          ? 0
          : int.parse(m.group(1)!) * 100 + int.parse(m.group(2)!);
      return MapEntry(t, line);
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return withTimes.map((e) => e.value).toList();
  }

  /// Two event lines are considered the same if their text after the time
  /// matches.
  static bool _eventsAreSame(String existing, String newEvent) {
    final stripTime = RegExp(r'^\s*[-*+]\s*@\d{1,2}:\d{2}\s*');
    return existing.replaceFirst(stripTime, '').trim() ==
        newEvent.replaceFirst(stripTime, '').trim();
  }

  /// Inserts [events] (an ICS import) into the events section, each with
  /// its description indented below it, before the first event starting
  /// later. An event the day already has (same time and title) is skipped.
  /// Without an events section, they are appended at the end. Returns the
  /// new content and how many events were added.
  static ({String content, int added}) insertEvents(
    String content,
    List<CalendarEvent> events,
    String eventHeaderRegex,
  ) {
    var added = 0;
    final updated = _keepingLineEndings(content, (c) {
      added = 0;
      final lines = c.split('\n');
      final header = _firstMatchingLine(lines, eventHeaderRegex);
      final known = {
        for (final line in lines)
          if (MarkdownParser.eventLine.firstMatch(line.trim()) case final m?)
            _eventKey(int.parse(m[1]!) * 60 + int.parse(m[2]!), m[3]!),
      };
      final sorted = [...events]..sort((a, b) => a.time.compareTo(b.time));
      final appended = <String>[];
      for (final event in sorted) {
        final minutes = event.time.hour * 60 + event.time.minute;
        if (!known.add(_eventKey(minutes, event.title))) continue;
        added++;
        final block = [
          '- @${event.formattedTime} ${event.title}',
          for (final line in event.description.split('\n'))
            if (line.trim().isNotEmpty) '  ${line.trim()}',
        ];
        if (header < 0) {
          appended.addAll(block);
        } else {
          _insertEventBlock(lines, header, minutes, block);
        }
      }
      final result = lines.join('\n');
      return appended.isEmpty
          ? result
          : _appendAtEnd(result, appended.join('\n'));
    });
    return (content: updated, added: added);
  }

  static String _eventKey(int minutes, String title) =>
      '$minutes ${title.trim()}';

  /// Index of the first line matching [pattern], -1 if none (or invalid).
  static int _firstMatchingLine(List<String> lines, String pattern) {
    if (pattern.isEmpty) return -1;
    try {
      final regex = RegExp(pattern, multiLine: true);
      return lines.indexWhere(regex.hasMatch);
    } on FormatException catch (e) {
      Log.e('DailyContentHelper: invalid regex "$pattern"', error: e);
      return -1;
    }
  }

  /// Put [block] in the events section under [header]: before the first
  /// event starting after [minutes], else after the last event and its
  /// description, else right below the header.
  static void _insertEventBlock(
      List<String> lines, int header, int minutes, List<String> block) {
    var insertAt = -1;
    var afterLast = -1;
    var i = header + 1;
    while (i < lines.length) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }
      final m = MarkdownParser.eventLine.firstMatch(trimmed);
      if (m == null) break; // end of the section
      if (insertAt < 0 && int.parse(m[1]!) * 60 + int.parse(m[2]!) > minutes) {
        insertAt = i;
      }
      i = MarkdownParser.eventBlockEnd(lines, i);
      afterLast = i;
    }
    if (insertAt < 0 && afterLast < 0) {
      // First event: keep a blank line before whatever follows.
      insertAt = header + 1;
      if (insertAt < lines.length && lines[insertAt].trim().isNotEmpty) {
        block = [...block, ''];
      }
    }
    lines.insertAll(insertAt >= 0 ? insertAt : afterLast, block);
  }

  /// Inserts an event after the last existing event in the events section.
  /// If the section exists but is empty, inserts right after the header with
  /// a blank-line separator. If the section doesn't exist, appends to end.
  static String insertAfterLastEvent(
    String content,
    String eventContent,
    String eventHeaderRegex,
  ) =>
      _keepingLineEndings(content,
          (c) => _insertAfterLastEvent(c, eventContent, eventHeaderRegex));

  static String _insertAfterLastEvent(
    String content,
    String eventContent,
    String eventHeaderRegex,
  ) {
    final lines = content.split('\n');
    final header = _firstMatchingLine(lines, eventHeaderRegex);
    if (header < 0) return _appendAtEnd(content, eventContent);
    // After the last event's description, not between event and
    // description: no event starts later than 24:00.
    _insertEventBlock(lines, header, 24 * 60, eventContent.split('\n'));
    return lines.join('\n');
  }

  /// Inserts a todo after the last existing todo in the tasks section.
  /// If the section exists but is empty, inserts right after the header
  /// with a blank-line separator. If the section doesn't exist, appends.
  static String insertAfterLastTodo(
    String content,
    String todoContent,
    String todoHeaderRegex,
  ) =>
      _keepingLineEndings(content,
          (c) => _insertAfterLastTodo(c, todoContent, todoHeaderRegex));

  static String _insertAfterLastTodo(
    String content,
    String todoContent,
    String todoHeaderRegex,
  ) {
    if (todoHeaderRegex.isEmpty) return _appendAtEnd(content, todoContent);

    try {
      final regex = RegExp(todoHeaderRegex, multiLine: true);
      final lines = content.split('\n');
      final range =
          _findSection(lines, regex, strictItemPredicate: _isTodoLine);
      if (!range.found) return _appendAtEnd(content, todoContent);

      return _insertItem(
        lines: lines,
        range: range,
        newItem: todoContent,
        itemMatcher: _isTodoLine,
      );
    } catch (e) {
      Log.e('DailyContentHelper: error inserting todo after last todo',
          error: e);
      return _appendAtEnd(content, todoContent);
    }
  }

  /// Insert [newItem] after the last line in [range] that matches
  /// [itemMatcher]. If no items exist in the section yet, insert after the
  /// header with a blank-line separator before any subsequent content.
  static String _insertItem({
    required List<String> lines,
    required _SectionRange range,
    required String newItem,
    required bool Function(String line) itemMatcher,
  }) {
    var lastItemIndex = range.headerIndex;
    var hasItems = false;
    for (var i = range.headerIndex + 1; i < range.endExclusive; i++) {
      if (itemMatcher(lines[i])) {
        lastItemIndex = i;
        hasItems = true;
      }
    }

    if (hasItems) {
      final before = lines.sublist(0, lastItemIndex + 1).join('\n');
      final after = lines.sublist(lastItemIndex + 1).join('\n');
      return after.isNotEmpty ? '$before\n$newItem\n$after' : '$before\n$newItem';
    }

    // No items yet — insert right after the header with appropriate spacing.
    final before = lines.sublist(0, range.headerIndex + 1).join('\n');
    final after = lines.sublist(range.headerIndex + 1).join('\n');
    return after.isNotEmpty
        ? '$before\n$newItem\n\n$after'
        : '$before\n\n$newItem';
  }

  static final RegExp _checkbox = RegExp(r'^(\s*[-*+]\s*\[)\s*[xX\s]\s*(\])');

  /// Checks ([done]) or unchecks the todo [task] was parsed from: the one
  /// at [TaskItem.line], or if the file changed since, the first todo with
  /// the same text and state. [content] is returned unchanged when no such
  /// todo is left. Only the checkbox changes.
  static String setTodoDone(String content, TaskItem task, bool done) =>
      _keepingLineEndings(content, (c) {
        final lines = c.split('\n');
        bool isTask(int i) {
          final parsed = MarkdownParser.parseTasks(lines[i]);
          return parsed.length == 1 &&
              parsed.single.text == task.text &&
              parsed.single.isCompleted == task.isCompleted;
        }

        var index = task.line;
        if (index < 0 || index >= lines.length || !isTask(index)) {
          index = Iterable<int>.generate(lines.length)
              .firstWhere(isTask, orElse: () => -1);
        }
        if (index < 0) return c;
        lines[index] = lines[index].replaceFirstMapped(
            _checkbox, (m) => '${m[1]}${done ? 'x' : ' '}${m[2]}');
        return lines.join('\n');
      });

  /// Removes one undone todo line per entry of [todoTexts], matched on the
  /// parsed task text: `* [ ]` bullets or extra spaces still match.
  /// Checked todos are left alone.
  static String removeUndoneTodos(String content, List<String> todoTexts) =>
      _keepingLineEndings(content, (c) {
        final remaining = <String, int>{};
        for (final text in todoTexts) {
          remaining[text] = (remaining[text] ?? 0) + 1;
        }
        final kept = <String>[];
        for (final line in c.split('\n')) {
          final tasks = MarkdownParser.parseTasks(line);
          final text = tasks.isEmpty ? null : tasks.single.text;
          final left = text == null ? 0 : remaining[text] ?? 0;
          if (left > 0 && !tasks.single.isCompleted) {
            remaining[text!] = left - 1;
            continue;
          }
          kept.add(line);
        }
        return kept.join('\n');
      });

  /// Inserts content at the end of a section (just before the next `#`
  /// header). If no matching section exists, appends to the end of the file.
  static String insertAtEndOfSection(
    String content,
    String newContent,
    String sectionHeaderRegex,
  ) =>
      _keepingLineEndings(content,
          (c) => _insertAtEndOfSection(c, newContent, sectionHeaderRegex));

  static String _insertAtEndOfSection(
    String content,
    String newContent,
    String sectionHeaderRegex,
  ) {
    if (sectionHeaderRegex.isEmpty) return _appendAtEnd(content, newContent);

    try {
      final regex = RegExp(sectionHeaderRegex, multiLine: true);
      final lines = content.split('\n');
      // No item predicate: walk until the next header/EOF, regardless of
      // line shape.
      final range = _findSection(lines, regex);
      if (!range.found) return _appendAtEnd(content, newContent);

      // Walk back from sectionEnd to find the last non-empty line.
      var lastContentIndex = range.endExclusive - 1;
      while (lastContentIndex > range.headerIndex &&
          lines[lastContentIndex].trim().isEmpty) {
        lastContentIndex--;
      }

      final insertIndex = lastContentIndex + 1;
      final before = lines.sublist(0, insertIndex).join('\n');
      final after = lines.sublist(insertIndex).join('\n');
      return after.isNotEmpty ? '$before\n$newContent\n$after' : '$before\n$newContent';
    } catch (e) {
      Log.e('DailyContentHelper: error inserting at end of section', error: e);
      return _appendAtEnd(content, newContent);
    }
  }
}
