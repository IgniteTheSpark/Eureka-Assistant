import 'package:flutter/material.dart';

import '../../capture_activity/capture_activity_event.dart';
import '../../chat/chat_models.dart';
import '../capture/thinking_orb.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

class SessionAnalysisBlock extends StatelessWidget {
  const SessionAnalysisBlock({
    super.key,
    this.phase = AgentWorkPhase.understanding,
  });

  final AgentWorkPhase phase;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final label = switch (phase) {
      AgentWorkPhase.understanding => '正在理解',
      AgentWorkPhase.executing => '检索 / 执行',
      AgentWorkPhase.composing => '组织回答',
      AgentWorkPhase.organizing => '正在整理',
    };
    final orbPhase = switch (phase) {
      AgentWorkPhase.understanding ||
      AgentWorkPhase.executing => CaptureActivityPhase.understanding,
      AgentWorkPhase.composing ||
      AgentWorkPhase.organizing => CaptureActivityPhase.organizing,
    };
    return Semantics(
      label: label,
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
            ThinkingOrb(phase: orbPhase, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
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

class SessionTurnFailureBlock extends StatelessWidget {
  const SessionTurnFailureBlock({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      key: const ValueKey('session-turn-failure'),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        border: Border.all(color: tokens.critical.withValues(alpha: 0.46)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 17, color: tokens.critical),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '这条回复暂未完成',
              style: TextStyle(
                color: tokens.foreground,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
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
                      '当前会话暂不可用',
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
