/// Names given to the second version of a file changed in two places at
/// once: Syncthing `name.sync-conflict-<date>-<time>-<device>.md`, Nextcloud
/// and Dropbox `name (… conflicted copy …).md`, and PlaneTxt's own
/// `name (conflict <date> <time>).md`.
final RegExp _conflictCopyName = RegExp(
  r'\.sync-conflict-|conflicted copy|\(conflict \d{4}-\d{2}-\d{2}',
  caseSensitive: false,
);

/// True when the file at [relPath] is a conflict copy (see above).
bool isConflictCopy(String relPath) =>
    _conflictCopyName.hasMatch(relPath.split('/').last);
