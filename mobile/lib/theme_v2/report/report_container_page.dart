import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../pages/report_viewer_page.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import '../shell/theme_v2_page_title.dart';
import 'report_container_controller.dart';
import 'report_create_sheet.dart';
import 'report_repository.dart';
import 'report_run_page.dart';

class ReportContainerPage extends StatefulWidget {
  const ReportContainerPage({
    super.key,
    this.controller,
    this.api,
    this.autoLoad = true,
    this.onBack,
    this.onCreate,
    this.onOpenRun,
    this.onOpenReport,
  });

  final ReportContainerController? controller;
  final ApiClient? api;
  final bool autoLoad;
  final VoidCallback? onBack;
  final VoidCallback? onCreate;
  final ValueChanged<ReportRunSummary>? onOpenRun;
  final ValueChanged<CompletedReportSummary>? onOpenReport;

  @override
  State<ReportContainerPage> createState() => _ReportContainerPageState();
}

class _ReportContainerPageState extends State<ReportContainerPage> {
  ApiClient? _ownedApi;
  late final ApiClient _api;
  late final ReportContainerController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    if (_ownsController) {
      _api = widget.api ?? ApiClient();
      if (widget.api == null) _ownedApi = _api;
      _controller = ReportContainerController(
        repository: ApiReportRepository(_api),
      );
    } else {
      _api = widget.api ?? ApiClient();
      if (widget.api == null) _ownedApi = _api;
      _controller = widget.controller!;
    }
    _controller.addListener(_changed);
    if (widget.autoLoad) _controller.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    if (_ownsController) _controller.dispose();
    _ownedApi?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.themeV2.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _controller.load,
          child: ListView(
            key: const PageStorageKey('theme-v2-report-container'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              _header(),
              const SizedBox(height: ThemeV2Spacing.xl),
              ..._content(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
    children: [
      ThemeV2IconButton(
        key: const ValueKey('report-back'),
        semanticLabel: '返回',
        icon: Icons.chevron_left_rounded,
        color: context.themeV2.foreground,
        onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
      ),
      const SizedBox(width: ThemeV2Spacing.xs),
      const Expanded(
        child: ThemeV2PageTitle(
          key: ValueKey('theme-v2-page-title-report'),
          title: '报告',
        ),
      ),
      FilledButton.icon(
        key: const ValueKey('report-create'),
        onPressed: widget.onCreate ?? _createReport,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('创建报告'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, ThemeV2Sizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: ThemeV2Spacing.md),
        ),
      ),
    ],
  );

  Future<void> _createReport() async {
    final runId = await showReportCreateSheet(context, api: _api);
    if (!mounted || runId == null || runId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportRunPage(runId: runId, api: _api),
      ),
    );
    if (mounted) await _controller.load();
  }

