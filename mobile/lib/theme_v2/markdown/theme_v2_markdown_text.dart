import 'package:flutter/material.dart';

import '../../chat/markdown_text.dart';
import '../../theme/app_theme.dart';
import '../../theme/eureka_colors.dart';

/// Theme V2-safe access to the app's established Markdown grammar.
///
/// The grammar remains shared (headings, emphasis, code, lists, quotes,
/// callouts, and tables), while this adapter supplies the palette extension
/// expected by the legacy-free renderer boundary.
class ThemeV2MarkdownText extends StatelessWidget {
  const ThemeV2MarkdownText(this.text, {super.key, this.baseStyle});

  final String text;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.brightness == Brightness.dark
        ? EurekaColors.dark
        : EurekaColors.light;
    return Theme(
      data: theme.copyWith(
        extensions: [
          for (final extension in theme.extensions.values)
            if (extension is! EurekaTheme) extension,
          EurekaTheme(colors),
        ],
      ),
      child: MarkdownText(text, baseStyle: baseStyle),
    );
  }
}
