import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';

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
        {'selected_option_id': optionId},
      );
      _applyRun(response);
    } catch (exception) {
      _setError(exception);
    } finally {
      _finishRequest();
    }
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
