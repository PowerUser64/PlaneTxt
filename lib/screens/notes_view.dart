import 'package:flutter/material.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/models/note_file.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/utils/exceptions.dart';
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
                      itemCount: filteredNotes.length,
                      itemBuilder: (context, index) {
                        final note = filteredNotes[index];
                        return NoteListItem(
                          note: note,
                          onTap: () => _openNote(note),
                          onRename: () => _renameNote(note),
                          onDelete: () => _deleteNote(note),
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

  Future<void> _openNote(NoteFile note) async {
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
    if (!mounted) return;
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

  String _sanitizeName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    // Prevent path separators in names.
    final withoutSeparators = trimmed.replaceAll(RegExp(r'[/\\]'), ' ');

    return withoutSeparators
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
  }

  String _sanitizeFolder(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final parts = trimmed.replaceAll('\\', '/').split('/');
    final sanitizedParts = <String>[];

    for (final part in parts) {
      final clean = _sanitizeName(part);
      if (clean.isEmpty) continue;
      if (clean == '.' || clean == '..') continue;
      sanitizedParts.add(clean);
    }

    return sanitizedParts.join('/');
  }

  Future<void> _createNote() async {
    final name = _sanitizeName(_nameController.text);
    if (name.isEmpty) return;

    final folder = _sanitizeFolder(_folderController.text);
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