  Future<void> _openRun(ReportRunSummary run) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportRunPage(runId: run.id, api: _api),
      ),
    );
    if (mounted) await _controller.load();
  }

  Future<void> _openReport(CompletedReportSummary report) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportViewerPage(
          title: report.title,
          html: report.html,
          reportId: report.id,
          enableLegacyEnhancements: false,
          enableThemeV2Actions: true,
          themeV2Palette: report.palette,
          api: _api,
        ),
      ),
    );
  }

  List<Widget> _content() {
    final status = _controller.status;
    if (status == ReportContainerStatus.loading &&
        _controller.overview == null) {
      return const [
        SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (status == ReportContainerStatus.offline ||
        status == ReportContainerStatus.error) {
      return [
        _ReportStateCard(
          title: status == ReportContainerStatus.offline
              ? '当前处于离线状态'
              : '报告加载失败',
          message: _controller.errorMessage,
          actionLabel: '重试',
          onAction: _controller.retry,
          actionKey: const ValueKey('report-retry'),
        ),
      ];
    }
    if (status == ReportContainerStatus.empty) {
      return const [
        _ReportStateCard(title: '还没有报告', message: '需要整理或调研时，可以从右上角创建'),
      ];
    }

    return [
      if (_controller.statusMessage case final message?) ...[
        _ReportPartialBanner(message: message, onRetry: _controller.retry),
        const SizedBox(height: ThemeV2Spacing.lg),
      ],
      if (_controller.pendingDecisionRuns.isNotEmpty) ...[
        const _SectionLabel('等待你确认'),
        const SizedBox(height: ThemeV2Spacing.sm),
        for (final run in _controller.pendingDecisionRuns) ...[
          _ReportRunCard(
            run: run,
            priority: true,
            onTap: () => widget.onOpenRun != null
                ? widget.onOpenRun!(run)
                : _openRun(run),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
        ],
        const SizedBox(height: ThemeV2Spacing.md),
      ],
      if (_controller.inProgressRuns.isNotEmpty) ...[
        const _SectionLabel('生成中/需要处理'),
        const SizedBox(height: ThemeV2Spacing.sm),
        for (final run in _controller.inProgressRuns) ...[
          _ReportRunCard(
            run: run,
            onTap: () => widget.onOpenRun != null
                ? widget.onOpenRun!(run)
                : _openRun(run),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
        ],
        const SizedBox(height: ThemeV2Spacing.md),
      ],
      const _SectionLabel('报告库'),
      const SizedBox(height: ThemeV2Spacing.sm),
      if (_controller.completedReports.isEmpty)
        const _ReportStateCard(title: '还没有已完成报告', message: '生成完成后会稳定保存在这里')
      else
        for (final report in _controller.completedReports) ...[
          _CompletedReportCard(
            report: report,
            onTap: () => widget.onOpenReport != null
                ? widget.onOpenReport!(report)
                : _openReport(report),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
        ],
      if (status == ReportContainerStatus.loading) ...[
        const SizedBox(height: ThemeV2Spacing.sm),
        const LinearProgressIndicator(minHeight: 2),
      ],
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: ThemeV2Typography.mono(
      fontSize: 10,
      color: context.themeV2.muted,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
}

class _ReportRunCard extends StatelessWidget {
  const _ReportRunCard({required this.run, this.priority = false, this.onTap});

  final ReportRunSummary run;
  final bool priority;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final accent = run.state == 'failed' ? tokens.critical : tokens.accent;
    return Material(
      color: priority ? tokens.accentSoft : tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        side: BorderSide(color: priority ? accent : tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('report-run-${run.id}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.all(ThemeV2Spacing.md),
            child: Row(
              children: [
                Icon(
                  priority
                      ? Icons.tune_rounded
                      : run.state == 'failed'
                      ? Icons.error_outline_rounded
                      : Icons.auto_awesome_rounded,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: ThemeV2Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        run.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: ThemeV2Spacing.xs),
                      Text(
                        run.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ThemeV2Spacing.sm),
                Icon(Icons.chevron_right_rounded, color: tokens.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletedReportCard extends StatelessWidget {
  const _CompletedReportCard({required this.report, this.onTap});

  final CompletedReportSummary report;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('report-item-${report.id}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 82),
          child: Padding(
            padding: const EdgeInsets.all(ThemeV2Spacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.description_outlined, color: tokens.accent),
                const SizedBox(width: ThemeV2Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (report.summary.isNotEmpty) ...[
                        const SizedBox(height: ThemeV2Spacing.xs),
                        Text(
                          report.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: tokens.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: tokens.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportStateCard extends StatelessWidget {
  const _ReportStateCard({
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionKey,
  });

  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 144),
    padding: const EdgeInsets.all(ThemeV2Spacing.xl),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.themeV2.surface,
      borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
      border: Border.all(color: context.themeV2.border),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (message != null) ...[
          const SizedBox(height: ThemeV2Spacing.xs),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: ThemeV2Spacing.md),
          TextButton(
            key: actionKey,
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

class _ReportPartialBanner extends StatelessWidget {
  const _ReportPartialBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    color: context.themeV2.accentSoft,
    padding: const EdgeInsets.only(left: ThemeV2Spacing.md),
    child: Row(
      children: [
        Expanded(child: Text(message)),
        TextButton(
          key: const ValueKey('report-partial-retry'),
          onPressed: onRetry,
          child: const Text('重试'),
        ),
      ],
    ),
  );
}
