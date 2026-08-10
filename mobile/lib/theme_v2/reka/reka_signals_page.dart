import 'dart:async';

import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import '../home/home_repository.dart';
import '../shell/theme_v2_async_state.dart';
import '../shell/theme_v2_page_title.dart';
import 'reka_signal_actions.dart';
import 'reka_signal_repository.dart';

class RekaSignalsPage extends StatefulWidget {
  const RekaSignalsPage({
    super.key,
    this.repository,
    this.onBack,
    this.onOpenTarget,
    this.onAction,
    this.onOpenReports,
    this.onCreateReport,
  });

  final RekaSignalRepository? repository;
  final VoidCallback? onBack;
  final RekaSignalTargetCallback? onOpenTarget;
  final RekaSignalMutationCallback? onAction;
  final VoidCallback? onOpenReports;
  final VoidCallback? onCreateReport;

  @override
  State<RekaSignalsPage> createState() => _RekaSignalsPageState();
}

class _RekaSignalsPageState extends State<RekaSignalsPage> {
  late final RekaSignalRepository _repository =
      widget.repository ?? ApiRekaSignalRepository();
  late final bool _ownsRepository = widget.repository == null;
  final Set<String> _mutating = <String>{};

  List<TodayRekaItem>? _items;
  List<String> _partialFailures = const [];
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    if (_ownsRepository && _repository is ApiRekaSignalRepository) {
      _repository.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final batch = await _repository.load();
      if (!mounted) return;
      setState(() {
        _items = mapTodayRekaSignals(batch.signals);
        _partialFailures = batch.partialFailures;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _mutate(TodayRekaItem item, String action) async {
    if (!_mutating.add(item.id)) return;
    try {
      final callback = widget.onAction;
      if (callback != null) {
        await callback(item, action);
      } else if (action == 'complete') {
        await _repository.completeTodo(item.targetId);
      } else if (action == 'dismiss') {
        await _repository.dismiss(item.id);
      } else {
        return;
      }
      if (!mounted) return;
      setState(() {
        _items = _items
            ?.where((candidate) => candidate.id != item.id)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
    } finally {
      _mutating.remove(item.id);
    }
  }

  Future<void> _openTarget(BuildContext context, TodayRekaItem item) {
    final callback = widget.onOpenTarget;
    return callback == null
        ? openRekaSignalTarget(context, item)
        : callback(context, item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.themeV2.background,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 18, 8),
    child: Row(
      children: [
        ThemeV2IconButton(
          semanticLabel: '返回',
          icon: Icons.chevron_left_rounded,
          color: context.themeV2.foreground,
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: ThemeV2Spacing.xs),
        const Expanded(
          child: ThemeV2PageTitle(
            key: ValueKey('theme-v2-page-title-reka'),
            title: 'Reka 发现',
          ),
        ),
      ],
    ),
  );

  Widget _content() {
    final items = _items;
    if (items == null && _error == null) {
      return const ThemeV2AsyncState.loading(label: '正在加载 Reka 发现');
    }
    if (items == null) {
      return ThemeV2AsyncState.error(
        title: 'Reka 发现加载失败',
        message: '请检查网络后重试',
        onRetry: () => unawaited(_load()),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          if (_partialFailures.isNotEmpty) ...[
            _PartialFailureBanner(count: _partialFailures.length),
            const SizedBox(height: ThemeV2Spacing.md),
          ],
          if (items.isEmpty)
            _EmptyRekaState(
              onOpenReports: widget.onOpenReports,
              onCreateReport: widget.onCreateReport,
            )
          else
            for (final item in items) ...[
              _RekaSignalCard(
                item: item,
                onOpenTarget: _openTarget,
                onAction: _mutate,
              ),
              const SizedBox(height: ThemeV2Spacing.sm),
            ],
        ],
      ),
    );
  }
}

class _RekaSignalCard extends StatelessWidget {
  const _RekaSignalCard({
    required this.item,
    required this.onOpenTarget,
    required this.onAction,
  });

  final TodayRekaItem item;
  final RekaSignalTargetCallback onOpenTarget;
  final RekaSignalMutationCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(onOpenTarget(context, item)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.accentSoft,
                  borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                ),
                child: Icon(
                  _rekaIcon(item.type),
                  key: ValueKey('theme-v2-reka-icon-${item.type}'),
                  size: 19,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: ThemeV2Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: _primary(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.foreground,
                      ),
                    ),
                    const SizedBox(height: ThemeV2Spacing.xs),
                    Text(
                      item.body,
                      style: _primary(fontSize: 12, color: tokens.muted),
                    ),
                    const SizedBox(height: ThemeV2Spacing.sm),
                    Text(
                      _rekaTypeLabel(item.type),
                      style: ThemeV2Typography.mono(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: tokens.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (_menuActions.isNotEmpty)
                SizedBox.square(
                  dimension: ThemeV2Sizes.minTouchTarget,
                  child: Semantics(
                    button: true,
                    label: '更多操作 ${item.title}',
                    child: PopupMenuButton<String>(
                      key: ValueKey('theme-v2-reka-menu-${item.id}'),
                      tooltip: '',
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 20,
                        color: tokens.muted,
                      ),
                      onSelected: (action) => unawaited(
                        action == 'reschedule'
                            ? onOpenTarget(context, item)
                            : onAction(item, action),
                      ),
                      itemBuilder: (_) => [
                        for (final action in _menuActions)
                          PopupMenuItem<String>(
                            value: action,
                            child: Text(_actionLabel(action)),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> get _menuActions => item.actions
      .where(
        (action) =>
            action == 'complete' ||
            action == 'reschedule' ||
            action == 'dismiss',
      )
      .toList(growable: false);
}

class _PartialFailureBanner extends StatelessWidget {
  const _PartialFailureBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(ThemeV2Spacing.md),
    decoration: BoxDecoration(
      color: context.themeV2.accentSoft,
      borderRadius: BorderRadius.circular(ThemeV2Radii.md),
    ),
    child: Text(
      '$count 类发现暂时未能刷新，下拉可重试',
      style: _primary(fontSize: 12, color: context.themeV2.muted),
    ),
  );
}

class _EmptyRekaState extends StatelessWidget {
  const _EmptyRekaState({this.onOpenReports, this.onCreateReport});

  final VoidCallback? onOpenReports;
  final VoidCallback? onCreateReport;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 120),
    child: Column(
      children: [
        Icon(Icons.auto_awesome_outlined, color: context.themeV2.muted),
        const SizedBox(height: ThemeV2Spacing.md),
        Text(
          '暂时没有新的发现',
          style: _primary(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.themeV2.foreground,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        Text(
          'Reka 会在发现逾期、节律变化或可生成报告时提醒你',
          textAlign: TextAlign.center,
          style: _primary(fontSize: 12, color: context.themeV2.muted),
        ),
        const SizedBox(height: ThemeV2Spacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: onOpenReports, child: const Text('查看历史报告')),
            const SizedBox(width: ThemeV2Spacing.sm),
            FilledButton.tonal(
              onPressed: onCreateReport,
              child: const Text('生成新报告'),
            ),
          ],
        ),
      ],
    ),
  );
}

IconData _rekaIcon(String type) => switch (type) {
  'overdue' => Icons.schedule_outlined,
  'rhythm_gap' => Icons.waves_outlined,
  _ => Icons.lightbulb_outline_rounded,
};

String _rekaTypeLabel(String type) => switch (type) {
  'overdue' => '逾期提醒',
  'rhythm_gap' => '节律提醒',
  _ => 'Reka 信号',
};

String _actionLabel(String action) => switch (action) {
  'complete' => '标记完成',
  'reschedule' => '调整时间',
  'dismiss' => '忽略提醒',
  _ => action,
};

TextStyle _primary({double? fontSize, Color? color, FontWeight? fontWeight}) =>
    TextStyle(
      fontFamily: ThemeV2Typography.primaryFont,
      fontFamilyFallback: ThemeV2Typography.fallbackFonts,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
    );
