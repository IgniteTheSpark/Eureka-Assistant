import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_events.dart' show openNotificationTarget;
import '../../pet/floating_mascot.dart' show rekaNudgeActRequest;
import '../../pet/reka_nudges.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import '../shell/theme_v2_async_state.dart';
import 'reka_inbox_controller.dart';
import 'reka_inbox_item.dart';

class RekaInboxPage extends StatefulWidget {
  const RekaInboxPage({
    super.key,
    this.controller,
    this.autoLoad = true,
    this.onBack,
    this.onAct,
  });

  final RekaInboxController? controller;
  final bool autoLoad;
  final VoidCallback? onBack;
  final ValueChanged<RekaInboxItem>? onAct;

  @override
  State<RekaInboxPage> createState() => _RekaInboxPageState();
}

class _RekaInboxPageState extends State<RekaInboxPage> {
  late final RekaInboxController _controller =
      widget.controller ?? RekaInboxController();
  late final bool _ownsController = widget.controller == null;
  final Set<String> _actInFlight = {};

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_controller.load());
      });
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _back() {
    final callback = widget.onBack;
    if (callback != null) {
      callback();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _act(RekaInboxItem item) async {
    if (!_actInFlight.add(item.id)) return;
    try {
      if (!await _controller.markActed(item.id) || !mounted) return;
      final callback = widget.onAct;
      if (callback != null) {
        callback(item);
        return;
      }
      if (item.cta == 'notification') {
        await openNotificationTarget(item.type, item.ref);
        return;
      }
      if (item.cta == 'view') {
        await openNotificationTarget('reminder', _viewLink(item.ref));
        return;
      }
      rekaNudgeActRequest.value = RekaNudge(
        id: item.id,
        text: item.title,
        body: item.body,
        ref: item.ref,
        cta: item.cta,
        kind: item.kind,
        status: 'acted',
      );
    } finally {
      _actInFlight.remove(item.id);
    }
  }

  String _viewLink(String ref) => ref.startsWith('reminder:')
      ? ref
      : (ref.startsWith('todo:') || ref.startsWith('evt:'))
      ? 'reminder:$ref'
      : 'reminder:todo:$ref';

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _themeV2WithLegacyExtension(context),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.themeV2.background,
          body: SafeArea(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _themeV2WithLegacyExtension(BuildContext context) {
    final ambient = Theme.of(context);
    var theme = buildThemeV2Theme(ambient.brightness);
    final legacyExtensions = ambient.extensions.values.where(
      (extension) => extension is! ThemeV2Tokens,
    );
    if (legacyExtensions.isNotEmpty) {
      theme = theme.copyWith(
        extensions: [...theme.extensions.values, ...legacyExtensions],
      );
    }
    return theme;
  }

  Widget _buildBody(BuildContext context) {
    if (_controller.items.isEmpty) {
      return switch (_controller.status) {
        RekaInboxStatus.idle ||
        RekaInboxStatus.loading ||
        RekaInboxStatus.refreshing => const ThemeV2AsyncState.loading(
          label: '正在接收 REKA 信号',
        ),
        RekaInboxStatus.error => ThemeV2AsyncState.error(
          title: '暂时无法加载 Inbox',
          message: _controller.errorMessage,
          retryLabel: '重试 Inbox',
          onRetry: _controller.retry,
        ),
        RekaInboxStatus.empty => const ThemeV2AsyncState.empty(
          title: 'Inbox 已清空',
          message: '新的提醒和建议会出现在这里',
        ),
        RekaInboxStatus.partial => ThemeV2AsyncState.error(
          title: '部分 Inbox 暂不可用',
          message: _controller.errorMessage,
          retryLabel: '重试 Inbox',
          onRetry: _controller.retry,
        ),
        RekaInboxStatus.ready => const ThemeV2AsyncState.empty(
          title: 'Inbox 已清空',
          message: '新的提醒和建议会出现在这里',
        ),
      };
    }

    return RefreshIndicator(
      onRefresh: _controller.load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              ThemeV2Spacing.lg,
              ThemeV2Spacing.sm,
              ThemeV2Spacing.lg,
              ThemeV2Spacing.xl,
            ),
            sliver: SliverList.list(
              children: [
                _InboxHeader(
                  unreadCount: _controller.unreadCount,
                  onBack: _back,
                  onMarkAllSeen: _controller.unreadCount == 0
                      ? null
                      : _controller.markAllSeen,
                ),
                if (_controller.isRefreshing) ...[
                  const SizedBox(height: ThemeV2Spacing.md),
                  const LinearProgressIndicator(
                    minHeight: 2,
                    semanticsLabel: '正在刷新 Inbox',
                  ),
                ],
                if (_controller.status == RekaInboxStatus.partial ||
                    _controller.status == RekaInboxStatus.error) ...[
                  const SizedBox(height: ThemeV2Spacing.md),
                  _InboxNotice(
                    message:
                        _controller.errorMessage ??
                        (_controller.status == RekaInboxStatus.error
                            ? '刷新失败，当前内容可能不是最新'
                            : '部分内容加载失败'),
                    onRetry: _controller.retry,
                  ),
                ],
                if (_controller.mutationError case final error?) ...[
                  const SizedBox(height: ThemeV2Spacing.md),
                  _InboxNotice(message: error),
                ],
                const SizedBox(height: ThemeV2Spacing.xl),
                Text(
                  'SIGNALS / ${_controller.items.length.toString().padLeft(2, '0')}',
                  style: ThemeV2Typography.mono(
                    fontSize: 9,
                    color: context.themeV2.muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: ThemeV2Spacing.sm),
                for (final item in _controller.items) ...[
                  _InboxCard(
                    item: item,
                    onSeen: item.isUnread
                        ? () => _controller.markSeen(item.id)
                        : null,
                    onAct: item.isTerminal ? null : () => _act(item),
                    onDismiss: item.isTerminal
                        ? null
                        : () => _controller.markDismissed(item.id),
                  ),
                  const SizedBox(height: ThemeV2Spacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxHeader extends StatelessWidget {
  const _InboxHeader({
    required this.unreadCount,
    required this.onBack,
    required this.onMarkAllSeen,
  });

  final int unreadCount;
  final VoidCallback onBack;
  final Future<bool> Function()? onMarkAllSeen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ThemeV2IconButton(
              semanticLabel: '返回',
              icon: Icons.arrow_back,
              color: tokens.muted,
              onPressed: onBack,
            ),
            const Spacer(),
            Semantics(
              label: '标记全部已读',
              button: true,
              enabled: onMarkAllSeen != null,
              onTap: onMarkAllSeen == null
                  ? null
                  : () => unawaited(onMarkAllSeen!()),
              child: ExcludeSemantics(
                child: ThemeV2HitTarget(
                  child: TextButton(
                    onPressed: onMarkAllSeen == null
                        ? null
                        : () => unawaited(onMarkAllSeen!()),
                    child: const Text('全部已读'),
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(
          'REKA / INBOX',
          style: ThemeV2Typography.mono(
            fontSize: 9,
            color: tokens.muted,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          'REKA Inbox',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: tokens.foreground,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.xs),
        Text(
          unreadCount == 0 ? '全部已读' : '$unreadCount 条未读',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: tokens.muted),
        ),
      ],
    );
  }
}

class _InboxNotice extends StatelessWidget {
  const _InboxNotice({required this.message, this.onRetry});

  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      padding: const EdgeInsets.only(left: ThemeV2Spacing.md),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: tokens.critical, width: 2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.muted),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: () => unawaited(onRetry!()),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.item,
    required this.onSeen,
    required this.onAct,
    required this.onDismiss,
  });

  final RekaInboxItem item;
  final VoidCallback? onSeen;
  final VoidCallback? onAct;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final icon = switch (item.kind) {
      'overdue' => Icons.schedule_outlined,
      'habit_reminder' => Icons.repeat,
      'briefing' => Icons.auto_awesome_outlined,
      'offer' => Icons.bolt_outlined,
      _ => Icons.notifications_none_outlined,
    };
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${item.title}，${_statusLabel(item.status)}',
      child: Material(
        color: item.isUnread ? tokens.accentSoft : tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
          side: BorderSide(
            color: item.isUnread ? tokens.accent : tokens.border,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(ThemeV2Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.background,
                      borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Icon(icon, size: 18, color: tokens.accent),
                  ),
                  const SizedBox(width: ThemeV2Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: tokens.foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (item.body.isNotEmpty) ...[
                          const SizedBox(height: ThemeV2Spacing.xs),
                          Text(
                            item.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.muted, height: 1.45),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: ThemeV2Spacing.sm),
                  _StatusPill(status: item.status),
                ],
              ),
              if (onSeen != null || onAct != null || onDismiss != null) ...[
                const SizedBox(height: ThemeV2Spacing.md),
                Row(
                  children: [
                    if (onSeen != null)
                      Expanded(
                        child: _InboxAction(
                          label: '标记 ${item.title} 为已读',
                          text: '已读',
                          onPressed: onSeen,
                        ),
                      ),
                    if (onSeen != null && onAct != null)
                      const SizedBox(width: ThemeV2Spacing.xs),
                    if (onAct != null)
                      Expanded(
                        child: _InboxAction(
                          label: '执行 ${item.title}',
                          text: '执行',
                          primary: true,
                          onPressed: onAct,
                        ),
                      ),
                    if ((onSeen != null || onAct != null) && onDismiss != null)
                      const SizedBox(width: ThemeV2Spacing.xs),
                    if (onDismiss != null)
                      Expanded(
                        child: _InboxAction(
                          label: '忽略 ${item.title}',
                          text: '忽略',
                          onPressed: onDismiss,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    'pending' || 'delivered' => '未读',
    'seen' => '已读',
    'acted' => '已执行',
    'dismissed' => '已忽略',
    _ => status,
  };
}

class _InboxAction extends StatelessWidget {
  const _InboxAction({
    required this.label,
    required this.text,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final String text;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: SizedBox(
          height: ThemeV2Sizes.minTouchTarget,
          child: Material(
            color: primary ? tokens.foreground : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
              side: BorderSide(
                color: primary ? tokens.foreground : tokens.border,
              ),
            ),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
              child: Center(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: primary ? tokens.background : tokens.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final label = switch (status) {
      'pending' || 'delivered' => 'NEW',
      'seen' => 'SEEN',
      'acted' => 'DONE',
      'dismissed' => 'SKIP',
      _ => status.toUpperCase(),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeV2Spacing.sm,
        vertical: ThemeV2Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.background,
        borderRadius: BorderRadius.circular(ThemeV2Radii.pill),
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        label,
        style: ThemeV2Typography.mono(
          fontSize: 8,
          color: status == 'pending' || status == 'delivered'
              ? tokens.accent
              : tokens.muted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
