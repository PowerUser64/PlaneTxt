import 'dart:async';

import 'package:flutter/material.dart';
import 'package:planetxt/models/daily_file.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/providers/theme_provider.dart';
import 'package:planetxt/utils/daily_content_helper.dart';
import 'package:planetxt/utils/logger.dart';
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
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
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
                firstDay: DateTime(2020),
                lastDay: DateTime(2030),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  if (!isSameDay(_selectedDay, selectedDay)) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                    _loadDailyContent(selectedDay);
                  }
                },
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
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _selectedDay != null
                    ? SingleChildScrollView(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom,
                        ),
                        child: _buildDailyContent(dailyFileProvider),
                      )
                    : const Center(child: Text('Select a day to view content')),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDailyContent(DailyFileProvider dailyFileProvider) {
    final dateString = _formatDate(_selectedDay!);
    final dailyFile = dailyFileProvider.getDailyFileFromCache(dateString);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
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
        const SizedBox(height: 16),
        if (dailyFile != null)
          GestureDetector(
            onDoubleTap: () =>
                _openDailyEditor(context, dailyFileProvider, dateString),
            child: DailyContentView(
              dailyFileProvider: dailyFileProvider,
              dateString: dateString,
            ),
          ),
      ],
    );
  }

  void _loadDailyContent(DateTime day) {
    final dateString = _formatDate(day);
    final provider = context.read<DailyFileProvider>();
    provider.setSelectedDate(dateString);
    // Revalidate the selected day against disk - the startup fast path only
    // refreshes today, so another date may still show stale cached content.
    unawaited(provider.ensureDailyFileLoaded(dateString).catchError((Object e) {
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
          String insert(String current) => switch (type) {
                QuickAddType.event => DailyContentHelper.insertAfterLastEvent(
                    current, content, themeProvider.eventHeaderRegex),
                QuickAddType.todo => DailyContentHelper.insertAfterLastTodo(
                    current, content, themeProvider.todoHeaderRegex),
                QuickAddType.log => DailyContentHelper.insertAtEndOfSection(
                    current, content, themeProvider.logHeaderRegex),
              };
          // Applied to the file as it is when saving, not as it was when
          // the dialog opened: a sync landing meanwhile is kept.
          dailyFileProvider
              .updateDailyFile(context, dateString, insert,
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

  void _showRefillDialog(BuildContext context,
      DailyFileProvider dailyFileProvider, String currentDate) {
    final undoneTodos = <RefillTodo>[];

    // Every daily file strictly before the selected day, newest first —
    // dailyFiles is already sorted by date descending.
    for (final dailyFile in dailyFileProvider.dailyFiles) {
      if (dailyFile.date.compareTo(currentDate) >= 0) continue;

      for (final task in dailyFileProvider.getTasks(dailyFile.date)) {
        if (!task.isCompleted) {
          undoneTodos.add(RefillTodo(
            content: '- [ ] ${task.text}',
            sourceDate: dailyFile.date,
            sourceDateDisplay:
                _formatDisplayDate(_parseDateFromString(dailyFile.date)),
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
        onRefill: (selectedTodos) =>
            _performRefill(context, dailyFileProvider, selectedTodos, currentDate),
      ),
    );
  }

  void _performRefill(BuildContext context, DailyFileProvider dailyFileProvider,
      List<RefillTodo> selectedTodos, String targetDate) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final targetDailyFile =
        await dailyFileProvider.ensureDailyFileLoaded(targetDate);
    String targetContent = targetDailyFile?.content ?? themeProvider.dailyTemplate;

    final todosByDate = <String, List<RefillTodo>>{};
    for (final todo in selectedTodos) {
      todosByDate.putIfAbsent(todo.sourceDate, () => []).add(todo);
    }

    for (final entry in todosByDate.entries) {
      final sourceDailyFile = await dailyFileProvider.getDailyFile(entry.key);
      if (sourceDailyFile != null) {
        String newSourceContent = sourceDailyFile.content;
        for (final todo in entry.value) {
          final lines = newSourceContent.split('\n');
          lines.removeWhere((line) => line.trim() == todo.content.trim());
          newSourceContent = lines.join('\n');
        }
        if (!context.mounted) return;
        await dailyFileProvider.saveDailyFile(
            context, entry.key, newSourceContent);
      }
    }

    for (final todo in selectedTodos) {
      targetContent = DailyContentHelper.insertAfterLastTodo(
          targetContent, todo.content, themeProvider.todoHeaderRegex);
    }

    if (context.mounted) {
      await dailyFileProvider.saveDailyFile(context, targetDate, targetContent);
    }
    if (context.mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Refilled ${selectedTodos.length} undone todo(s) to ${_formatDisplayDate(_parseDateFromString(targetDate))}')),
      );
    }
  }
}
