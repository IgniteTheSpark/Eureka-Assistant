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
    _run = response.cast<String, dynamic>();
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
