import 'package:flutter/material.dart';

import '../../../api/api_client.dart';
import '../../../assets/assets.dart';
import '../../../data_revision.dart';
import '../../../render/render_spec.dart';
import '../../../timeline/timeline.dart';
import '../../asset/asset_card.dart';
import '../../asset_detail/asset_detail_repository.dart';
import '../../asset_detail/asset_entity_ref.dart';
import '../../asset_detail/open_asset_detail.dart';
import '../../foundation/theme_v2_dither_field.dart';
import '../../foundation/theme_v2_dither_surface.dart';
import '../../foundation/theme_v2_content_surface.dart';
import '../../foundation/theme_v2_semantics.dart';
import '../../foundation/theme_v2_theme.dart';
import '../../foundation/theme_v2_tokens.dart';
import '../../foundation/theme_v2_typography.dart';
import 'asset_container_controller.dart';
import 'asset_record.dart';

enum AssetListSource { assets, entities }

class ThemeV2AssetListPage extends StatefulWidget {
  const ThemeV2AssetListPage.assets({
    super.key,
    required this.meta,
    required this.skillName,
    required this.initialAssets,
    required this.specs,
    this.api,
    this.coreRecordsOnly = false,
    this.autoLoad = true,
    this.today,
    this.onConfigureCard,
    this.onManageSkill,
    this.onBack,
    this.contentBottomPadding = 112,
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
    this.coreRecordsOnly = false,
    this.autoLoad = true,
    this.today,
    this.onConfigureCard,
    this.onManageSkill,
    this.onBack,
    this.contentBottomPadding = 112,
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
  final bool coreRecordsOnly;
  final bool autoLoad;
  final DateTime Function()? today;
  final VoidCallback? onConfigureCard;
  final VoidCallback? onManageSkill;
  final VoidCallback? onBack;
  final double contentBottomPadding;

  @override
  State<ThemeV2AssetListPage> createState() => _ThemeV2AssetListPageState();
}

class _ThemeV2AssetListPageState extends State<ThemeV2AssetListPage> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late Map<String, RenderSpec> _specs = {...widget.specs};
  late final _AssetListRepository _repository;
  late final AssetContainerController _controller;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _repository = _AssetListRepository(
      api: _api,
      source: widget.source,
      skillName: widget.skillName,
      userSkillId: widget.meta?.userSkillId,
      cardType: widget.cardType,
      label: widget.meta?.label ?? widget.title ?? '资产',
      coreRecordsOnly: widget.coreRecordsOnly,
      specs: _specs,
      onSpecsChanged: (specs) => _specs = specs,
    );
    _controller = AssetContainerController(
      repository: _repository,
      containerId: widget.skillName ?? widget.cardType ?? 'assets',
      today: widget.today,
      initialRecords: _initialRecords(),
    );
    _scrollController = ScrollController(
      initialScrollOffset: _controller.currentScrollOffset,
    )..addListener(_rememberScrollOffset);
    if (widget.autoLoad) {
      dataRevision.addListener(_refresh);
      _controller.load();
    }
  }

  @override
  void dispose() {
    if (widget.autoLoad) dataRevision.removeListener(_refresh);
    _scrollController
      ..removeListener(_rememberScrollOffset)
      ..dispose();
    _controller.dispose();
    if (widget.api == null) _api.close();
    super.dispose();
  }

  void _refresh() => _controller.refresh();

  void _rememberScrollOffset() {
    if (_scrollController.hasClients) {
      _controller.rememberOffset(_scrollController.offset);
    }
  }

  List<AssetRecordViewModel> _initialRecords() {
    if (widget.source == AssetListSource.entities) {
      return [
        for (final entity in widget.initialEntities)
          if (widget.cardType == 'event')
            AssetRecordAdapter.event(entity: entity)
          else
            AssetRecordAdapter.contact(entity: entity),
      ];
    }
    return [
      for (final asset in widget.initialAssets)
        _adaptAsset(asset, _specs[asset.skillName]),
    ];
  }

