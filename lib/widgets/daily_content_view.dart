import 'package:flutter/material.dart';
import 'package:planetxt/models/calendar_event.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/theme_provider.dart';
import 'package:planetxt/utils/markdown_parser.dart';
import 'package:provider/provider.dart';

class DailyContentView extends StatelessWidget {
  final DailyFileProvider dailyFileProvider;
  final String dateString;

  const DailyContentView({
    super.key,
    required this.dailyFileProvider,
    required this.dateString,
  });

  @override
  Widget build(BuildContext context) {
    final logHeaderRegex =
        context.select<ThemeProvider, String>((t) => t.logHeaderRegex);
    return Column(
      children: [
        CalendarEventsSection(
          dailyFileProvider: dailyFileProvider,
          dateString: dateString,
        ),
        const SizedBox(height: 12),
        TasksSection(
          dailyFileProvider: dailyFileProvider,
          dateString: dateString,
        ),
        const SizedBox(height: 12),
        _TextSection(
          icon: Icons.history_edu,
          title: 'Logs',
          lines: dailyFileProvider.getLogs(dateString, logHeaderRegex),
        ),
        const SizedBox(height: 12),
        _TextSection(
          icon: Icons.notes,
          title: 'Notes',
          lines: dailyFileProvider.getNotes(dateString,
              logHeaderRegex: logHeaderRegex),
        ),
      ],
    );
  }
}

class CalendarEventsSection extends StatelessWidget {
  final DailyFileProvider dailyFileProvider;
  final String dateString;

  const CalendarEventsSection({
    super.key,
    required this.dailyFileProvider,
    required this.dateString,
  });

  @override
  Widget build(BuildContext context) {
    final events = dailyFileProvider.getCalendarEvents(dateString);

    if (events.isEmpty) return const SizedBox.shrink();

    return _SectionContainer(
      icon: Icons.schedule,
      title: 'Events',
      children: events.map((event) => _EventRow(event: event)).toList(),
    );
  }
}

class _EventRow extends StatelessWidget {
  final CalendarEvent event;

  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BulletDot(color: Theme.of(context).colorScheme.primary),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      event.formattedTime,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        event.displayTitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                if (event.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TasksSection extends StatelessWidget {
  final DailyFileProvider dailyFileProvider;
  final String dateString;

  const TasksSection({
    super.key,
    required this.dailyFileProvider,
    required this.dateString,
  });

  @override
  Widget build(BuildContext context) {
    final tasks = dailyFileProvider.getTasks(dateString);
    if (tasks.isEmpty) return const SizedBox.shrink();

    return _SectionContainer(
      icon: Icons.task_alt,
      title: 'Tasks',
      children: tasks.map((task) => _TaskRow(task: task)).toList(),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TaskItem task;

  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BulletDot(
            color: task.isCompleted
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.error,
          ),
          Expanded(
            child: Text(
              task.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    decoration:
                        task.isCompleted ? TextDecoration.lineThrough : null,
                    color: task.isCompleted
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Free-text lines of the day: the logs section, or the notes.
class _TextSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;

  const _TextSection({
    required this.icon,
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();

    return _SectionContainer(
      icon: icon,
      title: title,
      children: lines
          .map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BulletDot(
                        color: Theme.of(context).colorScheme.primary),
                    Expanded(
                      child: Text(line,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

class _SectionContainer extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionContainer({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _BulletDot extends StatelessWidget {
  final Color color;

  const _BulletDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.only(top: 6, right: 8),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
