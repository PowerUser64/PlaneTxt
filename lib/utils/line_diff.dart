/// What became of a line between two versions of a file.
enum DiffKind {
  /// Present in both versions.
  same,

  /// Only in the second version.
  added,

  /// Only in the first version.
  removed,
}

/// One line of a diff, as [diffLines] lays it out.
class DiffLine {
  final DiffKind kind;
  final String text;

  const DiffLine(this.kind, this.text);

  @override
  String toString() => '${switch (kind) {
        DiffKind.same => ' ',
        DiffKind.added => '+',
        DiffKind.removed => '-',
      }}$text';
}

/// The lines to go from [before] to [after], in reading order: the lines they
/// share, the ones only [before] has, and the ones only [after] has.
///
/// Returns null when the two versions differ too much to be lined up in
/// reasonable time - the caller then shows them side by side instead. The
/// common head and tail are matched first, so two files differing by a few
/// lines are cheap whatever their length.
List<DiffLine>? diffLines(String before, String after, {int maxCompared = 600}) {
  final oldLines = before.split('\n');
  final newLines = after.split('\n');

  var head = 0;
  while (head < oldLines.length &&
      head < newLines.length &&
      oldLines[head] == newLines[head]) {
    head++;
  }
  var tail = 0;
  while (tail < oldLines.length - head &&
      tail < newLines.length - head &&
      oldLines[oldLines.length - 1 - tail] ==
          newLines[newLines.length - 1 - tail]) {
    tail++;
  }

  final oldMiddle = oldLines.sublist(head, oldLines.length - tail);
  final newMiddle = newLines.sublist(head, newLines.length - tail);
  if (oldMiddle.length > maxCompared || newMiddle.length > maxCompared) {
    return null;
  }

  return [
    for (var i = 0; i < head; i++) DiffLine(DiffKind.same, oldLines[i]),
    ..._alignMiddle(oldMiddle, newMiddle),
    for (var i = oldLines.length - tail; i < oldLines.length; i++)
      DiffLine(DiffKind.same, oldLines[i]),
  ];
}

/// Longest common subsequence of [oldLines] and [newLines], walked back into
/// a diff. Quadratic, hence the cap in [diffLines].
List<DiffLine> _alignMiddle(List<String> oldLines, List<String> newLines) {
  final common = List.generate(
    oldLines.length + 1,
    (_) => List.filled(newLines.length + 1, 0),
    growable: false,
  );
  for (var i = oldLines.length - 1; i >= 0; i--) {
    for (var j = newLines.length - 1; j >= 0; j--) {
      common[i][j] = oldLines[i] == newLines[j]
          ? common[i + 1][j + 1] + 1
          : (common[i + 1][j] >= common[i][j + 1]
              ? common[i + 1][j]
              : common[i][j + 1]);
    }
  }

  final lines = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < oldLines.length && j < newLines.length) {
    if (oldLines[i] == newLines[j]) {
      lines.add(DiffLine(DiffKind.same, oldLines[i]));
      i++;
      j++;
    } else if (common[i + 1][j] >= common[i][j + 1]) {
      lines.add(DiffLine(DiffKind.removed, oldLines[i]));
      i++;
    } else {
      lines.add(DiffLine(DiffKind.added, newLines[j]));
      j++;
    }
  }
  for (; i < oldLines.length; i++) {
    lines.add(DiffLine(DiffKind.removed, oldLines[i]));
  }
  for (; j < newLines.length; j++) {
    lines.add(DiffLine(DiffKind.added, newLines[j]));
  }
  return lines;
}
