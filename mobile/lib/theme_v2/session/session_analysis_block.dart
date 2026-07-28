import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

class SessionAnalysisBlock extends StatelessWidget {
  const SessionAnalysisBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: '正在理解并整理',
      liveRegion: true,
      child: Container(
        key: const ValueKey('session-analyzing'),
        constraints: const BoxConstraints(minHeight: 54),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          children: [
            for (var index = 0; index < 3; index++) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.35 + index * 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              if (index != 2) const SizedBox(width: 6),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '正在理解并整理…',
                style: TextStyle(
                  color: tokens.foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text('处理中', style: TextStyle(color: tokens.muted, fontSize: 9)),
          ],
        ),
      ),
    );
  }
}

class SessionErrorBlock extends StatelessWidget {
  const SessionErrorBlock({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onKeepDraft,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onKeepDraft;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      key: const ValueKey('session-state-error'),
      padding: const EdgeInsets.all(ThemeV2Spacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        border: Border.all(color: tokens.critical),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.background,
                  borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                  border: Border.all(color: tokens.border),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: tokens.critical,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '整理中断',
                      style: TextStyle(
                        color: tokens.foreground,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$message。原始内容和当前草稿都没有丢失。',
                      style: TextStyle(
                        color: tokens.muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  key: const ValueKey('session-retry'),
                  container: true,
                  label: '重试最近失败的消息',
                  button: true,
                  excludeSemantics: true,
                  onTap: onRetry,
                  child: SizedBox(
                    height: ThemeV2Sizes.minTouchTarget,
                    child: FilledButton.icon(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        backgroundColor: tokens.critical,
                        foregroundColor: tokens.background,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('重试'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: ThemeV2Sizes.minTouchTarget,
                  child: OutlinedButton(
                    onPressed: onKeepDraft,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.foreground,
                      side: BorderSide(color: tokens.border),
                    ),
                    child: const Text('保留草稿'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
