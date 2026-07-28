import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../assets/assets.dart';
import '../../../data_revision.dart';
import '../../../render/render_spec.dart';
import '../../../timeline/timeline.dart';
import '../../foundation/theme_v2_semantics.dart';
import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_typography.dart';
import 'asset_detail_sheet.dart';
import 'set_goal_action.dart';

enum AssetListSource { assets, entities }

class ThemeV2AssetListPage extends StatefulWidget {
  const ThemeV2AssetListPage.assets({
    super.key,
    required this.meta,
    required this.skillName,
    required this.initialAssets,
    required this.specs,
    this.api,
    this.autoLoad = true,
    this.onSetGoal,
  }) : source = AssetListSource.assets,
       title = null,
       cardType = null,
       initialEntities = const [];

  const ThemeV2AssetListPage.entities({
    super.key,
    required this.title,
    required this.cardType,
    required this.initialEntities,
    this.api,
    this.autoLoad = true,
    this.onSetGoal,
  }) : source = AssetListSource.entities,
       meta = null,
       skillName = null,
       initialAssets = const [],
       specs = const {};

  final AssetListSource source;
  final SkillMeta? meta;
  final String? skillName;
  final List<AssetItem> initialAssets;
  final Map<String, RenderSpec> specs;
  final String? title;
  final String? cardType;
  final List<Map<String, dynamic>> initialEntities;
  final ApiClient? api;
  final bool autoLoad;
  final ValueChanged<SetGoalIntent>? onSetGoal;

  @override
  State<ThemeV2AssetListPage> createState() => _ThemeV2AssetListPageState();
}

class _ThemeV2AssetListPageState extends State<ThemeV2AssetListPage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late List<AssetItem> _assets = [...widget.initialAssets];
  late List<Map<String, dynamic>> _entities = [...widget.initialEntities];
  late Map<String, RenderSpec> _specs = {...widget.specs};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      dataRevision.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    if (widget.autoLoad) dataRevision.removeListener(_reload);
    if (widget.api == null) _api.close();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.source == AssetListSource.assets) {
        final responses = await Future.wait<Object?>([
          _api.getJson(
            '/api/assets',
            query: {'user_skill_name': widget.skillName},
          ),
          _fetchSpecsSafely(),
        ]);
        final response = responses[0];
        final refreshedSpecs = responses[1] as Map<String, RenderSpec>;
        final list =
            (response is Map ? response['assets'] : null) as List? ?? const [];
        final assets = list
            .whereType<Map>()
            .map((item) => AssetItem.fromJson(item.cast<String, dynamic>()))
            .toList();
        if (mounted) {
          setState(() {
            _assets = assets;
            _specs = {..._specs, ...refreshedSpecs};
          });
        }
      } else {
        final type = widget.cardType!;
        final key = type == 'event' ? 'events' : 'contacts';
        final response = await _api.getJson('/api/$key');
        final list =
            (response is Map ? response[key] : null) as List? ?? const [];
        final entities = list
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
        if (mounted) setState(() => _entities = entities);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '内容暂时无法刷新');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, RenderSpec>> _fetchSpecsSafely() async {
    try {
      return await fetchRenderSpecs(_api);
    } catch (_) {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final records = _records();
    return ColoredBox(
      color: tokens.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.lg,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.lg,
          ThemeV2Spacing.xl,
        ),
        children: [
          _ListHeader(
            icon: widget.meta?.icon ?? _entityIcon(widget.cardType),
            title: widget.meta?.label ?? widget.title ?? '资产',
            count: records.length,
          ),
          if (_loading) ...[
            const SizedBox(height: ThemeV2Spacing.md),
            LinearProgressIndicator(
              minHeight: 2,
              color: tokens.accent,
              backgroundColor: tokens.accentSoft,
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: ThemeV2Spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: tokens.critical),
                    ),
                  ),
                  TextButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            ),
          const SizedBox(height: ThemeV2Spacing.lg),
          if (records.isEmpty)
            _EmptyList(
              label: widget.meta?.label ?? widget.title ?? '资产',
              icon: widget.meta?.icon ?? _entityIcon(widget.cardType),
            )
          else
            for (final record in records) ...[
              _AssetListRow(record: record, onTap: () => _open(record)),
              const SizedBox(height: ThemeV2Spacing.sm),
            ],
        ],
      ),
    );
  }

  List<_ListRecord> _records() {
    final records = widget.source == AssetListSource.assets
        ? [
            for (final asset in _assets)
              _ListRecord(
                id: asset.id,
                cardType: asset.skillName,
                title: readableTitle(
                  asset.payload,
                  _specs[asset.skillName],
                  fallback: widget.meta?.label ?? asset.skillName,
                ),
                subtitle: _assetSubtitle(asset),
                effectiveAt: asset.effectiveAt,
                payload: asset.payload,
                userSkillId: asset.userSkillId ?? widget.meta?.userSkillId,
                sessionId: asset.sessionId,
                spec: _specs[asset.skillName],
                domain: asset.domain,
              ),
          ]
        : [
            for (final entity in _entities)
              _ListRecord(
                id: _entityId(entity, widget.cardType!),
                cardType: widget.cardType!,
                title: _entityTitle(entity),
                subtitle: widget.cardType == 'event'
                    ? eventCardSummary(entity)
                    : _contactSummary(entity),
                effectiveAt: _entityTime(entity, widget.cardType!),
                payload: entity,
                spec: synthesizeSpec(widget.cardType!),
              ),
          ];
    records.sort((a, b) {
      final effective = b.effectiveAt.compareTo(a.effectiveAt);
      return effective != 0 ? effective : b.id.compareTo(a.id);
    });
    return records;
  }

  Future<void> _open(_ListRecord record) async {
    final data = buildCard(
      payload: record.payload,
      spec: record.spec,
      displayName: record.cardType,
    ).copyWith(domain: record.domain);
    await showThemeV2AssetDetail(
      context,
      api: _api,
      data: data,
      payload: record.payload,
      cardType: record.cardType,
      assetId: record.id,
      userSkillId: record.userSkillId,
      sessionId: record.sessionId,
      spec: record.spec,
      onSetGoal: widget.onSetGoal,
    );
  }
}

