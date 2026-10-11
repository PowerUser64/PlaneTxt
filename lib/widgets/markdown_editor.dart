import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planetxt/models/expected_content.dart';
import 'package:planetxt/utils/exceptions.dart';
import 'package:planetxt/utils/logger.dart';

enum EditorMode {
  embedded, // For use within other widgets (like DailyEditor)
  fullscreen, // For full-screen editing (like NoteEditor, DailyEditorFullscreen)
}

/// Saves [content], checked against [expected]: what the editor last knew
/// to be on disk. Throws [FileConflictException] when the file changed.
typedef EditorSave = Future<void> Function(
    String content, ExpectedContent expected);

class MarkdownEditor extends StatefulWidget {
  final String initialContent;

  /// The file's content on disk (`null`: no file yet). Saves are checked
  /// against it; when it changes while nothing local is pending, the
  /// editor reloads.
  final String? diskContent;
  final EditorSave onSave;
  final EditorSave? onAutoSave;

  /// Keeps the editor's text as a separate file when it loses a conflict
  /// ("Keep both", or a conflict found while the editor closes).
  final Future<void> Function(String content)? onSaveCopy;
  final String title;
  final String hintText;
  final EditorMode mode;
  final bool showHeaderButton;
  final bool showCodeButton;
  final bool showToggleTodo;
  final bool showSaveButton;
  final String? saveSuccessMessage;

  const MarkdownEditor({
    super.key,
    required this.initialContent,
    required this.diskContent,
    required this.onSave,
    this.onAutoSave,
    this.onSaveCopy,
    required this.title,
    required this.hintText,
    this.mode = EditorMode.embedded,
    this.showHeaderButton = true,
    this.showCodeButton = true,
    this.showToggleTodo = true,
    this.showSaveButton = true,
    this.saveSuccessMessage,
  });

  @override
  State<MarkdownEditor> createState() => MarkdownEditorState();
}

enum _ConflictChoice { keepMine, loadTheirs, keepBoth }

