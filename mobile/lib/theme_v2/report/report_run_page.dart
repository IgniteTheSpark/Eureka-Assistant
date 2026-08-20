import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../pages/report_viewer_page.dart';
import '../../voice_input/voice_input_controller.dart';
import '../../voice_input/voice_input_field.dart';
import '../../voice_input/voice_input_scope.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_content_surface.dart';
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
  final _focusController = VoiceInputTextController();
  final _presentationController = TextEditingController();
  late final VoiceInputController _focusVoiceController;
  final Map<String, TextEditingController> _clarificationTextControllers = {};
  final Set<String> _activeClarificationVoice = {};
  ReportPlanDraftView? _draft;
  int _planStep = 0;
  bool _generateAfterScopeResolution = false;

  @override
  void initState() {
    super.initState();
    _focusVoiceController = VoiceInputController(
      textController: _focusController,
      service: VoiceInputScope.sharedService,
    )..addListener(_voiceChanged);
    _focusController.addListener(_syncAdditionalFocus);
    final runId = widget.runId;
    if (runId != null) {
      unawaited(_controller.loadRun(runId));
    } else if (widget.triggerExecutionId != null) {
      unawaited(_controller.startFromTrigger(widget.triggerExecutionId!));
    } else {
      unawaited(_controller.startUserInitiated(widget.intent!));
    }
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  void _syncAdditionalFocus() {
    _controller.updateScopeAdditionalFocus(_focusController.text);
  }

  TextEditingController _clarificationController(String id) {
    return _clarificationTextControllers.putIfAbsent(id, () {
      final current = _controller.clarificationAnswers[id]?.toString() ?? '';
      final controller = TextEditingController(text: current);
      controller.addListener(() {
        _controller.answerQuestion(id, controller.text);
      });
      return controller;
    });
  }

  void _clarificationVoiceChanged(String id, bool busy) {
    if (busy) {
      _activeClarificationVoice.add(id);
    } else {
      _activeClarificationVoice.remove(id);
    }
    if (mounted) setState(() {});
  }

  void _changed() {
    if (_controller.needsScopeConfirmation &&
        _controller.scopeCandidates == null &&
        !_controller.busy &&
        _controller.error == null) {
      unawaited(_controller.loadScopeCandidates());
    }
    final serverDraft = _controller.planDraft;
    if (serverDraft != null && (_planStep <= 1 || _draft == null)) {
      _draft = serverDraft;
    }
    final scopeFocus = _controller.scopeDraft?.additionalFocus ?? '';
    if (_planStep == 0 &&
        !_focusVoiceController.isBusy &&
        _focusController.text != scopeFocus) {
      _focusController.text = scopeFocus;
    }
    final presentationText =
        _controller.scopeDraft?.presentationPreference.customText ?? '';
    if (_planStep == 0 && _presentationController.text != presentationText) {
      _presentationController.text = presentationText;
    }
    if (!_controller.needsScopeConfirmation &&
        serverDraft != null &&
        _planStep == 0) {
      _planStep = 1;
    }
    if (mounted) setState(() {});
    if (_generateAfterScopeResolution &&
        _controller.state == 'awaiting_selection') {
      _generateAfterScopeResolution = false;
      if ((_controller.planDraft?.blockers ?? const []).isEmpty) {
        unawaited(_controller.generateConfirmedDraft());
      }
    }
    if (const {
          'completed',
          'illustration_pending',
        }.contains(_controller.state) &&
        !_openingReport) {
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
            initialIllustrationStatus:
                report['illustration_status']?.toString() ?? 'not_required',
            initialRevision: (report['revision'] as num?)?.toInt() ?? 1,
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
    for (final controller in _clarificationTextControllers.values) {
      controller.dispose();
    }
    _focusController.removeListener(_syncAdditionalFocus);
    _focusVoiceController.removeListener(_voiceChanged);
    unawaited(_focusVoiceController.close());
    _focusVoiceController.dispose();
    _focusController.dispose();
    _presentationController.dispose();
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final cancellationError = _controller.cancellationError;
    final content = cancellationError != null
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
              _controller.error ?? _controller.failureMessage ?? '报告生成没有完成',
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
            'illustration_pending' => _message('报告正文已完成，正在打开…'),
            'generating' => _progress('正在生成报告…'),
            _ when _controller.error != null => _message(
              _controller.error!,
              actionLabel: '重试',
              actionKey: const ValueKey('report-run-retry'),
              onAction: widget.runId != null
                  ? () => _controller.loadRun(widget.runId!)
                  : widget.triggerExecutionId != null
                  ? () =>
                        _controller.startFromTrigger(widget.triggerExecutionId!)
                  : () => _controller.startUserInitiated(widget.intent!),
            ),
            _ => _progress('正在准备报告方案…'),
          };
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
            child: ThemeV2ContentSurface(
              key: const ValueKey('report-run-content-surface'),
              opacity: ThemeV2ContentOpacity.dense,
              child: Padding(
                padding: const EdgeInsets.all(ThemeV2Spacing.md),
                child: content,
              ),
            ),
          ),
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
    final scope = _controller.scopeDraft;
    if (_planStep == 0 &&
        (_controller.scopeCandidates == null || scope == null)) {
      return _progress('正在准备可选范围…');
    }
    if (_planStep > 0 && draft == null) {
      return _progress('正在准备报告方案…');
    }
    final body = switch (_planStep) {
      0 => _scopeStepBody(scope!),
      1 => _planStepBody(options, recommended, draft!),
      _ => _confirmationStepBody(options, draft!),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: body,
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.md),
        _planStepActions(recommended, scope, draft),
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
        if (_draftNeedsEvidence(draft)) ...[
          const SizedBox(height: ThemeV2Spacing.sm),
          Text(
            '当前方案还没有参考资产，请先选择后再生成。',
            style: TextStyle(color: context.themeV2.critical),
          ),
        ],
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

  Widget _scopeStepBody(ReportScopeDraftView scope) {
    final candidates = _controller.scopeCandidates!;
    final adapter = scope.adapterKind;
    final intent = _controller.intent.isNotEmpty
        ? _controller.intent
        : widget.intent?.trim() ?? '';
    return ListView(
      key: const ValueKey('report-step-scope'),
      children: [
        const Text(
          '确认报告输入',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        const Text('先确认使用哪些资产；呈现方式和补充说明都可以留给 Reka 推荐。'),
        if (intent.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          Container(
            padding: const EdgeInsets.all(ThemeV2Spacing.md),
            decoration: BoxDecoration(
              color: context.themeV2.surface,
              borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
              border: Border.all(color: context.themeV2.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '你的需求',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.themeV2.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: ThemeV2Spacing.xs),
                Text(intent),
              ],
            ),
          ),
        ],
        const SizedBox(height: ThemeV2Spacing.xl),
        const Text(
          '资产范围',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.xs),
        Text('已选择 ${scope.references.length} 项资产'),
        if (adapter == 'generic' && scope.references.length == 1) ...[
          const SizedBox(height: ThemeV2Spacing.xs),
          const Text('已定位到这项资产；如果需要，可以继续关联其他资产。'),
        ],
        if (adapter == 'period_summary' &&
            candidates.timeRangeOptions.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.md),
          const Text('时间范围'),
          const SizedBox(height: ThemeV2Spacing.sm),
          Wrap(
            spacing: ThemeV2Spacing.sm,
            runSpacing: ThemeV2Spacing.sm,
            children: [
              for (final option in candidates.timeRangeOptions)
                ChoiceChip(
                  key: ValueKey('report-time-range-${option.id}'),
                  label: Text(option.label),
                  selected: option.id == 'custom'
                      ? scope.timeRange != null &&
                            !candidates.timeRangeOptions.any(
                              (candidate) =>
                                  candidate.id != 'custom' &&
                                  _sameTimeRange(
                                    scope.timeRange,
                                    candidate.timeRange,
                                  ),
                            )
                      : _sameTimeRange(scope.timeRange, option.timeRange),
                  onSelected: (_) => unawaited(
                    option.id == 'custom'
                        ? _pickCustomTimeRange()
                        : _controller.selectScopeTimeRange(option),
                  ),
                ),
            ],
          ),
        ],
        if (adapter == 'period_summary' &&
            scope.missingDimensions.contains('asset_type') &&
            candidates.recordGroups.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          const Text('资产类型'),
          const SizedBox(height: ThemeV2Spacing.xs),
          const Text('选择你想纳入报告的记录类型。'),
          const SizedBox(height: ThemeV2Spacing.sm),
          Wrap(
            spacing: ThemeV2Spacing.sm,
            runSpacing: ThemeV2Spacing.sm,
            children: [
              for (final group in candidates.recordGroups)
                FilterChip(
                  key: ValueKey('report-scope-type-${group.skillId}'),
                  label: Text(group.label),
                  selected: scope.skillIds.contains(group.skillId),
                  onSelected: (selected) =>
                      _controller.toggleScopeGroup(group.skillId, selected),
                ),
            ],
          ),
        ],
        if (adapter == 'period_summary' &&
            scope.supportingReferences.isNotEmpty) ...[
          const SizedBox(height: ThemeV2Spacing.lg),
          Wrap(
            spacing: ThemeV2Spacing.sm,
            runSpacing: ThemeV2Spacing.sm,
            children: [
              for (final group in candidates.recordGroups)
                if (_selectedRecordCount(group, scope) > 0)
                  ActionChip(
                    key: ValueKey('report-selected-group-${group.skillId}'),
                    label: Text(
                      '${group.label} × ${_selectedRecordCount(group, scope)}',
                    ),
                    avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                    onPressed: () =>
                        _openEvidencePicker(initialSkillId: group.skillId),
                  ),
            ],
          ),
        ],
        const SizedBox(height: ThemeV2Spacing.lg),
        OutlinedButton.icon(
          key: const ValueKey('report-open-evidence-picker'),
          onPressed: () => _openEvidencePicker(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('手动添加资产'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
        ),
        const SizedBox(height: ThemeV2Spacing.lg),
        if (adapter == 'pre_event_briefing') ...[
          const Text(
            '选择会议',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
          if (candidates.events.isEmpty)
            _emptyScopeCard('未来没有可用于会前调研的日程')
          else
            for (final event in candidates.events) ...[
              _eventScopeCard(
                event,
                selected: scope.primaryReference == event.reference,
                onTap: () => _controller.selectScopeEvent(event.reference),
              ),
              const SizedBox(height: ThemeV2Spacing.sm),
            ],
        ] else if (adapter == 'period_summary') ...[
          if (scope.timeRange == null)
            _emptyScopeCard('选择时间后，Reka 会筛出对应资产')
          else if (candidates.recordGroups.isEmpty)
            _emptyScopeCard('这段时间内还没有可汇总的记录'),
        ],
        const SizedBox(height: ThemeV2Spacing.xl),
        const Text(
          '呈现方式（选填）',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.xs),
        const Text('不选择时，Reka 会根据资产内容推荐。'),
        const SizedBox(height: ThemeV2Spacing.sm),
        Wrap(
          spacing: ThemeV2Spacing.sm,
          runSpacing: ThemeV2Spacing.sm,
          children: [
            for (final entry in const {
              'data_trend': '数据复盘',
              'theme_synthesis': '主题综合',
              'professional_evaluation': '专业评估',
              'briefing_research': '调研简报',
              'custom': '其他',
            }.entries)
              ChoiceChip(
                key: ValueKey('report-presentation-${entry.key}'),
                label: Text(entry.value),
                selected: scope.presentationPreference.family == entry.key,
                onSelected: (_) =>
                    _controller.setScopePresentationFamily(entry.key),
              ),
          ],
        ),
        if (scope.presentationPreference.family == 'custom') ...[
          const SizedBox(height: ThemeV2Spacing.sm),
          TextField(
            key: const ValueKey('report-custom-presentation'),
            controller: _presentationController,
            maxLength: 240,
            onChanged: _controller.updateScopeCustomPresentation,
            decoration: InputDecoration(
              labelText: '描述你希望的呈现方式',
              hintText: '例如：做成适合分享的一页卡片',
              counterText: '',
            ),
          ),
        ],
        const SizedBox(height: ThemeV2Spacing.xl),
        const Text(
          '补充信息（选填）',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        if (scope.attentionFocus.isNotEmpty) ...[
          Wrap(
            spacing: ThemeV2Spacing.sm,
            runSpacing: ThemeV2Spacing.sm,
            children: [
              for (final focus in scope.attentionFocus)
                Chip(label: Text(focus)),
            ],
          ),
          const SizedBox(height: ThemeV2Spacing.sm),
        ],
        VoiceInputField(
          key: const ValueKey('report-additional-focus-voice'),
          controller: _focusVoiceController,
          enabled: !_controller.busy,
          builder: (context, voiceBusy) => TextField(
            key: const ValueKey('report-additional-focus'),
            controller: _focusController,
            readOnly: voiceBusy,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '背景、重点或需要排除的内容',
              hintText: '例如：重点解释周末支出，忽略报销项目',
            ),
          ),
        ),
      ],
    );
  }

  Widget _eventScopeCard(
    ReportScopeEventCandidateView event, {
    required bool selected,
    required VoidCallback onTap,
  }) => InkWell(
    key: ValueKey('report-scope-event-${event.reference.id}'),
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.all(ThemeV2Spacing.lg),
      decoration: BoxDecoration(
        color: context.themeV2.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : context.themeV2.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : context.themeV2.muted,
          ),
          const SizedBox(width: ThemeV2Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: ThemeV2Spacing.xs),
                Text(
                  '${event.localDate}  ${event.localStart}–${event.localEnd}',
                ),
                if ((event.location ?? '').trim().isNotEmpty)
                  Text(event.location!, style: _scopeSecondaryStyle()),
                if ((event.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: ThemeV2Spacing.xs),
                  Text(
                    event.notes!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _scopeSecondaryStyle(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );

  int _selectedRecordCount(
    ReportScopeRecordGroupView group,
    ReportScopeDraftView scope,
  ) => group.records
      .where((record) => scope.supportingReferences.contains(record.reference))
      .length;

  Widget _emptyScopeCard(String message) => Container(
    padding: const EdgeInsets.all(ThemeV2Spacing.lg),
    decoration: BoxDecoration(
      color: context.themeV2.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.themeV2.border),
    ),
    child: Text(message, style: _scopeSecondaryStyle()),
  );

  TextStyle _scopeSecondaryStyle() =>
      TextStyle(color: context.themeV2.muted, height: 1.35);

  bool _sameTimeRange(
    Map<String, dynamic>? current,
    Map<String, dynamic>? candidate,
  ) {
    if (current == null || candidate == null) return false;
    return current['from']?.toString() == candidate['from']?.toString() &&
        current['to']?.toString() == candidate['to']?.toString();
  }

  Future<void> _pickCustomTimeRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
    );
    if (!mounted || selected == null) return;
    final start = DateTime(
      selected.start.year,
      selected.start.month,
      selected.start.day,
    );
    final endExclusive = DateTime(
      selected.end.year,
      selected.end.month,
      selected.end.day + 1,
    );
    await _controller.selectScopeTimeRange(
      ReportTimeRangeOptionView(
        id: 'custom_selected',
        label: '自定义',
        timeRange: {
          'from': reportTimeBoundaryIso(start),
          'to': reportTimeBoundaryIso(endExclusive),
        },
      ),
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
    ReportScopeDraftView? scope,
    ReportPlanDraftView? draft,
  ) => switch (_planStep) {
    0 => FilledButton(
      key: const ValueKey('report-scope-confirm'),
      onPressed:
          _controller.busy ||
              _focusVoiceController.isBusy ||
              scope == null ||
              !_scopeCanContinue(scope)
          ? null
          : () => _controller.confirmScope(
              scope.copyWith(additionalFocus: _focusController.text.trim()),
            ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
      ),
      child: Text(_controller.busy ? '确认中…' : '确认输入，生成方案'),
    ),
    1 => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: const ValueKey('report-run-generate'),
          onPressed:
              _controller.busy ||
                  recommended == null ||
                  (draft?.blockers.isNotEmpty ?? true) ||
                  (draft != null && _draftNeedsEvidence(draft))
              ? null
              : _controller.quickGenerate,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
          ),
          child: Text(_controller.busy ? '启动中…' : '按推荐方案生成'),
        ),
        const SizedBox(height: ThemeV2Spacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('report-run-adjust'),
                onPressed: () => setState(() => _planStep = 0),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    ThemeV2Sizes.minTouchTarget,
                  ),
                ),
                child: const Text('调整范围'),
              ),
            ),
            const SizedBox(width: ThemeV2Spacing.sm),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('report-step-next'),
                onPressed: () => setState(() => _planStep = 2),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    ThemeV2Sizes.minTouchTarget,
                  ),
                ),
                child: const Text('检查后生成'),
              ),
            ),
          ],
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
                    draft == null ||
                    draft.blockers.isNotEmpty ||
                    _draftNeedsEvidence(draft)
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

  bool _scopeCanContinue(ReportScopeDraftView scope) =>
      switch (scope.adapterKind) {
        'pre_event_briefing' => scope.primaryReference != null,
        'period_summary' => scope.supportingReferences.isNotEmpty,
        _ => true,
      };

  bool _draftNeedsEvidence(ReportPlanDraftView draft) {
    final scope = _controller.scopeDraft;
    return draft.references.isEmpty &&
        (scope == null || scope.adapterKind != 'generic');
  }

  Future<void> _openEvidencePicker({String? initialSkillId}) async {
    final scope = _controller.scopeDraft;
    if (scope == null) return;
    final selected = await showReportEvidencePickerSheet(
      context,
      loadPage: _controller.loadEvidenceOptions,
      initialSelected: scope.supportingReferences,
      initialSkillId: initialSkillId,
    );
    if (!mounted || selected == null) return;
    _controller.replaceScopeSupportingReferences(selected);
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
              final answerController = options.isEmpty
                  ? _clarificationController(id)
                  : null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: ThemeV2Spacing.sm),
                  if (options.isEmpty)
                    VoiceInputTextAdapter(
                      key: ValueKey('report-clarification-voice-$id'),
                      controller: answerController!,
                      enabled: !_controller.busy,
                      onBusyChanged: (busy) =>
                          _clarificationVoiceChanged(id, busy),
                      builder: (context, controller, voiceBusy) => TextField(
                        controller: controller,
                        readOnly: voiceBusy,
                        decoration: const InputDecoration(hintText: '请输入'),
                      ),
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
          onPressed:
              _controller.busy ||
                  _activeClarificationVoice.isNotEmpty ||
                  !_controller.canSubmitClarification
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
