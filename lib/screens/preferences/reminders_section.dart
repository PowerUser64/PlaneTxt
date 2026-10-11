import 'package:flutter/material.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/services/file_monitor_service.dart';
import 'package:planetxt/services/notification_service.dart';
import 'package:provider/provider.dart';

/// How long before an event its reminder fires, or no reminders at all.
class RemindersTile extends StatefulWidget {
  const RemindersTile({super.key});

  /// The choices offered: minutes before the event, null for off.
  static const List<int?> choices = [null, 0, 10, 30, 60];

  static String describe(int? minutes) => switch (minutes) {
        null => 'Off',
        0 => 'When the event starts',
        60 => '1 hour before',
        final m => '$m minutes before',
      };

  @override
  State<RemindersTile> createState() => _RemindersTileState();
}

class _RemindersTileState extends State<RemindersTile> {
  int? _minutes = NotificationService().reminderMinutes;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_minutes == null
          ? Icons.notifications_off_outlined
          : Icons.notifications_active_outlined),
      title: const Text('Event reminders'),
      subtitle: Text(RemindersTile.describe(_minutes)),
      trailing: const Icon(Icons.arrow_forward_ios),
      onTap: _choose,
    );
  }

  Future<void> _choose() async {
    // -1 stands for "off" in the dialog: a null radio value would read as
    // "nothing selected".
    const off = -1;
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Event reminders'),
        children: [
          RadioGroup<int>(
            groupValue: _minutes ?? off,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              children: [
                for (final minutes in RemindersTile.choices)
                  RadioListTile<int>(
                    value: minutes ?? off,
                    title: Text(RemindersTile.describe(minutes)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final minutes = chosen == off ? null : chosen;
    if (minutes == _minutes) return;

    final dailyFiles = context.read<DailyFileProvider>().dailyFiles;
    setState(() => _minutes = minutes);
    await NotificationService().setReminderMinutes(minutes);
    // Reschedule every upcoming event with the new delay.
    await FileMonitorService().scheduleExistingEvents(dailyFiles: dailyFiles);
  }
}