class MarkdownEditorState extends State<MarkdownEditor>
    with WidgetsBindingObserver {
  late TextEditingController _controller;
  bool _hasChanges = false;
  Timer? _autoSaveTimer;
  String _savedContent = '';
  bool _autoSaveErrorShown = false;
  bool _saving = false;
  Future<void> _lastWrite = Future.value();

  /// What the file holds on disk as far as the editor knows (`null`: no
  /// file). Every save is checked against it, then moves it forward.
  String? _base;
  bool _conflictPending = false;
  bool _applyingExternal = false;

  @override
  void initState() {
    super.initState();
    _savedContent = widget.initialContent;
    _base = widget.diskContent;
    _controller = TextEditingController(text: widget.initialContent);
    _controller.addListener(_onTextChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final disk = widget.diskContent;
    if (disk == oldWidget.diskContent || disk == _base) return;
    if (disk != null && disk == _savedContent) {
      _base = disk; // our own save, echoed back by the provider
      return;
    }
    // Changed outside the editor. Reload if nothing local is pending;
    // otherwise the next save detects the conflict and asks.
    final pending = _controller.text != _savedContent ||
        (_autoSaveTimer?.isActive ?? false) ||
        _conflictPending;
    if (pending) return;
    _base = disk;
    _replaceText(disk ?? '');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS may kill a backgrounded app before the debounce fires.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _flushAutoSave();
    }
  }

  /// Run the pending autosave now instead of waiting for the debounce.
  void _flushAutoSave() {
    if (_autoSaveTimer?.isActive ?? false) {
      _autoSaveTimer!.cancel();
      unawaited(_autoSave());
    }
  }

  /// Run [save] once any write still in flight has finished: overlapping
  /// writes of one file race on its temp file and can land out of order.
  Future<void> _serialized(Future<void> Function() save) {
    final next = _lastWrite.catchError((_) {}).then((_) => save());
    _lastWrite = next;
    return next;
  }

  /// Write [content] checked against [_base], which then moves to it. The
  /// base is read when the write runs, not when it is queued.
  Future<void> _write(EditorSave save, String content) =>
      _serialized(() async {
        await save(content, ExpectedContent(_base));
        _base = content;
      });

  /// Show [text] as the saved state, without triggering an autosave.
  void _replaceText(String text) {
    final offset = _controller.selection.baseOffset.clamp(0, text.length);
    _applyingExternal = true;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
    _applyingExternal = false;
    _savedContent = text;
    _hasChanges = false;
  }

  void _onTextChanged() {
    if (_applyingExternal) return;
    setState(() {
      _hasChanges = _controller.text != _savedContent;
    });

    // Cancel previous timer
    _autoSaveTimer?.cancel();

    // Start new timer for autosave
    _autoSaveTimer = Timer(const Duration(milliseconds: 500), _autoSave);
  }

  Future<void> _autoSave() async {
    final onAutoSave = widget.onAutoSave;
    if (onAutoSave == null || !_hasChanges || _conflictPending) return;
    await _persist(onAutoSave, _controller.text, isAutoSave: true);
  }

  /// Save [content]; returns whether it reached the disk. A conflict asks
  /// the user what to keep instead of overwriting the other version.
  Future<bool> _persist(
    EditorSave save,
    String content, {
    required bool isAutoSave,
  }) async {
    try {
      await _write(save, content);
    } on FileConflictException catch (e) {
      if (mounted) await _resolveConflict(e.diskContent);
      return false;
    } catch (e) {
      // Keep _hasChanges true so the Save button stays visible and the
      // content isn't considered persisted.
      if (mounted && !(isAutoSave && _autoSaveErrorShown)) {
        if (isAutoSave) _autoSaveErrorShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${isAutoSave ? 'Autosave' : 'Save'} failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return false;
    }
    if (isAutoSave) _autoSaveErrorShown = false;
    if (!mounted) return true;
    setState(() {
      _savedContent = content;
      // The user may have kept typing while the save was in flight.
      _hasChanges = _controller.text != _savedContent;
    });
    return true;
  }

  /// The file changed on disk since the editor last saw it ([theirs] is
  /// its new content, `null` if deleted). Ask which version to keep.
  Future<void> _resolveConflict(String? theirs) async {
    if (_conflictPending) return; // already asking; it uses the latest text
    _conflictPending = true;
    _autoSaveTimer?.cancel();
    final choice = await showDialog<_ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ConflictDialog(
        deleted: theirs == null,
        canKeepBoth: widget.onSaveCopy != null,
      ),
    );
    _conflictPending = false;
    if (!mounted || choice == null) return; // undecided: ask again on save

    final mine = _controller.text;
    switch (choice) {
      case _ConflictChoice.keepMine:
        _base = theirs; // overwrite what is there now, knowingly
        await _persist(widget.onAutoSave ?? widget.onSave, mine,
            isAutoSave: false);
      case _ConflictChoice.keepBoth:
        try {
          await widget.onSaveCopy!(mine);
        } catch (e) {
          Log.e('❌ MarkdownEditor: Could not save conflict copy', error: e);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Could not save your version: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ));
          }
          return; // keep the text in the editor rather than lose it
        }
        if (mounted) setState(() => _loadTheirs(theirs));
      case _ConflictChoice.loadTheirs:
        setState(() => _loadTheirs(theirs));
    }
  }

  void _loadTheirs(String? theirs) {
    _base = theirs;
    _replaceText(theirs ?? '');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    final onAutoSave = widget.onAutoSave;
    final onSaveCopy = widget.onSaveCopy;
    final content = _controller.text;
    if (onAutoSave != null && content != _savedContent) {
      // Leaving right after typing (back gesture, app switch): the debounced
      // autosave will never run, so persist the last keystrokes now.
      unawaited(_write(onAutoSave, content).catchError((Object e) async {
        if (e is FileConflictException && onSaveCopy != null) {
          // Nobody left to ask: keep this version as a copy.
          try {
            await onSaveCopy(content);
          } catch (copyError) {
            Log.e('❌ MarkdownEditor: Could not save conflict copy',
                error: copyError);
          }
        } else {
          Log.e('❌ MarkdownEditor: Save on close failed', error: e);
        }
      }));
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editorContent = Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _insertText('**', '**'),
                icon: const Icon(Icons.format_bold),
                tooltip: 'Bold',
              ),
              IconButton(
                onPressed: () => _insertText('*', '*'),
                icon: const Icon(Icons.format_italic),
                tooltip: 'Italic',
              ),
              if (widget.showHeaderButton)
                IconButton(
                  onPressed: () => _insertLinePrefix('# '),
                  icon: const Icon(Icons.title),
                  tooltip: 'Header',
                ),
              IconButton(
                onPressed: () => _insertLinePrefix('- '),
                icon: const Icon(Icons.format_list_bulleted),
                tooltip: 'Bullet List',
              ),
              IconButton(
                onPressed: () => _insertLinePrefix('1. '),
                icon: const Icon(Icons.format_list_numbered),
                tooltip: 'Numbered List',
              ),
              if (widget.showToggleTodo)
                IconButton(
                  onPressed: _toggleTodo,
                  icon: const Icon(Icons.check_box),
                  tooltip: 'Toggle Todo',
                )
              else
                IconButton(
                  onPressed: () => _insertLinePrefix('- [ ] '),
                  icon: const Icon(Icons.check_box_outline_blank),
                  tooltip: 'Todo Item',
                ),
              IconButton(
                onPressed: _showDateTimeDialog,
                icon: const Icon(Icons.access_time),
                tooltip: 'Insert Time',
              ),
              const Spacer(),
              if (widget.showCodeButton)
                IconButton(
                  onPressed: () => _insertText('`', '`'),
                  icon: const Icon(Icons.code),
                  tooltip: 'Code',
                ),
              if (widget.showSaveButton &&
                  widget.mode == EditorMode.embedded &&
                  _hasChanges)
                TextButton(
                  onPressed: _saveContent,
                  child: const Text('Save'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Text editor
        Expanded(
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: widget.hintText,
              border: const OutlineInputBorder(),
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            inputFormatters: [
              _MarkdownInputFormatter(),
            ],
          ),
        ),
      ],
    );

    if (widget.mode == EditorMode.fullscreen) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (_hasChanges)
              TextButton(
                onPressed: _saveContent,
                child: const Text('Save'),
              ),
          ],
        ),
        body: editorContent,
      );
    } else {
      return editorContent;
    }
  }

  /// The cursor, or the end of the text if the field was never focused.
  TextSelection get _selectionOrEnd => _controller.selection.isValid
      ? _controller.selection
      : TextSelection.collapsed(offset: _controller.text.length);

  /// Wrap the selection in [prefix] and [suffix]. With nothing selected,
  /// the cursor lands between them, ready to type.
  void _insertText(String prefix, [String suffix = '']) {
    final text = _controller.text;
    final selection = _selectionOrEnd;
    final selected = selection.textInside(text);
    _controller.value = TextEditingValue(
      text: text.replaceRange(
          selection.start, selection.end, '$prefix$selected$suffix'),
      selection: TextSelection.collapsed(
        offset: selection.start +
            prefix.length +
            (selection.isCollapsed ? 0 : selected.length + suffix.length),
      ),
    );
  }

  /// Start the cursor's line with [prefix]: a header or list marker only
  /// means something at the start of a line.
  void _insertLinePrefix(String prefix) {
    final text = _controller.text;
    final selection = _selectionOrEnd;
    final lineStart = selection.start == 0
        ? 0
        : text.lastIndexOf('\n', selection.start - 1) + 1;
    _controller.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: selection.end + prefix.length),
    );
  }

  Future<void> _saveContent() async {
    if (_saving) return;
    _saving = true;
    final bool saved;
    try {
      saved = await _persist(widget.onSave, _controller.text,
          isAutoSave: false);
    } finally {
      _saving = false;
    }
    if (!saved || !mounted) return;
    if (widget.mode == EditorMode.fullscreen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.saveSuccessMessage ?? 'Content saved')),
      );
    }
  }

  void _toggleTodo() {
    final text = _controller.text;
    final selection = _controller.selection;

    if (!selection.isValid) return;

    // Find the current line
    final lines = text.split('\n');
    int currentLine = 0;
    int currentPosition = 0;

    for (int i = 0; i < lines.length; i++) {
      final lineLength = lines[i].length + 1; // +1 for newline
      if (currentPosition + lineLength > selection.start) {
        currentLine = i;
        break;
      }
      currentPosition += lineLength;
    }

    if (currentLine >= lines.length) return;

    final currentLineText = lines[currentLine];

    // Check if this line has a todo checkbox
    final todoMatch = RegExp(r'^(\s*[-*+]\s*)\[\s*([xX\s])\s*\]\s*(.*)$')
        .firstMatch(currentLineText);

    if (todoMatch != null) {
      // Toggle the checkbox
      final prefix = todoMatch.group(1)!;
      final isChecked = todoMatch.group(2)!.toLowerCase() == 'x';
      final content = todoMatch.group(3)!;

      final newCheckbox = isChecked ? '[ ]' : '[x]';
      final newLine = '$prefix$newCheckbox $content';

      // Replace the line
      lines[currentLine] = newLine;
      final newText = lines.join('\n');

      // Calculate new cursor position
      final newCursorPosition = currentPosition + newLine.length;

      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCursorPosition),
      );
    } else {
      // If no todo checkbox, insert a new todo item
      final indentMatch = RegExp(r'^(\s*)').firstMatch(currentLineText);
      final indent = indentMatch?.group(1) ?? '';
      final newTodo = '$indent- [ ] ';

      // Insert at the beginning of the line
      final newLine = newTodo + currentLineText.trim();
      lines[currentLine] = newLine;
      final newText = lines.join('\n');

      // Calculate new cursor position
      final newCursorPosition = currentPosition + newTodo.length;

      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCursorPosition),
      );
    }
  }

  String _formatTime24Hour(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showDateTimeDialog() {
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Insert Time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select time:'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                      builder: (context, child) {
                        return MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() {
                        selectedTime = picked;
                      });
                    }
                  },
                  icon: const Icon(Icons.access_time),
                  label: Text(_formatTime24Hour(selectedTime)),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.preview, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Preview: @${_formatTime24Hour(selectedTime)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final timeStr = _formatTime24Hour(selectedTime);
                _insertText('@$timeStr ');
                Navigator.of(context).pop();
              },
              child: const Text('Insert'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Continues lists on Enter: a new line after a list item starts with the
/// same marker (a todo always starts unchecked, a numbered item counts up),
/// and Enter on an empty item ends the list instead.
class _MarkdownInputFormatter extends TextInputFormatter {
  static final RegExp _todoItem =
      RegExp(r'^(\s*)([-*+])\s*\[\s*[xX\s]\s*\]\s*(.*)$');
  static final RegExp _eventItem =
      RegExp(r'^(\s*)([-*+]\s+@\d{1,2}:\d{2}\s+)(.*)$');
  static final RegExp _numberedItem = RegExp(r'^(\s*)(\d+)([.)]\s+)(.*)$');
  static final RegExp _bulletItem = RegExp(r'^(\s*)([-*+]\s+)(.*)$');

  /// The marker that continues the list item [line] starts, and that
  /// item's content; null if [line] is no list item.
  static ({String next, String content})? _listItem(String line) {
    var m = _todoItem.firstMatch(line);
    if (m != null) return (next: '${m[1]}${m[2]} [ ] ', content: m[3]!);
    m = _eventItem.firstMatch(line);
    if (m != null) return (next: '${m[1]}${m[2]}', content: m[3]!);
    m = _numberedItem.firstMatch(line);
    if (m != null) {
      return (
        next: '${m[1]}${int.parse(m[2]!) + 1}${m[3]}',
        content: m[4]!,
      );
    }
    m = _bulletItem.firstMatch(line);
    if (m != null) return (next: '${m[1]}${m[2]}', content: m[3]!);
    return null;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final selection = oldValue.selection;
    if (!selection.isValid) return newValue;
    final text = oldValue.text;
    // Only Enter typed at the cursor; a pasted block is left as it is.
    if (newValue.text != text.replaceRange(selection.start, selection.end, '\n')) {
      return newValue;
    }

    final lineStart = selection.start == 0
        ? 0
        : text.lastIndexOf('\n', selection.start - 1) + 1;
    final nextBreak = text.indexOf('\n', selection.end);
    final lineEnd = nextBreak < 0 ? text.length : nextBreak;
    final item = _listItem(text.substring(lineStart, selection.start));
    if (item == null) return newValue;

    if (item.content.trim().isEmpty &&
        text.substring(selection.end, lineEnd).trim().isEmpty) {
      // Enter on an empty item: drop its marker, the list ends here.
      return TextEditingValue(
        text: text.replaceRange(lineStart, selection.end, ''),
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }

    final inserted = '\n${item.next}';
    return TextEditingValue(
      text: text.replaceRange(selection.start, selection.end, inserted),
      selection:
          TextSelection.collapsed(offset: selection.start + inserted.length),
    );
  }
}

class _ConflictDialog extends StatelessWidget {
  final bool deleted;
  final bool canKeepBoth;

  const _ConflictDialog({required this.deleted, required this.canKeepBoth});

  @override
  Widget build(BuildContext context) {
    final what = deleted
        ? 'Another app or a sync tool deleted this file while you were '
            'editing it.'
        : 'Another app or a sync tool changed this file while you were '
            'editing it.';
    return AlertDialog(
      title: const Text('File changed outside PlaneTxt'),
      content: Text(canKeepBoth
          ? '$what\n\n"Keep both" saves your version as a separate note.'
          : what),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_ConflictChoice.loadTheirs),
          child: Text(deleted ? 'Discard mine' : 'Load theirs'),
        ),
        if (canKeepBoth)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_ConflictChoice.keepBoth),
            child: const Text('Keep both'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ConflictChoice.keepMine),
          child: Text(deleted ? 'Recreate with mine' : 'Keep mine'),
        ),
      ],
    );
  }
}
