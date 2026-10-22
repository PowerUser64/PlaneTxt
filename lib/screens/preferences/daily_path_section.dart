import 'package:flutter/material.dart';
import 'package:planetxt/providers/theme_provider.dart';
import 'package:planetxt/screens/preferences/storage_section.dart';
import 'package:provider/provider.dart';

/// Lets the user configure how a calendar date maps to that day's note file
/// path (see lib/utils/daily_path_format.dart). Defaults to the classic
/// `dailies/YYYYMMDD.md`; a Notes-style repository can use e.g.
/// `cal/%Y/%m/%d/daily.md` (or `cal/%Y/%m/%d/*.md` for any file name).
class DailyPathTile extends StatelessWidget {
  const DailyPathTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return ListTile(
          leading: const Icon(Icons.calendar_today),
          title: const Text('Daily File Layout'),
          subtitle: Text(themeProvider.dailyPathFormat.isEmpty
              ? 'No layout set'
              : themeProvider.dailyPathFormat),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () => _edit(context, themeProvider),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, ThemeProvider themeProvider) async {
    final format = await showDailyPathDialog(
      context,
      currentFormat: themeProvider.dailyPathFormat,
    );
    if (format == null || !context.mounted) return;
    if (format == themeProvider.dailyPathFormat) return;

    await themeProvider.setDailyPathFormat(format);
    if (!context.mounted) return;
    // The layout change moves the daily files and their scan directory:
    // reload storage + reattach the file monitor so the new paths take
    // effect immediately.
    await StorageSection.reinitializeStorage(context);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Daily file layout saved and reloaded'),
      ));
    }
  }
}

/// Ask the user for a daily file layout format string. Returns the new
/// format, or `null` when cancelled. Validates that the format maps a date
/// (contains `%Y`, `%m` or `%d`).
Future<String?> showDailyPathDialog(
  BuildContext context, {
  required String currentFormat,
}) async {
  final controller = TextEditingController(text: currentFormat);
  final messenger = ScaffoldMessenger.of(context);

  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Daily File Layout'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set the path each day\'s note is stored at, relative to your '
              'storage folder. Tokens are replaced with the date:\n'
              '%Y year, %m month, %d day.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text('* matches any file name in a day directory.',
                style: TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            const Text('Examples:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            const Text('  dailies/%Y%m%d.md',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const Text('    dailies/20260713.md (default layout)',
                style: TextStyle(fontSize: 12)),
            const Text('  cal/%Y/%m/%d/daily.md',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const Text('    cal/2026/07/13/daily.md (Notes-style repo)',
                style: TextStyle(fontSize: 12)),
            const Text('  cal/%Y/%m/%d/*.md',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const Text('    any .md file under cal/2026/07/13/',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Daily file path format',
                hintText: 'cal/%Y/%m/%d/daily.md',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final format = controller.text.trim();
            if (!_hasDateToken(format)) {
              messenger.showSnackBar(SnackBar(
                content: Text(
                    'Invalid format: add %Y, %m or %d so a date maps to a '
                    'path'),
                backgroundColor: Colors.red,
              ));
              return;
            }
            if (format.startsWith('/') || format.contains('..')) {
              messenger.showSnackBar(SnackBar(
                content: Text('Invalid format: path must be relative'),
                backgroundColor: Colors.red,
              ));
              return;
            }
            Navigator.of(context).pop(format);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return result;
}

bool _hasDateToken(String format) =>
    format.contains('%Y') || format.contains('%m') || format.contains('%d');
