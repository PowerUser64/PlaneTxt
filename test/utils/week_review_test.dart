import 'package:flutter_test/flutter_test.dart';
import 'package:planetxt/utils/markdown_parser.dart';
import 'package:planetxt/utils/week_review.dart';

void main() {
  // Monday 5 to Sunday 11 October 2026, plus days around it.
  final files = {
    '20261004': '- [ ] outside the week',
    '20261005': '- [ ] call the bank\n- [x] gym\n- @09:00 Standup',
    '20261007': '- [ ] call the bank\n- [ ] Book train',
    '20261009': '- [x] call the bank',
    '20261011': '- [ ] book train',
    '20261012': '- [x] next week',
  };

  WeekReview review(DateTime day) => WeekReview.of(
        day,
        tasksOf: (date) => MarkdownParser.parseTasks(files[date] ?? ''),
        eventsOf: (date) =>
            MarkdownParser.parseEvents(date, files[date] ?? ''),
      );

  test('covers Monday to Sunday of the given day', () {
    final week = review(DateTime(2026, 10, 8));
    expect(week.monday, DateTime(2026, 10, 5));
    expect(week.dates.first, '20261005');
    expect(week.dates.last, '20261011');
  });

  test('splits done and still open todos, each open one once', () {
    final week = review(DateTime(2026, 10, 11));
    expect(week.done.map((t) => '${t.date} ${t.task.text}'),
        ['20261005 gym', '20261009 call the bank']);
    expect(week.open.map((t) => '${t.date} ${t.task.text}'),
        ['20261011 book train']);
  });

  test('lists the todos carried over several days', () {
    final week = review(DateTime(2026, 10, 5));
    expect(week.carried.map((c) => '${c.text} ${c.days} ${c.done}'),
        // As last written.
        ['call the bank 3 true', 'book train 2 false']);
  });

  test('gathers the events of the week', () {
    expect(review(DateTime(2026, 10, 6)).events.single.displayTitle,
        'Standup');
  });
}
