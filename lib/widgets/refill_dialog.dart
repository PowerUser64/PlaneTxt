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
  final List<RefillTodo> undoneTodos;
  final Function(List<RefillTodo>) onRefill;

  const RefillDialog({
    super.key,
    required this.undoneTodos,
    required this.onRefill,
  });

  @override
  State<RefillDialog> createState() => _RefillDialogState();
}

class _RefillDialogState extends State<RefillDialog> {
  // Indexes into undoneTodos: the same text can be undone on several days.
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Refill Undone Todos to Selected Day'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Found ${widget.undoneTodos.length} undone todos from previous days:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selected.addAll(
                          List.generate(widget.undoneTodos.length, (i) => i));
                    });
                  },
                  child: const Text('Select All'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selected.clear();
                    });
                  },
                  child: const Text('Select None'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.undoneTodos.length,
                itemBuilder: (context, index) {
                  final todo = widget.undoneTodos[index];
                  return CheckboxListTile(
                    title: Text(todo.content),
                    subtitle: Text('From ${todo.sourceDateDisplay}'),
                    value: _selected.contains(index),
                    onChanged: (value) {
                      setState(() {
                        if (value ?? false) {
                          _selected.add(index);
                        } else {
                          _selected.remove(index);
                        }
                      });
                    },
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
          onPressed: () {
            final selectedTodos = [
              for (var i = 0; i < widget.undoneTodos.length; i++)
                if (_selected.contains(i)) widget.undoneTodos[i],
            ];

            if (selectedTodos.isNotEmpty) {
              widget.onRefill(selectedTodos);
              Navigator.of(context).pop();
            }
          },
          child: const Text('Refill to Selected Day'),
        ),
      ],
    );
  }
}
