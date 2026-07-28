import 'package:flutter/material.dart';

import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_typography.dart';

class SessionHeader extends StatelessWidget {
  const SessionHeader({
    super.key,
    required this.title,
    required this.messageCount,
    required this.onBack,
    required this.onNewSession,
    required this.onOpenHistory,
  });

  final String title;
  final int messageCount;
  final VoidCallback onBack;
  final VoidCallback onNewSession;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.background,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              ThemeV2IconButton(
                semanticLabel: '返回',
                icon: Icons.chevron_left_rounded,
                color: tokens.foreground,
                onPressed: onBack,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      messageCount.toString().padLeft(2, '0'),
                      style: ThemeV2Typography.mono(
                        color: tokens.muted,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              ThemeV2IconButton(
                semanticLabel: '新会话',
                icon: Icons.add_comment_outlined,
                color: tokens.muted,
                onPressed: onNewSession,
              ),
              ThemeV2IconButton(
                semanticLabel: '历史会话',
                icon: Icons.history_rounded,
                color: tokens.muted,
                onPressed: onOpenHistory,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
