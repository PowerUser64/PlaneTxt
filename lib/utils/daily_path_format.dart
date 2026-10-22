import 'package:planetxt/utils/conflict_files.dart';

/// Maps a calendar date to the store-relative path of that day's note file,
/// from two user-configurable settings (see Settings → Daily File Layout): a
/// directory and a file name, both supporting date expansion.
///
/// Tokens follow the `strftime` conventions:
///   `%Y` → 4-digit year    (`2026`)
///   `%m` → 2-digit month   (`01`..`12`)
///   `%d` → 2-digit day     (`01`..`31`)
///
/// The directory setting decides where each date lives (e.g. `dailies` or
/// `cal/%Y/%m/%d`); the file name setting decides what a new daily note is
/// called (e.g. `%Y%m%d.md` or `daily.md`).
///
/// Examples:
///   directory `dailies`, file name `%Y%m%d.md`
///       → `dailies/20260713.md`                      (the default)
///   directory `cal/%Y/%m/%d`, file name `daily.md`
///       → `cal/2026/07/13/daily.md`                  (Notes-style repo)
///
/// Scanning indexes every `.md` note in each day's directory: when the
/// directory carries the date tokens, any file name inside that directory is
/// a daily note; the file name setting only names newly created files.
class DailyPathFormat {
  final String directory;
  final String fileName;

  DailyPathFormat(this.directory, this.fileName);

  static const String yearToken = '%Y';
  static const String monthToken = '%m';
  static const String dayToken = '%d';

  static const List<String> _tokens = [yearToken, monthToken, dayToken];

  /// Whether [directory] carries a date token: each date then lives in its
  /// own directory, so scanning accepts every `.md` note in it.
  bool get directoryHasDate => _hasDateToken(directory);

  bool _hasDateToken(String value) =>
      value.contains(yearToken) ||
      value.contains(monthToken) ||
      value.contains(dayToken);

  /// The first date-token position in [directory], or -1 when the directory
  /// carries none.
  int get _firstTokenIndex {
    int? best;
    for (final token in _tokens) {
      final index = directory.indexOf(token);
      if (index != -1 && (best == null || index < best)) best = index;
    }
    return best ?? -1;
  }

  /// Directory to scan for daily files: the literal path prefix before the
  /// first date token in the directory setting (e.g. `cal` for
  /// `cal/%Y/%m/%d`), or the whole directory when it has no tokens.
  String get scanDir {
    final index = _firstTokenIndex;
    if (index == -1) return _trimTrailingSlash(directory);
    var prefix = directory.substring(0, index);
    if (prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    return _trimTrailingSlash(prefix);
  }

  /// Whether scanning must recurse into subdirectories: true when date
  /// tokens appear inside directory segments (a `YYYY/MM/DD` layout).
  bool get recursive {
    final index = _firstTokenIndex;
    if (index == -1) return false;
    return directory.substring(index).contains('/');
  }

  String _trimTrailingSlash(String value) {
    var v = value;
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// Store-relative path for a `yyyyMMdd` [date]: the expanded directory and
  /// the expanded file name joined.
  String pathForDate(String date) {
    final year = date.substring(0, 4);
    final month = date.substring(4, 6);
    final day = date.substring(6, 8);
    final dir = _expand(directory, year, month, day);
    final name = _expand(fileName, year, month, day);
    return dir.isEmpty ? name : '$dir/$name';
  }

  /// The store-relative directory that holds a date's file(s), from the
  /// directory setting (e.g. `cal/2026/07/13`). Empty when the directory
  /// setting is empty (a flat layout at the storage root).
  String directoryForDate(String date) {
    final year = date.substring(0, 4);
    final month = date.substring(4, 6);
    final day = date.substring(6, 8);
    return _expand(directory, year, month, day);
  }

  String _expand(String value, String year, String month, String day) => value
      .replaceAll(yearToken, year)
      .replaceAll(monthToken, month)
      .replaceAll(dayToken, day);

  /// Extract the `yyyyMMdd` date from a scanned store-relative path, or
  /// `null` when it does not map to a date.
  ///
  /// The directory setting's date tokens are authoritative; when the file
  /// name setting itself carries date tokens (a flat layout like `dailies` +
  /// `%Y%m%d.md`), those are matched too. Otherwise any file name inside a
  /// day directory is accepted, so every note there is indexed.
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

  /// Regex derived from the directory + file name settings: date tokens
  /// become capture groups (first occurrence wins, so the directory is
  /// authoritative), everything else is matched literally. A file name
  /// without date tokens matches any `.md` name.
  late final RegExp _regex = RegExp(_buildRegex());

  /// Capture-group index of each date token, in the order they first appear
  /// in the directory + file name settings.
  int _yearGroup = -1;
  int _monthGroup = -1;
  int _dayGroup = -1;

  String _buildRegex() {
    final buffer = StringBuffer();
    var group = 0;

    void writeSegment(String segment, {required bool anyFileName}) {
      if (anyFileName) {
        buffer.write(r'[^/]+\.md');
        return;
      }
      var i = 0;
      while (i < segment.length) {
        final char = segment[i];
        switch (char) {
          case '%':
            // Try to match a multi-char token (`%Y`, `%m`, `%d`).
            String? token;
            for (final t in _tokens) {
              if (segment.startsWith(t, i)) {
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
                  if (_yearGroup == -1) _yearGroup = group;
                  buffer.write(r'(\d{4})');
                case monthToken:
                  if (_monthGroup == -1) _monthGroup = group;
                  buffer.write(r'(\d{2})');
                case dayToken:
                  if (_dayGroup == -1) _dayGroup = group;
                  buffer.write(r'(\d{2})');
              }
              i += token.length;
            }
            break;
          default:
            buffer.write(_escapeLiteral(char));
            i++;
        }
      }
    }

    writeSegment(directory, anyFileName: false);
    if (directory.isNotEmpty) buffer.write('/');
    // A file name carrying date tokens (flat layout) is matched literally so
    // the date can be read from it; otherwise every `.md` name is accepted.
    writeSegment(fileName, anyFileName: !_hasDateToken(fileName));
    return buffer.toString();
  }

  /// Escape one regex metacharacter literally.
  static String _escapeLiteral(String char) {
    const specials = r'\.+*?[]^$(){}=!<>|:-';
    return specials.contains(char) ? '\\$char' : char;
  }
}
