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
  int _planStep = 0;
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
    if (serverDraft != null && (_planStep == 0 || _draft == null)) {
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
    if (draft == null) return _progress('正在准备报告方案…');
    final body = switch (_planStep) {
      0 => _planStepBody(options, recommended, draft),
      1 => _scopeStepBody(draft),
      _ => _confirmationStepBody(options, draft),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportPlanStepper(
          key: const ValueKey('report-plan-stepper'),
          currentStep: _planStep,
        ),
        const SizedBox(height: ThemeV2Spacing.xl),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: body,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.md),
        _planStepActions(recommended, draft),
      ],
    );
  }

  Widget _planStepBody(
    List<Map<String, dynamic>> options,
    Map<String, dynamic>? recommended,
    ReportPlanDraftView draft,
  ) {
    final evidenceCount = draft.references.isNotEmpty
        ? draft.references.length
        : ((recommended?['evidence'] as Map?)?['asset_count'] as num?)
                  ?.toInt() ??
              0;
    final publicEntities = draft.publicResearch.entities
        .where((entity) => entity.enabled)
        .map((entity) => entity.name)
        .toList(growable: false);
    return ListView(
      key: const ValueKey('report-step-plan'),
      children: [
        const Text(
          '选择报告方案',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        const Text('Reka 已根据当前内容准备好推荐方案，你也可以选择其他方向。'),
        const SizedBox(height: ThemeV2Spacing.xl),
        for (final option in options) ...[
          _planOptionCard(
            option,
            selected:
                (option['id']?.toString() ?? '') == draft.selectedOptionId,
            evidenceCount:
                (option['id']?.toString() ?? '') ==
                    (recommended?['id']?.toString() ?? '')
                ? evidenceCount
                : ((option['evidence'] as Map?)?['asset_count'] as num?)
                          ?.toInt() ??
                      0,
            publicEntities:
                (option['id']?.toString() ?? '') == draft.selectedOptionId
                ? publicEntities
                : const [],
            onTap: () {
              final id = option['id']?.toString() ?? '';
              if (id.isEmpty) return;
              setState(() => _draft = draft.copyWith(selectedOptionId: id));
            },
          ),
          const SizedBox(height: ThemeV2Spacing.md),
        ],
        if (draft.references.isEmpty)
          Text(
            '当前方案还没有参考资产，请先选择后再生成。',
            style: TextStyle(color: context.themeV2.critical),
          ),
      ],
    );
  }

  Widget _planOptionCard(
    Map<String, dynamic> option, {
    required bool selected,
    required int evidenceCount,
    required List<String> publicEntities,
    required VoidCallback onTap,
  }) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      key: option['recommended'] == true
          ? const ValueKey('report-recommended-plan')
          : ValueKey('report-plan-option-${option['id']}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(ThemeV2Spacing.xl),
        decoration: BoxDecoration(
          color: context.themeV2.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : context.themeV2.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : context.themeV2.muted,
                ),
                const SizedBox(width: ThemeV2Spacing.sm),
                if (option['recommended'] == true) ...[
                  const Icon(Icons.auto_awesome_rounded, size: 18),
                  const SizedBox(width: ThemeV2Spacing.xs),
                  const Text(
                    '推荐',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ] else
                  const Text('备选方案'),
              ],
            ),
            const SizedBox(height: ThemeV2Spacing.lg),
            Text(
              option['title']?.toString() ?? '综合分析报告',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ThemeV2Spacing.sm),
            Text(option['summary']?.toString() ?? '整理现有内容并形成可执行结论'),
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
    ),
  );

  Widget _scopeStepBody(ReportPlanDraftView draft) {
    return ListView(
      key: const ValueKey('report-step-scope'),
      children: [
        const Text(
          '确认范围与资料',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        const Text('确认报告需要回答的问题、使用的个人资产，以及允许进行的公开调研。'),
        const SizedBox(height: ThemeV2Spacing.xl),
        const Text(
          '关注的问题',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
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
          onChanged: (value) => _draft = draft.copyWith(additionalFocus: value),
          decoration: const InputDecoration(
            labelText: '补充你的关注点',
            hintText: '例如：补充 Kevin（Eureka CEO）的公开职业背景',
          ),
        ),
        if (draft.publicResearch.entities.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.sm),
          const Text(
            '公开调研对象',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
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
        const Text(
          '参考资产',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.xs),
        Text('已选择 ${draft.references.length} 项，可包含日程、联系人和自定义资产。'),
        const SizedBox(height: ThemeV2Spacing.sm),
        OutlinedButton.icon(
          key: const ValueKey('report-open-evidence-picker'),
          onPressed: _openEvidencePicker,
          icon: const Icon(Icons.add_rounded),
          label: const Text('选择参考资产'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
        ),
        if (draft.blockers.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          for (final blocker in draft.blockers)
            Text(
              blocker.message,
              style: TextStyle(color: context.themeV2.critical),
            ),
        ],
        if (draft.references.isEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          Text(
            '请至少选择一项参考资产。',
            style: TextStyle(color: context.themeV2.critical),
          ),
        ],
      ],
    );
  }

  Widget _confirmationStepBody(
    List<Map<String, dynamic>> options,
    ReportPlanDraftView draft,
  ) {
    final option = options.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id']?.toString() == draft.selectedOptionId,
      orElse: () => options.isEmpty ? null : options.first,
    );
    final entities = draft.publicResearch.entities
        .where((entity) => entity.enabled)
        .map((entity) => entity.name)
        .toList(growable: false);
    final kindCounts = <String, int>{};
    for (final reference in draft.references) {
      kindCounts[reference.kind] = (kindCounts[reference.kind] ?? 0) + 1;
    }
    final webPolicy = (option?['web_search'] as Map?)?['policy']?.toString();
    final illustrationPolicy = (option?['illustration'] as Map?)?['policy']
        ?.toString();
    return ListView(
      key: const ValueKey('report-step-confirm'),
      children: [
        const Text(
          '确认并生成',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        const Text('生成前最后确认一次，提交后本次报告方案将被冻结。'),
        const SizedBox(height: ThemeV2Spacing.xl),
        Container(
          key: const ValueKey('report-final-summary'),
          padding: const EdgeInsets.all(ThemeV2Spacing.xl),
          decoration: BoxDecoration(
            color: context.themeV2.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.themeV2.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryLabel('报告方案'),
              Text(
                option?['title']?.toString() ?? '综合分析报告',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ((option?['summary']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: ThemeV2Spacing.xs),
                Text(option!['summary'].toString()),
              ],
              const SizedBox(height: ThemeV2Spacing.lg),
              _summaryLabel('关注范围'),
              if (draft.attentionQuestions.isEmpty)
                const Text('使用方案默认关注范围')
              else
                for (final question in draft.attentionQuestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: ThemeV2Spacing.xs),
                    child: Text('• $question'),
                  ),
              if (_focusController.text.trim().isNotEmpty) ...[
                const SizedBox(height: ThemeV2Spacing.xs),
                Text(_focusController.text.trim()),
              ],
              const SizedBox(height: ThemeV2Spacing.lg),
              _summaryLabel('参考资产'),
              Text('${draft.references.length} 项参考资产'),
              if (kindCounts.isNotEmpty) ...[
                const SizedBox(height: ThemeV2Spacing.sm),
                Wrap(
                  spacing: ThemeV2Spacing.sm,
                  runSpacing: ThemeV2Spacing.sm,
                  children: [
                    for (final entry in kindCounts.entries)
                      Chip(
                        label: Text(
                          '${_referenceKindLabel(entry.key)} ${entry.value}',
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: ThemeV2Spacing.lg),
              _summaryLabel('公开调研'),
              Text(entities.isEmpty ? '不进行公开实体调研' : entities.join('、')),
              const SizedBox(height: ThemeV2Spacing.sm),
              Text('联网资料：${_capabilityLabel(webPolicy)}'),
              Text('报告插图：${_capabilityLabel(illustrationPolicy)}'),
            ],
          ),
        ),
        if (draft.blockers.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          for (final blocker in draft.blockers)
            Text(
              blocker.message,
              style: TextStyle(color: context.themeV2.critical),
            ),
        ],
        if (draft.references.isEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          Text(
            '请至少选择一项参考资产。',
            style: TextStyle(color: context.themeV2.critical),
          ),
        ],
      ],
    );
  }

  Widget _summaryLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: ThemeV2Spacing.sm),
    child: Text(
      label,
      style: TextStyle(
        color: context.themeV2.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  String _referenceKindLabel(String kind) => switch (kind) {
    'event' => '日程',
    'contact' => '联系人',
    _ => '资产',
  };

  String _capabilityLabel(String? policy) => switch (policy) {
    'required' || 'authoritative_only' => '需要',
    'optional' => '按需使用',
    _ => '不使用',
  };

  Widget _planStepActions(
    Map<String, dynamic>? recommended,
    ReportPlanDraftView draft,
  ) => switch (_planStep) {
    0 => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: const ValueKey('report-run-generate'),
          onPressed: _controller.busy || recommended == null
              ? null
              : draft.references.isEmpty
              ? () => setState(() => _planStep = 1)
              : _controller.quickGenerate,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
          child: Text(
            _controller.busy
                ? '启动中…'
                : draft.references.isEmpty
                ? '选择参考资产'
                : '一键生成',
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        OutlinedButton(
          key: const ValueKey('report-run-adjust'),
          onPressed: () => setState(() => _planStep = 1),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
          child: const Text('调整关注范围与资料'),
        ),
      ],
    ),
    1 => Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('report-step-back'),
            onPressed: () => setState(() => _planStep = 0),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
            ),
            child: const Text('上一步'),
          ),
        ),
        const SizedBox(width: ThemeV2Spacing.sm),
        Expanded(
          child: FilledButton(
            key: const ValueKey('report-step-next'),
            onPressed: () => setState(() => _planStep = 2),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
            ),
            child: const Text('下一步'),
          ),
        ),
      ],
    ),
    _ => Row(
      children: [
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('report-step-back'),
            onPressed: () => setState(() => _planStep = 1),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
            ),
            child: const Text('上一步'),
          ),
        ),
        const SizedBox(width: ThemeV2Spacing.sm),
        Expanded(
          child: FilledButton(
            key: const ValueKey('report-run-confirm-generate'),
            onPressed:
                _controller.busy ||
                    draft.blockers.isNotEmpty ||
                    draft.references.isEmpty
                ? null
                : _confirmAdjusted,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
            ),
            child: Text(_controller.busy ? '确认中…' : '确认并生成'),
          ),
        ),
      ],
    ),
  };

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

