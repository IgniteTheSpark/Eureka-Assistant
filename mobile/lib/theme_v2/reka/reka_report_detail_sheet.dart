import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

enum RekaReportDetailAction { primary, dismiss }

Future<RekaReportDetailAction?> showRekaReportDetailSheet(
  BuildContext context,
  TodayRekaItem item,
) => showModalBottomSheet<RekaReportDetailAction>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _RekaReportDetailSheet(item: item),
);

class _RekaReportDetailSheet extends StatelessWidget {
  const _RekaReportDetailSheet({required this.item});

  final TodayRekaItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final detail = _ReportDetail.from(item);
    return Material(
      key: const ValueKey('reka-report-detail-sheet'),
      color: tokens.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(ThemeV2Radii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            ThemeV2Spacing.xl,
            ThemeV2Spacing.sm,
            ThemeV2Spacing.xl,
            ThemeV2Spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      detail.label,
                      style: TextStyle(
                        color: tokens.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('reka-report-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: ThemeV2Spacing.md),
              Text(
                detail.title,
                style: TextStyle(
                  color: tokens.foreground,
                  fontSize: 22,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: ThemeV2Spacing.md),
              Text(
                detail.summary,
                style: TextStyle(
                  color: tokens.muted,
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              if (detail.meta case final meta?) ...[
                const SizedBox(height: ThemeV2Spacing.lg),
                Container(
                  padding: const EdgeInsets.all(ThemeV2Spacing.md),
                  decoration: BoxDecoration(
                    color: tokens.background,
                    borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                  ),
                  child: Text(
                    meta,
                    style: TextStyle(
                      color: tokens.foreground,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: ThemeV2Spacing.xl),
              FilledButton(
                key: const ValueKey('reka-report-primary'),
                onPressed: () =>
                    Navigator.of(context).pop(RekaReportDetailAction.primary),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    ThemeV2Sizes.minTouchTarget,
                  ),
                ),
                child: Text(detail.primaryLabel),
              ),
              TextButton(
                key: const ValueKey('reka-report-dismiss'),
                onPressed: () =>
                    Navigator.of(context).pop(RekaReportDetailAction.dismiss),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    ThemeV2Sizes.minTouchTarget,
                  ),
                ),
                child: Text(detail.dismissLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportDetail {
  const _ReportDetail({
    required this.label,
    required this.title,
    required this.summary,
    required this.primaryLabel,
    required this.dismissLabel,
    this.meta,
  });

  final String label;
  final String title;
  final String summary;
  final String primaryLabel;
  final String dismissLabel;
  final String? meta;

  factory _ReportDetail.from(TodayRekaItem item) {
    final evidence = item.evidence;
    return switch (item.reportPhase) {
      'plan_ready' => _ReportDetail(
        label: '报告方案',
        title: item.title,
        summary: _planGoal(evidence) ?? item.body,
        meta: evidence['asset_count'] is num
            ? '将使用 ${(evidence['asset_count'] as num).toInt()} 条材料，你可以在确认前调整范围。'
            : '进入方案后可以确认材料范围与生成方式。',
        primaryLabel: '查看并确认方案',
        dismissLabel: '暂不提醒',
      ),
      'report_ready' => _ReportDetail(
        label: '报告已生成',
        title: evidence['title']?.toString().trim().isNotEmpty == true
            ? evidence['title'].toString().trim()
            : item.body,
        summary: evidence['summary']?.toString().trim().isNotEmpty == true
            ? evidence['summary'].toString().trim()
            : '报告已经完成，可以查看完整内容。',
        primaryLabel: '查看完整报告',
        dismissLabel: '不再提醒',
      ),
      _ => _ReportDetail(
        label: '报告可能性',
        title: item.title,
        summary: item.body,
        meta: _opportunityMeta(evidence),
        primaryLabel: '生成报告方案',
        dismissLabel: '暂不生成',
      ),
    };
  }

  static String? _planGoal(Map<String, dynamic> evidence) {
    final plan = evidence['plan'];
    if (plan is! Map) return null;
    for (final key in const ['report_goal', 'goal', 'title']) {
      final value = plan[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _opportunityMeta(Map<String, dynamic> evidence) {
    for (final key in const ['event_title', 'scope_label', 'title']) {
      final value = evidence[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return '触发范围：$value';
    }
    final count = evidence['asset_count'];
    return count is num ? '已积累 ${count.toInt()} 条可用材料' : null;
  }
}
