import 'package:path/path.dart' as path;
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/models/note_file.dart';
import 'package:planetxt/repositories/base_repository.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/utils/exceptions.dart';
import 'package:planetxt/utils/logger.dart';

class NoteRepository extends BaseRepository<NoteFile> {
  NoteRepository(super.storageService);

  static final _notesPrefix = '${StorageService.notesDirName}/';

  @override
  String get scanDir => StorageService.notesDirName;

  @override
  String get cacheFileName => '._note_cache.json';

  @override
  String get tag => '📝 NoteRepository';

  @override
  bool get recursive => true;

  /// Store path (`notes/a/b.md`) → path relative to the notes dir (`a/b.md`).
  String _relativeToNotes(String relPath) =>
      relPath.startsWith(_notesPrefix)
          ? relPath.substring(_notesPrefix.length)
          : relPath;

  @override
  String? matchEntry(StoreEntry entry) => _relativeToNotes(entry.relPath);

  @override
  NoteFile? itemFromContent(StoreEntry entry, String content) {
    return NoteFile(
      path: entry.relPath,
      relativePath: _relativeToNotes(entry.relPath),
      content: content,
      lastModified: entry.modified ?? DateTime.now(),
    );
  }

  @override
  String fileKey(NoteFile item) => item.relativePath;

  @override
  int compare(NoteFile a, NoteFile b) =>
      b.lastModified.compareTo(a.lastModified);

  @override
  Map<String, dynamic> serializeItem(NoteFile item, DateTime? mtime) => {
        'content': item.content,
        'path': item.path,
        'lastModified': item.lastModified.millisecondsSinceEpoch,
        'mtime': mtime?.millisecondsSinceEpoch,
      };

  @override
  (NoteFile, DateTime?) deserializeItem(
      String key, Map<String, dynamic> data) {
    final item = NoteFile(
      path: data['path'] as String,
      relativePath: key,
      content: data['content'] as String,
      lastModified: DateTime.fromMillisecondsSinceEpoch(
        data['lastModified'] as int,
      ),
    );
    final mtime = data['mtime'] != null
        ? DateTime.fromMillisecondsSinceEpoch(data['mtime'] as int)
        : null;
    return (item, mtime);
  }

  // --- domain-specific methods ----------------------------------------------

  /// Get cached notes.
  List<NoteFile> get cachedNotes => List.unmodifiable(cache.values);

  /// Re-read one note from disk: `null` when it no longer exists.
  Future<NoteFile?> loadByRelativePath(String relativePath) async {
    final store = storageService.store;
    if (store == null) throw Exception('Storage not initialized');

    final storePath = StorageService.notePath(relativePath);
    final mtime = await store.modified(storePath);
    final content = await store.read(storePath);
    if (content == null) {
      cache.remove(relativePath);
      lastModified.remove(relativePath);
      return null;
    }
    final note = itemFromContent(StoreEntry(storePath, mtime), content)!;
    cache[relativePath] = note;
    if (mtime != null) lastModified[relativePath] = mtime;
    rememberDisk(storePath, mtime, content);
    return note;
  }

  /// Save note file. With [expected], fails with [FileConflictException]
  /// when the file no longer holds that content.
  Future<void> save(NoteFile noteFile, {ExpectedContent? expected}) async {
    try {
      final store = storageService.store!;
      if (expected != null) await checkExpected(noteFile.path, expected);
      await store.write(noteFile.path, noteFile.content);
      cache[noteFile.relativePath] =
          noteFile.copyWith(lastModified: DateTime.now());
      try {
        final mtime = await store.modified(noteFile.path);
        if (mtime != null) lastModified[noteFile.relativePath] = mtime;
        rememberDisk(noteFile.path, mtime, noteFile.content);
      } catch (_) {}
      Log.d('📝 NoteRepository: Saved note file ${noteFile.relativePath}');
    } catch (e) {
      Log.e('❌ NoteRepository: Error saving note file', error: e);
      rethrow;
    }
  }

  String _sanitizeRelativePath(String relativePath) {
    final trimmed = relativePath.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Note path cannot be empty');
    }

    final normalized = path.posix.normalize(trimmed.replaceAll('\\', '/'));

    if (path.posix.isAbsolute(normalized)) {
      throw ArgumentError('Note path must be relative');
    }

    final segments =
        path.posix.split(normalized).where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty || segments.any((s) => s == '.' || s == '..')) {
      throw ArgumentError('Invalid note path');
    }

    var sanitized = path.posix.joinAll(segments);
    if (!sanitized.endsWith('.md')) {
      sanitized = '$sanitized.md';
    }

    return sanitized;
  }

  /// Create a note that must not exist yet. Throws
  /// [FileAlreadyExistsException] instead of overwriting an existing file.
  Future<NoteFile> createNew(String relativePath, String content) async {
    if (!storageService.isInitialized) {
      throw Exception('Storage not initialized');
    }

    final sanitizedRelativePath = _sanitizeRelativePath(relativePath);
    final storePath = StorageService.notePath(sanitizedRelativePath);
    if (await storageService.store!.exists(storePath)) {
      throw FileAlreadyExistsException(
        'A note named $sanitizedRelativePath already exists',
        filePath: storePath,
      );
    }
    return create(sanitizedRelativePath, content);
  }

  /// Write a note, creating or overwriting it (used by the editor's saves).
  Future<NoteFile> create(
    String relativePath,
    String content, {
    ExpectedContent? expected,
  }) async {
    if (!storageService.isInitialized) {
      throw Exception('Storage not initialized');
    }

    final sanitizedRelativePath = _sanitizeRelativePath(relativePath);

    final noteFile = NoteFile(
      path: StorageService.notePath(sanitizedRelativePath),
      relativePath: sanitizedRelativePath,
      content: content,
      lastModified: DateTime.now(),
    );

    await save(noteFile, expected: expected);
    return noteFile;
  }

  /// Rename/move a note within the notes directory.
  Future<NoteFile> rename(NoteFile noteFile, String newRelativePath) async {
    final sanitized = _sanitizeRelativePath(newRelativePath);
    final newStorePath = StorageService.notePath(sanitized);

    final store = storageService.store!;
    if (await store.exists(newStorePath)) {
      throw ArgumentError('A note named $sanitized already exists');
    }

    await store.rename(noteFile.path, newStorePath);
    cache.remove(noteFile.relativePath);
    lastModified.remove(noteFile.relativePath);

    final renamed = noteFile.copyWith(
      path: newStorePath,
      relativePath: sanitized,
      lastModified: DateTime.now(),
    );
    cache[renamed.relativePath] = renamed;
    Log.d('📝 NoteRepository: Renamed ${noteFile.relativePath} → $sanitized');
    return renamed;
  }

  /// Delete note file.
  Future<void> delete(NoteFile noteFile) async {
    try {
      await storageService.store!.delete(noteFile.path);
      cache.remove(noteFile.relativePath);
      Log.d('📝 NoteRepository: Deleted note file ${noteFile.relativePath}');
    } catch (e) {
      Log.e('❌ NoteRepository: Error deleting note file', error: e);
      rethrow;
    }
  }
}
