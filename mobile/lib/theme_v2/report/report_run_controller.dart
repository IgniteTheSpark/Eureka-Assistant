import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';
import 'report_plan_models.dart';

class ReportRunController extends ChangeNotifier {
  ReportRunController({
    ApiClient? api,
    this.autoPoll = true,
    this.pollInterval = const Duration(seconds: 2),
  }) : _api = api ?? ApiClient(),
       _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;
  final bool autoPoll;
  final Duration pollInterval;

  Map<String, dynamic>? _run;
  ReportScopeCandidateResponseView? _scopeCandidates;
  ReportScopeDraftView? _scopeDraftOverride;
  String? error;
  String? cancellationError;
  bool busy = false;
  String? selectedOptionId;
  final Map<String, dynamic> clarificationAnswers = {};
  Timer? _pollTimer;
  bool _disposed = false;

  String get runId => _run?['id']?.toString() ?? '';
  String get state => _run?['state']?.toString() ?? 'idle';
  String get activeStage => _run?['active_stage']?.toString() ?? '';
  int get planRevision => (_run?['plan_revision'] as num?)?.toInt() ?? 0;
  int get scopeRevision => (_run?['scope_revision'] as num?)?.toInt() ?? 0;
  String? get reportId => _run?['report_id']?.toString();
  String? get failureMessage {
    final failure = _run?['failure'];
    if (failure is! Map) return null;
    final message = failure['message']?.toString().trim();
    return message == null || message.isEmpty ? null : message;
  }

  List<Map<String, dynamic>> get planOptions =>
      (_run?['plan_options'] as List? ?? const [])
          .whereType<Map>()
          .map((option) => option.cast<String, dynamic>())
          .toList(growable: false);
  Map<String, dynamic>? get recommendedOption {
    for (final option in planOptions) {
      if (option['recommended'] == true) return option;
    }
    return planOptions.isEmpty ? null : planOptions.first;
  }

