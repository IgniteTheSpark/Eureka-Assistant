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
    this.api,
  }) : assert(triggerExecutionId != null || runId != null);

  final String? triggerExecutionId;
  final String? runId;
  final ApiClient? api;

  @override
  State<ReportRunPage> createState() => _ReportRunPageState();
}

class _ReportRunPageState extends State<ReportRunPage> {
  late final ReportRunController _controller = ReportRunController(
    api: widget.api,
  )..addListener(_changed);
  var _openingReport = false;

  @override
  void initState() {
    super.initState();
    final runId = widget.runId;
    if (runId != null) {
      unawaited(_controller.loadRun(runId));
    } else {
      unawaited(_controller.startFromTrigger(widget.triggerExecutionId!));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
    if (_controller.state == 'completed' && !_openingReport) {
      unawaited(_openCompletedReport());
    }
  }

  Future<void> _openCompletedReport() async {
    _openingReport = true;
    try {
      final report = await _controller.loadReport();
      if (!mounted || report == null) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ReportViewerPage(
            title: report['title']?.toString() ?? '会前调研',
            html: report['html']?.toString() ?? '',
            reportId: report['id']?.toString(),
            enableLegacyEnhancements: false,
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _openingReport = false);
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
    return Scaffold(
      backgroundColor: context.themeV2.background,
      appBar: AppBar(title: const Text('会前调研')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ThemeV2Spacing.xl),
          child: switch (state) {
            'awaiting_selection' =>
              _controller.needsClarification
                  ? _clarification()
                  : _planSelection(),
            'failed' => _message(
              _controller.error ?? '调研生成没有完成',
              actionLabel: '重试',
              onAction: _controller.retry,
            ),
            'completed' => _message('调研已完成，正在打开…'),
            'generating' => _progress('正在进行会前调研…'),
            _ when _controller.error != null => _message(
              _controller.error!,
              actionLabel: '重试',
              onAction: widget.runId != null
                  ? () => _controller.loadRun(widget.runId!)
                  : () => _controller.startFromTrigger(
                      widget.triggerExecutionId!,
                    ),
            ),
            _ => _progress('正在准备调研方案…'),
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

  Widget _message(
    String message, {
    String? actionLabel,
    Future<void> Function()? onAction,
  }) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
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
          '选择调研方向',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        const Text('方案已结合当前日程和已有记录生成。'),
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
                title: Text(option['title']?.toString() ?? '调研方案'),
                subtitle: Text(option['summary']?.toString() ?? ''),
              );
            },
          ),
        ),
        FilledButton(
          onPressed: _controller.busy || _controller.selectedOptionId == null
              ? null
              : _controller.generate,
          child: Text(_controller.busy ? '启动中…' : '开始调研'),
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
        const Text('回答后，Reka 会继续准备调研方案。'),
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
          onPressed: _controller.busy || !_controller.canSubmitClarification
              ? null
              : _controller.submitClarification,
          child: Text(_controller.busy ? '提交中…' : '继续准备方案'),
        ),
      ],
    );
  }
}
