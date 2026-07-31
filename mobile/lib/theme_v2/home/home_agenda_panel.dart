import 'dart:async';

import 'package:flutter/material.dart';

import '../../today/today_data.dart';
import '../asset_detail/asset_entity_ref.dart';
import '../asset_detail/open_asset_detail.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'home_today_panel.dart';

class HomeAgendaPanel extends StatelessWidget {
  const HomeAgendaPanel({
    super.key,
    required this.data,
    required this.onCloseAgenda,
    this.date,
  });

  final TodayData data;
  final VoidCallback onCloseAgenda;
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final items = <ChainItem>[
      ...supportedHomeQueueItems(data.chain),
      ...supportedHomeQueueItems(data.noTimeTodos),
    ];
    final currentDate = date ?? DateTime.now();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(homePanelRadius),
        border: Border.all(color: tokens.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(homePanelRadius),
        child: Column(
          children: [
            _AgendaHeader(date: currentDate, onClose: onCloseAgenda),
            Divider(height: 1, color: tokens.border),
            Expanded(child: _AgendaViewport(items: items)),
            Divider(height: 1, color: tokens.border),
            _GeneratedAssetChamber(assets: data.pool),
          ],
        ),
      ),
    );
  }
}

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({required this.date, required this.onClose});

  final DateTime date;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 10, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日日程',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.month}月${date.day}日的时间脉络',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
          ThemeV2IconButton(
            semanticLabel: '收起日程',
            icon: Icons.keyboard_arrow_down,
            color: tokens.foreground,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _AgendaViewport extends StatelessWidget {
  const _AgendaViewport({required this.items});

  final List<ChainItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ThemeV2Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.route_outlined, size: 32, color: tokens.muted),
              const SizedBox(height: ThemeV2Spacing.md),
              Text(
                '今天的时间脉络还很安静',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.muted),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      key: const PageStorageKey('theme-v2-agenda-scroll'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return _AgendaNode(
          item: items[index],
          isFirst: index == 0,
          isLast: index == items.length - 1,
        );
      },
    );
  }
}

class _AgendaNode extends StatelessWidget {
  const _AgendaNode({
    required this.item,
    required this.isFirst,
    required this.isLast,
  });

  final ChainItem item;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      label: '打开 ${item.title}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeV2Radii.md),
          onTap: () => unawaited(
            openAssetDetail(
              context,
              AssetEntityRef(
                kind: item.kind == 'event'
                    ? AssetEntityKind.event
                    : AssetEntityKind.asset,
                id: item.id,
              ),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 58,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 17),
                    child: Text(
                      item.timed ? _clock(item.at) : '待排',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: item.timed ? tokens.accent : tokens.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 22,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: isFirst ? 22 : 0,
                        bottom: isLast ? 36 : 0,
                        child: Container(width: 1, color: tokens.border),
                      ),
                      Positioned(
                        top: 19,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: tokens.accent, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ThemeV2Spacing.sm),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: ThemeV2Spacing.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.background,
                      borderRadius: BorderRadius.circular(ThemeV2Radii.md),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (item.sub.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratedAssetChamber extends StatelessWidget {
  const _GeneratedAssetChamber({required this.assets});

  final List<PoolAsset> assets;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final visible = assets.take(4).toList();
    return SizedBox(
      height: 170,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '生成舱',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${assets.length} 项资产',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: tokens.muted),
                ),
              ],
            ),
            const SizedBox(height: ThemeV2Spacing.md),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(ThemeV2Spacing.md),
                decoration: BoxDecoration(
                  color: tokens.background,
                  borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
                  border: Border.all(color: tokens.border),
                ),
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          '完成记录后，资产会沉入这里',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final asset in visible)
                            _ChamberAsset(asset: asset),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChamberAsset extends StatelessWidget {
  const _ChamberAsset({required this.asset});

  final PoolAsset asset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      label: '打开资产 ${asset.title}',
      child: Material(
        color: tokens.accentSoft,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => unawaited(
            openAssetDetail(
              context,
              AssetEntityRef(kind: AssetEntityKind.asset, id: asset.id),
            ),
          ),
          child: SizedBox.square(
            dimension: 54,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Center(
                child: Text(
                  asset.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.foreground,
                    height: 1.1,
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

String _clock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
