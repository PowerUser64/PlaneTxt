import 'package:planetxt/models/calendar_event.dart';
import 'package:planetxt/utils/logger.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// One content line of an ICS component: `NAME;PARAM=VALUE:value`.
class _IcsProperty {
  final Map<String, String> params;
  final String value;
  const _IcsProperty(this.params, this.value);
}

class IcsParserService {
  /// Parse ICS content and extract calendar events
  /// Returns a list of CalendarEvent objects
  static List<CalendarEvent> parseIcsContent(String icsContent) {
    final events = <CalendarEvent>[];

    try {
      Log.d('📅 IcsParserService: Starting to parse ICS content');

      final vEvents = _extractVEvents(_unfoldedLines(icsContent));
      Log.d(
          '📅 IcsParserService: Found ${vEvents.length} VEVENT components to process');

      for (final vEvent in vEvents) {
        try {
          final event = _parseVEvent(vEvent);
          if (event != null) {
            events.add(event);
            Log.d(
                '📅 IcsParserService: Successfully parsed event: ${event.title}');
          } else {
            Log.w('⚠️  IcsParserService: VEVENT parsing returned null');
          }
        } catch (e) {
          Log.e('❌ IcsParserService: Error parsing VEVENT component', error: e);
          continue;
        }
      }

      Log.i(
          '📅 IcsParserService: Successfully parsed ${events.length} events from ICS content');
    } catch (e) {
      Log.e('❌ IcsParserService: Error parsing ICS content', error: e);
      throw Exception('Failed to parse ICS content: ${e.toString()}');
    }

    return events;
  }

  /// Content lines with folding undone: RFC 5545 continues a long line on
  /// the next one, starting with a space or a tab.
  static List<String> _unfoldedLines(String content) => content
      .replaceAll(RegExp(r'\r?\n[ \t]'), '')
      .split(RegExp(r'\r?\n'));

  /// The properties of each VEVENT. Those of nested components (a VALARM's
  /// DESCRIPTION, say) are left out, and the first occurrence of a
  /// property wins.
  static List<Map<String, _IcsProperty>> _extractVEvents(List<String> lines) {
    final vEvents = <Map<String, _IcsProperty>>[];
    Map<String, _IcsProperty>? current;
    var depth = 0; // components open inside the current VEVENT
    for (final raw in lines) {
      final line = raw.trimRight();
      final upper = line.toUpperCase();
      if (current == null) {
        if (upper == 'BEGIN:VEVENT') {
          current = {};
          depth = 0;
        }
        continue;
      }
      if (upper.startsWith('BEGIN:')) {
        depth++;
      } else if (upper.startsWith('END:')) {
        if (depth == 0) {
          vEvents.add(current);
          current = null;
        } else {
          depth--;
        }
      } else if (depth == 0) {
        final property = _parseProperty(line);
        if (property != null) current.putIfAbsent(property.$1, () => property.$2);
      }
    }
    return vEvents;
  }

