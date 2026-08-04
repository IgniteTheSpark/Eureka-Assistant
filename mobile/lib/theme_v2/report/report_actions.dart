import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../theme/eureka_colors.dart';

@immutable
class ReportActionItem {
  const ReportActionItem({
    required this.id,
    required this.title,
    required this.dueAt,
    required this.created,
    required this.todoAssetId,
  });

  final String id;
  final String title;
  final DateTime? dueAt;
  final bool created;
  final String? todoAssetId;

  static ReportActionItem? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final title = json['title']?.toString().trim() ?? '';
    if (id.isEmpty || title.isEmpty) return null;
    final todoAssetId = _optionalString(json['todo_asset_id']);
    return ReportActionItem(
      id: id,
      title: title,
      dueAt: DateTime.tryParse(json['due_at']?.toString() ?? '')?.toLocal(),
      created: json['created'] == true || todoAssetId != null,
      todoAssetId: todoAssetId,
    );
  }
}

String? _optionalString(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

class ReportActionsController extends ChangeNotifier {
  ReportActionsController({
    ApiClient? api,
    FutureOr<void> Function()? onTodoCreated,
  }) : _api = api ?? ApiClient(),
       _ownsApi = api == null,
       _onTodoCreated = onTodoCreated;

  final ApiClient _api;
  final bool _ownsApi;
  final FutureOr<void> Function()? _onTodoCreated;
  final Set<String> _adding = <String>{};
  List<ReportActionItem> _actions = const [];
  bool _loading = false;
  String? _errorMessage;

  List<ReportActionItem> get actions => List.unmodifiable(_actions);
  bool get loading => _loading;
  String? get errorMessage => _errorMessage;
  int get pendingCount => _actions.where((action) => !action.created).length;
  bool isAdding(String actionId) => _adding.contains(actionId);
  bool get adding => _adding.isNotEmpty;

  Future<void> load(String reportId) async {
    if (_loading) return;
    _loading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _api.getJson('/api/reports/$reportId/actions');
      final raw = response is Map ? response['actions'] : null;
      _actions = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (item) => ReportActionItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .whereType<ReportActionItem>()
                .toList(growable: false)
          : const [];
    } catch (_) {
      _actions = const [];
      _errorMessage = '行动暂时无法加载';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> add(String reportId, String actionId) async {
    if (_adding.contains(actionId)) return false;
    final index = _actions.indexWhere((action) => action.id == actionId);
    if (index < 0 || _actions[index].created) return false;
    _adding.add(actionId);
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _api.postJson(
        '/api/reports/$reportId/actions/$actionId',
        const <String, dynamic>{},
      );
      if (response is! Map) throw const FormatException('Invalid action');
      final returned = ReportActionItem.fromJson(
        Map<String, dynamic>.from(response),
      );
      if (returned == null || returned.id != actionId) {
        throw const FormatException('Invalid action');
      }
      _actions = [
        for (final action in _actions)
          if (action.id == actionId) returned else action,
      ];
      if (response['created'] == true) {
        await _onTodoCreated?.call();
      }
      return true;
    } catch (_) {
      _errorMessage = '加入待办失败，请稍后重试';
      return false;
    } finally {
      _adding.remove(actionId);
      notifyListeners();
    }
  }

  Future<void> addAll(String reportId) async {
    var failed = false;
    final ids = _actions
        .where((action) => !action.created)
        .map((action) => action.id)
        .toList(growable: false);
    for (final id in ids) {
      if (!await add(reportId, id)) failed = true;
    }
    if (failed) {
      _errorMessage = '部分行动未能加入待办，请稍后重试';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    super.dispose();
  }
}

class ReportActionsTray extends StatelessWidget {
  const ReportActionsTray({
    super.key,
    required this.reportId,
    required this.controller,
    required this.colors,
  });

  final String reportId;
  final ReportActionsController controller;
  final EurekaColors colors;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.actions.isEmpty && !controller.loading) {
        return const SizedBox.shrink();
      }
      return Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.rule)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      children: [
                        Text(
                          '✦ 接下来',
                          maxLines: 1,
                          style: TextStyle(
                            color: colors.brand,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const Spacer(),
                        if (controller.pendingCount >= 2)
                          TextButton(
                            key: const ValueKey('report-actions-add-all'),
                            onPressed: controller.adding
                                ? null
                                : () => controller.addAll(reportId),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                            child: const Text('全部加入待办'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (controller.loading)
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: colors.brand,
                    backgroundColor: Colors.transparent,
                  ),
                if (controller.errorMessage case final error?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error,
                        style: TextStyle(color: colors.accentRed, fontSize: 12),
                      ),
                    ),
                  ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: controller.actions.length,
                    itemBuilder: (context, index) {
                      final action = controller.actions[index];
                      return _ReportActionRow(
                        key: ValueKey('report-action-${action.id}'),
                        reportId: reportId,
                        action: action,
                        controller: controller,
                        colors: colors,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ReportActionRow extends StatelessWidget {
  const _ReportActionRow({
    super.key,
    required this.reportId,
    required this.action,
    required this.controller,
    required this.colors,
  });

  final String reportId;
  final ReportActionItem action;
  final ReportActionsController controller;
  final EurekaColors colors;

  @override
  Widget build(BuildContext context) {
    final busy = controller.isAdding(action.id);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
        child: Row(
          children: [
            Icon(
              action.created
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: action.created ? colors.brand : colors.textLo,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textHi, fontSize: 13.5),
                  ),
                  if (action.dueAt case final due?)
                    Text(
                      _dueLabel(due),
                      style: TextStyle(color: colors.textLo, fontSize: 11),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (action.created)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '已加入',
                  style: TextStyle(color: colors.textLo, fontSize: 12),
                ),
              )
            else
              OutlinedButton(
                key: ValueKey('report-action-add-${action.id}'),
                onPressed: busy
                    ? null
                    : () => controller.add(reportId, action.id),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.brand,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: colors.brand.withValues(alpha: 0.5)),
                ),
                child: Text(busy ? '加入中…' : '加入待办'),
              ),
          ],
        ),
      ),
    );
  }
}

String _dueLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.month}月${local.day}日 ${two(local.hour)}:${two(local.minute)}';
}
