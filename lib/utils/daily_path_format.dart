import 'package:planetxt/utils/conflict_files.dart';

/// Maps a calendar date to the store-relative path of that day's note file,
/// from a user-configurable format string (see Settings → Daily File Layout).
///
/// Tokens follow the `strftime` conventions:
///   `%Y` → 4-digit year    (`2026`)
///   `%m` → 2-digit month   (`01`..`12`)
///   `%d` → 2-digit day     (`01`..`31`)
///   `*`  → any file name   (optional; only the last path segment)
///
/// Examples:
///   `dailies/%Y%m%d.md`            → `dailies/20260713.md`      (the default)
///   `cal/%Y/%m/%d/daily.md`        → `cal/2026/07/13/daily.md`
///   `cal/%Y/%m/%d/*.md`            → one file per day, any name
///
/// A `*` in the file-name segment makes the app read whatever `.md` file a
/// day directory holds (so existing repositories are picked up); new files
/// are written as `daily.md` inside that directory.
class DailyPathFormat {
  final String format;

  DailyPathFormat(this.format);

  static const String yearToken = '%Y';
  static const String monthToken = '%m';
  static const String dayToken = '%d';
  static const String wildcard = '*';

  static const List<String> _tokens = [yearToken, monthToken, dayToken];

  /// Whether the format asks for any file name (`*`) in the last segment.
  bool get hasWildcard => format.contains(wildcard);

  /// The first date-token position, or -1 when the format has no tokens.
  int get _firstTokenIndex {
    int? best;
    for (final token in _tokens) {
      final index = format.indexOf(token);
      if (index != -1 && (best == null || index < best)) best = index;
    }
    return best ?? -1;
  }

  /// Directory to scan for daily files: the literal path prefix before the
  /// first date token (e.g. `cal` for `cal/%Y/%m/%d/daily.md`).
  String get scanDir {
    final index = _firstTokenIndex;
    if (index == -1) {
      final last = format.lastIndexOf('/');
      return last == -1 ? '' : format.substring(0, last);
    }
    var prefix = format.substring(0, index);
    if (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return prefix;
  }

  /// Whether scanning must recurse into subdirectories: true when date
  /// tokens appear inside path segments (a `YYYY/MM/DD` layout).
  bool get recursive {
    final index = _firstTokenIndex;
    if (index == -1) return false;
    return format.substring(index).contains('/');
  }

  /// Store-relative path for a `yyyyMMdd` [date]. A `*` wildcard is replaced
  /// with the canonical file name `daily` (used when writing a new file).
  String pathForDate(String date) {
    final year = date.substring(0, 4);
    final month = date.substring(4, 6);
    final day = date.substring(6, 8);
    return format
        .replaceAll(yearToken, year)
        .replaceAll(monthToken, month)
        .replaceAll(dayToken, day)
        .replaceAll(wildcard, 'daily');
  }

  /// The store-relative directory that holds a date's file(s): [pathForDate]
  /// up to the last `/` (e.g. `cal/2026/07/13`). Empty when the format has
  /// no directory part.
  String directoryForDate(String date) {
    final path = pathForDate(date);
    final last = path.lastIndexOf('/');
    return last == -1 ? '' : path.substring(0, last);
  }

  /// Extract the `yyyyMMdd` date from a scanned store-relative path, or
  /// `null` when it does not match the format. Conflict copies (see
  /// [isConflictCopy]) never map to a date.
  String? dateFromPath(String relPath) {
    if (isConflictCopy(relPath)) return null;
    final match = _regex.firstMatch(relPath);
    if (match == null) return null;
    if (_yearGroup == -1 || _monthGroup == -1 || _dayGroup == -1) return null;

    final year = int.parse(match.group(_yearGroup)!);
    final month = int.parse(match.group(_monthGroup)!);
    final day = int.parse(match.group(_dayGroup)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    // DateTime normalises invalid days (e.g. Feb 31), so compare to reject
    // impossible dates rather than silently re-mapping them.
    final parsed = DateTime(year, month, day);
    if (parsed.month != month || parsed.day != day) return null;

    return '${match.group(_yearGroup)}${match.group(_monthGroup)}'
        '${match.group(_dayGroup)}';
  }

  /// Regex derived from [format]: date tokens become capture groups, a `*`
  /// matches any file name, everything else is matched literally.
  late final RegExp _regex = RegExp(_buildRegex());

  /// Capture-group index of each date token, in the order they appear in the
  /// format (so `%m/%d/%Y` still maps correctly).
  int _yearGroup = -1;
  int _monthGroup = -1;
  int _dayGroup = -1;

  String _buildRegex() {
    final buffer = StringBuffer();
    var i = 0;
    var group = 0;
    while (i < format.length) {
      final char = format[i];
      switch (char) {
        case '%':
          // Try to match a multi-char token (`%Y`, `%m`, `%d`).
          String? token;
          for (final t in _tokens) {
            if (format.startsWith(t, i)) {
              token = t;
              break;
            }
          }
          if (token == null) {
            buffer.write(_escapeLiteral('%'));
            i++;
          } else {
            group++;
            switch (token) {
              case yearToken:
                _yearGroup = group;
                buffer.write(r'(\d{4})');
              case monthToken:
                _monthGroup = group;
                buffer.write(r'(\d{2})');
              case dayToken:
                _dayGroup = group;
                buffer.write(r'(\d{2})');
            }
            i += token.length;
          }
          break;
        case '*':
          buffer.write(r'[^/]+');
          i++;
          break;
        default:
          buffer.write(_escapeLiteral(char));
          i++;
      }
    }
    return buffer.toString();
  }

  /// Escape one regex metacharacter literally.
  static String _escapeLiteral(String char) {
    const specials = r'\.+*?[]^$(){}=!<>|:-';
    return specials.contains(char) ? '\\$char' : char;
  }
}
