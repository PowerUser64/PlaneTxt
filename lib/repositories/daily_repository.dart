import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/repositories/base_repository.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/utils/conflict_files.dart';
import 'package:planetxt/utils/daily_path_format.dart';
import 'package:planetxt/utils/logger.dart';

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
      };

  @override
  (DailyFile, DateTime?) deserializeItem(
      String key, Map<String, dynamic> data) {
    final item = DailyFile(
      path: data['path'] as String,
      date: key,
      content: data['content'] as String,
    );
    final mtime = data['mtime'] != null
        ? DateTime.fromMillisecondsSinceEpoch(data['mtime'] as int)
        : null;
    return (item, mtime);
  }

  // --- domain-specific methods ----------------------------------------------

  /// Get daily file by date from cache.
  DailyFile? getByDate(String date) => cache[date];

  /// Load the daily file for [date], revalidating the cache against the
  /// file's mtime. The plaintext files can be edited by external tools at
  /// any time - returning a stale cache entry here would make the next save
  /// silently overwrite those edits.
  Future<DailyFile?> loadByDate(String date) async {
    final store = storageService.store;
    if (store == null) {
      Log.e('❌ DailyRepository: Storage not initialized');
      return cache[date];
    }

    // When the directory carries the date, each date lives in its own
    // directory and scanning indexes every `.md` note there - locate the
    // day's real file rather than assuming the configured file name. In a
    // flat layout the date is encoded in the file name, so read the
    // canonical file directly.
    final String relPath;
    if (_format.directoryHasDate) {
      final chosen = _pickDailyEntry(
          await store.list(_format.directoryForDate(date)));
      if (chosen == null) {
        Log.d('📅 DailyRepository: No file exists for date $date');
        cache.remove(date);
        lastModified.remove(date);
        return null;
      }
      relPath = chosen.relPath;
    } else {
      relPath = StorageService.dailyPath(date);
    }
    final currentMod = await store.modified(relPath);

    if (currentMod == null && !await store.exists(relPath)) {
      Log.d('📅 DailyRepository: No file exists for date $date');
      cache.remove(date);
      lastModified.remove(date);
      return null;
    }

    final cached = cache[date];
    final cachedMod = lastModified[date];
    if (cached != null &&
        cachedMod != null &&
        currentMod != null &&
        !cachedMod.isBefore(currentMod)) {
      return cached;
    }

    Log.i('📅 DailyRepository: Loading daily file for $date from disk');
    final dailyFile = await loadSingleEntry(StoreEntry(relPath, currentMod));
    if (dailyFile != null) {
      cache[date] = dailyFile;
      if (currentMod != null) lastModified[date] = currentMod;
      rememberDisk(relPath, currentMod, dailyFile.content);
    }
    return dailyFile;
  }

  /// Pick the day's file from a (non-recursive) listing of its directory:
  /// prefer the canonical `daily.md`, else the first `.md` file (excluding
  /// conflict copies). Returns null when the day has no file.
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
  /// when the file no longer holds that content.
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

  /// Create new daily file.
  Future<DailyFile> create(
    String date,
    String content, {
    ExpectedContent? expected,
  }) async {
    if (!storageService.isInitialized) {
      throw Exception('Storage not initialized');
    }

    final dailyFile = DailyFile(
      path: StorageService.dailyPath(date),
      date: date,
      content: content,
    );
    await save(dailyFile, expected: expected);
    return dailyFile;
  }
}
