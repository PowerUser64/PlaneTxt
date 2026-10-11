/// Turn what the user typed into a note file name: letters (accented ones
/// included, "Réunion" stays "Réunion"), digits, `-` and `_`, with spaces
/// as underscores. Path separators and other symbols are dropped.
String sanitizeNoteName(String value) => value
    .trim()
    .replaceAll(RegExp(r'[/\\]'), ' ')
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s_-]', unicode: true), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '_');

/// Turn a typed folder (`Work/Projects`) into a relative folder path, each
/// segment cleaned like a note name. Empty and `..` segments are dropped.
String sanitizeNoteFolder(String value) => value
    .trim()
    .replaceAll('\\', '/')
    .split('/')
    .map(sanitizeNoteName)
    .where((part) => part.isNotEmpty && part != '.' && part != '..')
    .join('/');
