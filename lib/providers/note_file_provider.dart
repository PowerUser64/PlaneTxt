import 'dart:async';

import 'package:flutter/material.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/models/note_file.dart';
import 'package:planetxt/repositories/note_repository.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/services/widget_service.dart';
import 'package:planetxt/utils/exceptions.dart';
import 'package:planetxt/utils/logger.dart';

class NoteFileProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  late NoteRepository _noteRepository;

  List<NoteFile> _noteFiles = [];
  Timer? _widgetUpdateTimer;
  static const Duration _widgetUpdateInterval = Duration(minutes: 30);

  // Debounces the home-screen widget push during autosave bursts (500ms).
  Timer? _postSaveWidgetTimer;
  static const Duration _postSaveDebounce = Duration(seconds: 2);

  NoteFileProvider() {
    Log.i('🚀 NoteFileProvider: Constructor called');
    _noteRepository = NoteRepository(_storageService);
  }

  List<NoteFile> get noteFiles => List.unmodifiable(_noteFiles);

  /// The loaded note at [relativePath], if any.
  NoteFile? noteByPath(String relativePath) {
    for (final note in _noteFiles) {
      if (note.relativePath == relativePath) return note;
    }
    return null;
  }

  // First full scan reads every note file (slow on large folders and SAF
  // trees) - exposed so the UI can show a "building cache" indicator.
  bool _isBuildingCache = false;
  int _cacheProgressDone = 0;
  int _cacheProgressTotal = 0;
  bool get isBuildingCache => _isBuildingCache;
  int get cacheProgressDone => _cacheProgressDone;
  int get cacheProgressTotal => _cacheProgressTotal;

  /// Persist the repository disk cache now (e.g. when the app is paused).
  Future<void> persistCache() => _noteRepository.persistCache();

  Future<void> loadNoteFiles({bool forceReload = false}) async {
    Log.i(
        '📝 NoteFileProvider: Loading note files (forceReload: $forceReload)...');
    // No disk cache to restore from (first run, or storage location just
    // changed): every file gets read, which can take a while - surface it.
    final buildingCache = _noteRepository.cacheSize == 0 || forceReload;
    if (buildingCache) {
      _isBuildingCache = true;
      _cacheProgressDone = 0;
      _cacheProgressTotal = 0;
      notifyListeners();
    }
    try {
      _noteFiles = await _noteRepository.loadAll(
        forceReload: forceReload,
        onProgress: buildingCache
            ? (done, total) {
                _cacheProgressDone = done;
                _cacheProgressTotal = total;
                notifyListeners();
              }
            : null,
      );
      Log.i('📝 NoteFileProvider: Loaded ${_noteFiles.length} note files');

      // Update widget with recent notes
      await _updateWidget();

      notifyListeners();
    } catch (e) {
      Log.e('❌ NoteFileProvider: Error loading note files', error: e);
      rethrow;
    } finally {
      if (buildingCache) {
        _isBuildingCache = false;
        notifyListeners();
      }
    }
  }

  /// Incremental update - only load modified note files
  Future<void> loadNoteFilesIncremental() async {
    Log.i('📝 NoteFileProvider: Loading incremental note file changes...');
    try {
      _noteFiles = await _noteRepository.loadIncremental();
      Log.i(
          '📝 NoteFileProvider: Incremental load completed, ${_noteFiles.length} total files');

      // Update widget with recent notes
      await _updateWidget();

      notifyListeners();
    } catch (e) {
      Log.e('❌ NoteFileProvider: Error in incremental note file load',
          error: e);
      rethrow;
    }
  }

  /// With [expected], the save fails with [FileConflictException] when the
  /// file changed on disk since the caller read it.
  Future<void> saveNoteFile(String relativePath, String content,
      {ExpectedContent? expected}) async {
    try {
      Log.d('📝 NoteFileProvider: Saving note file $relativePath');
      final saved = await _noteRepository.create(relativePath, content,
          expected: expected);
      _onNoteWritten(saved);
      Log.d('📝 NoteFileProvider: Saved note file $relativePath');
    } catch (e) {
      Log.e('❌ NoteFileProvider: Error saving note file', error: e);
      rethrow;
    }
  }

  /// Create an empty note. Throws [FileAlreadyExistsException] when a note
  /// already lives at [relativePath] - creating must never clobber one.
  Future<NoteFile> createNoteFile(String relativePath) async {
    try {
      Log.d('📝 NoteFileProvider: Creating note file $relativePath');
      final created = await _noteRepository.createNew(relativePath, '');
      _onNoteWritten(created);
      return created;
    } catch (e) {
      Log.e('❌ NoteFileProvider: Error creating note file', error: e);
      rethrow;
    }
  }

  /// Re-read one note from disk before editing it - the list may hold a
  /// version older than the file. Returns `null` when the note is gone.
  Future<NoteFile?> reloadNote(String relativePath) async {
    final fresh = await _noteRepository.loadByRelativePath(relativePath);
    final index = _noteFiles.indexWhere((n) => n.relativePath == relativePath);
    if (fresh == null) {
      if (index != -1) {
        _noteFiles = [..._noteFiles]..removeAt(index);
        notifyListeners();
      }
    } else if (index == -1 || _noteFiles[index].content != fresh.content) {
      _noteFiles = [..._noteFiles];
      if (index == -1) {
        _noteFiles.insert(0, fresh);
      } else {
        _noteFiles[index] = fresh;
      }
      notifyListeners();
    }
    return fresh;
  }

  /// Save [content] as a new note next to the others, named after
  /// [baseName] and the current time: a version that lost a conflict is
  /// kept where the user can open it, never dropped.
  Future<NoteFile> saveConflictCopy({
    required String folder,
    required String baseName,
    required String content,
  }) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final prefix = folder.isEmpty ? '' : '$folder/';
    for (var n = 1;; n++) {
      final suffix = n == 1 ? '' : ' $n';
      final relativePath = '$prefix$baseName (conflict $stamp$suffix).md';
      try {
        final copy = await _noteRepository.createNew(relativePath, content);
        _onNoteWritten(copy);
        Log.w('⚠️ NoteFileProvider: Saved conflicting version as $relativePath');
        return copy;
      } on FileAlreadyExistsException {
        if (n >= 20) rethrow;
      }
    }
  }

  void _onNoteWritten(NoteFile saved) {
    // Upsert into the in-memory list instead of re-scanning the whole
    // notes directory - this runs on every 500ms autosave. The list is
    // sorted newest-first, and the note just saved is the newest.
    _noteFiles = [
      saved,
      ..._noteFiles.where((n) => n.relativePath != saved.relativePath),
    ];
    notifyListeners();

    _postSaveWidgetTimer?.cancel();
    _postSaveWidgetTimer = Timer(_postSaveDebounce, () {
      unawaited(_updateWidget());
      // Flush the disk cache so a process kill doesn't lose this save
      // from the next startup's fast-paint restore.
      unawaited(_noteRepository.persistCache());
    });
  }

  Future<bool> renameNoteFile(NoteFile note, String newName) async {
    Log.d('📝 NoteFileProvider: Renaming note ${note.fileName} to $newName');

    // Validate new name
    if (newName.trim().isEmpty) {
      Log.w('📝 NoteFileProvider: New name is empty');
      return false;
    }

    // Clean the new name
    final cleanName =
        newName.trim().replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    if (cleanName.isEmpty) {
      Log.w('📝 NoteFileProvider: Cleaned name is empty');
      return false;
    }

    // Create new relative path
    final newRelativePath = note.folderPath.isEmpty
        ? '$cleanName.md'
        : '${note.folderPath}/$cleanName.md';

    try {
      if (!_storageService.isInitialized) {
        Log.e('❌ NoteFileProvider: Storage not initialized');
        return false;
      }

      await _noteRepository.rename(note, newRelativePath);

      // Reload notes
      await loadNoteFiles();

      Log.d(
          '📝 NoteFileProvider: Successfully renamed note to $newRelativePath');
      return true;
    } catch (e) {
      Log.e('❌ NoteFileProvider: Error renaming note', error: e);
      return false;
    }
  }

  Future<void> deleteNoteFile(NoteFile noteFile) async {
    try {
      Log.d('📝 NoteFileProvider: Deleting note file ${noteFile.relativePath}');
      await _noteRepository.delete(noteFile);

      // Remove from local list
      _noteFiles.removeWhere((n) => n.path == noteFile.path);

      // Update widget
      await _updateWidget();

      Log.d('📝 NoteFileProvider: Deleted note file ${noteFile.relativePath}');
      notifyListeners();
    } catch (e) {
      Log.e('❌ NoteFileProvider: Error deleting note file', error: e);
      rethrow;
    }
  }

  /// Update widget with recent notes
  Future<void> _updateWidget() async {
    try {
      if (!_storageService.isInitialized) {
        Log.d(
            '📱 NoteFileProvider: Skipping widget update - storage not initialized');
        return;
      }

      Log.d('📱 NoteFileProvider: Updating widget with notes');
      await WidgetService.updateWithNotes(_noteFiles);
      Log.i('📱 NoteFileProvider: Widget updated successfully');
    } catch (e) {
      Log.e('❌ NoteFileProvider: Error updating widget', error: e);
    }
  }

  void startWidgetUpdateTimer() {
    _widgetUpdateTimer?.cancel();
    _widgetUpdateTimer = Timer.periodic(_widgetUpdateInterval, (timer) async {
      Log.d('📱 NoteFileProvider: Periodic widget update triggered');
      try {
        await loadNoteFiles();
        Log.d('📱 NoteFileProvider: Periodic widget update completed');
      } catch (e) {
        Log.e('❌ NoteFileProvider: Error in periodic widget update', error: e);
      }
    });
    Log.i(
        '📱 NoteFileProvider: Started periodic widget update timer (every 30 minutes)');
  }

  @override
  void dispose() {
    _widgetUpdateTimer?.cancel();
    _widgetUpdateTimer = null;
    _postSaveWidgetTimer?.cancel();
    _postSaveWidgetTimer = null;
    Log.i('📝 NoteFileProvider: Disposed');
    super.dispose();
  }
}
