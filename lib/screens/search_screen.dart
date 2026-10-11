import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/screens/notes_view.dart';
import 'package:planetxt/utils/search.dart';
import 'package:provider/provider.dart';

/// Search every day and every note. A day opens in the calendar, a note in
/// the editor.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final dailies = context.watch<DailyFileProvider>().dailyFiles;
    final notes = context.watch<NoteFileProvider>().noteFiles;
    // One letter matches nearly everything: wait for a second one.
    final hits = _query.trim().length < 2
        ? const <SearchHit>[]
        : searchAll(_query, dailies: dailies, notes: notes);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search days and notes',
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      body: hits.isEmpty
          ? Center(
              child: Text(
                _query.trim().length < 2 ? 'Type to search' : 'No results',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView.builder(
              itemCount: hits.length,
              itemBuilder: (context, index) => _HitTile(hit: hits[index]),
            ),
    );
  }
}

class _HitTile extends StatelessWidget {
  final SearchHit hit;

  const _HitTile({required this.hit});

  @override
  Widget build(BuildContext context) {
    final date = hit.date;
    final note = hit.note;
    final subtitle = [
      if (note != null && note.folderPath.isNotEmpty) note.folderPath,
      ...hit.lines,
    ].join('\n');
    return ListTile(
      leading: Icon(date != null ? Icons.today : Icons.note_outlined),
      title: Text(date != null
          ? DateFormat('EEE d MMM yyyy').format(DateTime(
              int.parse(date.substring(0, 4)),
              int.parse(date.substring(4, 6)),
              int.parse(date.substring(6, 8))))
          : note!.displayName),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 4, overflow: TextOverflow.ellipsis),
      onTap: () {
        if (date != null) {
          // The calendar follows the selected date.
          context.read<DailyFileProvider>().setSelectedDate(date);
          Navigator.of(context).pop();
        } else {
          openNoteEditor(context, note!);
        }
      },
    );
  }
}
