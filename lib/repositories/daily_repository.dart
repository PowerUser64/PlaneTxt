import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/repositories/base_repository.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/utils/daily_file_naming.dart';
import 'package:planetxt/utils/logger.dart';

class DailyRepository extends BaseRepository<DailyFile> {
  DailyRepository(super.storageService);

  @override
  String get scanDir => StorageService.dailiesDirName;

  @override
  String get cacheFileName => '._daily_cache.json';

  @override
  String get tag => '📅 DailyRepository';

  @override
  String? matchEntry(StoreEntry entry) =>
      DailyFileNaming.current.dateOf(entry.relPath);

  @override
  void onScanned(List<StoreEntry> entries) {
    final paths = <String, String>{};
    for (final entry in entries) {
      final date = DailyFileNaming.current.dateOf(entry.relPath);
      if (date != null) paths[date] = entry.relPath;
    }
    _listedPaths = paths;
  }

  @override
  DailyFile? itemFromContent(StoreEntry entry, String content) {
    final date = DailyFileNaming.current.dateOf(entry.relPath);
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

  /// Path of each day's file, as the last scan listed it. Before the
  /// first scan the cache is empty, and a day whose file follows an older
  /// naming would go unnoticed - then be written a second time under the
  /// current one.
  Map<String, String>? _listedPaths;

  /// Store path of the day [date]'s file: the one it already has on disk,
  /// else the name the configured naming gives it. A day written before
  /// the template changed keeps its file rather than gaining a second one.
  Future<String> pathFor(String date) async {
    final cached = cache[date]?.path;
    if (cached != null) return cached;

    final templatePath = StorageService.dailyPath(date);
    final store = storageService.store;
    if (store == null) return templatePath;
    if (await store.exists(templatePath)) return templatePath;

    // The day may hold a file under a name the current template doesn't
    // give - deleted since the scan listed it, though.
    final listed = (await _scannedPaths(store))?[date];
    if (listed != null && await store.exists(listed)) return listed;
    return templatePath;
  }

  Future<Map<String, String>?> _scannedPaths(FileStore store) async {
    if (_listedPaths != null) return _listedPaths;
    try {
      onScanned(await store.list(scanDir));
    } catch (e) {
      Log.e('❌ DailyRepository: Cannot list $scanDir', error: e);
    }
    return _listedPaths;
  }

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

    final relPath = await pathFor(date);
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
      path: await pathFor(date),
      date: date,
      content: content,
    );
    await save(dailyFile, expected: expected);
    return dailyFile;
  }
}
