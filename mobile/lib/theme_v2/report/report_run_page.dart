import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../pages/report_viewer_page.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'report_run_controller.dart';

class ReportRunPage extends StatefulWidget {
  const ReportRunPage({
    super.key,
    this.triggerExecutionId,
    this.runId,
    this.intent,
    this.api,
  }) : assert(triggerExecutionId != null || runId != null || intent != null);

  final String? triggerExecutionId;
  final String? runId;
  final String? intent;
  final ApiClient? api;

  @override
  State<ReportRunPage> createState() => _ReportRunPageState();
}

class _ReportRunPageState extends State<ReportRunPage> {
  late final ReportRunController _controller = ReportRunController(
    api: widget.api,
  )..addListener(_changed);
  var _openingReport = false;
  String? _openReportError;

  @override
  void initState() {
    super.initState();
    final runId = widget.runId;
    if (runId != null) {
      unawaited(_controller.loadRun(runId));
    } else if (widget.triggerExecutionId != null) {
      unawaited(_controller.startFromTrigger(widget.triggerExecutionId!));
    } else {
      unawaited(_controller.startUserInitiated(widget.intent!));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
    if (_controller.state == 'completed' && !_openingReport) {
      unawaited(_openCompletedReport());
    }
  }

  Future<void> _openCompletedReport() async {
    if (mounted) {
      setState(() {
        _openingReport = true;
        _openReportError = null;
      });
    }
    try {
      if (_controller.reportId == null) await _controller.refresh();
      final report = await _controller.loadReport();
      if (!mounted) return;
      if (report == null) {
        setState(() {
          _openingReport = false;
          _openReportError = _controller.error ?? '报告内容暂时无法打开';
        });
        return;
      }
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReportViewerPage(
            title: report['title']?.toString() ?? '报告',
            html: report['html']?.toString() ?? '',
            reportId: report['id']?.toString(),
            enableLegacyEnhancements: false,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _openingReport = false;
          _openReportError = '报告内容暂时无法打开';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final cancellationError = _controller.cancellationError;
    return Scaffold(
      backgroundColor: context.themeV2.background,
      appBar: AppBar(
        title: const Text('报告'),
        actions: [
          if (_controller.canCancel)
            IconButton(
              key: const ValueKey('report-run-cancel'),
              tooltip: '取消报告任务',
              onPressed: _controller.busy ? null : _cancel,
              constraints: const BoxConstraints(
                minWidth: ThemeV2Sizes.minTouchTarget,
                minHeight: ThemeV2Sizes.minTouchTarget,
              ),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ThemeV2Spacing.xl),
          child: cancellationError != null
              ? _message(
                  cancellationError,
                  actionLabel: '重试取消',
                  actionKey: const ValueKey('report-run-cancel-retry'),
                  onAction: _cancel,
                )
              : switch (state) {
                  'awaiting_selection' =>
                    _controller.needsClarification
                        ? _clarification()
                        : _planSelection(),
                  'failed' => _message(
                    _controller.error ??
                        _controller.failureMessage ??
                        '报告生成没有完成',
                    actionLabel: '重试',
                    actionKey: const ValueKey('report-run-retry'),
                    onAction: _controller.retry,
                  ),
                  'cancelled' => _message('报告任务已取消'),
                  'completed' =>
                    _openReportError == null
                        ? _message('报告已完成，正在打开…')
                        : _message(
                            _openReportError!,
                            actionLabel: '重试打开',
                            actionKey: const ValueKey('report-run-open-retry'),
                            onAction: _openCompletedReport,
                          ),
                  'generating' => _progress('正在生成报告…'),
                  _ when _controller.error != null => _message(
                    _controller.error!,
                    actionLabel: '重试',
                    actionKey: const ValueKey('report-run-retry'),
                    onAction: widget.runId != null
                        ? () => _controller.loadRun(widget.runId!)
                        : widget.triggerExecutionId != null
                        ? () => _controller.startFromTrigger(
                            widget.triggerExecutionId!,
                          )
                        : () => _controller.startUserInitiated(widget.intent!),
                  ),
                  _ => _progress('正在准备报告方案…'),
                },
        ),
      ),
    );
  }

  Widget _progress(String label) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: ThemeV2Spacing.lg),
        Text(label),
      ],
    ),
  );

  Future<void> _cancel() async {
    await _controller.cancel();
    if (mounted && _controller.state == 'cancelled') {
      Navigator.of(context).maybePop();
    }
  }

  Widget _message(
    String message, {
    String? actionLabel,
    Key? actionKey,
    Future<void> Function()? onAction,
  }) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          FilledButton(
            key: actionKey,
            onPressed: onAction,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
            ),
            child: Text(actionLabel),
          ),
        ],
      ],
    ),
  );

  Widget _planSelection() {
    final options = _controller.planOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '选择报告方向',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        const Text('方案已结合当前资料和已有记录生成。'),
        const SizedBox(height: ThemeV2Spacing.xl),
        Expanded(
          child: ListView.separated(
            itemCount: options.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: ThemeV2Spacing.sm),
            itemBuilder: (context, index) {
              final option = options[index];
              final id = option['id']?.toString() ?? '';
              final selected = _controller.selectedOptionId == id;
              return ListTile(
                selected: selected,
                onTap: () => _controller.selectOption(id),
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(option['title']?.toString() ?? '报告方案'),
                subtitle: Text(option['summary']?.toString() ?? ''),
              );
            },
          ),
        ),
        FilledButton(
          key: const ValueKey('report-run-generate'),
          onPressed: _controller.busy || _controller.selectedOptionId == null
              ? null
              : _controller.generate,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
          child: Text(_controller.busy ? '启动中…' : '开始生成'),
        ),
      ],
    );
  }

  Widget _clarification() {
    final questions = _controller.clarificationQuestions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '补充一点信息',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        const Text('回答后，Reka 会继续准备报告方案。'),
        const SizedBox(height: ThemeV2Spacing.xl),
        Expanded(
          child: ListView.separated(
            itemCount: questions.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: ThemeV2Spacing.xl),
            itemBuilder: (context, index) {
              final question = questions[index];
              final id = question['id']?.toString() ?? '';
              final label = question['question']?.toString() ?? '请补充信息';
              final options = (question['options'] as List? ?? const [])
                  .map((option) => option.toString())
                  .where((option) => option.isNotEmpty)
                  .toList(growable: false);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: ThemeV2Spacing.sm),
                  if (options.isEmpty)
                    TextField(
                      onChanged: (value) =>
                          _controller.answerQuestion(id, value),
                      decoration: const InputDecoration(hintText: '请输入'),
                    )
                  else
                    Wrap(
                      spacing: ThemeV2Spacing.sm,
                      runSpacing: ThemeV2Spacing.sm,
                      children: [
                        for (final option in options)
                          ChoiceChip(
                            label: Text(option),
                            selected:
                                _controller.clarificationAnswers[id] == option,
                            onSelected: (_) =>
                                _controller.answerQuestion(id, option),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
        FilledButton(
          key: const ValueKey('report-run-clarification-submit'),
          onPressed: _controller.busy || !_controller.canSubmitClarification
              ? null
              : _controller.submitClarification,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
          child: Text(_controller.busy ? '提交中…' : '继续准备方案'),
        ),
      ],
    );
  }
}
