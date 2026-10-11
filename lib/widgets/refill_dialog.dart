import 'package:flutter/material.dart';

class RefillTodo {
  /// The task text, without its `- [ ]` marker.
  final String text;
  final String sourceDate;
  final String sourceDateDisplay;

  RefillTodo({
    required this.text,
    required this.sourceDate,
    required this.sourceDateDisplay,
  });

  String get content => '- [ ] $text';
}

class RefillDialog extends StatefulWidget {
  /// Undone todos, grouped by [RefillTodo.sourceDate] in the order given.
  final List<RefillTodo> undoneTodos;

  /// Called with the chosen todos, and whether they leave their day
  /// ([move]) or are copied.
  final void Function(List<RefillTodo> todos, {required bool move}) onRefill;

  /// Indexes into [undoneTodos] selected when the dialog opens.
  final Set<int> initiallySelected;

  const RefillDialog({
    super.key,
    required this.undoneTodos,
    required this.onRefill,
    this.initiallySelected = const {},
  });

  @override
  State<RefillDialog> createState() => _RefillDialogState();
}

class _RefillDialogState extends State<RefillDialog> {
  // Indexes into undoneTodos: the same text can be undone on several days.
  late final Set<int> _selected = {...widget.initiallySelected};
  bool _move = true;

  /// Rows of the list: a day's header (its first todo's index, negated
  /// minus one) followed by that day's todo indexes.
  List<int> get _rows {
    final rows = <int>[];
    String? day;
    for (var i = 0; i < widget.undoneTodos.length; i++) {
      if (widget.undoneTodos[i].sourceDate != day) {
        day = widget.undoneTodos[i].sourceDate;
        rows.add(-i - 1);
      }
      rows.add(i);
    }
    return rows;
  }

  Iterable<int> _indexesOfDay(String date) => [
        for (var i = 0; i < widget.undoneTodos.length; i++)
          if (widget.undoneTodos[i].sourceDate == date) i,
      ];

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return AlertDialog(
      title: const Text('Carry over undone todos'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Move'),
                    icon: Icon(Icons.drive_file_move_outline),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Copy'),
                    icon: Icon(Icons.copy),
                  ),
                ],
                selected: {_move},
                onSelectionChanged: (value) =>
                    setState(() => _move = value.first),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _move
                  ? 'They leave their day and appear on the selected one.'
                  : 'They stay in their day and also appear on the '
                      'selected one.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _selected.addAll(
                      List.generate(widget.undoneTodos.length, (i) => i))),
                  child: const Text('Select All'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('Select None'),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  if (row < 0) return _dayHeader(widget.undoneTodos[-row - 1]);
                  final todo = widget.undoneTodos[row];
                  return CheckboxListTile(
                    title: Text(todo.text),
                    value: _selected.contains(row),
                    onChanged: (value) => setState(() {
                      if (value ?? false) {
                        _selected.add(row);
                      } else {
                        _selected.remove(row);
                      }
                    }),
                    dense: true,
                  );
                },
              ),
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
          onPressed: _selected.isEmpty
              ? null
              : () {
                  final selectedTodos = [
                    for (var i = 0; i < widget.undoneTodos.length; i++)
                      if (_selected.contains(i)) widget.undoneTodos[i],
                  ];
                  widget.onRefill(selectedTodos, move: _move);
                  Navigator.of(context).pop();
                },
          child: Text(_move ? 'Move here' : 'Copy here'),
        ),
      ],
    );
  }

  /// A day's header, with a checkbox for all of its todos.
  Widget _dayHeader(RefillTodo first) {
    final indexes = _indexesOfDay(first.sourceDate).toList();
    final selected = indexes.where(_selected.contains).length;
    return CheckboxListTile(
      title: Text(
        first.sourceDateDisplay,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
      tristate: true,
      value: selected == 0
          ? false
          : selected == indexes.length
              ? true
              : null,
      onChanged: (_) => setState(() {
        if (selected == indexes.length) {
          _selected.removeAll(indexes);
        } else {
          _selected.addAll(indexes);
        }
      }),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
