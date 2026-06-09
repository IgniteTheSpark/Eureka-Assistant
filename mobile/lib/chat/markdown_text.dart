import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// Lightweight markdown for agent replies: **bold**, `code`, *italic*, bullet
/// and numbered lists, and `#` headings. Mirrors the web renderer — built from
/// spans/widgets (no HTML), styled for chat (not a heavy doc).
class MarkdownText extends StatelessWidget {
  final String text;

  /// Optional base text style — lets a document reader render at a larger,
  /// looser reading size while chat keeps the compact default. Headings / lists
  /// derive from this.
  final TextStyle? baseStyle;
  const MarkdownText(this.text, {super.key, this.baseStyle});

  static final _bullet = RegExp(r'^\s*[-*]\s+');
  static final _numbered = RegExp(r'^\s*\d+\.\s+');
  static final _numberedCap = RegExp(r'^\s*(\d+)\.\s+(.*)');
  static final _heading = RegExp(r'^#{1,6}\s+(.*)');
  static final _quote = RegExp(r'^\s*>\s?');
  static final _inlineRe = RegExp(r'(\*\*([^*]+)\*\*|`([^`]+)`|\*([^*\n]+)\*)');
  // §6 注解 Markdown — md tables + `:::callout{tone=…}` fenced blocks. Other
  // directives (`:::rank`/`:::kpi`/`:::compare`) gracefully render their inner md
  // (fence stripped) instead of showing raw `:::` text.
  static final _tableRow = RegExp(r'^\s*\|.*\|\s*$');
  static final _tableSep = RegExp(r'^\s*\|?[\s:\-|]+\|[\s:\-|]*$');
  static final _fenceLine = RegExp(r'^\s*:::\s*([A-Za-z]\w*)?\s*(\{[^}]*\})?\s*$');

  bool _looksTable(int i, List<String> lines) =>
      i + 1 < lines.length && _tableRow.hasMatch(lines[i]) && _tableSep.hasMatch(lines[i + 1]);

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final base = baseStyle ?? TextStyle(color: eu.text, fontSize: 14, height: 1.4);
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

      if (_quote.hasMatch(line)) {
        final items = <String>[];
        while (i < lines.length && _quote.hasMatch(lines[i])) {
          items.add(lines[i].replaceFirst(_quote, ''));
          i++;
        }
        final qs = base.copyWith(color: eu.textMid, fontStyle: FontStyle.italic);
        blocks.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
                border: Border(left: BorderSide(color: eu.brand.withValues(alpha: 0.5), width: 3))),
            child: RichText(text: TextSpan(style: qs, children: _inline(items.join('\n'), qs, eu))),
          ),
        ));
        continue;
      }

      // fenced directive: :::callout{tone=…} … :::  (and generic :::name … :::)
      final fm = _fenceLine.firstMatch(line);
      if (fm != null && (fm.group(1) != null || fm.group(2) != null)) {
        final name = fm.group(1) ?? '';
        final attrs = fm.group(2) ?? '';
        final tone = RegExp(r'tone\s*=\s*(\w+)').firstMatch(attrs)?.group(1) ?? '';
        i++; // skip opening fence
        final inner = <String>[];
        while (i < lines.length) {
          final cm = _fenceLine.firstMatch(lines[i]);
          if (cm != null && cm.group(1) == null && cm.group(2) == null) {
            i++; // consume closing :::
            break;
          }
          inner.add(lines[i]);
          i++;
        }
        final innerText = inner.join('\n');
        blocks.add(name == 'callout'
            ? _callout(eu, base, tone, innerText)
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: MarkdownText(innerText, baseStyle: base)));
        continue;
      }

      // md table
      if (_looksTable(i, lines)) {
        final rows = <List<String>>[];
        rows.add(_cells(lines[i]));
        i += 2; // header + separator
        while (i < lines.length && _tableRow.hasMatch(lines[i]) && !_tableSep.hasMatch(lines[i])) {
          rows.add(_cells(lines[i]));
          i++;
        }
        blocks.add(_table(eu, base, rows));
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
          !_heading.hasMatch(lines[i]) &&
          !_quote.hasMatch(lines[i]) &&
          !_fenceLine.hasMatch(lines[i]) &&
          !_looksTable(i, lines)) {
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

  // §6 :::callout{tone=insight|warn|success} — a tinted box with an icon.
  Widget _callout(EurekaColors eu, TextStyle base, String tone, String innerText) {
    final (Color c, String icon) = switch (tone) {
      'warn' => (eu.accentAmber, '⚠️'),
      'success' => (eu.accentGreen, '✅'),
      'danger' => (eu.accentRed, '⛔'),
      _ => (eu.accentBlue, '💡'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withValues(alpha: 0.32)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 9),
            Expanded(child: MarkdownText(innerText, baseStyle: base)),
          ],
        ),
      ),
    );
  }

  List<String> _cells(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => c.trim()).toList();
  }

  Widget _table(EurekaColors eu, TextStyle base, List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final cols = rows.first.length;
    TableRow buildRow(List<String> cells, bool head) => TableRow(
          decoration: head ? BoxDecoration(color: eu.surface) : null,
          children: [
            for (var c = 0; c < cols; c++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: RichText(
                  text: TextSpan(
                    style: head ? base.copyWith(fontWeight: FontWeight.w700, color: eu.textHi) : base,
                    children: _inline(c < cells.length ? cells[c] : '', base, eu),
                  ),
                ),
              ),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: eu.border), borderRadius: BorderRadius.circular(9)),
          child: Table(
            border: TableBorder.symmetric(inside: BorderSide(color: eu.border)),
            defaultColumnWidth: const FlexColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              buildRow(rows.first, true),
              for (final b in rows.skip(1)) buildRow(b, false),
            ],
          ),
        ),
      ),
    );
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
