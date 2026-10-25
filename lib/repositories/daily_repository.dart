import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/repositories/base_repository.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/utils/conflict_files.dart';
import 'package:planetxt/utils/daily_path_format.dart';
import 'package:planetxt/utils/logger.dart';

/// Caches one [DailyFile] per calendar date.
///
/// In a layout where the directory carries date tokens (`cal/%Y/%m/%d`),
/// every `.md` note inside a day's directory belongs to that date: scanning
/// merges them into a single [DailyFile] whose [DailyFile.mergedContent]
/// holds all of them, so the Calendar page and reminders see every note of
/// the day. The primary file (preferring `daily.md`, else the first note by
/// name) is the editable one; the other notes stay separate files and are
/// only merged for display and parsing.
class DailyRepository extends BaseRepository<DailyFile> {
  DailyRepository(super.storageService);

  DailyPathFormat get _format => StorageService.dailyFormat;

  @override
  String get scanDir => StorageService.dailiesDirName;

  @override
  String get cacheFileName => '._daily_cache.json';

  @override
  String get tag => '📅 DailyRepository';

  /// Whether the configured layout nests dates in subdirectories
  /// (`cal/YYYY/MM/DD/...`): such layouts need a recursive scan.
  @override
  bool get recursive => _format.recursive;

  @override
  String? matchEntry(StoreEntry entry) => _format.dateFromPath(entry.relPath);

  @override
  DailyFile? itemFromContent(StoreEntry entry, String content) {
    final date = _format.dateFromPath(entry.relPath);
    if (date == null) return null;
    return DailyFile(path: entry.relPath, date: date, content: content);
  }

  @override
  String fileKey(DailyFile item) => item.date;

  @override
  int compare(DailyFile a, DailyFile b) => b.date.compareTo(a.date);

  @override
  Map<String, dynamic> serializeItem(DailyFile item, DateTime? mtime) => {
        'content': item.content,
        'path': item.path,
        'mtime': mtime?.millisecondsSinceEpoch,
        'notes': item.notes
            .map((n) => {'path': n.path, 'content': n.content})
            .toList(),
      };

  @override
  (DailyFile, DateTime?) deserializeItem(
      String key, Map<String, dynamic> data) {
    final notes = (data['notes'] as List? ?? const [])
        .map((n) => DailyNote(
            path: (n as Map)['path'] as String,
            content: n['content'] as String))
        .toList();
    final item = DailyFile(
      path: data['path'] as String,
      date: key,
      content: data['content'] as String,
      notes: notes,
    );
    final mtime = data['mtime'] != null
        ? DateTime.fromMillisecondsSinceEpoch(data['mtime'] as int)
        : null;
    return (item, mtime);
  }

  // --- loading --------------------------------------------------------------

  /// Scan every `.md` note and index one merged [DailyFile] per date.
  @override
  Future<List<DailyFile>> loadAll({
    bool forceReload = false,
    void Function(int done, int total)? onProgress,
  }) async {
    Log.d('$tag: Loading all files (forceReload: $forceReload)...');

    final store = storageService.store;
    if (store == null) {
      Log.e('❌ $tag: Storage not initialized');
      return [];
    }

    if (cache.isEmpty && !forceReload) {
      await restoreCache();
    }

    final entries = await store.list(scanDir, recursive: recursive);
    scanConflicts(entries);

    if (forceReload) {
      cache.clear();
      lastModified.clear();
    }

    // A day directory may hold several `.md` notes; group them by date so
    // each date is loaded as one merged file.
    final byDate = _groupByDate(entries);
    final seenDates = byDate.keys.toSet();

    final removedCount =
        cache.length - cache.keys.where(seenDates.contains).length;
    cache.removeWhere((k, _) => !seenDates.contains(k));
    lastModified.removeWhere((k, _) => !seenDates.contains(k));

    // A date is up to date when every note in it is unchanged.
    final cachedItems = <DailyFile>[];
    final datesToLoad = <String>[];
    for (final date in byDate.keys) {
      final currentMod = _maxModified(byDate[date]!);
      final cached = cache[date];
      if (cached != null &&
          currentMod != null &&
          lastModified[date] != null &&
          !lastModified[date]!.isBefore(currentMod) &&
          !forceReload) {
        cachedItems.add(cached);
      } else {
        datesToLoad.add(date);
      }
    }

    final loadedItems =
        await _loadDatesParallel(byDate, datesToLoad, onProgress: onProgress);
    _storeLoadedDates(byDate, loadedItems);

    final allItems = [...cachedItems, ...loadedItems]..sort(compare);

    Log.i(
        '$tag: Loaded ${allItems.length} daily files (${cachedItems.length} from cache, ${loadedItems.length} newly loaded)');

    if (loadedItems.isNotEmpty || removedCount > 0 || forceReload) {
      await persistCache();
    }
    return allItems;
  }

