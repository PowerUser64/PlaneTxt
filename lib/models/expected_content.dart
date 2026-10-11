/// What a caller believes a file holds right before overwriting it.
///
/// A save that carries one fails with `FileConflictException` when the file
/// changed in the meantime (another app, a sync tool), instead of silently
/// overwriting that change.
class ExpectedContent {
  /// Expected file content, or `null` when the file should not exist yet.
  final String? content;

  const ExpectedContent(this.content);
}
