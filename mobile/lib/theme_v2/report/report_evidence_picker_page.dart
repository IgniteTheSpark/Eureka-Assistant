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

Color _pickerSurface(BuildContext context) =>
    Theme.of(context).extension<ThemeV2Tokens>()?.surface ??
    Theme.of(context).colorScheme.surface;

Future<List<EvidenceReferenceView>?> showReportEvidencePickerSheet(
  BuildContext context, {
  required ReportEvidenceLoader loadPage,
  List<EvidenceReferenceView> initialSelected = const [],
  String? initialSkillId,
}) => showReportEvidencePickerPage(
  context,
  loadPage: loadPage,
  initialSelected: initialSelected,
  initialSkillId: initialSkillId,
);

Future<List<EvidenceReferenceView>?> showReportEvidencePickerPage(
  BuildContext context, {
  required ReportEvidenceLoader loadPage,
  List<EvidenceReferenceView> initialSelected = const [],
  String? initialSkillId,
}) => Navigator.of(context).push<List<EvidenceReferenceView>>(
  MaterialPageRoute<List<EvidenceReferenceView>>(
    fullscreenDialog: true,
    builder: (_) => ReportEvidencePickerPage(
      loadPage: loadPage,
      initialSelected: initialSelected,
      initialSkillId: initialSkillId,
    ),
  ),
);

class ReportEvidencePickerPage extends StatefulWidget {
  const ReportEvidencePickerPage({
    super.key,
    required this.loadPage,
    this.initialSelected = const [],
    this.initialSkillId,
  });

  final ReportEvidenceLoader loadPage;
  final List<EvidenceReferenceView> initialSelected;
  final String? initialSkillId;

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
    _filterId = widget.initialSkillId ?? 'all';
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

  Future<void> _reviewSelected() async {
    final reviewed = await Navigator.of(context)
        .push<List<EvidenceReferenceView>>(
          MaterialPageRoute<List<EvidenceReferenceView>>(
            builder: (_) => _SelectedEvidenceReviewPage(
              selected: _selected.values.toList(growable: false),
              known: Map<String, ReportEvidenceOption>.from(_known),
            ),
          ),
        );
    if (!mounted || reviewed == null) return;
    setState(() {
      _selected
        ..clear()
        ..addEntries(reviewed.map((item) => MapEntry(item.key, item)));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _pickerSurface(context),
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: _pickerSurface(context),
      title: const Text('参考资产'),
      leading: IconButton(
        key: const ValueKey('report-evidence-cancel'),
        tooltip: '取消',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close_rounded),
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.lg,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.lg,
          ThemeV2Spacing.md,
        ),
        decoration: BoxDecoration(
          color: _pickerSurface(context),
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                key: const ValueKey('report-evidence-selected-review'),
                onPressed: _selected.isEmpty ? null : _reviewSelected,
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                child: Text('已选择 ${_selected.length} 项'),
              ),
            ),
            const SizedBox(width: ThemeV2Spacing.sm),
            FilledButton(
              key: const ValueKey('report-evidence-confirm'),
              onPressed: () => Navigator.of(
                context,
              ).pop(_selected.values.toList(growable: false)),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.lg),
            child: Wrap(
              key: const ValueKey('report-evidence-filter-wrap'),
              spacing: ThemeV2Spacing.sm,
              runSpacing: ThemeV2Spacing.sm,
              children: [
                for (final filter in _filters)
                  ChoiceChip(
                    key: ValueKey(
                      'report-evidence-filter-${filter['id'] ?? 'all'}',
                    ),
                    label: Text(filter['label'] ?? filter['id'] ?? '全部'),
                    selected: (filter['id'] ?? 'all') == _filterId,
                    onSelected: (_) {
                      setState(() => _filterId = filter['id'] ?? 'all');
                      unawaited(_load(reset: true));
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
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
          subtitle: (option.subtitle ?? '').trim().isEmpty
              ? null
              : Text(
                  option.subtitle!,
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

class _SelectedEvidenceReviewPage extends StatefulWidget {
  const _SelectedEvidenceReviewPage({
    required this.selected,
    required this.known,
  });

  final List<EvidenceReferenceView> selected;
  final Map<String, ReportEvidenceOption> known;

  @override
  State<_SelectedEvidenceReviewPage> createState() =>
      _SelectedEvidenceReviewPageState();
}

class _SelectedEvidenceReviewPageState
    extends State<_SelectedEvidenceReviewPage> {
  late final Map<String, EvidenceReferenceView> _selected = {
    for (final item in widget.selected) item.key: item,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _pickerSurface(context),
    appBar: AppBar(
      backgroundColor: _pickerSurface(context),
      title: const Text('已选资产'),
      actions: [
        TextButton(
          key: const ValueKey('report-evidence-review-done'),
          onPressed: () => Navigator.of(
            context,
          ).pop(_selected.values.toList(growable: false)),
          child: const Text('完成'),
        ),
      ],
    ),
    body: _selected.isEmpty
        ? const Center(child: Text('还没有选择资产'))
        : ListView(
            children: [
              for (final entry in _selected.entries)
                ListTile(
                  leading: Text(
                    widget.known[entry.key]?.icon ?? '•',
                    style: const TextStyle(fontSize: 22),
                  ),
                  title: Text(
                    widget.known[entry.key]?.title ??
                        switch (entry.value.kind) {
                          'event' => '日程',
                          'contact' => '联系人',
                          _ => '资产',
                        },
                  ),
                  subtitle:
                      (widget.known[entry.key]?.subtitle ?? '').trim().isEmpty
                      ? null
                      : Text(widget.known[entry.key]!.subtitle!),
                  trailing: IconButton(
                    key: ValueKey('report-evidence-review-remove-${entry.key}'),
                    tooltip: '移除',
                    onPressed: () =>
                        setState(() => _selected.remove(entry.key)),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                ),
            ],
          ),
  );
}