  /// Split `NAME;PARAM=VALUE:value` at the first colon outside quotes: a
  /// quoted parameter value may hold one.
  static (String, _IcsProperty)? _parseProperty(String line) {
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ':' && !inQuotes) {
        final head = line.substring(0, i).split(';');
        if (head.first.isEmpty) return null;
        final params = <String, String>{};
        for (final param in head.skip(1)) {
          final eq = param.indexOf('=');
          if (eq > 0) {
            params[param.substring(0, eq).toUpperCase()] =
                param.substring(eq + 1).replaceAll('"', '');
          }
        }
        return (
          head.first.toUpperCase(),
          _IcsProperty(params, line.substring(i + 1)),
        );
      }
    }
    return null;
  }

  /// Parse a VEVENT component into a CalendarEvent
  static CalendarEvent? _parseVEvent(Map<String, _IcsProperty> properties) {
    Log.d(
        '📅 IcsParserService: VEVENT properties: ${properties.keys.join(", ")}');

    final dtStart = properties['DTSTART'];
    // One line in the daily file: no line breaks in the title.
    final summary = properties['SUMMARY'] == null
        ? ''
        : _unescape(properties['SUMMARY']!.value)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

    if (dtStart == null || summary.isEmpty) {
      Log.w(
          '⚠️  IcsParserService: VEVENT missing required properties (DTSTART: ${dtStart?.value}, SUMMARY: $summary)');
      return null;
    }

    final eventDateTime = _parseIcsDateTime(dtStart);
    if (eventDateTime == null) {
      Log.w('⚠️  IcsParserService: Failed to parse DTSTART: ${dtStart.value}');
      return null;
    }

    // Format date as YYYYMMDD
    final date =
        '${eventDateTime.year}${eventDateTime.month.toString().padLeft(2, '0')}${eventDateTime.day.toString().padLeft(2, '0')}';

    final description =
        _unescape(properties['DESCRIPTION']?.value ?? '').trim();

    Log.d(
        '📅 IcsParserService: Parsed event - Title: $summary, Date: $date, Time: $eventDateTime');

    return CalendarEvent(
      title: summary,
      time: eventDateTime,
      description: description,
      date: date,
    );
  }

  /// Undo the escaping of RFC 5545 text values: `\n`, `\,`, `\;`, `\\`.
  static String _unescape(String value) => value.replaceAllMapped(
        RegExp(r'\\([nN,;\\])'),
        (m) => switch (m[1]) { 'n' || 'N' => '\n', final c => c! },
      );

  static final RegExp _dateTime =
      RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?$');

  /// Parse a DTSTART into the device's local time: a UTC time (`Z`) or a
  /// time in its TZID zone is converted, a floating time is kept as
  /// written, and a date without a time (all-day event) gets 09:00.
  static DateTime? _parseIcsDateTime(_IcsProperty property) {
    final m = _dateTime.firstMatch(property.value.trim());
    if (m == null) {
      Log.e('❌ IcsParserService: Error parsing datetime: ${property.value}');
      return null;
    }
    final year = int.parse(m[1]!);
    final month = int.parse(m[2]!);
    final day = int.parse(m[3]!);
    if (m[4] == null) return DateTime(year, month, day, 9, 0, 0);

    final hour = int.parse(m[4]!);
    final minute = int.parse(m[5]!);
    final second = int.parse(m[6] ?? '0');
    if (m[7] != null) {
      return DateTime.utc(year, month, day, hour, minute, second).toLocal();
    }
    final tzid = property.params['TZID'];
    if (tzid != null) {
      final converted =
          _fromZone(tzid, year, month, day, hour, minute, second);
      if (converted != null) return converted;
    }
    return DateTime(year, month, day, hour, minute, second);
  }

  /// The local time of [hour]:[minute] in the IANA zone [tzid], or null if
  /// the zone is unknown (Outlook writes Windows zone names).
  static DateTime? _fromZone(String tzid, int year, int month, int day,
      int hour, int minute, int second) {
    try {
      // Initialised once only: doing it again resets tz.local, which the
      // notification service has set.
      if (!tz.timeZoneDatabase.isInitialized) tz_data.initializeTimeZones();
      final inZone = tz.TZDateTime(
          tz.getLocation(tzid), year, month, day, hour, minute, second);
      return DateTime.fromMillisecondsSinceEpoch(
          inZone.millisecondsSinceEpoch);
    } catch (e) {
      Log.w('⚠️  IcsParserService: Unknown time zone "$tzid", keeping the '
          'time as written', error: e);
      return null;
    }
  }

  /// Validate that the content looks like ICS format
  static bool isValidIcsContent(String content) {
    if (content.isEmpty) return false;

    // Check for basic ICS structure
    final hasBeginCalendar = content.contains('BEGIN:VCALENDAR');
    final hasEndCalendar = content.contains('END:VCALENDAR');
    final hasVersion = content.contains('VERSION:');

    return hasBeginCalendar && hasEndCalendar && hasVersion;
  }
}
