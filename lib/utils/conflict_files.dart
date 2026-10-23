/// Names given to the second version of a file changed in two places at
/// once: Syncthing `name.sync-conflict-<date>-<time>-<device>.md`, Nextcloud
/// and Dropbox `name (… conflicted copy …).md`, and PlaneTxt's own
/// `name (conflict <date> <time>).md`.
final RegExp _conflictCopyName = RegExp(
  r'\.sync-conflict-|conflicted copy|\(conflict \d{4}-\d{2}-\d{2}',
  caseSensitive: false,
);

/// The marker each tool appends, to take back out of the name.
final RegExp _conflictCopyMarker = RegExp(
  r'\.sync-conflict-\d{8}-\d{6}-[^.]*$'
  r'|\s*\([^()]*conflicted copy[^()]*\)\s*$'
  r'|\s*\(conflict \d{4}-\d{2}-\d{2}[^()]*\)\s*$',
  caseSensitive: false,
);

/// True when the file at [relPath] is a conflict copy (see above).
bool isConflictCopy(String relPath) =>
    _conflictCopyName.hasMatch(relPath.split('/').last);

/// Store path of the file [relPath] is a second version of, or null when
/// [relPath] is not a conflict copy, or when its name holds nothing but the
/// marker. The file is not looked up: a copy outlives what it was made from,
/// and the caller decides what to do when it is gone.
String? originalPathOf(String relPath) {
  if (!isConflictCopy(relPath)) return null;
  final cut = relPath.lastIndexOf('/') + 1;
  final dir = relPath.substring(0, cut);
  final name = relPath.substring(cut);
  final dot = name.lastIndexOf('.');
  // A name made only of an extension (`.hidden`) has no base to strip.
  final base = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  final original = base.replaceFirst(_conflictCopyMarker, '');
  if (original.isEmpty || original == base) return null;
  return '$dir$original$extension';
}
