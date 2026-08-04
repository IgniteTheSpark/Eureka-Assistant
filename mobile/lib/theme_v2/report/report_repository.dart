import 'dart:io';

import 'package:http/http.dart' as http;

import '../../api/api_client.dart';
import 'report_models.dart';

export 'report_models.dart';

abstract interface class ReportRepository {
  Future<ReportOverview> loadOverview();
}

class ApiReportRepository implements ReportRepository {
  ApiReportRepository(this.api);

  final ApiClient api;

  @override
  Future<ReportOverview> loadOverview() async {
    final sources = await Future.wait([
      _capture(
        'runs',
        () => api.getJson(
          '/api/report-generation-runs',
          query: const {'active': true},
        ),
      ),
      _capture('reports', () => api.getJson('/api/reports')),
    ]);
    final failures = [
      for (final source in sources)
        if (source.failure != null) source.failure!,
    ];
    if (failures.length == sources.length) {
      throw ReportLoadFailure(
        '报告暂时无法加载',
        isOffline: failures.every((failure) => failure.isOffline),
      );
    }

    return ReportOverview(
      activeRuns: _rows(sources[0].value)
          .map(ReportRunSummary.fromJson)
          .whereType<ReportRunSummary>()
          .toList(growable: false),
      completedReports: _rows(sources[1].value)
          .map(CompletedReportSummary.fromJson)
          .whereType<CompletedReportSummary>()
          .toList(growable: false),
      failedSources: failures,
    );
  }

  List<Map<String, dynamic>> _rows(dynamic response) => switch (response) {
    List value =>
      value
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList(growable: false),
    _ => const [],
  };

  Future<_CapturedReportSource> _capture(
    String source,
    Future<dynamic> Function() request,
  ) async {
    try {
      return _CapturedReportSource(value: await request());
    } catch (error) {
      return _CapturedReportSource(
        failure: ReportSourceFailure(
          source: source,
          isOffline: error is SocketException || error is http.ClientException,
        ),
      );
    }
  }
}

class _CapturedReportSource {
  const _CapturedReportSource({this.value, this.failure});

  final dynamic value;
  final ReportSourceFailure? failure;
}
