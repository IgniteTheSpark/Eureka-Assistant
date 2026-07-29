import 'package:flutter/material.dart';

import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

enum _LibraryStateKind { loading, empty, emptySearch, error }

class LibraryStateView extends StatelessWidget {
  const LibraryStateView.loading({super.key})
    : _kind = _LibraryStateKind.loading,
      title = '正在加载资产库',
      message = null,
      onAction = null;

  const LibraryStateView.empty({
    super.key,
    this.title = '还没有资产',
    this.message,
    this.onAction,
  }) : _kind = _LibraryStateKind.empty;

  const LibraryStateView.emptySearch({super.key, required VoidCallback onClear})
    : _kind = _LibraryStateKind.emptySearch,
      title = '没有匹配的容器',
      message = '换个关键词试试',
      onAction = onClear;

  const LibraryStateView.error({
    super.key,
    this.title = '资产库加载失败',
    this.message,
    required VoidCallback onRetry,
  }) : _kind = _LibraryStateKind.error,
       onAction = onRetry;

  final _LibraryStateKind _kind;
  final String title;
  final String? message;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (_kind == _LibraryStateKind.loading) {
      return const _LibrarySkeleton();
    }
    final tokens = context.themeV2;
    return Container(
      key: ValueKey('library-state-${_kind.name}'),
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(ThemeV2Spacing.xl),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (message case final value?) ...[
            const SizedBox(height: ThemeV2Spacing.xs),
            Text(
              value,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ],
          if (onAction != null) ...[
            const SizedBox(height: ThemeV2Spacing.md),
            TextButton(
              onPressed: onAction,
              child: Text(
                _kind == _LibraryStateKind.emptySearch ? '清除搜索' : '重试',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class LibraryPartialBanner extends StatelessWidget {
  const LibraryPartialBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('library-partial-banner'),
      decoration: BoxDecoration(
        color: context.themeV2.accentSoft,
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
      ),
      padding: const EdgeInsets.only(left: ThemeV2Spacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) {
    final color = context.themeV2.border.withValues(alpha: .72);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(ThemeV2Radii.sm),
      ),
    );
    return Semantics(
      label: '正在加载资产库',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(92, 28),
              const SizedBox(height: 18),
              bar(double.infinity, 54),
              const SizedBox(height: 24),
              bar(86, 10),
              const SizedBox(height: 10),
              for (var index = 0; index < 4; index++) ...[
                bar(double.infinity, 54),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