class _ListRecord {
  const _ListRecord({
    required this.id,
    required this.cardType,
    required this.title,
    required this.subtitle,
    required this.effectiveAt,
    required this.payload,
    required this.spec,
    this.userSkillId,
    this.sessionId,
    this.domain,
  });

  final String id;
  final String cardType;
  final String title;
  final String subtitle;
  final DateTime effectiveAt;
  final Map<String, dynamic> payload;
  final RenderSpec? spec;
  final String? userSkillId;
  final String? sessionId;
  final String? domain;
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final String icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ThemeV2IconButton(
              semanticLabel: '返回资产库',
              icon: Icons.arrow_back,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: ThemeV2Spacing.sm),
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(ThemeV2Radii.md),
              ),
              child: Text(icon),
            ),
            const SizedBox(width: ThemeV2Spacing.md),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ThemeV2Spacing.xs),
        Padding(
          padding: const EdgeInsets.only(left: ThemeV2Sizes.minTouchTarget + 8),
          child: Text(
            '$count ITEMS',
            style: ThemeV2Typography.mono(fontSize: 9, color: tokens.muted),
          ),
        ),
      ],
    );
  }
}

class _AssetListRow extends StatelessWidget {
  const _AssetListRow({required this.record, required this.onTap});

  final _ListRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      button: true,
      label: '打开 ${record.title}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: ThemeV2Spacing.lg,
            vertical: ThemeV2Spacing.md,
          ),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                child: Text(
                  _date(record.effectiveAt),
                  style: ThemeV2Typography.mono(
                    fontSize: 9,
                    color: tokens.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (record.subtitle.isNotEmpty)
                      Text(
                        record.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: tokens.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.label, required this.icon});

  final String label;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      height: 230,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: ThemeV2Spacing.md),
          Text(
            '还没有内容',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          Text('新的$label会显示在这里', style: TextStyle(color: tokens.muted)),
        ],
      ),
    );
  }
}

String _date(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

String _assetSubtitle(AssetItem asset) {
  if (asset.period.isNotEmpty) return asset.period;
  if (asset.occurredAt != null) {
    final at = asset.occurredAt!;
    return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }
  return '';
}

String _entityIcon(String? cardType) => cardType == 'event' ? '📅' : '👤';

String _entityId(Map<String, dynamic> entity, String cardType) =>
    (cardType == 'event'
            ? entity['event_id'] ?? entity['id']
            : entity['contact_id'] ?? entity['id'])
        ?.toString() ??
    '';

String _entityTitle(Map<String, dynamic> entity) =>
    (entity['title'] ?? entity['name'] ?? entity['display_name'])
        ?.toString()
        .trim() ??
    '未命名';

String _contactSummary(Map<String, dynamic> contact) => [
  contact['company'],
  contact['title'],
].where((value) => value != null && '$value'.trim().isNotEmpty).join(' · ');

DateTime _entityTime(Map<String, dynamic> entity, String cardType) {
  final raw = cardType == 'event'
      ? entity['start_at']
      : entity['effective_at'] ?? entity['created_at'];
  return DateTime.tryParse(raw?.toString() ?? '')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
