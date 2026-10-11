import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/models/note_file.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/services/intent_handler_service.dart';
import 'package:planetxt/utils/exceptions.dart';
import 'package:planetxt/utils/note_names.dart';
import 'package:planetxt/widgets/note_editor.dart';
import 'package:planetxt/widgets/note_list_item.dart';
import 'package:provider/provider.dart';

class NotesView extends StatefulWidget {
  const NotesView({super.key});

  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  /// Folders shown unfolded; every folder starts folded.
  final Set<String> _openFolders = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NoteFileProvider>(
      builder: (context, noteFileProvider, child) {
        final filteredNotes = _filterNotes(noteFileProvider.noteFiles);
        final entries = _listEntries(filteredNotes);

        return Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search notes...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                          icon: const Icon(Icons.clear),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),

            // Notes list
            Expanded(
              child: filteredNotes.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry is _FolderEntry) {
                          return _FolderHeader(
                            folder: entry.folder,
                            count: entry.count,
                            open: _openFolders.contains(entry.folder),
                            onTap: () => setState(() {
                              if (!_openFolders.remove(entry.folder)) {
                                _openFolders.add(entry.folder);
                              }
                            }),
                          );
                        }
                        final note = entry as NoteFile;
                        return NoteListItem(
                          note: note,
                          // In a search, folders are not grouped.
                          showFolder: _searchQuery.isNotEmpty,
                          onTap: () => _openNote(note),
                          onRename: () => _renameNote(note),
                          onDelete: () => _deleteNote(note),
                          onShare: () => _shareNote(note),
                          onArchive: () => _archiveNote(note),
                        );
                      },
                    ),
            ),

            // Add note button
            Padding(
              padding: const EdgeInsets.all(16),
              child: FloatingActionButton.extended(
                onPressed: _addNote,
                icon: const Icon(Icons.add),
                label: const Text('Add Note'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.note_add,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No notes yet' : 'No notes found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Tap the + button to create your first note'
                : 'Try a different search term',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  /// The list's rows: the notes at the top level, then each folder's
  /// header followed by its notes when unfolded. A search lists the
  /// matching notes flat.
  List<Object> _listEntries(List<NoteFile> notes) {
    if (_searchQuery.isNotEmpty) return notes;
    final root = <NoteFile>[];
    final byFolder = <String, List<NoteFile>>{};
    for (final note in notes) {
      if (note.folderPath.isEmpty) {
        root.add(note);
      } else {
        byFolder.putIfAbsent(note.folderPath, () => []).add(note);
      }
    }
    final folders = byFolder.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      ...root,
      for (final folder in folders) ...[
        _FolderEntry(folder, byFolder[folder]!.length),
        if (_openFolders.contains(folder)) ...byFolder[folder]!,
      ],
    ];
  }

  List<NoteFile> _filterNotes(List<NoteFile> notes) {
    if (_searchQuery.isEmpty) return notes;

    return notes.where((note) {
      return note.displayName
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          note.content.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _addNote() async {
    final created = await showDialog<NoteFile>(
      context: context,
      builder: (context) => _AddNoteDialog(),
    );
    if (created != null && mounted) _openNote(created);
  }

  Future<void> _openNote(NoteFile note) => openNoteEditor(context, note);

  Future<void> _shareNote(NoteFile note) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (Platform.isAndroid) {
        await IntentHandlerService.shareText(note.content,
            subject: note.displayName);
      } else {
        await Clipboard.setData(ClipboardData(text: note.content));
        messenger.showSnackBar(SnackBar(
            content: Text('"${note.displayName}" copied to the clipboard')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not share: $e')));
    }
  }

  /// Move the note to the archives folder, with an undo.
  Future<void> _archiveNote(NoteFile note) async {
    final provider = context.read<NoteFileProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final archivedPath = await provider.archiveNoteFile(note);
      messenger.showSnackBar(SnackBar(
        content: Text('"${note.displayName}" moved to $archivedPath'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => provider
              .unarchiveNoteFile(archivedPath, note)
              .catchError((Object e) => messenger.showSnackBar(
                  SnackBar(content: Text('Could not restore: $e')))),
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not archive: $e')));
    }
  }

  void _renameNote(NoteFile note) {
    showDialog(
      context: context,
      builder: (context) => _RenameNoteDialog(note: note),
    );
  }

  void _deleteNote(NoteFile note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${note.displayName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<NoteFileProvider>().deleteNoteFile(note);
              Navigator.of(context).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Open [note] in the editor, from what is on disk. [context] must stay
/// mounted while the note is read (a screen, not a dialog).
Future<void> openNoteEditor(BuildContext context, NoteFile note) async {
  // Captured up front: the editor saves once more while it is being
  // disposed, when the route's own context can no longer look it up.
  final provider = context.read<NoteFileProvider>();
  final messenger = ScaffoldMessenger.of(context);
  final errorColor = Theme.of(context).colorScheme.error;

  // Edit what is on disk, not the list's copy: it can be older.
  final NoteFile? fresh;
  try {
    fresh = await provider.reloadNote(note.relativePath);
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text('"${note.displayName}" could not be read (is it valid '
          'UTF-8 text?). It was left untouched.'),
      backgroundColor: errorColor,
    ));
    return;
  }
  if (fresh == null) {
    messenger.showSnackBar(SnackBar(
      content: Text('"${note.displayName}" no longer exists'),
    ));
    return;
  }
  if (!context.mounted) return;
  final opened = fresh;

  Future<void> save(String content, ExpectedContent expected) =>
      provider.saveNoteFile(opened.relativePath, content,
          expected: expected);
  Navigator.of(context).push(
    MaterialPageRoute(
      // Rebuilt with the note's latest known content, so the editor can
      // reload after an external change.
      builder: (context) => Selector<NoteFileProvider, String?>(
        selector: (_, p) => p.noteByPath(opened.relativePath)?.content,
        builder: (context, diskContent, _) => NoteEditor(
          note: opened,
          diskContent: diskContent,
          onSave: save,
          onAutoSave: save,
          onSaveCopy: (content) => provider.saveConflictCopy(
            folder: opened.folderPath,
            baseName: opened.fileName,
            content: content,
          ),
        ),
      ),
    ),
  );
}

/// A folder row in the notes list.
class _FolderEntry {
  final String folder;
  final int count;
  const _FolderEntry(this.folder, this.count);
}

class _FolderHeader extends StatelessWidget {
  final String folder;
  final int count;
  final bool open;
  final VoidCallback onTap;

  const _FolderHeader({
    required this.folder,
    required this.count,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(open ? Icons.folder_open : Icons.folder,
          color: theme.colorScheme.primary),
      title: Text(folder, style: theme.textTheme.titleSmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count', style: theme.textTheme.bodySmall),
          Icon(open ? Icons.expand_less : Icons.expand_more),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _AddNoteDialog extends StatefulWidget {
  @override
  State<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<_AddNoteDialog> {
  final _nameController = TextEditingController();
  final _folderController = TextEditingController();
  String? _error;
  bool _creating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Note Name',
              hintText: 'Enter note name',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _folderController,
            decoration: const InputDecoration(
              labelText: 'Folder (optional)',
              hintText: 'e.g., Work, Personal',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _creating ? null : _createNote,
          child: const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createNote() async {
    final name = sanitizeNoteName(_nameController.text);
    if (name.isEmpty) return;

    final folder = sanitizeNoteFolder(_folderController.text);
    final relativePath = folder.isEmpty ? '$name.md' : '$folder/$name.md';

    final provider = context.read<NoteFileProvider>();
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final created = await provider.createNoteFile(relativePath);
      if (mounted) Navigator.of(context).pop(created);
    } on FileAlreadyExistsException {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = 'A note with this name already exists';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = 'Could not create the note: $e';
      });
    }
  }
}

class _RenameNoteDialog extends StatefulWidget {
  final NoteFile note;

  const _RenameNoteDialog({required this.note});

  @override
  State<_RenameNoteDialog> createState() => _RenameNoteDialogState();
}

class _RenameNoteDialogState extends State<_RenameNoteDialog> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.note.fileName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename Note'),
      content: TextField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Note Name',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _renameNote,
          child: const Text('Rename'),
        ),
      ],
    );
  }

  void _renameNote() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == widget.note.fileName) return;

    final noteFileProvider =
        Provider.of<NoteFileProvider>(context, listen: false);
    final success = await noteFileProvider.renameNoteFile(widget.note, newName);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note renamed to "$newName"')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Failed to rename note. A file with that name may already exist.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
