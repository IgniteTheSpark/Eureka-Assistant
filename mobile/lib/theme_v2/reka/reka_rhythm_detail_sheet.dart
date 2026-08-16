import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';

enum RekaRhythmDetailAction { record, dismiss }

Future<RekaRhythmDetailAction?> showRekaRhythmDetailSheet(
  BuildContext context,
  TodayRekaItem item,
) => showModalBottomSheet<RekaRhythmDetailAction>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _RekaRhythmDetailSheet(item: item),
);

class _RekaRhythmDetailSheet extends StatelessWidget {
  const _RekaRhythmDetailSheet({required this.item});

  final TodayRekaItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final detail = _RhythmDetail.from(item);
    return Material(
      key: const ValueKey('reka-rhythm-detail-sheet'),
      color: tokens.surface,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(ThemeV2Radii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
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
                      '节律提醒',
                      style: TextStyle(
                        color: tokens.foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('reka-rhythm-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: ThemeV2Spacing.md),
              Text(
                detail.pattern,
                style: TextStyle(
                  color: tokens.foreground,
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: ThemeV2Spacing.lg),
              _RhythmFact(icon: Icons.insights_outlined, text: detail.evidence),
              const SizedBox(height: ThemeV2Spacing.sm),
              _RhythmFact(icon: Icons.timelapse_rounded, text: detail.gap),
              const SizedBox(height: ThemeV2Spacing.xl),
              FilledButton(
                key: const ValueKey('reka-rhythm-record'),
                onPressed: () =>
                    Navigator.of(context).pop(RekaRhythmDetailAction.record),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    ThemeV2Sizes.minTouchTarget,
                  ),
                ),
                child: const Text('立即记录'),
              ),
              TextButton(
                key: const ValueKey('reka-rhythm-dismiss'),
                onPressed: () =>
                    Navigator.of(context).pop(RekaRhythmDetailAction.dismiss),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    ThemeV2Sizes.minTouchTarget,
                  ),
                ),
                child: const Text('暂不提醒此节律'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RhythmFact extends StatelessWidget {
  const _RhythmFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tokens.muted),
        const SizedBox(width: ThemeV2Spacing.sm),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: tokens.muted, fontSize: 14, height: 1.45),
          ),
        ),
      ],
    );
  }
}

class _RhythmDetail {
  const _RhythmDetail({
    required this.pattern,
    required this.evidence,
    required this.gap,
  });

  static const _periods = <String>{'凌晨', '上午', '中午', '下午', '晚上'};
  static const _weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  final String pattern;
  final String evidence;
  final String gap;

  factory _RhythmDetail.from(TodayRekaItem item) {
    final evidence = item.evidence;
    final parts = item.naturalKey.split(':');
    final cadence =
        evidence['cadence']?.toString() ??
        (parts.contains('weekly') ? 'weekly' : 'daily');
    final rawPeriod = evidence['period']?.toString();
    final period = _periods.contains(rawPeriod)
        ? rawPeriod!
        : _periods.firstWhere(
            (value) => parts.contains(value),
            orElse: () => '',
          );
    final weekday = _weekdayLabel(evidence['weekdays'], parts);
    final skill = item.title.replaceFirst(RegExp(r'还没有记录$'), '').trim();
    final timing = cadence == 'weekly'
        ? '$weekday$period'
        : period.isEmpty
        ? '这个时段'
        : period;
    final sample = evidence['sample_n'];
    final sampleCount = sample is num ? sample.toInt() : null;
    return _RhythmDetail(
      pattern: '你通常在$timing记录$skill',
      evidence: sampleCount == null
          ? '这个节律来自最近 28 天里的重复记录'
          : '最近 28 天有 $sampleCount 次记录支持这个节律',
      gap: cadence == 'weekly' ? '本周还没有$skill记录' : '今天还没有$skill记录',
    );
  }

  static String _weekdayLabel(Object? raw, List<String> parts) {
    int? value;
    if (raw is Iterable) {
      for (final candidate in raw) {
        if (candidate is num) {
          value = candidate.toInt();
          break;
        }
      }
    }
    if (value == null) {
      final index = parts.indexOf('weekly');
      if (index >= 0 && index + 1 < parts.length) {
        value = int.tryParse(parts[index + 1]);
      }
    }
    return value != null && value >= 0 && value < _weekdays.length
        ? _weekdays[value]
        : '';
  }
}
