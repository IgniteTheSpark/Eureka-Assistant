import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/theme_v2_tokens.dart';
import 'report_plan_models.dart';

typedef ReportEvidenceLoader =
    Future<ReportEvidenceOptionPage> Function({
      String query,
      String type,
      String? skill,
      String? cursor,
    });

class ReportEvidencePickerPage extends StatefulWidget {
  const ReportEvidencePickerPage({
    super.key,
    required this.loadPage,
    this.initialSelected = const [],
  });

  final ReportEvidenceLoader loadPage;
  final List<EvidenceReferenceView> initialSelected;

  @override
  State<ReportEvidencePickerPage> createState() =>
      _ReportEvidencePickerPageState();
}

class _ReportEvidencePickerPageState extends State<ReportEvidencePickerPage> {
  final _searchController = TextEditingController();
  final Map<String, EvidenceReferenceView> _selected = {};
  final Map<String, ReportEvidenceOption> _known = {};
  List<ReportEvidenceOption> _items = const [];
  List<Map<String, String>> _filters = const [
    {'id': 'all', 'label': '全部'},
  ];
  String _filterId = 'all';
  String? _nextCursor;
  Object? _error;
  bool _loading = true;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    for (final reference in widget.initialSelected) {
      _selected[reference.key] = reference;
    }
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  ({String type, String? skill}) get _requestFilter => switch (_filterId) {
    'all' => (type: 'all', skill: null),
    'event' => (type: 'event', skill: null),
    'contact' => (type: 'contact', skill: null),
    _ => (type: 'asset', skill: _filterId),
  };

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final filter = _requestFilter;
      final page = await widget.loadPage(
        query: _searchController.text.trim(),
        type: filter.type,
        skill: filter.skill,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        for (final item in page.items) {
          _known[item.reference.key] = item;
        }
        if (page.filters.isNotEmpty) _filters = page.filters;
        _nextCursor = page.nextCursor;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  void _searchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_load(reset: true)),
    );
  }

  void _toggle(ReportEvidenceOption option) {
    setState(() {
      if (_selected.containsKey(option.reference.key)) {
        _selected.remove(option.reference.key);
      } else {
        _selected[option.reference.key] = option.reference;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('参考资产'),
      leading: IconButton(
        key: const ValueKey('report-evidence-cancel'),
        tooltip: '取消',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close_rounded),
      ),
      actions: [
        TextButton(
          key: const ValueKey('report-evidence-confirm'),
          onPressed: () => Navigator.of(
            context,
          ).pop(_selected.values.toList(growable: false)),
          child: Text('完成 ${_selected.length}'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeV2Spacing.lg,
              ThemeV2Spacing.sm,
              ThemeV2Spacing.lg,
              ThemeV2Spacing.sm,
            ),
            child: TextField(
              key: const ValueKey('report-evidence-search'),
              controller: _searchController,
              onChanged: _searchChanged,
              decoration: const InputDecoration(
                hintText: '搜索日程、联系人或记录',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeV2Spacing.lg,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: ThemeV2Spacing.sm),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final id = filter['id'] ?? 'all';
                return ChoiceChip(
                  key: ValueKey('report-evidence-filter-$id'),
                  label: Text(filter['label'] ?? id),
                  selected: id == _filterId,
                  onSelected: (_) {
                    setState(() => _filterId = id);
                    unawaited(_load(reset: true));
                  },
                );
              },
            ),
          ),
          if (_selected.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeV2Spacing.lg,
                  vertical: ThemeV2Spacing.sm,
                ),
                children: [
                  for (final entry in _selected.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: ThemeV2Spacing.sm),
                      child: InputChip(
                        key: ValueKey('selected-${entry.key}'),
                        label: Text(
                          _known[entry.key]?.title ??
                              switch (entry.value.kind) {
                                'event' => '日程',
                                'contact' => '联系人',
                                _ => '资产',
                              },
                        ),
                        onDeleted: () =>
                            setState(() => _selected.remove(entry.key)),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _content()),
        ],
      ),
    ),
  );

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: FilledButton(
          onPressed: () => unawaited(_load(reset: true)),
          child: const Text('重新加载'),
        ),
      );
    }
    if (_items.isEmpty) return const Center(child: Text('没有符合条件的资产'));
    return ListView.builder(
      itemCount: _items.length + (_nextCursor == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return Padding(
            padding: const EdgeInsets.all(ThemeV2Spacing.lg),
            child: OutlinedButton(
              key: const ValueKey('report-evidence-load-more'),
              onPressed: () => unawaited(_load(reset: false)),
              child: const Text('加载更多'),
            ),
          );
        }
        final option = _items[index];
        final selected = _selected.containsKey(option.reference.key);
        return ListTile(
          key: ValueKey('evidence-${option.reference.key}'),
          onTap: () => _toggle(option),
          leading: Text(option.icon, style: const TextStyle(fontSize: 22)),
          title: Text(
            option.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [option.typeLabel, option.subtitle]
                .whereType<String>()
                .where((value) => value.isNotEmpty)
                .join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
          ),
        );
      },
    );
  }
}