class _ReportPlanStepper extends StatelessWidget {
  const _ReportPlanStepper({super.key, required this.currentStep});

  final int currentStep;

  static const _labels = ['方案', '范围', '确认'];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final border = context.themeV2.border;
    final muted = context.themeV2.muted;
    return Semantics(
      label: '报告方案步骤 ${currentStep + 1} / ${_labels.length}',
      child: Column(
        children: [
          Row(
            children: [
              for (var index = 0; index < _labels.length; index++) ...[
                if (index > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: index <= currentStep ? primary : border,
                    ),
                  ),
                Semantics(
                  selected: index == currentStep,
                  label: '第 ${index + 1} 步：${_labels[index]}',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index <= currentStep
                          ? primary
                          : Colors.transparent,
                      border: Border.all(
                        color: index <= currentStep ? primary : border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: index < currentStep
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.onPrimary,
                          )
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: index == currentStep
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: ThemeV2Spacing.xs),
          Row(
            children: [
              for (var index = 0; index < _labels.length; index++)
                Expanded(
                  child: Text(
                    _labels[index],
                    textAlign: switch (index) {
                      0 => TextAlign.left,
                      2 => TextAlign.right,
                      _ => TextAlign.center,
                    },
                    style: TextStyle(
                      color: index == currentStep
                          ? context.themeV2.foreground
                          : muted,
                      fontSize: 12,
                      fontWeight: index == currentStep
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