  /// Load only the dates whose notes changed on disk.
  @override
  Future<List<DailyFile>> loadIncremental() async {
    Log.d('$tag: Loading incremental changes...');

    final store = storageService.store;
    if (store == null) {
      Log.e('❌ $tag: Storage not initialized');
      return cache.values.toList()..sort(compare);
    }

    final entries = await store.list(scanDir, recursive: recursive);
    scanConflicts(entries);
    final byDate = _groupByDate(entries);
    final seenDates = byDate.keys.toSet();

    cache.removeWhere((k, _) => !seenDates.contains(k));
    lastModified.removeWhere((k, _) => !seenDates.contains(k));

    // A date changed when any of its notes changed.
    final datesToLoad = <String>[];
    for (final date in byDate.keys) {
      final currentMod = _maxModified(byDate[date]!);
      if (currentMod == null ||
          lastModified[date] == null ||
          lastModified[date]!.isBefore(currentMod)) {
        datesToLoad.add(date);
      }
    }

    final loadedItems = await _loadDatesParallel(byDate, datesToLoad);
    _storeLoadedDates(byDate, loadedItems);

    final allItems = cache.values.toList()..sort(compare);

    Log.i(
        '$tag: Incremental load completed - ${loadedItems.length} dates updated, ${allItems.length} total');

    if (loadedItems.isNotEmpty) {
      await persistCache();
    }
    return allItems;
  }

  /// Group scanned [entries] by the date they map to.
  Map<String, List<StoreEntry>> _groupByDate(List<StoreEntry> entries) {
    final byDate = <String, List<StoreEntry>>{};
    for (final entry in entries) {
      final date = _format.dateFromPath(entry.relPath);
      if (date == null) continue;
      byDate.putIfAbsent(date, () => []).add(entry);
    }
    return byDate;
  }

  /// The latest modification time among a date's notes.
  DateTime? _maxModified(List<StoreEntry> entries) {
    DateTime? best;
    for (final entry in entries) {
      final mod = entry.modified;
      if (mod != null && (best == null || mod.isAfter(best))) best = mod;
    }
    return best;
  }

  /// Read every note of [datesToLoad] (batched like the base class) and build
  /// one merged [DailyFile] per date. An unreadable primary file skips its
  /// date; an unreadable additional note is dropped but the day is kept.
  Future<List<DailyFile>> _loadDatesParallel(
    Map<String, List<StoreEntry>> byDate,
    List<String> datesToLoad, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (datesToLoad.isEmpty) return const [];

    final store = storageService.store!;
    final allEntries = datesToLoad.expand((d) => byDate[d]!).toList();
    final contents = <String, String>{};

    try {
      const batchSize = 20;
      var done = 0;
      for (var i = 0; i < allEntries.length; i += batchSize) {
        final batch = allEntries.skip(i).take(batchSize).toList();
        final reads = await store.readAll(batch.map((e) => e.relPath).toList());
        for (final read in reads.entries) {
          if (read.value != null) contents[read.key] = read.value!;
        }
        done += batch.length;
        onProgress?.call(done, allEntries.length);
      }
    } catch (e) {
      Log.e('❌ $tag: Error in parallel loading, falling back to sequential',
          error: e);
      for (final entry in allEntries) {
        try {
          final content = await store.read(entry.relPath);
          if (content != null) contents[entry.relPath] = content;
        } catch (_) {}
      }
    }

    final loaded = <DailyFile>[];
    for (final date in datesToLoad) {
      final file = _buildDateFile(date, byDate[date]!, contents);
      if (file != null) loaded.add(file);
    }
    return loaded;
  }

