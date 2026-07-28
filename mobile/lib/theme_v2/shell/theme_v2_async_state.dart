import 'package:flutter/material.dart';

import '../../widgets/skeleton_loader.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

enum _ThemeV2AsyncKind { loading, empty, error }

class ThemeV2AsyncState extends StatelessWidget {
  const ThemeV2AsyncState.loading({
    super.key,
    this.label = '正在加载',
    this.title = '',
    this.message,
  }) : _kind = _ThemeV2AsyncKind.loading,
       onRetry = null,
       retryLabel = '重试';

  const ThemeV2AsyncState.empty({super.key, required this.title, this.message})
    : _kind = _ThemeV2AsyncKind.empty,
      label = '',
      onRetry = null,
      retryLabel = '重试';

  const ThemeV2AsyncState.error({
    super.key,
    required this.title,
    this.message,
    required this.onRetry,
    this.retryLabel = '重试',
  }) : _kind = _ThemeV2AsyncKind.error,
       label = '';

  final _ThemeV2AsyncKind _kind;
  final String label;
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return switch (_kind) {
      _ThemeV2AsyncKind.loading => _LoadingState(label: label),
      _ThemeV2AsyncKind.empty => _MessageState(
        icon: Icons.inbox_outlined,
        title: title,
        message: message,
      ),
      _ThemeV2AsyncKind.error => _MessageState(
        icon: Icons.error_outline,
        title: title,
        message: message,
        critical: true,
        action: _RetryButton(label: retryLabel, onPressed: onRetry!),
      ),
    };
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: label,
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.all(ThemeV2Spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: tokens.muted),
              ),
            ),
            const SizedBox(height: ThemeV2Spacing.md),
            const USkeletonLine(widthFactor: 0.62, height: 14),
            const USkeletonLine(
              widthFactor: 1,
              height: 12,
              margin: EdgeInsets.only(top: ThemeV2Spacing.md),
            ),
            const USkeletonLine(
              widthFactor: 0.78,
              height: 12,
              margin: EdgeInsets.only(top: ThemeV2Spacing.sm),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    this.message,
    this.critical = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool critical;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ThemeV2Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: critical ? tokens.critical : tokens.muted,
            ),
            const SizedBox(height: ThemeV2Spacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: ThemeV2Spacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.muted),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: ThemeV2Spacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(label),
          ),
        ),
      ),
    );
  }
}