  ReportPlanDraftView? get planDraft {
    final raw = _run?['plan_draft'];
    if (raw is Map) {
      return ReportPlanDraftView.fromJson(raw.cast<String, dynamic>());
    }
    final option = recommendedOption;
    if (option == null) return null;
    final evidence =
        (option['evidence'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return ReportPlanDraftView.fromJson({
      'selected_option_id': option['id']?.toString() ?? '',
      'evidence_scope': evidence,
      'public_research_scope': const <String, dynamic>{},
    });
  }

  Map<String, dynamic> get pendingDecision =>
      (_run?['pending_decision'] as Map?)?.cast<String, dynamic>() ?? const {};
  bool get needsClarification =>
      pendingDecision['type']?.toString() == 'clarification';
  bool get needsScopeConfirmation =>
      pendingDecision['type']?.toString() == 'scope_confirmation';
  ReportScopeCandidateResponseView? get scopeCandidates => _scopeCandidates;
  ReportScopeDraftView? get scopeDraft {
    if (_scopeDraftOverride != null) return _scopeDraftOverride;
    final raw = _run?['scope_draft'];
    if (raw is! Map) return null;
    return ReportScopeDraftView.fromJson(raw.cast<String, dynamic>());
  }

  List<Map<String, dynamic>> get clarificationQuestions =>
      (pendingDecision['questions'] as List? ?? const [])
          .whereType<Map>()
          .map((question) => question.cast<String, dynamic>())
          .toList(growable: false);
  bool get canSubmitClarification =>
      needsClarification &&
      clarificationQuestions.every((question) {
        if (question['required'] != true) return true;
        final answer = clarificationAnswers[question['id']?.toString()];
        return answer != null && answer.toString().trim().isNotEmpty;
      });
  bool get canCancel =>
      runId.isNotEmpty &&
      const {
        'planning',
        'awaiting_selection',
        'generating',
        'failed',
      }.contains(state);

  Future<void> startUserInitiated(String intent) async {
    final normalized = intent.trim();
    if (_disposed || normalized.isEmpty || busy) return;
    busy = true;
    error = null;
    cancellationError = null;
    _notify();
    try {
      final response = await _api.postJson('/api/report-generation-runs', {
        'origin': 'user_initiated',
        'intent': normalized,
      });
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  Future<void> startFromTrigger(String triggerExecutionId) async {
    if (_disposed || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.postJson('/api/report-generation-runs', {
        'origin': 'trigger',
        'trigger_execution_id': triggerExecutionId,
      });
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  Future<void> refresh() async {
    final id = runId;
    if (_disposed || id.isEmpty || busy) return;
    try {
      final response = await _api.getJson('/api/report-generation-runs/$id');
      _applyRun(response);
      _notify();
    } catch (exception) {
      _setError(exception);
      _notify();
    }
  }

  Future<void> loadRun(String id) async {
    if (_disposed || id.trim().isEmpty || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.getJson(
        '/api/report-generation-runs/${id.trim()}',
      );
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  void answerQuestion(String questionId, dynamic answer) {
    clarificationAnswers[questionId] = answer;
    error = null;
    _notify();
  }

  Future<void> submitClarification() async {
    final id = runId;
    if (_disposed || id.isEmpty || !canSubmitClarification || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.postJson(
        '/api/report-generation-runs/$id/decision',
        {'answers': Map<String, dynamic>.from(clarificationAnswers)},
      );
      clarificationAnswers.clear();
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  void selectOption(String optionId) {
    if (selectedOptionId == optionId) return;
    selectedOptionId = optionId;
    error = null;
    _notify();
  }

  Future<void> loadScopeCandidates() async {
    final id = runId;
    if (_disposed || id.isEmpty || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.getJson(
        '/api/report-generation-runs/$id/scope-candidates',
      );
      if (response is! Map) {
        throw const FormatException('报告范围候选项返回格式不正确');
      }
      final candidates = ReportScopeCandidateResponseView.fromJson(
        response.cast<String, dynamic>(),
      );
      _scopeCandidates = candidates;
      final current = scopeDraft;
      if (current == null || _scopeIsEmpty(current)) {
        _scopeDraftOverride = candidates.defaultScope;
      }
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  void selectScopeEvent(EvidenceReferenceView reference) {
    final current = scopeDraft;
    if (current == null) return;
    _scopeDraftOverride = current.copyWith(primaryReference: reference);
    error = null;
    _notify();
  }

  void updateScopeAdditionalFocus(String value) {
    final current = scopeDraft;
    if (current == null) return;
    _scopeDraftOverride = current.copyWith(additionalFocus: value);
    error = null;
    _notify();
  }

  void replaceScopeSupportingReferences(
    List<EvidenceReferenceView> references,
  ) {
    final current = scopeDraft;
    if (current == null) return;
    _scopeDraftOverride = current.copyWith(supportingReferences: references);
    error = null;
    _notify();
  }

  void toggleScopeGroup(String skillId, bool selected) {
    final current = scopeDraft;
    final candidates = scopeCandidates;
    if (current == null || candidates == null) return;
    final group = candidates.recordGroups
        .where((item) => item.skillId == skillId)
        .firstOrNull;
    if (group == null) return;
    final skillIds = current.skillIds.toSet();
    final references = current.supportingReferences.toSet();
    if (selected) {
      skillIds.add(skillId);
      references.addAll(group.records.map((item) => item.reference));
    } else {
      skillIds.remove(skillId);
      references.removeAll(group.records.map((item) => item.reference));
    }
    _scopeDraftOverride = current.copyWith(
      skillIds: skillIds.toList(growable: false),
      supportingReferences: references.toList(growable: false),
    );
    error = null;
    _notify();
  }

  void toggleScopeRecord(EvidenceReferenceView reference, bool selected) {
    final current = scopeDraft;
    final candidates = scopeCandidates;
    if (current == null || candidates == null) return;
    final references = current.supportingReferences.toSet();
    if (selected) {
      references.add(reference);
    } else {
      references.remove(reference);
    }
    final skillIds = <String>[];
    for (final group in candidates.recordGroups) {
      if (group.records.any(
        (record) => references.contains(record.reference),
      )) {
        skillIds.add(group.skillId);
      }
    }
    _scopeDraftOverride = current.copyWith(
      skillIds: skillIds,
      supportingReferences: references.toList(growable: false),
    );
    error = null;
    _notify();
  }

  Future<void> saveScopeDraft(ReportScopeDraftView draft) async {
    final id = runId;
    if (_disposed || id.isEmpty || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.putJson(
        '/api/report-generation-runs/$id/scope-draft',
        {'expected_revision': scopeRevision, 'draft': draft.toJson()},
      );
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  Future<void> preparePlan() async {
    final id = runId;
    if (_disposed || id.isEmpty || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.postJson(
        '/api/report-generation-runs/$id/prepare-plan',
        {'expected_revision': scopeRevision},
      );
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  Future<void> confirmScope(ReportScopeDraftView draft) async {
    await saveScopeDraft(draft);
    if (_disposed || error != null) return;
    await preparePlan();
  }

  Future<void> generate() async {
    final id = runId;
    final optionId = selectedOptionId;
    if (_disposed ||
        id.isEmpty ||
        optionId == null ||
        optionId.isEmpty ||
        busy) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.postJson(
        '/api/report-generation-runs/$id/generate',
        {
          'selected_option_id': optionId,
          'expected_plan_revision': planRevision,
        },
      );
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  Future<void> quickGenerate() async {
    final recommendedId = recommendedOption?['id']?.toString();
    if (recommendedId != null && recommendedId.isNotEmpty) {
      selectedOptionId = recommendedId;
    }
    await generate();
  }

  Future<void> generateConfirmedDraft() async {
    final draft = planDraft;
    if (draft == null || draft.blockers.isNotEmpty) return;
    selectedOptionId = draft.selectedOptionId;
    await generate();
  }

  Future<void> updateDraft(ReportPlanDraftView draft) async {
    final id = runId;
    if (_disposed || id.isEmpty || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.putJson(
        '/api/report-generation-runs/$id/plan-draft',
        draft.toUpdateJson(planRevision),
      );
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  Future<ReportEvidenceOptionPage> loadEvidenceOptions({
    String query = '',
    String type = 'all',
    String? skill,
    String? cursor,
  }) async {
    final response = await _api.getJson(
      '/api/report-generation-runs/evidence-options',
      query: {
        'q': query,
        'type': type,
        if (skill != null && skill.isNotEmpty) 'skill': skill,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': 50,
      },
    );
    if (response is! Map) {
      throw const FormatException('报告资产列表返回格式不正确');
    }
    return ReportEvidenceOptionPage.fromJson(response.cast<String, dynamic>());
  }

  Future<void> retry() async {
    final id = runId;
    if (_disposed || id.isEmpty || busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      final response = await _api.postJson(
        '/api/report-generation-runs/$id/retry',
        const {},
      );
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
  }

  Future<void> cancel() async {
    final id = runId;
    if (_disposed || !canCancel || busy) return;
    busy = true;
    error = null;
    cancellationError = null;
    _notify();
    try {
      final response = await _api.postJson(
        '/api/report-generation-runs/$id/cancel',
        const {},
      );
      _applyRun(response);
    } catch (exception) {
      if (!_disposed) cancellationError = _errorMessage(exception);
    } finally {
      _finishRequest();
    }
  }

  Future<Map<String, dynamic>?> loadReport() async {
    final id = reportId;
    if (id == null || id.isEmpty) return null;
    final response = await _api.getJson('/api/reports/$id');
    return response is Map ? response.cast<String, dynamic>() : null;
  }

  void _applyRun(dynamic response) {
    if (_disposed) return;
    if (response is! Map) {
      throw const FormatException('报告任务返回格式不正确');
    }
    final previousRunId = runId;
    final previousScopeRevision = scopeRevision;
    _run = response.cast<String, dynamic>();
    if (previousRunId != runId) {
      _scopeCandidates = null;
      _scopeDraftOverride = null;
    } else if (previousScopeRevision != scopeRevision) {
      final rawScope = _run?['scope_draft'];
      _scopeDraftOverride = rawScope is Map
          ? ReportScopeDraftView.fromJson(rawScope.cast<String, dynamic>())
          : null;
    }
    error = null;
    if (!needsClarification) clarificationAnswers.clear();
    final options = planOptions;
    if (selectedOptionId == null ||
        !options.any((option) => option['id'] == selectedOptionId)) {
      Map<String, dynamic>? recommended;
      for (final option in options) {
        if (option['recommended'] == true) {
          recommended = option;
          break;
        }
      }
      selectedOptionId =
          (recommended ?? (options.isEmpty ? null : options.first))?['id']
              ?.toString();
    }
    _schedulePoll();
  }

  bool _scopeIsEmpty(ReportScopeDraftView draft) =>
      draft.primaryReference == null &&
      draft.supportingReferences.isEmpty &&
      draft.skillIds.isEmpty &&
      draft.attentionFocus.isEmpty &&
      draft.additionalFocus.trim().isEmpty;

  void _schedulePoll() {
    if (_disposed) return;
    _pollTimer?.cancel();
    if (!autoPoll || !const {'planning', 'generating'}.contains(state)) return;
    _pollTimer = Timer(pollInterval, refresh);
  }

  void _setError(Object exception) {
    if (_disposed) return;
    _pollTimer?.cancel();
    error = _errorMessage(exception);
  }

  String _errorMessage(Object exception) => switch (exception) {
    ApiException(statusCode: 410) => '这次报告任务已经过期',
    ApiException(statusCode: 503) => '报告服务尚未配置完成',
    ApiException(statusCode: 409) => '报告方案已更新，请查看最新内容后重试',
    ApiException() => '报告任务暂时无法处理，请稍后重试',
    _ => '报告任务暂时无法处理，请稍后重试',
  };

  void _finishRequest() {
    if (_disposed) return;
    busy = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    if (_ownsApi) _api.close();
    super.dispose();
  }
}