  /// Cache [loadedItems] with the latest mtime of each date's notes.
  void _storeLoadedDates(
      Map<String, List<StoreEntry>> byDate, List<DailyFile> loadedItems) {
    for (final item in loadedItems) {
      cache[item.date] = item;
      final mod = _maxModified(byDate[item.date]!);
      if (mod != null) lastModified[item.date] = mod;
    }
  }

  /// Build one [DailyFile] for [date] from its [entries] and [contents]
  /// (relPath -> content, null when a file could not be read). The primary
  /// file is preferred by [_pickDailyEntry]; every other note becomes a
  /// [DailyNote]. Returns null when the day has no readable primary file.
  DailyFile? _buildDateFile(
      String date, List<StoreEntry> entries, Map<String, String?> contents) {
    final candidates = entries.where((e) => !isConflictCopy(e.relPath)).toList();
    if (candidates.isEmpty) return null;
    final primary = _pickDailyEntry(candidates);
    if (primary == null) return null;
    final primaryContent = contents[primary.relPath];
    if (primaryContent == null) return null;

    final notes = <DailyNote>[];
    for (final entry in candidates) {
      if (entry.relPath == primary.relPath) continue;
      final c = contents[entry.relPath];
      if (c == null) continue;
      notes.add(DailyNote(path: entry.relPath, content: c));
    }
    return DailyFile(
      path: primary.relPath,
      date: date,
      content: primaryContent,
      notes: notes,
    );
  }

  // --- domain-specific methods ----------------------------------------------

  /// Get daily file by date from cache.
  DailyFile? getByDate(String date) => cache[date];

  /// Load the daily file for [date], revalidating the cache against the
  /// notes' mtimes. The plaintext files can be edited by external tools at
  /// any time - returning a stale cache entry here would make the next save
  /// silently overwrite those edits.
  ///
  /// When the directory carries the date, every `.md` note in that day's
  /// directory is read and merged; in a flat layout the date is encoded in
  /// the file name, so the canonical file is read directly.
  Future<DailyFile?> loadByDate(String date) async {
    final store = storageService.store;
    if (store == null) {
      Log.e('❌ DailyRepository: Storage not initialized');
      return cache[date];
    }

    final List<StoreEntry> entries;
    if (_format.directoryHasDate) {
      entries = await store.list(_format.directoryForDate(date));
    } else {
      final canonical = StorageService.dailyPath(date);
      if (!await store.exists(canonical)) {
        Log.d('📅 DailyRepository: No file exists for date $date');
        cache.remove(date);
        lastModified.remove(date);
        return null;
      }
      entries = [StoreEntry(canonical, await store.modified(canonical))];
    }

    final candidates = entries.where((e) => !isConflictCopy(e.relPath)).toList();
    if (candidates.isEmpty) {
      Log.d('📅 DailyRepository: No file exists for date $date');
      cache.remove(date);
      lastModified.remove(date);
      return null;
    }

    final currentMod = _maxModified(candidates);

    final cached = cache[date];
    final cachedMod = lastModified[date];
    if (cached != null &&
        cachedMod != null &&
        currentMod != null &&
        !cachedMod.isBefore(currentMod)) {
      return cached;
    }

    Log.i('📅 DailyRepository: Loading daily file for $date from disk');
    final contents = await store.readAll(candidates.map((e) => e.relPath).toList());
    final dailyFile = _buildDateFile(date, candidates, contents);
    if (dailyFile != null) {
      cache[date] = dailyFile;
      if (currentMod != null) lastModified[date] = currentMod;
      for (final entry in candidates) {
        final c = contents[entry.relPath];
        if (c != null) rememberDisk(entry.relPath, entry.modified, c);
      }
    }
    return dailyFile;
  }

