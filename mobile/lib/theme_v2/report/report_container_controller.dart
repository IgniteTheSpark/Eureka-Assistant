import 'package:flutter/foundation.dart';

import 'report_repository.dart';

enum ReportContainerStatus {
  idle,
  loading,
  ready,
  partial,
  empty,
  offline,
  error,
}

class ReportContainerController extends ChangeNotifier {
  ReportContainerController({required this.repository});

  final ReportRepository repository;

  ReportContainerStatus _status = ReportContainerStatus.idle;
  ReportOverview? _overview;
  String? _errorMessage;
  var _loadRevision = 0;
  var _disposed = false;

  ReportContainerStatus get status => _status;
  ReportOverview? get overview => _overview;
  String? get errorMessage => _errorMessage;

  List<ReportRunSummary> get pendingDecisionRuns => [
    for (final run in _overview?.activeRuns ?? const <ReportRunSummary>[])
      if (run.needsDecision) run,
  ];

  List<ReportRunSummary> get inProgressRuns => [
    for (final run in _overview?.activeRuns ?? const <ReportRunSummary>[])
      if (!run.needsDecision) run,
  ];

  List<CompletedReportSummary> get completedReports =>
      _overview?.completedReports ?? const [];

  String? get statusMessage =>
      _status == ReportContainerStatus.partial ? '部分报告内容加载失败，可重试刷新' : null;

  Future<void> load() async {
    if (_disposed) return;
    final revision = ++_loadRevision;
    _status = ReportContainerStatus.loading;
    _errorMessage = null;
    _notify();
    try {
      final next = await repository.loadOverview();
      if (!_isCurrent(revision)) return;
      _overview = next;
      _status = next.failedSources.isNotEmpty
          ? ReportContainerStatus.partial
          : next.isEmpty
          ? ReportContainerStatus.empty
          : ReportContainerStatus.ready;
    } on ReportLoadFailure catch (error) {
      if (!_isCurrent(revision)) return;
      _errorMessage = error.message;
      if (_overview != null) {
        _status = ReportContainerStatus.partial;
      } else {
        _status = error.isOffline
            ? ReportContainerStatus.offline
            : ReportContainerStatus.error;
      }
    } catch (error) {
      if (!_isCurrent(revision)) return;
      _errorMessage = error.toString();
      _status = _overview == null
          ? ReportContainerStatus.error
          : ReportContainerStatus.partial;
    }
    _notify();
  }

  Future<void> retry() => load();

  bool _isCurrent(int revision) => !_disposed && revision == _loadRevision;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadRevision++;
    super.dispose();
  }
}
