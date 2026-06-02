import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// Lightweight markdown for agent replies: **bold**, `code`, *italic*, bullet
/// and numbered lists, and `#` headings. Mirrors the web renderer — built from
/// spans/widgets (no HTML), styled for chat (not a heavy doc).
class MarkdownText extends StatelessWidget {
  final String text;
  const MarkdownText(this.text, {super.key});

  static final _bullet = RegExp(r'^\s*[-*]\s+');
  static final _numbered = RegExp(r'^\s*\d+\.\s+');
  static final _numberedCap = RegExp(r'^\s*(\d+)\.\s+(.*)');
  static final _heading = RegExp(r'^#{1,6}\s+(.*)');
  static final _inlineRe = RegExp(r'(\*\*([^*]+)\*\*|`([^`]+)`|\*([^*\n]+)\*)');

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final base = TextStyle(color: eu.text, fontSize: 14, height: 1.4);
    final lines = text.split('\n');
    final blocks = <Widget>[];
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      if (_bullet.hasMatch(line)) {
        final items = <String>[];
        while (i < lines.length && _bullet.hasMatch(lines[i])) {
          items.add(lines[i].replaceFirst(_bullet, ''));
          i++;
        }
        blocks.add(_list(eu, base, [for (final _ in items) '·'], items));
        continue;
      }

      if (_numbered.hasMatch(line)) {
        final markers = <String>[];
        final items = <String>[];
        while (i < lines.length) {
          final m = _numberedCap.firstMatch(lines[i]);
          if (m == null) break;
          markers.add('${m.group(1)}.');
          items.add(m.group(2)!);
          i++;
        }
        blocks.add(_list(eu, base, markers, items));
        continue;
      }

      final h = _heading.firstMatch(line);
      if (h != null) {
        final hs = base.copyWith(fontWeight: FontWeight.w700, color: eu.textHi);
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(text: TextSpan(style: hs, children: _inline(h.group(1)!, hs, eu))),
        ));
        i++;
        continue;
      }

      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      final para = <String>[];
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !_bullet.hasMatch(lines[i]) &&
          !_numbered.hasMatch(lines[i]) &&
          !_heading.hasMatch(lines[i])) {
        para.add(lines[i]);
        i++;
      }
      blocks.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: RichText(text: TextSpan(style: base, children: _inline(para.join('\n'), base, eu))),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  Widget _list(EurekaColors eu, TextStyle base, List<String> markers, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var k = 0; k < items.length; k++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${markers[k]}  ', style: TextStyle(color: eu.textLo, fontSize: 14, height: 1.4)),
                Expanded(
                  child: RichText(text: TextSpan(style: base, children: _inline(items[k], base, eu))),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<InlineSpan> _inline(String text, TextStyle base, EurekaColors eu) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inlineRe.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      if (m.group(2) != null) {
        spans.add(TextSpan(
            text: m.group(2),
            style: base.copyWith(fontWeight: FontWeight.w700, color: eu.textHi)));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
            text: m.group(3),
            style: base.copyWith(fontFamily: 'monospace', color: eu.accentBlue)));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(text: m.group(4), style: base.copyWith(fontStyle: FontStyle.italic)));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }
}
