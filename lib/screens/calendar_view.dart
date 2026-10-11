import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planetxt/constants/app_constants.dart';
import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/providers/theme_provider.dart';
import 'package:planetxt/services/shared_prefs_service.dart';
import 'package:planetxt/utils/logger.dart';
import 'package:planetxt/utils/markdown_parser.dart';
import 'package:planetxt/widgets/calendar_day_widget.dart';
import 'package:planetxt/widgets/daily_content_view.dart';
import 'package:planetxt/widgets/daily_editor_fullscreen.dart';
import 'package:planetxt/widgets/quick_add_modal.dart';
import 'package:planetxt/widgets/refill_dialog.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  static final DateTime _firstDay = DateTime(2000);
  static final DateTime _lastDay = DateTime(2100, 12, 31);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Set<String> _pendingToggles = {};

  /// Day the carry-over prompt was last answered (`yyyyMMdd`).
  String? _carryOverAnswered;
  late final DailyFileProvider _dailyFileProvider;

  @override
  void initState() {
    super.initState();
    _dailyFileProvider = context.read<DailyFileProvider>();
    // The day picked last (or by an ICS import before this view existed).
    _selectedDay =
        _shownDay(_dailyFileProvider.selectedDate) ?? DateTime.now();
    _focusedDay = _selectedDay!;
    _dailyFileProvider.addListener(_followSelectedDate);
    try {
      _carryOverAnswered = SharedPrefsService.instance
          .getString(AppConstants.carryOverPromptDateKey);
    } on StateError {
      // Preferences not loaded (tests).
    }
  }

  @override
  void dispose() {
    _dailyFileProvider.removeListener(_followSelectedDate);
    super.dispose();
  }

  /// Show the day selected from outside this view: after an ICS import,
  /// the app opens on the imported day.
  void _followSelectedDate() {
    final date = _dailyFileProvider.selectedDate;
    if (date == _formatDate(_selectedDay!)) return;
    final day = _shownDay(date);
    if (day == null) return;
    setState(() {
      _selectedDay = day;
      _focusedDay = day;
    });
    _revalidate(date);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DailyFileProvider>(
      builder: (context, dailyFileProvider, child) {
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TableCalendar<DailyFile>(
                firstDay: _firstDay,
                lastDay: _lastDay,
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, _) => _selectDay(selectedDay),
                onPageChanged: (focusedDay) => _focusedDay = focusedDay,
                eventLoader: (day) => [],
                calendarFormat: CalendarFormat.month,
                startingDayOfWeek: StartingDayOfWeek.monday,
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: false,
                  markersMaxCount: 0,
                  cellPadding: EdgeInsets.zero,
                  cellMargin: EdgeInsets.zero,
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) =>
                      _buildCustomDay(context, day, focusedDay, dailyFileProvider),
                  selectedBuilder: (context, day, focusedDay) =>
                      _buildCustomDay(context, day, focusedDay, dailyFileProvider, isSelected: true),
                  todayBuilder: (context, day, focusedDay) =>
                      _buildCustomDay(context, day, focusedDay, dailyFileProvider, isToday: true),
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  leftChevronPadding: EdgeInsets.zero,
                  rightChevronPadding: EdgeInsets.zero,
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(fontSize: 12),
                  weekendStyle: TextStyle(fontSize: 12),
                ),
              ),
            ),
            Expanded(
              // Swipe the day's content to move to the next or previous
              // day; the calendar above swipes by month.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: _onDaySwipe,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: _buildDailyContent(dailyFileProvider),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Select [day] in the calendar and show its content.
  void _selectDay(DateTime day) {
    if (isSameDay(_selectedDay, day) ||
        day.isBefore(_firstDay) ||
        day.isAfter(_lastDay)) {
      return;
    }
    setState(() {
      _selectedDay = day;
      _focusedDay = day;
    });
    _loadDailyContent(day);
  }

  void _onDaySwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return; // a slow drag is not a swipe
    final day = _selectedDay!;
    // Built from the date parts, not by adding 24 hours: a day with a
    // daylight saving change is 23 or 25 hours long.
    _selectDay(DateTime(day.year, day.month, day.day + (velocity < 0 ? 1 : -1)));
  }

  Widget _buildDailyContent(DailyFileProvider dailyFileProvider) {
    final dateString = _formatDate(_selectedDay!);
    final dailyFile = dailyFileProvider.getDailyFileFromCache(dateString);
    final isToday = isSameDay(_selectedDay, DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('EEE d MMM').format(_selectedDay!),
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!isToday)
              TextButton(
                onPressed: () => _selectDay(DateTime.now()),
                child: const Text('Today'),
              ),
            IconButton(
              onPressed: () => _showQuickAddModal(context, dailyFileProvider),
              icon: const Icon(Icons.add),
              tooltip: 'Quick add event or todo',
            ),
            IconButton(
              onPressed: () =>
                  _openDailyEditor(context, dailyFileProvider, dateString),
              icon: const Icon(Icons.edit),
              tooltip: 'Edit daily notes',
            ),
            IconButton(
              onPressed: () =>
                  _showRefillDialog(context, dailyFileProvider, dateString),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refill undone todos to this day',
            ),
          ],
        ),
        if (isToday) _buildCarryOverPrompt(dailyFileProvider, dateString),
        const SizedBox(height: 16),
        if (dailyFile == null)
          _buildEmptyDay(dailyFileProvider, dateString, isToday)
        else
          Selector<ThemeProvider, String>(
            selector: (_, theme) => theme.logHeaderRegex,
            // The callbacks use the view's context, not the builder's.
            builder: (_, logHeaderRegex, __) => DailyContentView(
              dailyFileProvider: dailyFileProvider,
              dateString: dateString,
              logHeaderRegex: logHeaderRegex,
              onOpenEditor: () =>
                  _openDailyEditor(context, dailyFileProvider, dateString),
              onToggleTask: (task, done) =>
                  _toggleTask(dailyFileProvider, dateString, task, done),
            ),
          ),
      ],
    );
  }

  /// First look at today: offer to carry over the todos left undone on the
  /// last day that has some, within a week. Shown until answered, once a
  /// day.
  Widget _buildCarryOverPrompt(
      DailyFileProvider dailyFileProvider, String today) {
    if (_carryOverAnswered == today) return const SizedBox.shrink();
    final latest = dailyFileProvider.latestUndoneBefore(today);
    // Older todos are likely dropped: no prompt about them every morning.
    if (latest == null ||
        _parseDateFromString(latest.date)
            .isBefore(_selectedDay!.subtract(const Duration(days: 7)))) {
      return const SizedBox.shrink();
    }
    final count = latest.todos.length;
    final day = DateFormat('EEE d MMM').format(_parseDateFromString(latest.date));
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(count == 1
                ? '1 todo left undone on $day'
                : '$count todos left undone on $day'),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _answerCarryOver(today),
                  child: const Text('Dismiss'),
                ),
                TextButton(
                  onPressed: () {
                    _answerCarryOver(today);
                    _showRefillDialog(context, dailyFileProvider, today,
                        preselectDate: latest.date);
                  },
                  child: const Text('Carry over'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _answerCarryOver(String today) {
    setState(() => _carryOverAnswered = today);
    try {
      unawaited(SharedPrefsService.instance
          .setString(AppConstants.carryOverPromptDateKey, today));
    } on StateError {
      // Preferences not loaded (tests): answered for this session only.
    }
  }

  /// A day without a file: say so, and offer the two ways to fill it.
  Widget _buildEmptyDay(
      DailyFileProvider dailyFileProvider, String dateString, bool isToday) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          children: [
            Icon(isToday ? Icons.wb_sunny_outlined : Icons.event_note,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              isToday ? 'Nothing planned yet today' : 'Nothing for this day',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  _openDailyEditor(context, dailyFileProvider, dateString),
              icon: const Icon(Icons.edit),
              label: Text(isToday ? 'Start the day' : 'Write this day'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _showQuickAddModal(context, dailyFileProvider),
              icon: const Icon(Icons.add),
              label: const Text('Quick add'),
            ),
          ],
        ),
      ),
    );
  }

  /// The day [date] (`yyyyMMdd`) names, if the calendar can show it.
  DateTime? _shownDay(String date) {
    if (!RegExp(r'^\d{8}$').hasMatch(date)) return null;
    final day = _parseDateFromString(date);
    return day.isBefore(_firstDay) || day.isAfter(_lastDay) ? null : day;
  }

  /// Check or uncheck [task]. A second tap on the same row while the first
  /// one is being written is ignored: it would act on the stale state.
  Future<void> _toggleTask(DailyFileProvider dailyFileProvider, String date,
      TaskItem task, bool done) async {
    final key = '$date:${task.line}';
    if (!_pendingToggles.add(key)) return;
    try {
      await dailyFileProvider.setTodoDone(date, task, done);
    } catch (e) {
      if (mounted) _showSaveError(context, e);
    } finally {
      _pendingToggles.remove(key);
    }
  }

  void _loadDailyContent(DateTime day) {
    final dateString = _formatDate(day);
    _dailyFileProvider.setSelectedDate(dateString);
    _revalidate(dateString);
  }

  /// Revalidate [dateString] against disk - the startup fast path only
  /// refreshes today, so another date may still show stale cached content.
  void _revalidate(String dateString) {
    unawaited(_dailyFileProvider
        .ensureDailyFileLoaded(dateString)
        .catchError((Object e) {
      Log.e('❌ CalendarView: Cannot read daily file $dateString', error: e);
      return null;
    }));
  }

  void _showSaveError(BuildContext context, Object error) {
    Log.e('❌ CalendarView: Cannot save daily file', error: error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not save: $error'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// The day's file exists but could not be read: say so, and never fall
  /// back to the template - its first save would overwrite the real file.
  void _showReadError(BuildContext context, Object error) {
    Log.e('❌ CalendarView: Cannot read daily file', error: error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("This day's file could not be read (is it valid "
            'UTF-8 text?). It was left untouched.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showQuickAddModal(
      BuildContext context, DailyFileProvider dailyFileProvider) async {
    if (_selectedDay == null) return;

    final dateString = _formatDate(_selectedDay!);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    // Fail early on an unreadable file, before the user types anything.
    try {
      await dailyFileProvider.ensureDailyFileLoaded(dateString);
    } catch (e) {
      if (context.mounted) _showReadError(context, e);
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      // The saves below use the view's context: the dialog's own one
      // unmounts as soon as it pops.
      builder: (dialogContext) => QuickAddModal(
        selectedDate: _selectedDay!,
        onAdd: (content, type) {
          // Applied to the file as it is when saving, not as it was when
          // the dialog opened: a sync landing meanwhile is kept.
          dailyFileProvider
              .updateDailyFile(dateString,
                  (current) =>
                      insertQuickAdd(current, content, type, themeProvider),
                  template: themeProvider.dailyTemplate)
              .catchError((Object e) {
            if (context.mounted) _showSaveError(context, e);
          });
        },
      ),
    );
  }

  Future<void> _openDailyEditor(BuildContext context,
      DailyFileProvider dailyFileProvider, String dateString) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    // Re-read from disk before editing: opening the editor from a stale
    // cache and autosaving would overwrite newer file content.
    final DailyFile? fresh;
    try {
      fresh = await dailyFileProvider.ensureDailyFileLoaded(dateString);
    } catch (e) {
      if (context.mounted) _showReadError(context, e);
      return;
    }
    final initialContent = fresh?.content ?? themeProvider.dailyTemplate;

    if (!context.mounted) return;
    final noteFileProvider = context.read<NoteFileProvider>();
    Future<void> save(String content, ExpectedContent expected) =>
        dailyFileProvider.saveDailyFile(context, dateString, content,
            expected: expected);
    Navigator.of(context).push(
      MaterialPageRoute(
        // Rebuilt with the file's latest known content, so the editor can
        // reload after an external change.
        builder: (context) => Selector<DailyFileProvider, String?>(
          selector: (_, provider) =>
              provider.getDailyFileFromCache(dateString)?.content,
          builder: (context, diskContent, _) => DailyEditorFullscreen(
            date: dateString,
            initialContent: initialContent,
            diskContent: diskContent,
            onSave: save,
            onAutoSave: save,
            // Kept as a note: notes can be opened in the app, so the user
            // can merge the lost lines back.
            onSaveCopy: (content) => noteFileProvider.saveConflictCopy(
              folder: 'conflicts',
              baseName: 'daily $dateString',
              content: content,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildCustomDay(BuildContext context, DateTime day,
      DateTime focusedDay, DailyFileProvider dailyFileProvider,
      {bool isSelected = false, bool isToday = false}) {
    final dateString = _formatDate(day);

    // The provider memoises parsing per date (invalidated by content hash) —
    // never re-parse markdown here: this runs for ~42 cells on every rebuild.
    return CalendarDayWidget(
      day: day,
      isSelected: isSelected,
      isToday: isToday,
      isOutsideMonth: day.month != focusedDay.month,
      undoneTodoCount: dailyFileProvider.getUndoneTodoCount(dateString),
      hasTodos: dailyFileProvider.hasTodos(dateString),
      hasDailyFile: dailyFileProvider.getDailyFileFromCache(dateString) != null,
      hasCalendarEvents: dailyFileProvider.hasCalendarEvents(dateString),
    );
  }

  DateTime _parseDateFromString(String dateString) {
    return DateTime(
      int.parse(dateString.substring(0, 4)),
      int.parse(dateString.substring(4, 6)),
      int.parse(dateString.substring(6, 8)),
    );
  }

  /// Offer the undone todos of the days before [currentDate], those of
  /// [preselectDate] already ticked.
  void _showRefillDialog(BuildContext context,
      DailyFileProvider dailyFileProvider, String currentDate,
      {String? preselectDate}) {
    final undoneTodos = <RefillTodo>[];

    // Every daily file strictly before the selected day, newest first —
    // dailyFiles is already sorted by date descending.
    for (final dailyFile in dailyFileProvider.dailyFiles) {
      if (dailyFile.date.compareTo(currentDate) >= 0) continue;

      for (final task in dailyFileProvider.getTasks(dailyFile.date)) {
        if (!task.isCompleted) {
          undoneTodos.add(RefillTodo(
            text: task.text,
            sourceDate: dailyFile.date,
            sourceDateDisplay: DateFormat('EEE d MMM yyyy')
                .format(_parseDateFromString(dailyFile.date)),
          ));
        }
      }
    }

    if (undoneTodos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No undone todos found in previous days')),
      );
      return;
    }

    showDialog(
      context: context,
      // NOTE: _performRefill must get the view's context, not the dialog's:
      // the dialog pops right after onRefill, so its context unmounts during
      // the first await and every context.mounted guard would skip the saves.
      builder: (dialogContext) => RefillDialog(
        undoneTodos: undoneTodos,
        initiallySelected: {
          for (var i = 0; i < undoneTodos.length; i++)
            if (undoneTodos[i].sourceDate == preselectDate) i,
        },
        onRefill: (selectedTodos, {required move}) => _performRefill(
            context, dailyFileProvider, selectedTodos, currentDate,
            move: move),
      ),
    );
  }

  void _performRefill(BuildContext context, DailyFileProvider dailyFileProvider,
      List<RefillTodo> selectedTodos, String targetDate,
      {required bool move}) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final textsBySource = <String, List<String>>{};
    for (final todo in selectedTodos) {
      textsBySource.putIfAbsent(todo.sourceDate, () => []).add(todo.text);
    }

    try {
      await dailyFileProvider.refillTodos(
        targetDate,
        textsBySource,
        template: themeProvider.dailyTemplate,
        todoHeaderRegex: themeProvider.todoHeaderRegex,
        move: move,
      );
    } catch (e) {
      if (context.mounted) _showSaveError(context, e);
      return;
    }
    if (context.mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${move ? 'Moved' : 'Copied'} ${selectedTodos.length} todo(s) to ${_formatDisplayDate(_parseDateFromString(targetDate))}')),
      );
    }
  }

}
