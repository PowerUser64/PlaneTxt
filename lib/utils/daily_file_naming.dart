import 'package:planetxt/utils/logger.dart';

/// Names the file of a day, and recognises the days' files by their name,
/// from a user-configured template such as `YYYYMMDD` (the default) or
/// `YYYY-MM-DD-Agenda`.
///
/// A template holds the placeholders `YYYY` (year), `MM` (month) and `DD`
/// (day), each exactly once; everything else is kept as written. The `.md`
/// extension is added when the template does not carry it - the stores only
/// ever list markdown files.
///
/// A day is always addressed inside the app by its `yyyyMMdd` key, never by
/// its file name: the template changes the file on disk, nothing else.
/// Names following [defaultTemplate] stay recognised whatever the template
/// is, so the days written before a change keep their file - and are still
/// written to it, see `DailyRepository.pathFor`.
class DailyFileNaming {
  static const String defaultTemplate = 'YYYYMMDD';

  /// The template, without the `.md` extension.
  final String template;

  final RegExp _namePattern;

  /// Position of the year, month and day among [_namePattern]'s groups.
  final int _yearGroup;
  final int _monthGroup;
  final int _dayGroup;

  /// Recognises the names [defaultTemplate] gives, for the days written
  /// before the template was changed. Null for the default naming itself.
  final DailyFileNaming? _fallback;

  DailyFileNaming._(
    this.template,
    this._namePattern,
    this._yearGroup,
    this._monthGroup,
    this._dayGroup,
    this._fallback,
  );

  static final DailyFileNaming _default = _build(defaultTemplate, null)!;

  static DailyFileNaming _current = _default;

  /// The configured naming, shared by everything that builds or reads the
  /// name of a daily file.
  static DailyFileNaming get current => _current;

  /// Name the days' files after [template] from now on. Nothing (the
  /// setting was never touched) or an invalid template falls back to
  /// [defaultTemplate]: a day must always have a file to be written to.
  static void useTemplate(String? template) {
    final normalized = normalize(template ?? '');
    if (normalized.isEmpty) {
      _current = _default;
      return;
    }
    if (normalized == _current.template) return;
    final naming = _build(normalized, _default);
    if (naming == null) {
      Log.w('⚠️ DailyFileNaming: Invalid template "$template", '
          'keeping the default naming');
      _current = _default;
      return;
    }
    Log.i('📅 DailyFileNaming: Daily files named after "$normalized"');
    _current = naming;
  }

  /// [template] without its `.md` extension and surrounding blanks.
  static String normalize(String template) {
    final trimmed = template.trim();
    return trimmed.toLowerCase().endsWith('.md')
        ? trimmed.substring(0, trimmed.length - 3)
        : trimmed;
  }

  /// Why [template] cannot name the days' files, or null when it can.
  static String? validate(String template) {
    final normalized = normalize(template);
    if (normalized.isEmpty) return 'The template cannot be empty.';
    if (normalized.contains('/') || normalized.contains('\\')) {
      return 'The template cannot hold a path separator.';
    }
    // A name that no synced filesystem would take, or that the stores use
    // for the temporary copy of a write in progress.
    if (_illegalInName.hasMatch(normalized)) {
      return 'The template cannot hold : * ? " < > | characters.';
    }
    if (normalized.startsWith('.')) {
      return 'The template cannot start with a dot.';
    }
    for (final placeholder in const ['YYYY', 'MM', 'DD']) {
      final count = _placeholder
          .allMatches(normalized)
          .where((m) => m.group(0) == placeholder)
          .length;
      if (count == 0) return 'The template must hold $placeholder.';
      if (count > 1) return 'The template must hold $placeholder only once.';
    }
    return null;
  }

  /// The name [template] would give the day [date] (`yyyyMMdd`), or null
  /// when it can name no day: lets the settings show what it would do
  /// before it is saved.
  static String? nameFrom(String template, String date) =>
      _build(normalize(template), null)?.fileName(date);

  /// Name of the file holding the day [date] (`yyyyMMdd`).
  String fileName(String date) {
    if (date.length != 8) {
      throw ArgumentError.value(date, 'date', 'must be a yyyyMMdd day');
    }
    final name = template
        .replaceAll('YYYY', date.substring(0, 4))
        .replaceAll('MM', date.substring(4, 6))
        .replaceAll('DD', date.substring(6, 8));
    return '$name.md';
  }

  /// The day (`yyyyMMdd`) whose file is named [pathOrName], or null when
  /// that file is not a day's.
  String? dateOf(String pathOrName) {
    final name = pathOrName.split('/').last;
    final match = _namePattern.firstMatch(name);
    if (match == null) return _fallback?.dateOf(name);
    return '${match.group(_yearGroup)}${match.group(_monthGroup)}'
        '${match.group(_dayGroup)}';
  }

  static final RegExp _placeholder = RegExp('YYYY|MM|DD');

  static final RegExp _illegalInName = RegExp(r'[\x00-\x1f:*?"<>|]');

  /// The naming [template] describes, or null when it describes none.
  static DailyFileNaming? _build(String template, DailyFileNaming? fallback) {
    if (validate(template) != null) return null;

    final pattern = StringBuffer('^');
    final groups = <String>[];
    var literalStart = 0;
    for (final match in _placeholder.allMatches(template)) {
      pattern.write(
          RegExp.escape(template.substring(literalStart, match.start)));
      final placeholder = match.group(0)!;
      groups.add(placeholder);
      pattern.write(switch (placeholder) {
        'YYYY' => r'(\d{4})',
        'MM' => r'(0[1-9]|1[0-2])',
        _ => r'(0[1-9]|[12]\d|3[01])',
      });
      literalStart = match.end;
    }
    pattern
      ..write(RegExp.escape(template.substring(literalStart)))
      ..write(r'\.md$');

    return DailyFileNaming._(
      template,
      RegExp(pattern.toString()),
      groups.indexOf('YYYY') + 1,
      groups.indexOf('MM') + 1,
      groups.indexOf('DD') + 1,
      fallback,
    );
  }
}
