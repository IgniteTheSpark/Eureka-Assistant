import 'package:flutter/material.dart';

import '../foundation/theme_v2_motion.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'calendar_components.dart';
import 'calendar_controller.dart';

class CalendarInlineDraftView extends StatefulWidget {
  const CalendarInlineDraftView({
    super.key,
    required this.controller,
    required this.onCreate,
    required this.onOpenEditor,
    required this.onChanged,
  });

  final CalendarController controller;
  final CalendarDraftMutation onCreate;
  final ValueChanged<CalendarInlineDraft> onOpenEditor;
  final VoidCallback onChanged;

  @override
  State<CalendarInlineDraftView> createState() =>
      _CalendarInlineDraftViewState();
}

class _CalendarInlineDraftViewState extends State<CalendarInlineDraftView> {
  bool _failed = false;
  CalendarInlineDraft? _created;

  Future<void> _confirm() async {
    final draft = widget.controller.inlineDraft;
    if (draft == null) return;
    setState(() => _failed = false);
    final created = await widget.controller.confirmInlineDraft(widget.onCreate);
    if (!mounted) return;
    setState(() {
      _failed = !created;
      if (created) _created = draft;
    });
    widget.onChanged();
  }

  void _cancel() {
    widget.controller.cancelInlineDraft();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    final draft = widget.controller.inlineDraft ?? _created;
    if (draft == null) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: ThemeV2Motion.duration(context, ThemeV2MotionToken.standard),
      curve: ThemeV2Motion.easeFluid,
      builder: (context, progress, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: progress,
          child: Opacity(opacity: progress, child: child),
        ),
      ),
      child: Container(
        key: const ValueKey('calendar-inline-draft'),
        decoration: BoxDecoration(
          color: tokens.accentSoft,
          border: Border.all(color: tokens.accent),
          borderRadius: BorderRadius.circular(ThemeV2Radii.sm),
        ),
        padding: const EdgeInsets.only(left: ThemeV2Spacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _created == null ? '创建一个新日程' : '日程已创建',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${calendarTimeLabel(draft.startAt)}–${calendarTimeLabel(draft.endAt)}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: tokens.muted),
                  ),
                  if (_failed)
                    Text(
                      '创建失败，请重试',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: tokens.critical),
                    ),
                ],
              ),
            ),
            if (_created != null)
              _DraftAction(
                label: '打开完整日程编辑器',
                icon: Icons.open_in_new,
                onTap: () => widget.onOpenEditor(_created!),
              )
            else ...[
              _DraftAction(label: '取消临时日程', icon: Icons.close, onTap: _cancel),
              _DraftAction(
                label: _failed ? '重试创建临时日程' : '确认创建临时日程',
                icon: Icons.check,
                onTap: widget.controller.isConfirmingDraft ? null : _confirm,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DraftAction extends StatelessWidget {
  const _DraftAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Semantics(
      label: label,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ThemeV2HitTarget(
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: ThemeV2Sizes.minTouchTarget,
              child: Icon(icon, size: 18, color: tokens.accent),
            ),
          ),
        ),
      ),
    );
  }
}
