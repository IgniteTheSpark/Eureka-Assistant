import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../voice_input/voice_input_controller.dart';
import '../../voice_input/voice_input_field.dart';
import '../../voice_input/voice_input_scope.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'report_run_controller.dart';

Future<String?> showReportCreateSheet(BuildContext context, {ApiClient? api}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.themeV2.surface,
      builder: (sheetContext) => ReportCreateSheet(
        api: api,
        onCreated: (runId) => Navigator.of(sheetContext).pop(runId),
      ),
    );

class ReportCreateSheet extends StatefulWidget {
  const ReportCreateSheet({super.key, this.api, required this.onCreated});

  final ApiClient? api;
  final ValueChanged<String> onCreated;

  @override
  State<ReportCreateSheet> createState() => _ReportCreateSheetState();
}

class _ReportCreateSheetState extends State<ReportCreateSheet> {
  final _intent = VoiceInputTextController();
  late final VoiceInputController _voiceController;
  bool _voiceBound = false;
  late final ReportRunController _controller = ReportRunController(
    api: widget.api,
    autoPoll: false,
  )..addListener(_changed);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_voiceBound) return;
    _voiceBound = true;
    _voiceController = VoiceInputController(
      textController: _intent,
      coordinator: VoiceInputScope.coordinatorOf(context),
    )..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    final value = _intent.text.trim();
    if (value.isEmpty || _controller.busy || _voiceController.isBusy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _controller.startUserInitiated(value);
    if (!mounted || _controller.runId.isEmpty || _controller.error != null) {
      return;
    }
    widget.onCreated(_controller.runId);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    _voiceController.removeListener(_changed);
    unawaited(_voiceController.close());
    _voiceController.dispose();
    _intent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final canSubmit =
        _intent.text.trim().isNotEmpty &&
        !_controller.busy &&
        !_voiceController.isBusy;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ThemeV2Spacing.xl,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.xl,
          ThemeV2Spacing.xl + bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '创建报告',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: ThemeV2Spacing.xs),
            Text(
              '描述你希望整理、分析或调研的内容，Reka 会在需要时继续询问。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.themeV2.muted),
            ),
            const SizedBox(height: ThemeV2Spacing.lg),
            VoiceInputField(
              key: const ValueKey('report-create-voice'),
              controller: _voiceController,
              enabled: !_controller.busy,
              builder: (context, voice) => TextField(
                key: const ValueKey('report-create-intent'),
                controller: _intent,
                readOnly: voice.isBusy,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: 4000,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (!voice.isBusy) unawaited(_submit());
                },
                decoration: InputDecoration(
                  labelText: '你想生成什么报告？',
                  hintText: '例如：总结最近一个月的跑步训练，并分析恢复情况',
                  alignLabelWithHint: true,
                  suffixIcon: voice.statusIcon(color: context.themeV2.accent),
                ),
              ),
            ),
            if (_controller.error case final error?) ...[
              const SizedBox(height: ThemeV2Spacing.sm),
              Text(
                error,
                style: TextStyle(
                  color: context.themeV2.critical,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: ThemeV2Spacing.md),
            FilledButton(
              key: const ValueKey('report-create-submit'),
              onPressed: canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(ThemeV2Sizes.minTouchTarget),
              ),
              child: Text(_controller.busy ? '正在创建…' : '开始准备'),
            ),
          ],
        ),
      ),
    );
  }
}
