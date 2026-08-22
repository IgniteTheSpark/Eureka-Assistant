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
  String get intent => _run?['intent']?.toString().trim() ?? '';
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
  bool get scopeRequiresReconfirmation =>
      pendingDecision['requires_reconfirmation'] == true;
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

  Future<void> loadScopeCandidates({Map<String, dynamic>? timeRange}) async {
    final id = runId;
    if (_disposed || id.isEmpty || busy) return;
    busy = true;
    error = null;
    final previousDraft = scopeDraft;
    _notify();
    try {
      final response = await _api.getJson(
        '/api/report-generation-runs/$id/scope-candidates',
        query: timeRange == null
            ? null
            : {'from': timeRange['from'], 'to': timeRange['to']},
      );
      if (response is! Map) {
        throw const FormatException('报告范围候选项返回格式不正确');
      }
      final candidates = ReportScopeCandidateResponseView.fromJson(
        response.cast<String, dynamic>(),
      );
      _scopeCandidates = candidates;
      if (timeRange != null && previousDraft != null) {
        _scopeDraftOverride = _mergeRefetchedCandidates(
          previousDraft,
          candidates,
          timeRange,
        );
      } else if (previousDraft == null || _scopeIsEmpty(previousDraft)) {
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

  Future<void> selectScopeTimeRange(ReportTimeRangeOptionView option) async {
    final current = scopeDraft;
    if (current == null || option.timeRange == null) {
      return;
    }
    await loadScopeCandidates(timeRange: option.timeRange);
  }

  ReportScopeDraftView _mergeRefetchedCandidates(
    ReportScopeDraftView current,
    ReportScopeCandidateResponseView candidates,
    Map<String, dynamic> timeRange,
  ) {
    final selectedSkillIds = current.skillIds.isEmpty
        ? candidates.recordGroups.map((group) => group.skillId).toSet()
        : current.skillIds.toSet();
    final auto = candidates.recordGroups
        .where((group) => selectedSkillIds.contains(group.skillId))
        .expand((group) => group.records)
        .map((record) => record.reference)
        .toList(growable: false);
    final selection = ReportAssetSelectionView(
      autoReferences: auto,
      manualReferences: current.selection.manualReferences,
      excludedReferenceIds: current.selection.excludedReferenceIds,
    );
    return current.copyWith(
      timeRange: timeRange,
      skillIds: selectedSkillIds.toList(growable: false),
      missingDimensions: current.missingDimensions
          .where((item) => item != 'time_range')
          .toList(growable: false),
      selection: selection,
      supportingReferences: selection.resolvedReferences,
    );
  }

  void setScopePresentationFamily(String? family) {
    final current = scopeDraft;
    if (current == null) return;
    final selected = current.presentationPreference.family == family
        ? null
        : family;
    _scopeDraftOverride = current.copyWith(
      presentationPreference: ReportPresentationPreferenceView(
        family: selected,
        customText: selected == 'custom'
            ? current.presentationPreference.customText
            : '',
      ),
    );
    error = null;
    _notify();
  }

  void updateScopeCustomPresentation(String value) {
    final current = scopeDraft;
    if (current == null) return;
    _scopeDraftOverride = current.copyWith(
      presentationPreference: ReportPresentationPreferenceView(
        family: 'custom',
        customText: value,
      ),
    );
    error = null;
    _notify();
  }

  void replaceScopeSupportingReferences(
    List<EvidenceReferenceView> references,
  ) {
    final current = scopeDraft;
    if (current == null) return;
    final auto = current.selection.autoReferences;
    final selected = references.toSet();
    final autoSet = auto.toSet();
    final excluded = current.selection.excludedReferenceIds.toSet();
    excluded.removeAll(selected.map((reference) => reference.id));
    for (final reference in auto) {
      if (selected.contains(reference)) {
        excluded.remove(reference.id);
      } else {
        excluded.add(reference.id);
      }
    }
    final selection = ReportAssetSelectionView(
      autoReferences: auto,
      manualReferences: selected.difference(autoSet).toList(growable: false),
      excludedReferenceIds: excluded.toList(growable: false),
    );
    _scopeDraftOverride = current.copyWith(
      supportingReferences: selection.resolvedReferences,
      selection: selection,
    );
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
    final groupReferences = group.records.map((item) => item.reference).toSet();
    final exclusions = current.selection.excludedReferenceIds.toSet();
    if (selected) {
      skillIds.add(skillId);
      exclusions.removeAll(groupReferences.map((item) => item.id));
    } else {
      skillIds.remove(skillId);
      exclusions.addAll(groupReferences.map((item) => item.id));
    }
    final candidateReferences = candidates.recordGroups
        .expand((item) => item.records)
        .map((item) => item.reference)
        .toSet();
    final auto = current.selection.autoReferences.isEmpty
        ? candidateReferences
        : current.selection.autoReferences.toSet();
    final selection = ReportAssetSelectionView(
      autoReferences: auto.toList(growable: false),
      manualReferences: current.selection.manualReferences,
      excludedReferenceIds: exclusions.toList(growable: false),
    );
    _scopeDraftOverride = current.copyWith(
      skillIds: skillIds.toList(growable: false),
      missingDimensions: current.missingDimensions
          .where((item) => item != 'asset_type')
          .toList(growable: false),
      supportingReferences: selection.resolvedReferences,
      selection: selection,
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
    final allCandidateReferences = candidates.recordGroups
        .expand((item) => item.records)
        .map((item) => item.reference)
        .toSet();
    final auto = current.selection.autoReferences.isEmpty
        ? allCandidateReferences
        : current.selection.autoReferences.toSet();
    final manual = references.difference(allCandidateReferences);
    final excluded = current.selection.excludedReferenceIds.toSet();
    if (selected) {
      excluded.remove(reference.id);
    } else if (auto.contains(reference)) {
      excluded.add(reference.id);
    }
    final selection = ReportAssetSelectionView(
      autoReferences: auto.toList(growable: false),
      manualReferences: manual.toList(growable: false),
      excludedReferenceIds: excluded.toList(growable: false),
    );
    _scopeDraftOverride = current.copyWith(
      skillIds: skillIds,
      supportingReferences: selection.resolvedReferences,
      selection: selection,
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
    if (scopeRequiresReconfirmation) {
      error = '数据范围已按服务器结果更新，请查看最终记录后再次确认';
      _notify();
      return;
    }
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