  /// Pick the day's primary file from a listing of its directory: prefer the
  /// canonical `daily.md`, else the first `.md` file (excluding conflict
  /// copies). Returns null when the day has no file.
  StoreEntry? _pickDailyEntry(List<StoreEntry> entries) {
    final candidates =
        entries.where((e) => !isConflictCopy(e.relPath)).toList();
    if (candidates.isEmpty) return null;
    for (final entry in candidates) {
      if (entry.relPath.split('/').last == 'daily.md') return entry;
    }
    candidates.sort((a, b) => a.relPath.compareTo(b.relPath));
    return candidates.first;
  }

  /// Save daily file. With [expected], fails with [FileConflictException]
  /// when the file no longer holds that content. Only the primary file's
  /// [content] is written - the additional notes are left untouched.
  Future<void> save(DailyFile dailyFile, {ExpectedContent? expected}) async {
    try {
      final store = storageService.store!;
      if (expected != null) await checkExpected(dailyFile.path, expected);
      forgetDisk(dailyFile.path);
      await store.write(dailyFile.path, dailyFile.content);
      cache[dailyFile.date] = dailyFile;
      // Record the new mtime so loadByDate doesn't re-read our own write.
      try {
        final mtime = await store.modified(dailyFile.path);
        if (mtime != null) lastModified[dailyFile.date] = mtime;
      } catch (_) {}
      Log.d('📅 DailyRepository: Saved daily file for ${dailyFile.date}');
    } catch (e) {
      Log.e('❌ DailyRepository: Error saving daily file', error: e);
      rethrow;
    }
  }

  /// Update one note of a day's merged file on disk and keep the cached day
  /// consistent. [notePath] is the store path of the note being edited;
  /// [content] is its new content. The primary file and the other notes keep
  /// their cached content, so the merged view stays intact.
  Future<void> savePart(String date, String notePath, String content,
      {ExpectedContent? expected}) async {
    try {
      final store = storageService.store!;
      if (expected != null) await checkExpected(notePath, expected);
      forgetDisk(notePath);
      await store.write(notePath, content);
      final cached = cache[date];
      if (cached != null) {
        if (cached.path == notePath) {
          cache[date] = cached.copyWith(content: content);
        } else {
          cache[date] = cached.copyWith(notes: [
            for (final n in cached.notes)
              n.path == notePath
                  ? DailyNote(path: n.path, content: content)
                  : n,
          ]);
        }
        try {
          final mtime = await store.modified(notePath);
          if (mtime != null) lastModified[date] = mtime;
        } catch (_) {}
      }
      Log.d('📅 DailyRepository: Saved note $notePath for ${cached?.date ?? date}');
    } catch (e) {
      Log.e('❌ DailyRepository: Error saving note $notePath', error: e);
      rethrow;
    }
  }

  /// Create new daily file. [notes] carries the other `.md` notes of the
  /// day, so a save keeps them merged in the cached [DailyFile].
  Future<DailyFile> create(
    String date,
    String content, {
    List<DailyNote>? notes,
    ExpectedContent? expected,
  }) async {
    if (!storageService.isInitialized) {
      throw Exception('Storage not initialized');
    }

    final dailyFile = DailyFile(
      path: StorageService.dailyPath(date),
      date: date,
      content: content,
      notes: notes ?? const [],
    );
    await save(dailyFile, expected: expected);
    return dailyFile;
  }
}
