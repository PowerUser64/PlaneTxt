import 'dart:async';

import 'package:flutter/material.dart';
import 'package:planetxt/models/calendar_event.dart';
import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/repositories/daily_repository.dart';
import 'package:planetxt/services/file_monitor_service.dart';
import 'package:planetxt/services/notification_service.dart';
import 'package:planetxt/services/storage_service.dart';
import 'package:planetxt/services/widget_service.dart';
import 'package:planetxt/utils/daily_content_helper.dart';
import 'package:planetxt/utils/exceptions.dart';
import 'package:planetxt/utils/logger.dart';
import 'package:planetxt/utils/markdown_parser.dart';

/// Cached parse result for one daily file. The [contentHash] is used to
/// detect when [content] has changed and invalidate.
class _ParsedDaily {
  final int contentHash;
  final List<TaskItem> tasks;
  final List<CalendarEvent> events; // sorted by time

  /// Free text split with [logHeaderRegex], computed on first use.
  String? logHeaderRegex;
  ({List<String> notes, List<String> logs})? freeText;
  _ParsedDaily(this.contentHash, this.tasks, this.events);
}

class DailyFileProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  late DailyRepository _dailyRepository;

  List<DailyFile> _dailyFiles = [];
  // Index of the same files keyed by date for O(1) lookup.
  final Map<String, DailyFile> _byDate = {};
  // Memoised task/event parsing per date — invalidated by content hash.
  final Map<String, _ParsedDaily> _parseCache = {};
  String _selectedDate = '';
  String? _lastWidgetUpdateDate;
  Timer? _widgetUpdateTimer;
  static const Duration _widgetUpdateInterval = Duration(minutes: 30);

  // Debounce for post-save side work (notifications + home-screen widget):
  // autosave fires every 500ms while typing, but rescheduling notifications
  // and pushing the widget only needs to happen once the burst settles.
  final Map<String, Timer> _postSaveTimers = {};
  static const Duration _postSaveDebounce = Duration(seconds: 2);

  DailyFileProvider() {
    Log.i('🚀 DailyFileProvider: Constructor called');
    _dailyRepository = DailyRepository(_storageService);
    FileMonitorService().onDailyFileChanged = _onExternalFileChanged;
  }

  List<DailyFile> get dailyFiles => List.unmodifiable(_dailyFiles);

  /// Conflict copies of daily files found by the last scan.
  Set<String> get conflictFiles => _dailyRepository.conflictFiles;
  String get selectedDate => _selectedDate;

  // First full scan reads every daily file (slow on large folders and SAF
  // trees) - exposed so the UI can show a "building cache" indicator.
  bool _isBuildingCache = false;
  int _cacheProgressDone = 0;
  int _cacheProgressTotal = 0;
  bool get isBuildingCache => _isBuildingCache;
  int get cacheProgressDone => _cacheProgressDone;
  int get cacheProgressTotal => _cacheProgressTotal;

  // -- internal index/cache management ---------------------------------------

  void _replaceAllFiles(List<DailyFile> files) {
    _dailyFiles = files;
    _byDate
      ..clear()
      ..addEntries(files.map((f) => MapEntry(f.date, f)));
    // Drop cache entries for dates that no longer exist; keep the rest —
    // their hash check will detect any content changes.
    _parseCache.removeWhere((date, _) => !_byDate.containsKey(date));
  }

  void _upsertFile(DailyFile file) {
    final existing = _byDate[file.date];
    if (existing == null) {
      _dailyFiles = [..._dailyFiles, file]
        ..sort((a, b) => b.date.compareTo(a.date));
    } else {
      final idx = _dailyFiles.indexOf(existing);
      if (idx != -1) {
        _dailyFiles[idx] = file;
      } else {
        _dailyFiles = [..._dailyFiles, file]
          ..sort((a, b) => b.date.compareTo(a.date));
      }
    }
    _byDate[file.date] = file;
    _parseCache.remove(file.date);
  }

  _ParsedDaily? _getParsed(String date) {
    final file = _byDate[date];
    if (file == null || file.content.isEmpty) return null;
    final hash = file.content.hashCode;
    final cached = _parseCache[date];
    if (cached != null && cached.contentHash == hash) return cached;
    final tasks = MarkdownParser.parseTasks(file.content);
    final events = MarkdownParser.parseEvents(date, file.content)
      ..sort((a, b) => a.time.compareTo(b.time));
    final parsed = _ParsedDaily(hash, tasks, events);
    _parseCache[date] = parsed;
    return parsed;
  }

  /// Re-read one date from disk after an external change and update the UI.
  void _onExternalFileChanged(String date) {
    unawaited(() async {
      try {
        final fromDisk = await _dailyRepository.loadByDate(date);
        final existing = _byDate[date];
        if (fromDisk != null) {
          if (existing == null || existing.content != fromDisk.content) {
            Log.i(
                '📅 DailyFileProvider: External change detected for $date, refreshing');
            _upsertFile(fromDisk);
            notifyListeners();
          }
        } else if (existing != null) {
          Log.i(
              '📅 DailyFileProvider: Daily file for $date deleted externally');
          _byDate.remove(date);
          _parseCache.remove(date);
          _dailyFiles = _dailyFiles.where((f) => f.date != date).toList();
          notifyListeners();
        }
      } catch (e) {
        Log.e('❌ DailyFileProvider: Error refreshing $date after change',
            error: e);
      }
    }());
  }

  Future<void> loadDailyFiles({bool forceReload = false}) async {
    Log.i(
        '📅 DailyFileProvider: Loading daily files (forceReload: $forceReload)...');
    // No disk cache to restore from (first run, or storage location just
    // changed): every file gets read, which can take a while - surface it.
    final buildingCache = _dailyRepository.cacheSize == 0 || forceReload;
    if (buildingCache) {
      _isBuildingCache = true;
      _cacheProgressDone = 0;
      _cacheProgressTotal = 0;
      notifyListeners();
    }
    try {
      _replaceAllFiles(await _dailyRepository.loadAll(
        forceReload: forceReload,
        onProgress: buildingCache
            ? (done, total) {
                _cacheProgressDone = done;
                _cacheProgressTotal = total;
                notifyListeners();
              }
            : null,
      ));
      Log.i('📅 DailyFileProvider: Loaded ${_dailyFiles.length} daily files');

      // Notify the UI first; the home-screen widget can follow.
      notifyListeners();
      unawaited(_updateWidget());
    } catch (e) {
      Log.e('❌ DailyFileProvider: Error loading daily files', error: e);
      rethrow;
    } finally {
      if (buildingCache) {
        _isBuildingCache = false;
        notifyListeners();
      }
    }
  }

  /// Fast startup load: restore last-known content from disk cache and
  /// refresh today's file from disk, notifying listeners after each step.
  /// Does NOT do a full mtime sweep — call [loadDailyFiles] in the
  /// background afterwards to validate the rest of the history.
  Future<void> loadTodayPriority() async {
    Log.i('📅 DailyFileProvider: Priority-loading today...');
    try {
      // Stage A: in-memory list from disk cache (instant).
      final cached = await _dailyRepository.restoreFromDiskCache();
      if (cached.isNotEmpty) {
        _replaceAllFiles(cached);
        Log.i(
            '📅 DailyFileProvider: Restored ${cached.length} daily files from disk cache');
        notifyListeners();
      }

      // Stage B: refresh today from disk so it's never stale. An unreadable
      // file must not abort startup; opening it reports the error.
      final todayDate = getTodayDate();
      try {
        final todayFile = await _dailyRepository.loadByDate(todayDate);
        if (todayFile != null) {
          _upsertFile(todayFile);
        }
      } catch (e) {
        Log.e('❌ DailyFileProvider: Cannot read today\'s file', error: e);
      }

      // Notify the UI first; the home-screen widget update (disk read +
      // platform channel) must not delay first paint.
      notifyListeners();
      unawaited(_updateWidget());
      Log.i('📅 DailyFileProvider: Today-priority load complete');
    } catch (e) {
      Log.e('❌ DailyFileProvider: Error in today-priority load', error: e);
      rethrow;
    }
  }

  /// Incremental update - only load modified daily files
  Future<void> loadDailyFilesIncremental() async {
    Log.i('📅 DailyFileProvider: Loading incremental daily file changes...');
    try {
      _replaceAllFiles(await _dailyRepository.loadIncremental());
      Log.i(
          '📅 DailyFileProvider: Incremental load completed, ${_dailyFiles.length} total files');

      notifyListeners();
      unawaited(_updateWidget());
    } catch (e) {
      Log.e('❌ DailyFileProvider: Error in incremental daily file load',
          error: e);
      rethrow;
    }
  }

  /// Add events from external sources (like ICS files) to appropriate daily files
  Future<void> addEventsFromIntent(
      BuildContext context, List<CalendarEvent> events) async {
    try {
      Log.i('📅 DailyFileProvider: Adding ${events.length} events from intent');

      // Group events by date
      final eventsByDate = <String, List<CalendarEvent>>{};
      for (final event in events) {
        eventsByDate.putIfAbsent(event.date, () => []).add(event);
      }

      // Process each date's events
      for (final entry in eventsByDate.entries) {
        final date = entry.key;
        final dateEvents = entry.value;

        // Get existing daily file or create template
        var dailyFile = await getDailyFile(date);
        String content = dailyFile?.content ?? '';

        // If no content exists, use the default template
        if (content.isEmpty) {
          // We need to get the template from ThemeProvider
          // This is a bit tricky since we can't access ThemeProvider directly here
          // For now, we'll use a basic template
          content = _getBasicDailyTemplate();
        }

        // Add events to content
        content = _addEventsToDailyContent(content, dateEvents);

        // Save the updated content
        if (!context.mounted) return;
        await saveDailyFile(context, date, content);
      }

      Log.i('📅 DailyFileProvider: Successfully added events from intent');
    } catch (e) {
      Log.e('❌ DailyFileProvider: Error adding events from intent', error: e);
      rethrow;
    }
  }

  /// Get a basic daily template
  String _getBasicDailyTemplate() {
    return '''# Daily Notes

## Events

## Tasks

## Notes
''';
  }

  /// Add events to daily content via the shared content helper.
  /// Each event becomes one logical line `- @HH:MM Title` followed by
  /// indented description lines.
  String _addEventsToDailyContent(String content, List<CalendarEvent> events) {
    final eventLines = events.map((e) {
      final desc = e.description
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => '  $l')
          .join('\n');
      final headerLine = '- @${e.formattedTime} ${e.title}';
      return desc.isEmpty ? headerLine : '$headerLine\n$desc';
    }).toList();

    return DailyContentHelper.insertEventsChronologically(
      content,
      eventLines,
      r'^#{1,2}\s+.*Events?',
    );
  }

  /// With [expected], the save fails with [FileConflictException] when the
  /// file changed on disk since the caller read it.
  Future<void> saveDailyFile(
          BuildContext context, String date, String content,
          {ExpectedContent? expected}) =>
      _saveDaily(date, content, expected: expected);

  Future<void> _saveDaily(String date, String content,
      {ExpectedContent? expected}) async {
    try {
      Log.d('📅 DailyFileProvider: Saving daily file for $date');
      final dailyFile =
          await _dailyRepository.create(date, content, expected: expected);

      _upsertFile(dailyFile);

      // Tell FileMonitorService to skip this date (avoid cancel+reschedule race)
      FileMonitorService().markRecentlyScheduled(date);

      // Notifications + widget update are debounced: while the user types
      // (autosave every 500ms) only the last save of the burst triggers them.
      _postSaveTimers[date]?.cancel();
      _postSaveTimers[date] = Timer(_postSaveDebounce, () {
        _postSaveTimers.remove(date);
        unawaited(_scheduleEventNotifications(date, content));
        unawaited(_updateWidget());
        // Flush the disk cache: the startup fast path restores from it, and
        // on Android the process is often killed before the next full scan.
        unawaited(_dailyRepository.persistCache());
      });

      Log.d('📅 DailyFileProvider: Saved daily file for $date');
      notifyListeners();
    } catch (e) {
      Log.e('❌ DailyFileProvider: Error saving daily file', error: e);
      rethrow;
    }
  }

  /// Edits of one day run one after another: run together, each would
  /// take the other's write for an external change and start over.
  final Map<String, Future<void>> _updateQueues = {};

  /// Read the day's file from disk, apply [edit] and save the result,
  /// checked against what was read. If another app or a sync tool writes
  /// the file in between, [edit] is re-applied to that newer content
  /// instead of overwriting it. [template] seeds a day without a file;
  /// without one, a missing file is left alone. Edits of the same day wait
  /// for each other.
  Future<void> updateDailyFile(
    String date,
    String Function(String content) edit, {
    String? template,
  }) {
    final next = (_updateQueues[date] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) => _updateDailyFile(date, edit, template: template));
    _updateQueues[date] = next;
    next.then((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_updateQueues[date], next)) _updateQueues.remove(date);
    });
    return next;
  }

  Future<void> _updateDailyFile(
    String date,
    String Function(String content) edit, {
    String? template,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1;; attempt++) {
      final current = await getDailyFile(date);
      final base = current?.content ?? template;
      if (base == null) return;
      final updated = edit(base);
      if (current != null && updated == current.content) return;
      try {
        await _saveDaily(date, updated,
            expected: ExpectedContent(current?.content));
        return;
      } on FileConflictException {
        if (attempt >= maxAttempts) rethrow;
        Log.w('⚠️ DailyFileProvider: $date changed while editing, retrying');
      }
    }
  }

  /// Check ([done]) or uncheck [task] of [date], in the file as it is on
  /// disk.
  Future<void> setTodoDone(String date, TaskItem task, bool done) =>
      updateDailyFile(
          date, (content) => DailyContentHelper.setTodoDone(content, task, done));

  /// The latest day before [date] that has undone todos, with them.
  ({String date, List<TaskItem> todos})? latestUndoneBefore(String date) {
    for (final file in _dailyFiles) {
      // Sorted newest first.
      if (file.date.compareTo(date) >= 0) continue;
      final undone = getTasks(file.date).where((t) => !t.isCompleted).toList();
      if (undone.isNotEmpty) return (date: file.date, todos: undone);
    }
    return null;
  }

  /// Move undone todos ([todoTextsBySource]: source date to todo texts) from
  /// earlier days to [targetDate], or copy them without [move]. The target
  /// is written first: if that fails, every todo is still in its source
  /// day. An interruption after it can leave a todo in both days, never in
  /// neither.
  Future<void> refillTodos(
    String targetDate,
    Map<String, List<String>> todoTextsBySource, {
    required String template,
    required String todoHeaderRegex,
    bool move = true,
  }) async {
    final texts = todoTextsBySource.values.expand((t) => t).toList();
    await updateDailyFile(targetDate, (content) {
      var updated = content;
      for (final text in texts) {
        updated = DailyContentHelper.insertAfterLastTodo(
            updated, '- [ ] $text', todoHeaderRegex);
      }
      return updated;
    }, template: template);

    if (!move) return;
    for (final entry in todoTextsBySource.entries) {
      await updateDailyFile(entry.key,
          (content) => DailyContentHelper.removeUndoneTodos(content, entry.value));
    }
    Log.i('📅 DailyFileProvider: Refilled ${texts.length} todo(s) '
        'to $targetDate');
  }

  Future<void> _scheduleEventNotifications(String date, String content) async {
    try {
      final notificationService = NotificationService();
      await notificationService.initialize();

      final events = MarkdownParser.parseEvents(date, content);

      await notificationService.cancelNotificationsForDate(date);

      for (final event in events) {
        final eventId =
            NotificationService.generateEventId(event.displayTitle, event.time);
        await notificationService.scheduleEventNotification(
          id: eventId,
          title: event.displayTitle,
          description: event.description,
          eventDateTime: event.time,
          date: date,
        );
      }

      Log.i(
          '📅 DailyFileProvider: Scheduled ${events.length} event notifications for $date');
    } catch (e) {
      Log.e('❌ DailyFileProvider: Error scheduling event notifications',
          error: e);
    }
  }

  void setSelectedDate(String date) {
    _selectedDate = date;
    Log.d('📅 DailyFileProvider: Selected date set to $date');
    notifyListeners();
  }

  /// Get daily file from memory cache only (fast, may be stale)
  DailyFile? getDailyFileFromCache(String date) => _byDate[date];

  /// Persist the repository disk cache now (e.g. when the app is paused).
  Future<void> persistCache() => _dailyRepository.persistCache();

  /// Get daily file, always checking disk for latest version
  /// Use this when you need to ensure you have the most recent data
  Future<DailyFile?> getDailyFile(String date) async {
    final fromDisk = await _dailyRepository.loadByDate(date);
    if (fromDisk != null) {
      final existing = _byDate[date];
      final changed = existing == null || existing.content != fromDisk.content;
      _upsertFile(fromDisk);
      if (changed) {
        Log.d('📅 DailyFileProvider: Loaded daily file for $date from disk');
        notifyListeners();
      }
      return fromDisk;
    }
    // Deleted on disk: drop the stale in-memory copy too, so nothing edits
    // or displays a file that no longer exists.
    if (_byDate.remove(date) != null) {
      _parseCache.remove(date);
      _dailyFiles = _dailyFiles.where((f) => f.date != date).toList();
      notifyListeners();
    }
    return null;
  }

  /// Alias for getDailyFile - loads from disk
  Future<DailyFile?> ensureDailyFileLoaded(String date) async {
    return getDailyFile(date);
  }

  String getTodayDate() {
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    Log.d('📅 DailyFileProvider: Today\'s date is $date');
    return date;
  }

  bool hasUndoneTodos(String date) =>
      _getParsed(date)?.tasks.any((t) => !t.isCompleted) ?? false;

  bool hasTodos(String date) => _getParsed(date)?.tasks.isNotEmpty ?? false;

  int getUndoneTodoCount(String date) =>
      _getParsed(date)?.tasks.where((t) => !t.isCompleted).length ?? 0;

  /// Memoised tasks for a date — cheap to call from build methods.
  List<TaskItem> getTasks(String date) => _getParsed(date)?.tasks ?? const [];

  /// Memoised free-text notes for a date, without the lines of the logs
  /// section ([logHeaderRegex]) - cheap to call from build methods.
  List<String> getNotes(String date, {String? logHeaderRegex}) =>
      _getFreeText(date, logHeaderRegex)?.notes ?? const [];

  /// Memoised lines of the logs section ([logHeaderRegex]) for a date.
  List<String> getLogs(String date, String logHeaderRegex) =>
      _getFreeText(date, logHeaderRegex)?.logs ?? const [];

  ({List<String> notes, List<String> logs})? _getFreeText(
      String date, String? logHeaderRegex) {
    final parsed = _getParsed(date);
    if (parsed == null) return null;
    if (parsed.freeText == null || parsed.logHeaderRegex != logHeaderRegex) {
      parsed
        ..logHeaderRegex = logHeaderRegex
        ..freeText = MarkdownParser.parseFreeText(_byDate[date]!.content,
            logHeaderRegex: logHeaderRegex);
    }
    return parsed.freeText;
  }

  List<CalendarEvent> getCalendarEvents(String date) =>
      _getParsed(date)?.events ?? const [];

  bool hasCalendarEvents(String date) =>
      _getParsed(date)?.events.isNotEmpty ?? false;

  Future<void> checkDateChangeAndUpdateWidget() async {
    final todayDate = getTodayDate();
    if (_lastWidgetUpdateDate != todayDate) {
      Log.i(
          '📱 DailyFileProvider: Date changed detected (was: $_lastWidgetUpdateDate, now: $todayDate), updating widget');
      await _updateWidget();
    }
  }

  /// Update widget with today's daily file
  Future<void> _updateWidget() async {
    try {
      if (!_storageService.isInitialized) {
        Log.d(
            '📱 DailyFileProvider: Skipping widget update - storage not initialized');
        return;
      }

      final todayDate = getTodayDate();

      if (_lastWidgetUpdateDate != todayDate) {
        Log.i(
            '📱 DailyFileProvider: Date changed from $_lastWidgetUpdateDate to $todayDate, updating widget');
        _lastWidgetUpdateDate = todayDate;
      } else {
        Log.d(
            '📱 DailyFileProvider: Updating widget (date unchanged: $todayDate)');
      }

      final todayDailyFile = await getDailyFile(todayDate);

      if (todayDailyFile != null && todayDailyFile.content.isNotEmpty) {
        await WidgetService.updateWithDailyFile(todayDailyFile);
      } else {
        await WidgetService.updateWidgetEmptyDay(todayDate);
      }

      Log.i('📱 DailyFileProvider: Widget updated successfully');
    } catch (e) {
      Log.e('❌ DailyFileProvider: Error updating widget', error: e);
    }
  }

  void startWidgetUpdateTimer() {
    _widgetUpdateTimer?.cancel();
    _widgetUpdateTimer = Timer.periodic(_widgetUpdateInterval, (timer) async {
      Log.d('📱 DailyFileProvider: Periodic widget update triggered');
      try {
        // Incremental: only re-reads files whose mtime changed, and skips
        // the disk-cache rewrite when nothing did.
        await loadDailyFilesIncremental();
        Log.d('📱 DailyFileProvider: Periodic widget update completed');
      } catch (e) {
        Log.e('❌ DailyFileProvider: Error in periodic widget update', error: e);
      }
    });
    Log.i(
        '📱 DailyFileProvider: Started periodic widget update timer (every 30 minutes)');
  }

  @override
  void dispose() {
    _widgetUpdateTimer?.cancel();
    _widgetUpdateTimer = null;
    for (final timer in _postSaveTimers.values) {
      timer.cancel();
    }
    _postSaveTimers.clear();
    if (FileMonitorService().onDailyFileChanged == _onExternalFileChanged) {
      FileMonitorService().onDailyFileChanged = null;
    }
    Log.i('📅 DailyFileProvider: Disposed');
    super.dispose();
  }
}
