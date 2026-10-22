import 'package:flutter/material.dart';
import 'package:planetxt/providers/theme_provider.dart';
import 'package:planetxt/screens/preferences/storage_section.dart';
import 'package:provider/provider.dart';

/// Lets the user configure how a calendar date maps to that day's note file
/// path (see lib/utils/daily_path_format.dart), as two settings: a directory
/// and a file name, both supporting date expansion (`%Y`, `%m`, `%d`).
/// Defaults are `dailies` + `%Y%m%d.md`; a Notes-style repository can use
/// `cal/%Y/%m/%d` + `daily.md`. Every `.md` note inside a day's directory is
/// indexed; new daily notes are named after the configured file name.
class DailyPathTile extends StatelessWidget {
  const DailyPathTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final dir = themeProvider.dailyPathDir;
        final fileName = themeProvider.dailyPathFileName;
        return ListTile(
          leading: const Icon(Icons.calendar_today),
          title: const Text('Daily File Layout'),
          subtitle: Text(
            dir.isEmpty ? fileName : '$dir/$fileName',
          ),
          trailing: const Icon(Icons.arrow_forward_ios),
          onTap: () => _edit(context, themeProvider),
        );
      },
    );
  }

  Future<void> _edit(BuildContext context, ThemeProvider themeProvider) async {
    final result = await showDailyPathDialog(
      context,
      directory: themeProvider.dailyPathDir,
      fileName: themeProvider.dailyPathFileName,
    );
    if (result == null || !context.mounted) return;
    final (dir, fileName) = result;
    if (dir == themeProvider.dailyPathDir &&
        fileName == themeProvider.dailyPathFileName) {
      return;
    }

    await themeProvider.setDailyPathDir(dir);
    await themeProvider.setDailyPathFileName(fileName);
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

/// Ask the user for a daily file layout: a directory and a file name, both
/// supporting date expansion. Returns `(directory, fileName)`, or `null`
/// when cancelled. Validates that the layout maps a date (a `%Y`, `%m` or
/// `%d` token in either part).
Future<(String, String)?> showDailyPathDialog(
  BuildContext context, {
  required String directory,
  required String fileName,
}) async {
  final dirController = TextEditingController(text: directory);
  final nameController = TextEditingController(text: fileName);
  final messenger = ScaffoldMessenger.of(context);

  final result = await showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      // The intro/examples text is long; keep it scrollable so the text fields
      // and Cancel/Save buttons stay visible when the keyboard appears.
      scrollable: true,
      title: const Text('Daily File Layout'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Two settings place each day\'s note inside your storage '
              'folder. Both support date expansion:\n'
              '%Y year, %m month, %d day.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'The directory sets where each date lives. When it carries '
              'the date, every .md note inside that directory is indexed; '
              'the file name only names new notes.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text('Examples:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            const Text('  dailies  +  %Y%m%d.md',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const Text('    dailies/20260713.md (default layout)',
                style: TextStyle(fontSize: 12)),
            const Text('  cal/%Y/%m/%d  +  daily.md',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const Text(
                '    cal/2026/07/13/daily.md, and any other .md note in '
                'that day\'s directory is indexed too',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: dirController,
              decoration: const InputDecoration(
                labelText: 'Directory',
                hintText: 'dailies, or cal/%Y/%m/%d',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'File name',
                hintText: '%Y%m%d.md, or daily.md',
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
            final dir = dirController.text.trim();
            final name = nameController.text.trim();
            if (!_hasDateToken(dir) && !_hasDateToken(name)) {
              messenger.showSnackBar(const SnackBar(
                content: Text(
                    'Invalid layout: add %Y, %m or %d so a date maps to a '
                    'path'),
                backgroundColor: Colors.red,
              ));
              return;
            }
            if (dir.startsWith('/') ||
                name.contains('/') ||
                dir.contains('..') ||
                name.contains('..')) {
              messenger.showSnackBar(const SnackBar(
                content: Text('Invalid layout: path must stay relative'),
                backgroundColor: Colors.red,
              ));
              return;
            }
            Navigator.of(context).pop((dir, name));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return result;
}

bool _hasDateToken(String value) =>
    value.contains('%Y') || value.contains('%m') || value.contains('%d');
