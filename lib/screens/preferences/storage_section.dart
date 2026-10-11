import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/directory_provider.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/providers/theme_provider.dart';
import 'package:planetxt/services/file_monitor_service.dart';
import 'package:planetxt/services/file_store/saf_file_store.dart';
import 'package:provider/provider.dart';

class StorageSection extends StatelessWidget {
  const StorageSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final hasCustom = themeProvider.customStoragePath != null ||
            themeProvider.storageTreeUri != null;
        return ListTile(
          leading: const Icon(Icons.folder),
          title: const Text('Storage Location'),
          subtitle: Text(themeProvider.getDisplayStoragePath()),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasCustom)
                IconButton(
                  onPressed: () =>
                      _resetStorageLocation(context, themeProvider),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reset to default',
                ),
              const Icon(Icons.arrow_forward_ios),
            ],
          ),
          onTap: () => _showStorageLocationDialog(context, themeProvider),
        );
      },
    );
  }

  void _showStorageLocationDialog(
      BuildContext context, ThemeProvider themeProvider) {
    final hasCustom = themeProvider.customStoragePath != null ||
        themeProvider.storageTreeUri != null;
    // Storage is switched with the section's context, after the dialog
    // closed: the dialog's own context unmounts during the switch.
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose Storage Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select where you want to store your PlaneTxt files:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isAndroid
                  ? 'Pick a folder synced by Syncthing, Dropbox, etc. to '
                      'access your files from other devices. No special '
                      'permission is required.'
                  : 'Pick any folder to share your files with other tools.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.folder_special),
              title: const Text('Default Location'),
              subtitle: Text(defaultLocationDescription),
              trailing: !hasCustom
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await themeProvider.setStorageTree(null, null);
                if (!context.mounted) return;
                await reinitializeStorage(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Custom Folder'),
              subtitle: const Text('Choose a folder (e.g. a synced one)'),
              trailing: hasCustom
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                Navigator.of(dialogContext).pop();
                pickCustomFolder(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// What the default location means for the user's files.
  static String get defaultLocationDescription => Platform.isAndroid
      ? 'Private to PlaneTxt: sync apps cannot see it, and uninstalling '
          'the app deletes it'
      : 'The Org folder in your Documents';

  /// Let the user pick a storage folder and switch to it. [context] must
  /// outlive the picker - not a dialog's context. Returns whether the
  /// storage location changed.
  static Future<bool> pickCustomFolder(BuildContext context) async {
    final themeProvider = context.read<ThemeProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      final String location;
      if (Platform.isAndroid) {
        // System folder picker; the returned document-tree URI carries a
        // persistable read/write grant - no storage permission involved.
        final treeUri = await SafFileStore.pickTree();
        if (treeUri == null) return false; // cancelled

        location = await SafFileStore.treeDisplayName(treeUri);
        await themeProvider.setStorageTree(treeUri, location);
      } else {
        // Desktop / iOS: raw filesystem path.
        final selected = await FilePicker.getDirectoryPath();
        if (selected == null) return false;
        try {
          final testFile = File('$selected/.test_write');
          await testFile.writeAsString('test');
          await testFile.delete();
        } catch (e) {
          messenger.showSnackBar(SnackBar(
            content: Text('Cannot write to $selected: $e\n'
                'The storage location was not changed.'),
            backgroundColor: errorColor,
            duration: const Duration(seconds: 5),
          ));
          return false;
        }
        location = selected;
        await themeProvider.setStoragePath(selected);
      }

      if (!context.mounted) return true;
      await reinitializeStorage(context);
      messenger.showSnackBar(SnackBar(
        content: Text('Storage location changed to: $location'),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ));
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Error selecting folder: $e'),
        backgroundColor: errorColor,
      ));
      return false;
    }
  }

  void _resetStorageLocation(
      BuildContext context, ThemeProvider themeProvider) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Storage Location'),
        content: const Text(
          'Are you sure you want to reset the storage location to the default folder?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final treeUri = themeProvider.storageTreeUri;
              await themeProvider.setStorageTree(null, null);
              // Release the now-unused grant (best effort).
              if (treeUri != null) {
                try {
                  await SafFileStore.releaseTree(treeUri);
                } catch (_) {}
              }
              if (!context.mounted) return;
              await reinitializeStorage(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Storage location reset to default')),
                );
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  /// Switch every provider to the storage location now configured.
  static Future<void> reinitializeStorage(BuildContext context) async {
    // Looked up before the first await: [context] may unmount meanwhile,
    // and the reloads below must still run.
    final directoryProvider = context.read<DirectoryProvider>();
    final dailyProvider = context.read<DailyFileProvider>();
    final noteProvider = context.read<NoteFileProvider>();
    await directoryProvider.initializeDirectories(context);
    // Re-attach the file monitor to the new root (watch vs polling may
    // differ between io and SAF roots).
    await FileMonitorService().reinitialize();
    // Force-reload from the new root; the in-memory and disk caches still
    // hold the previous folder's content. Runs in the background - the
    // "building cache" banner covers the wait.
    unawaited(dailyProvider.loadDailyFiles(forceReload: true));
    unawaited(noteProvider.loadNoteFiles(forceReload: true));
  }
}
