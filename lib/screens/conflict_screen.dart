import 'package:flutter/material.dart';
import 'package:planetxt/providers/daily_file_provider.dart';
import 'package:planetxt/providers/note_file_provider.dart';
import 'package:planetxt/services/conflict_service.dart';
import 'package:planetxt/utils/line_diff.dart';
import 'package:planetxt/utils/logger.dart';
import 'package:provider/provider.dart';

/// The files changed in two places at once, and what to do with them.
///
/// A sync tool (or PlaneTxt itself) keeps the second version beside the
/// first; here the two are compared and one of them, or both, is kept. The
/// list is the providers' own, so a file resolved here leaves it as soon as
/// they have reloaded.
class ConflictScreen extends StatelessWidget {
  const ConflictScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final daily = context.watch<DailyFileProvider>();
    final notes = context.watch<NoteFileProvider>();
    final conflicts = {...daily.conflictFiles, ...notes.conflictFiles}.toList()
      ..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('Sync conflicts')),
      body: conflicts.isEmpty
          ? _buildEmpty(context)
          : ListView.separated(
              itemCount: conflicts.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) return _buildHeader(context, conflicts.length);
                final copyPath = conflicts[index - 1];
                return ListTile(
                  leading: const Icon(Icons.call_split),
                  title: Text(copyPath.split('/').last),
                  subtitle: Text(copyPath),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ConflictDetailScreen(copyPath: copyPath),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmpty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline,
                  size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              const Text('No conflicting versions left.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );

  Widget _buildHeader(BuildContext context, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Text(
          count == 1
              ? 'One file changed in two places at once. Open it to compare '
                  'both versions and keep what you need.'
              : '$count files changed in two places at once. Open one to '
                  'compare both versions and keep what you need.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
}

/// Both versions of one conflicting file, and the three ways out.
class ConflictDetailScreen extends StatefulWidget {
  /// Store path of the copy left aside, e.g.
  /// `dailies/20261011.sync-conflict-20261011-153045-ABCDEFG.md`.
  final String copyPath;

  const ConflictDetailScreen({super.key, required this.copyPath});

  @override
  State<ConflictDetailScreen> createState() => _ConflictDetailScreenState();
}

class _ConflictDetailScreenState extends State<ConflictDetailScreen> {
  late Future<ConflictVersions> _versions;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _versions = ConflictService().read(widget.copyPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.copyPath.split('/').last)),
      body: FutureBuilder<ConflictVersions>(
        future: _versions,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text("This copy can't be read: ${snapshot.error}"),
            );
          }
          final versions = snapshot.data;
          if (versions == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Expanded(child: _buildComparison(context, versions)),
              const Divider(height: 1),
              _buildActions(context, versions),
            ],
          );
        },
      ),
    );
  }

  Widget _buildComparison(BuildContext context, ConflictVersions versions) {
    final diff = versions.current == null
        ? null
        : diffLines(versions.current!, versions.copy);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        _buildSummary(context, versions),
        const SizedBox(height: 16),
        if (diff == null)
          _buildPlainVersions(context, versions)
        else
          _DiffView(lines: diff),
      ],
    );
  }

  Widget _buildSummary(BuildContext context, ConflictVersions versions) {
    final textTheme = Theme.of(context).textTheme;
    final String explanation;
    if (versions.currentIsGone) {
      explanation = 'The file this copy was made from is gone. Keep the copy '
          'to put it back, or drop it.';
    } else if (versions.versionsMatch) {
      explanation = 'Both versions hold the same text, so the copy can be '
          'dropped.';
    } else {
      explanation = 'Lines only in the copy are marked +, lines only in the '
          'current file are marked -.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A copy whose file is gone has no second side to tell apart, so it
        // gets no swatch either.
        _buildSideLabel(context, 'Current file',
            versions.currentIsGone ? null : _SideColors.current),
        Text(versions.originalPath, style: textTheme.bodySmall),
        const SizedBox(height: 8),
        _buildSideLabel(context, 'Copy', _SideColors.copy),
        Text(versions.copyPath, style: textTheme.bodySmall),
        const SizedBox(height: 12),
        Text(explanation, style: textTheme.bodyMedium),
      ],
    );
  }

  /// One side's name, behind the colour its lines carry in the comparison.
  Widget _buildSideLabel(BuildContext context, String label, _SideColors? side) {
    final textTheme = Theme.of(context).textTheme;
    if (side == null) return Text(label, style: textTheme.labelLarge);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: side.container(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: textTheme.labelLarge),
      ],
    );
  }

  /// Both texts one after the other, for versions too far apart to line up.
  Widget _buildPlainVersions(BuildContext context, ConflictVersions versions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (versions.current != null) ...[
          _buildSideLabel(context, 'Current file', _SideColors.current),
          const SizedBox(height: 4),
          _MonospaceBlock(text: versions.current!),
          const SizedBox(height: 16),
        ],
        _buildSideLabel(context, 'Copy', _SideColors.copy),
        const SizedBox(height: 4),
        _MonospaceBlock(text: versions.copy),
      ],
    );
  }

  /// Each button wears the colour of the version it keeps, the one its lines
  /// already have in the comparison above. Keeping both keeps no single side,
  /// and dropping a copy left without a file keeps nothing: those stay plain.
  Widget _buildActions(BuildContext context, ConflictVersions versions) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: _resolving
                ? null
                : () => _resolve(versions, ConflictChoice.keepBoth),
            child: const Text('Keep both'),
          ),
          if (versions.currentIsGone)
            OutlinedButton(
              onPressed: _resolving
                  ? null
                  : () => _resolve(versions, ConflictChoice.keepCurrent),
              child: const Text('Drop the copy'),
            )
          else
            FilledButton(
              onPressed: _resolving
                  ? null
                  : () => _resolve(versions, ConflictChoice.keepCurrent),
              style: _SideColors.current.buttonStyle(context),
              child: const Text('Keep the current file'),
            ),
          FilledButton(
            onPressed: _resolving
                ? null
                : () => _resolve(versions, ConflictChoice.keepCopy),
            style: _SideColors.copy.buttonStyle(context),
            child: const Text('Keep the copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(
      ConflictVersions versions, ConflictChoice choice) async {
    setState(() => _resolving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final daily = context.read<DailyFileProvider>();
    final notes = context.read<NoteFileProvider>();
    try {
      final kept = await ConflictService().resolve(versions, choice);
      // The copy and the file it came from can each be a day or a note, and
      // both lists carry the copies left to resolve.
      await Future.wait([
        daily.loadDailyFilesIncremental(),
        notes.loadNoteFilesIncremental(),
      ]);
      messenger.showSnackBar(SnackBar(
        content: Text(switch (choice) {
          ConflictChoice.keepCurrent => 'Copy deleted',
          ConflictChoice.keepCopy => 'Copy kept as ${versions.originalPath}',
          ConflictChoice.keepBoth => 'Copy kept as $kept',
        }),
      ));
      navigator.pop();
    } catch (e, stackTrace) {
      Log.e('❌ ConflictScreen: Cannot resolve ${versions.copyPath}',
          error: e, stackTrace: stackTrace);
      if (mounted) setState(() => _resolving = false);
      messenger.showSnackBar(
          SnackBar(content: Text("The conflict can't be resolved: $e")));
    }
  }
}

/// The colour each side of a conflict carries: on its lines in the diff, on
/// the swatch beside its name, and on the button that keeps it.
enum _SideColors {
  current,
  copy;

  Color container(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (this) {
      _SideColors.current => colors.errorContainer,
      _SideColors.copy => colors.tertiaryContainer,
    };
  }

  Color onContainer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (this) {
      _SideColors.current => colors.onErrorContainer,
      _SideColors.copy => colors.onTertiaryContainer,
    };
  }

  /// Left without a disabled colour on purpose: the theme's own greyed-out
  /// filled button is what should show while a resolution is running.
  ButtonStyle buttonStyle(BuildContext context) => FilledButton.styleFrom(
        backgroundColor: container(context),
        foregroundColor: onContainer(context),
      );
}

/// A unified diff: the lines both versions share, those only the current
/// file has, and those only the copy has.
class _DiffView extends StatelessWidget {
  final List<DiffLine> lines;

  const _DiffView({required this.lines});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in lines)
          Container(
            color: switch (line.kind) {
              DiffKind.same => null,
              DiffKind.added => _SideColors.copy.container(context),
              DiffKind.removed => _SideColors.current.container(context),
            },
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              '${switch (line.kind) {
                DiffKind.same => '  ',
                DiffKind.added => '+ ',
                DiffKind.removed => '- ',
              }}${line.text}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: switch (line.kind) {
                  DiffKind.same => colors.onSurfaceVariant,
                  DiffKind.added => _SideColors.copy.onContainer(context),
                  DiffKind.removed => _SideColors.current.onContainer(context),
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _MonospaceBlock extends StatelessWidget {
  final String text;

  const _MonospaceBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
    );
  }
}