  AssetRecordViewModel _adaptAsset(AssetItem asset, RenderSpec? sourceSpec) {
    final spec = sourceSpec ?? synthesizeSpec(asset.skillName);
    return AssetRecordAdapter.asset(
      asset: asset,
      skillLabel: widget.meta?.label ?? asset.skillName,
      spec: spec,
      renderSpec: _renderMap(spec),
      payloadSchema: _schemaMap(spec),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final tokens = context.themeV2;
        final records = _controller.records;
        return ColoredBox(
          color: Colors.transparent,
          child: ListView(
            key: PageStorageKey<String>(
              'theme-v2-assets-${widget.skillName ?? widget.cardType}',
            ),
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(
              ThemeV2Spacing.lg,
              ThemeV2Spacing.sm,
              ThemeV2Spacing.lg,
              0,
            ).copyWith(bottom: widget.contentBottomPadding),
            children: [
              _ListHeader(
                icon: widget.meta?.icon ?? _entityIcon(widget.cardType),
                title: widget.meta?.label ?? widget.title ?? '资产',
                count: _controller.isTodo
                    ? _controller.countFor(TodoAssetFilter.all)
                    : records.length,
                onConfigureCard: widget.onConfigureCard,
                onManageSkill: widget.onManageSkill,
                onBack: widget.onBack,
              ),
              if (_controller.isTodo) ...[
                const SizedBox(height: ThemeV2Spacing.lg),
                _TodoFilterTabs(
                  controller: _controller,
                  onSelected: _selectTodoFilter,
                ),
              ],
              if (_controller.loadState == AssetContainerLoadState.loading ||
                  _controller.refreshing) ...[
                const SizedBox(height: ThemeV2Spacing.md),
                LinearProgressIndicator(
                  minHeight: 2,
                  color: tokens.accent,
                  backgroundColor: tokens.accentSoft,
                ),
              ],
              if (_controller.errorMessage case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: ThemeV2Spacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(color: tokens.critical),
                        ),
                      ),
                      TextButton(
                        onPressed: _controller.refresh,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: ThemeV2Spacing.lg),
              if (records.isEmpty)
                _EmptyList(
                  label: _emptyLabel(),
                  icon: widget.meta?.icon ?? _entityIcon(widget.cardType),
                )
              else
                ..._recordWidgets(records),
              if (_controller.canLoadMore ||
                  _controller.paginationError != null)
                Padding(
                  padding: const EdgeInsets.only(top: ThemeV2Spacing.md),
                  child: TextButton(
                    onPressed: _controller.loadingMore
                        ? null
                        : _controller.loadMore,
                    child: Text(
                      _controller.paginationError ?? '加载更多',
                      style: TextStyle(
                        color: _controller.paginationError == null
                            ? tokens.accent
                            : tokens.critical,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Iterable<Widget> _recordWidgets(List<AssetRecordViewModel> records) sync* {
    DateTime? previousDate;
    for (final record in records) {
      final date = record.dueAt ?? record.effectiveAt;
      if (!_controller.isTodo || record.dueAt != null) {
        if (previousDate == null || !_sameDay(previousDate, date)) {
          yield _DateLabel(date: date);
          yield const SizedBox(height: ThemeV2Spacing.sm);
          previousDate = date;
        }
      } else if (previousDate != null) {
        yield const _UnscheduledLabel();
        yield const SizedBox(height: ThemeV2Spacing.sm);
        previousDate = null;
      }
      yield _AssetRecordRow(
        record: record,
        onOpen: () => _open(record),
        onToggleTodo: record.kind == AssetRecordKind.todo
            ? () => _toggleTodo(record.id)
            : null,
      );
      yield const SizedBox(height: ThemeV2Spacing.sm);
    }
  }

  void _selectTodoFilter(TodoAssetFilter filter) {
    _rememberScrollOffset();
    _controller.selectTodoFilter(filter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      _scrollController.jumpTo(
        _controller.currentScrollOffset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> _toggleTodo(String id) async {
    try {
      await _controller.toggleTodo(id);
      bumpData();
    } catch (_) {
      // The controller restores the exact record and exposes an inline error.
    }
  }

  String _emptyLabel() {
    if (!_controller.isTodo) {
      return widget.meta?.label ?? widget.title ?? '资产';
    }
    return switch (_controller.filter) {
      TodoAssetFilter.all => '待办',
      TodoAssetFilter.today => '今天的待办',
      TodoAssetFilter.completed => '已完成待办',
      TodoAssetFilter.unscheduled => '待安排待办',
    };
  }

  Future<void> _open(AssetRecordViewModel record) async {
    final kind = switch (record.kind) {
      AssetRecordKind.event => AssetEntityKind.event,
      AssetRecordKind.contact => AssetEntityKind.contact,
      _ => AssetEntityKind.asset,
    };
    await openAssetDetail(
      context,
      AssetEntityRef(kind: kind, id: record.id),
      repository: ApiAssetDetailRepository(
        _api,
        coreRecordsOnly: widget.coreRecordsOnly,
      ),
    );
  }
}

class _AssetListRepository implements AssetContainerRepository {
  _AssetListRepository({
    required this.api,
    required this.source,
    required this.skillName,
    required this.userSkillId,
    required this.cardType,
    required this.label,
    required this.coreRecordsOnly,
    required Map<String, RenderSpec> specs,
    required this.onSpecsChanged,
  }) : _specs = specs;

  final ApiClient api;
  final AssetListSource source;
  final String? skillName;
  final String? userSkillId;
  final String? cardType;
  final String label;
  final bool coreRecordsOnly;
  final ValueChanged<Map<String, RenderSpec>> onSpecsChanged;
  Map<String, RenderSpec> _specs;
  final Map<String, Map<String, dynamic>> _payloadsById = {};
  bool _usesCoreContract = false;

  @override
  Future<AssetContainerPage> load({String? cursor}) async {
    if (source == AssetListSource.entities) {
      final type = cardType!;
      final key = type == 'event' ? 'events' : 'contacts';
      final responses = await Future.wait<Object?>([
        api.getJson('/api/$key'),
        _fetchEntityPresentation(),
      ]);
      final response = responses[0];
      final presentation = responses[1] as _EntityPresentation?;
      final rows = _responseRows(response, key);
      return AssetContainerPage(
        records: [
          for (final item in rows.whereType<Map>())
            _adaptEntity(item.cast<String, dynamic>(), presentation),
        ],
      );
    }

    final responses = await Future.wait<Object?>([
      api.getJson(
        '/api/assets',
        query: {
          'user_skill_name': ?skillName,
          'user_skill_id': ?userSkillId,
          'cursor': ?cursor,
          'limit': 100,
        },
      ),
      _fetchSpecsSafely(),
    ]);
    final refreshed = responses[1] as Map<String, RenderSpec>;
    if (refreshed.isNotEmpty) {
      _specs = {..._specs, ...refreshed};
      onSpecsChanged(_specs);
    }
    final response = responses[0];
    _usesCoreContract = coreRecordsOnly || response is List;
    final rows = _responseRows(response, 'assets');
    for (final item in rows.whereType<Map>()) {
      final id = item['id']?.toString();
      final payload = (item['payload'] as Map?)?.cast<String, dynamic>();
      if (id != null && payload != null) _payloadsById[id] = payload;
    }
    return AssetContainerPage(
      records: [
        for (final item in rows.whereType<Map>())
          _adapt(
            AssetItem.fromJson({
              ...item.cast<String, dynamic>(),
              if (item['user_skill_name'] == null && skillName != null)
                'user_skill_name': skillName,
            }),
          ),
      ],
      nextCursor: response is Map ? response['next_cursor']?.toString() : null,
    );
  }

  List _responseRows(dynamic response, String key) => switch (response) {
    List value => value,
    Map value => value[key] as List? ?? const [],
    _ => const [],
  };

  AssetRecordViewModel _adaptEntity(
    Map<String, dynamic> entity,
    _EntityPresentation? presentation,
  ) {
    final type = cardType!;
    if (type == 'event') {
      return AssetRecordAdapter.event(
        entity: entity,
        spec: presentation?.spec,
        renderSpec: presentation?.renderSpec ?? const {},
        skillLabel: presentation?.label ?? label,
      );
    }
    return AssetRecordAdapter.contact(
      entity: entity,
      spec: presentation?.spec,
      renderSpec: presentation?.renderSpec ?? const {},
      skillLabel: presentation?.label ?? label,
    );
  }

  Future<_EntityPresentation?> _fetchEntityPresentation() async {
    try {
      final response = await api.getJson('/api/user-skills');
      for (final raw in _responseRows(response, 'skills').whereType<Map>()) {
        final row = raw.cast<String, dynamic>();
        final name = (row['machine_name'] ?? row['name'])?.toString();
        if (name != cardType) continue;
        final renderSpec =
            (row['render_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
        if (renderSpec.isEmpty) return null;
        final schema = row['schema'] ?? row['payload_schema'];
        final canonicalIcon = cardType == 'event'
            ? eventAssetIcon
            : contactAssetIcon;
        final spec = RenderSpec.fromJson(
          renderSpec,
        ).withSchema(schema).copyWith(icon: canonicalIcon);
        return _EntityPresentation(
          spec: spec,
          renderSpec: renderSpec,
          label: row['display_name']?.toString().trim().isNotEmpty == true
              ? row['display_name'].toString().trim()
              : label,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  AssetRecordViewModel _adapt(AssetItem asset) {
    final spec = _specs[asset.skillName] ?? synthesizeSpec(asset.skillName);
    return AssetRecordAdapter.asset(
      asset: asset,
      skillLabel: label,
      spec: spec,
      renderSpec: _renderMap(spec),
      payloadSchema: _schemaMap(spec),
    );
  }

  Future<Map<String, RenderSpec>> _fetchSpecsSafely() async {
    try {
      return await fetchRenderSpecs(api, coreRecordsOnly: coreRecordsOnly);
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> setTodoCompleted(String id, bool completed) async {
    if (!_usesCoreContract) {
      await api.putJson('/api/assets/$id', {
        'payload_patch': {'status': completed ? 'done' : 'pending'},
      });
      return;
    }
    final payload = {
      ...?_payloadsById[id],
      'status': completed ? 'done' : 'pending',
    };
    await api.patchJson('/api/assets/$id', {'payload': payload});
    _payloadsById[id] = payload;
  }
}

class _EntityPresentation {
  const _EntityPresentation({
    required this.spec,
    required this.renderSpec,
    required this.label,
  });

  final RenderSpec spec;
  final Map<String, dynamic> renderSpec;
  final String label;
}

class _TodoFilterTabs extends StatelessWidget {
  const _TodoFilterTabs({required this.controller, required this.onSelected});

  final AssetContainerController controller;
  final ValueChanged<TodoAssetFilter> onSelected;

  static const _items = [
    (TodoAssetFilter.all, '全部', 'all'),
    (TodoAssetFilter.today, '今天', 'today'),
    (TodoAssetFilter.completed, '已完成', 'completed'),
    (TodoAssetFilter.unscheduled, '待安排', 'unscheduled'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return SizedBox(
      height: ThemeV2Sizes.minTouchTarget,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < _items.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            Expanded(
              child: Material(
                color: controller.filter == _items[index].$1
                    ? tokens.foreground
                    : tokens.surface,
                shape: StadiumBorder(side: BorderSide(color: tokens.border)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('todo-filter-${_items[index].$3}'),
                  onTap: () => onSelected(_items[index].$1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _items[index].$2,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          style: TextStyle(
                            color: controller.filter == _items[index].$1
                                ? tokens.background
                                : tokens.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${controller.countFor(_items[index].$1)}',
                        style: ThemeV2Typography.mono(
                          fontSize: 9,
                          color: controller.filter == _items[index].$1
                              ? tokens.background.withValues(alpha: 0.7)
                              : tokens.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssetRecordRow extends StatelessWidget {
  const _AssetRecordRow({
    required this.record,
    required this.onOpen,
    this.onToggleTodo,
  });

  final AssetRecordViewModel record;
  final VoidCallback onOpen;
  final VoidCallback? onToggleTodo;

  @override
  Widget build(BuildContext context) {
    late final Widget row;
    if (onToggleTodo == null) {
      row = ThemeV2AssetCard(
        key: ValueKey('asset-record-${record.id}'),
        variant: AssetCardVariant.richCard,
        data: record.card,
        height: record.kind == AssetRecordKind.custom ? 98 : 86,
        onOpen: onOpen,
      );
    } else {
      final tokens = context.themeV2;
      row = Row(
        children: [
          Semantics(
            label: record.completed ? '重新打开待办' : '完成待办',
            button: true,
            child: ThemeV2HitTarget(
              child: IconButton(
                key: ValueKey('todo-complete-${record.id}'),
                onPressed: onToggleTodo,
                icon: Icon(
                  record.completed
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: record.completed ? tokens.accent : tokens.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: ThemeV2Spacing.xs),
          Expanded(
            child: ThemeV2AssetCard(
              key: ValueKey('asset-record-${record.id}'),
              variant: AssetCardVariant.richCard,
              data: record.card,
              height: 66,
              onOpen: onOpen,
            ),
          ),
        ],
      );
    }
    return ThemeV2DitherSourceReporter(
      id: 'library-asset-${record.id}',
      shape: ThemeV2DitherSourceShape.capsule,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(ThemeV2Radii.md),
        child: ThemeV2ContentSurface(
          key: ValueKey('asset-list-content-surface-${record.id}'),
          opacity: ThemeV2ContentOpacity.card,
          child: row,
        ),
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.icon,
    required this.title,
    required this.count,
    this.onConfigureCard,
    this.onManageSkill,
    this.onBack,
  });

  final String icon;
  final String title;
  final int count;
  final VoidCallback? onConfigureCard;
  final VoidCallback? onManageSkill;
  final VoidCallback? onBack;

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
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
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
            if (onConfigureCard != null)
              ThemeV2IconButton(
                semanticLabel: 'Card Display Settings',
                icon: Icons.tune,
                onPressed: onConfigureCard,
              ),
            if (onManageSkill != null)
              ThemeV2IconButton(
                key: const ValueKey('custom-skill-edit'),
                semanticLabel: '编辑或删除 Skill',
                icon: Icons.more_vert,
                onPressed: onManageSkill,
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

class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Text(
      _date(date),
      style: ThemeV2Typography.mono(
        fontSize: 9,
        color: context.themeV2.muted,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _UnscheduledLabel extends StatelessWidget {
  const _UnscheduledLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      '待安排',
      style: ThemeV2Typography.mono(
        fontSize: 9,
        color: context.themeV2.muted,
        fontWeight: FontWeight.w700,
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
      constraints: const BoxConstraints(minHeight: 120),
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
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: ThemeV2Spacing.sm),
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

Map<String, dynamic> _renderMap(RenderSpec spec) => {
  'card_layout': spec.cardLayout,
  'icon': spec.icon,
  'accent_color': spec.accentColor,
  'primary_field': ?spec.primaryField,
  'primary_format': ?spec.primaryFormat,
  'secondary_field': ?spec.secondaryField,
  'secondary_format': ?spec.secondaryFormat,
  'meta_fields': [
    for (final meta in spec.metaFields)
      {'field': meta.field, 'format': ?meta.format},
  ],
};

Map<String, dynamic> _schemaMap(RenderSpec spec) => {
  for (final field in spec.schemaFields)
    field: {
      'label': spec.fieldLabels[field] ?? field,
      'type': spec.fieldTypes[field] ?? 'string',
      if (spec.requiredFields.contains(field)) 'required': true,
      if (spec.longFields.contains(field)) 'long': true,
    },
};

String _date(DateTime date) =>
    '${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';

String _entityIcon(String? cardType) =>
    cardType == 'event' ? eventAssetIcon : contactAssetIcon;

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
