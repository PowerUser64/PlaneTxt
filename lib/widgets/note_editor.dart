import 'package:flutter/material.dart';
import 'package:planetxt/models/note_file.dart';
import 'package:planetxt/widgets/markdown_editor.dart';

class NoteEditor extends StatefulWidget {
  final NoteFile note;
  final String? diskContent;
  final EditorSave onSave;
  final EditorSave? onAutoSave;
  final Future<void> Function(String content)? onSaveCopy;

  const NoteEditor({
    super.key,
    required this.note,
    required this.diskContent,
    required this.onSave,
    this.onAutoSave,
    this.onSaveCopy,
  });

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends State<NoteEditor> {
  @override
  Widget build(BuildContext context) {
    return MarkdownEditor(
      initialContent: widget.note.content,
      diskContent: widget.diskContent,
      onSave: widget.onSave,
      onAutoSave: widget.onAutoSave,
      onSaveCopy: widget.onSaveCopy,
      title: widget.note.displayName,
      hintText:
          'Write your note here...\n\nYou can use Markdown syntax:\n'
          '# Header\n**bold** *italic*\n- bullet list\n1. numbered list\n'
          '- [ ] todo item',
      mode: EditorMode.fullscreen,
      showHeaderButton: true,
      showCodeButton: true,
      showToggleTodo: true, // Same as fullscreen daily editor
      showSaveButton: true,
      saveSuccessMessage: 'Note saved',
    );
  }
}
