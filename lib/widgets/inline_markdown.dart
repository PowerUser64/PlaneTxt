import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:planetxt/utils/logger.dart';
import 'package:url_launcher/url_launcher.dart';

/// One short piece of markdown, rendered inside a list row: no block
/// spacing above or below, headers no bigger than the surrounding text,
/// and a single line break kept as written - the daily files are plain
/// text, where a wrapped line is a line.
class InlineMarkdown extends StatelessWidget {
  final String data;

  /// Style of the unformatted text; emphasis, code and links derive from it.
  final TextStyle? style;

  const InlineMarkdown({super.key, required this.data, this.style});

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium;
    return MarkdownBody(
      data: data,
      softLineBreak: true,
      styleSheet: _styleSheet(context, base),
      onTapLink: (text, href, title) => _openLink(context, href),
    );
  }

  MarkdownStyleSheet _styleSheet(BuildContext context, TextStyle? base) {
    final colors = Theme.of(context).colorScheme;
    final header = base?.copyWith(fontWeight: FontWeight.bold);
    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: base,
      pPadding: EdgeInsets.zero,
      a: base?.copyWith(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary,
      ),
      code: base?.copyWith(
        fontFamily: 'monospace',
        fontSize: (base.fontSize ?? 14) * 0.9,
        backgroundColor: colors.surfaceContainerHigh,
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      codeblockPadding: const EdgeInsets.all(6),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 8),
      // A `#` at the start of an event is a heading to markdown, but the
      // row it is drawn in has no space for a title three times the size.
      h1: header,
      h2: header,
      h3: header,
      h4: header,
      h5: header,
      h6: header,
      h1Padding: EdgeInsets.zero,
      h2Padding: EdgeInsets.zero,
      h3Padding: EdgeInsets.zero,
      h4Padding: EdgeInsets.zero,
      h5Padding: EdgeInsets.zero,
      h6Padding: EdgeInsets.zero,
      blockSpacing: 4,
      listIndent: 16,
      listBullet: base,
      listBulletPadding: const EdgeInsets.only(right: 4),
    );
  }

  Future<void> _openLink(BuildContext context, String? href) async {
    if (href == null || href.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri.parse(href);
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      Log.w('🔗 InlineMarkdown: Nothing could open $href');
    } catch (e) {
      Log.e('❌ InlineMarkdown: Could not open $href', error: e);
    }
    messenger.showSnackBar(SnackBar(content: Text('Could not open $href')));
  }
}
