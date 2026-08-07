import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../pages/report_viewer_page.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'report_evidence_picker_page.dart';
import 'report_plan_models.dart';
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
  final _focusController = TextEditingController();
  ReportPlanDraftView? _draft;
  bool _adjusting = false;
  bool _generateAfterScopeResolution = false;

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
    final serverDraft = _controller.planDraft;
    if (serverDraft != null && (!_adjusting || _draft == null)) {
      _draft = serverDraft;
      if (_focusController.text != serverDraft.additionalFocus) {
        _focusController.text = serverDraft.additionalFocus;
      }
    }
    if (mounted) setState(() {});
    if (_generateAfterScopeResolution &&
        _controller.state == 'awaiting_selection') {
      _generateAfterScopeResolution = false;
      if ((_controller.planDraft?.blockers ?? const []).isEmpty) {
        unawaited(_controller.generateConfirmedDraft());
      }
    }
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
            enableThemeV2Actions: true,
            themeV2Palette: (report['spec'] as Map?)?['palette']?.toString(),
            api: widget.api,
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
    _focusController.dispose();
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
    final recommended = _controller.recommendedOption;
    final draft = _draft ?? _controller.planDraft;
    if (_adjusting && draft != null) {
      return _adjustPlan(options, draft);
    }
    final evidenceCount =
        draft?.references.length ??
        ((recommended?['evidence'] as Map?)?['asset_count'] as num?)?.toInt() ??
        0;
    final publicEntities =
        draft?.publicResearch.entities
            .where((entity) => entity.enabled)
            .map((entity) => entity.name)
            .toList(growable: false) ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '报告方案',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        const Text('Reka 已根据当前内容准备了一个推荐方案。'),
        const SizedBox(height: ThemeV2Spacing.xl),
        Expanded(
          child: ListView(
            children: [
              Container(
                key: const ValueKey('report-recommended-plan'),
                padding: const EdgeInsets.all(ThemeV2Spacing.xl),
                decoration: BoxDecoration(
                  color: context.themeV2.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.themeV2.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 19),
                        const SizedBox(width: ThemeV2Spacing.sm),
                        const Text(
                          '推荐',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: ThemeV2Spacing.lg),
                    Text(
                      recommended?['title']?.toString() ?? '综合分析报告',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: ThemeV2Spacing.sm),
                    Text(
                      recommended?['summary']?.toString() ?? '整理现有内容并形成可执行结论',
                    ),
                    const SizedBox(height: ThemeV2Spacing.lg),
                    Wrap(
                      spacing: ThemeV2Spacing.sm,
                      runSpacing: ThemeV2Spacing.sm,
                      children: [
                        Chip(label: Text('参考 $evidenceCount 项资产')),
                        if (publicEntities.isNotEmpty)
                          Chip(label: Text('公开调研 ${publicEntities.join('、')}')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        FilledButton(
          key: const ValueKey('report-run-generate'),
          onPressed: _controller.busy || recommended == null
              ? null
              : _controller.quickGenerate,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
          child: Text(_controller.busy ? '启动中…' : '一键生成'),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        OutlinedButton(
          key: const ValueKey('report-run-adjust'),
          onPressed: draft == null
              ? null
              : () => setState(() {
                  _draft = draft;
                  _adjusting = true;
                }),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
          child: const Text('调整方案'),
        ),
      ],
    );
  }

  Widget _adjustPlan(
    List<Map<String, dynamic>> options,
    ReportPlanDraftView draft,
  ) {
    final blockers = draft.blockers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('report-adjust-back'),
              onPressed: () => setState(() => _adjusting = false),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const Text(
              '调整报告方案',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        Expanded(
          child: ListView(
            children: [
              _sectionTitle('1', '报告方案'),
              for (final option in options)
                ListTile(
                  selected:
                      (option['id']?.toString() ?? '') ==
                      draft.selectedOptionId,
                  onTap: () {
                    final value = option['id']?.toString() ?? '';
                    if (value.isEmpty) return;
                    setState(
                      () => _draft = draft.copyWith(selectedOptionId: value),
                    );
                  },
                  leading: Icon(
                    (option['id']?.toString() ?? '') == draft.selectedOptionId
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                  ),
                  title: Text(option['title']?.toString() ?? '报告方案'),
                  subtitle: Text(option['summary']?.toString() ?? ''),
                ),
              const SizedBox(height: ThemeV2Spacing.xl),
              _sectionTitle('2', '关注范围'),
              if (draft.attentionQuestions.isNotEmpty)
                Wrap(
                  spacing: ThemeV2Spacing.sm,
                  runSpacing: ThemeV2Spacing.sm,
                  children: [
                    for (final question in draft.attentionQuestions)
                      InputChip(
                        label: Text(question),
                        onDeleted: () => setState(
                          () => _draft = draft.copyWith(
                            attentionQuestions: draft.attentionQuestions
                                .where((item) => item != question)
                                .toList(growable: false),
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: ThemeV2Spacing.sm),
              TextField(
                key: const ValueKey('report-additional-focus'),
                controller: _focusController,
                maxLength: 500,
                maxLines: 3,
                onChanged: (value) =>
                    _draft = draft.copyWith(additionalFocus: value),
                decoration: const InputDecoration(
                  labelText: '补充你的关注点',
                  hintText: '例如：补充 Kevin（Eureka CEO）的公开职业背景',
                ),
              ),
              if (draft.publicResearch.entities.isNotEmpty) ...[
                const SizedBox(height: ThemeV2Spacing.sm),
                const Text('公开调研对象'),
                const SizedBox(height: ThemeV2Spacing.sm),
                Wrap(
                  spacing: ThemeV2Spacing.sm,
                  runSpacing: ThemeV2Spacing.sm,
                  children: [
                    for (
                      var index = 0;
                      index < draft.publicResearch.entities.length;
                      index++
                    )
                      FilterChip(
                        label: Text(
                          [
                            draft.publicResearch.entities[index].name,
                            draft.publicResearch.entities[index].qualifier,
                          ].whereType<String>().join(' · '),
                        ),
                        selected: draft.publicResearch.entities[index].enabled,
                        onSelected: (selected) {
                          final entities = [...draft.publicResearch.entities];
                          entities[index] = entities[index].copyWith(
                            enabled: selected,
                          );
                          setState(
                            () => _draft = draft.copyWith(
                              publicResearch: draft.publicResearch.copyWith(
                                entities: entities,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: ThemeV2Spacing.xl),
              _sectionTitle('3', '参考资产'),
              Text('已选择 ${draft.references.length} 项，可包含日程、联系人和自定义资产。'),
              const SizedBox(height: ThemeV2Spacing.sm),
              OutlinedButton.icon(
                key: const ValueKey('report-open-evidence-picker'),
                onPressed: _openEvidencePicker,
                icon: const Icon(Icons.add_rounded),
                label: const Text('选择参考资产'),
              ),
              if (blockers.isNotEmpty) ...[
                const SizedBox(height: ThemeV2Spacing.lg),
                for (final blocker in blockers)
                  Text(
                    blocker.message,
                    style: TextStyle(color: context.themeV2.critical),
                  ),
              ],
            ],
          ),
        ),
        FilledButton(
          key: const ValueKey('report-run-confirm-generate'),
          onPressed: _controller.busy ? null : _confirmAdjusted,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
          child: Text(_controller.busy ? '确认中…' : '确认并生成'),
        ),
      ],
    );
  }

  Widget _sectionTitle(String number, String label) => Padding(
    padding: const EdgeInsets.only(bottom: ThemeV2Spacing.sm),
    child: Text(
      '$number  $label',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );

  Future<void> _openEvidencePicker() async {
    final draft = _draft;
    if (draft == null) return;
    final selected = await Navigator.of(context)
        .push<List<EvidenceReferenceView>>(
          MaterialPageRoute(
            builder: (_) => ReportEvidencePickerPage(
              loadPage: _controller.loadEvidenceOptions,
              initialSelected: draft.references,
            ),
          ),
        );
    if (!mounted || selected == null) return;
    setState(() => _draft = draft.copyWith(references: selected));
  }

  Future<void> _confirmAdjusted() async {
    final draft = _draft;
    if (draft == null) return;
    _generateAfterScopeResolution = true;
    await _controller.updateDraft(
      draft.copyWith(additionalFocus: _focusController.text.trim()),
    );
    if (!mounted || _controller.error != null) {
      _generateAfterScopeResolution = false;
      return;
    }
    if (_controller.state == 'awaiting_selection') {
      _generateAfterScopeResolution = false;
      await _controller.generateConfirmedDraft();
    }
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
