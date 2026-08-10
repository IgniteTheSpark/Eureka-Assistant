import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../data_revision.dart';
import '../../pages/calendar_page.dart';
import '../../render/render_spec.dart';
import '../../timeline/timeline.dart';
import '../capture/capture_session_page.dart';
import '../foundation/theme_v2_motion.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import '../shell/theme_v2_async_state.dart';
import '../shell/theme_v2_page_title.dart';
import 'calendar_controller.dart';
import 'calendar_components.dart';
import 'calendar_day_detail.dart';
import 'calendar_editor_router.dart';
import 'calendar_flow_view.dart';
import 'calendar_manual_record_picker.dart';
import 'calendar_mode_state.dart';
import 'calendar_models.dart';
import 'calendar_month_view.dart';
import 'calendar_schedule_grid.dart';
import 'calendar_scale_droplet.dart';
import 'calendar_year_view.dart';

typedef CalendarDataLoader = Future<CalendarData> Function();

Future<void> updateThemeV2CalendarTodo(
  ApiClient api,
  CalendarRecord record,
) async {
  final next = !todoPayloadIsDone(record.item.payload);
  await api.patchJson('/api/assets/${record.id}', {
    'payload': {...record.item.payload, 'status': next ? 'done' : 'pending'},
  });
}

class ThemeV2CalendarPage extends StatefulWidget {
  const ThemeV2CalendarPage({
    super.key,
    this.api,
    this.dataLoader,
    this.initialData,
    this.controller,
    this.today,
    this.onOpenDay,
    this.onRequestManualRecord,
    this.onOpenRecord,
    this.onOpenFlash,
    this.onCreateDraft,
    this.onOpenDraftEditor,
  });

  final ApiClient? api;
  final CalendarDataLoader? dataLoader;
  final CalendarData? initialData;
  final CalendarController? controller;
  final DateTime? today;
  final ValueChanged<DateTime>? onOpenDay;
  final ValueChanged<DateTime>? onRequestManualRecord;
  final ValueChanged<CalendarRecord>? onOpenRecord;
  final ValueChanged<DateTime>? onOpenFlash;
  final CalendarDraftMutation? onCreateDraft;
  final ValueChanged<CalendarInlineDraft>? onOpenDraftEditor;

  @override
  State<ThemeV2CalendarPage> createState() => _ThemeV2CalendarPageState();
}

class _ThemeV2CalendarPageState extends State<ThemeV2CalendarPage> {
  static const _pageSeed = 3000;

  ApiClient? _ownedApi;
  ApiClient get _apiClient => widget.api ?? (_ownedApi ??= ApiClient());
  late final bool _ownsController = widget.controller == null;
  late final CalendarController _controller =
      widget.controller ??
      CalendarController(modeState: CalendarModeState.fromStartDefine());
  late final DateTime _today = calendarDayOf(widget.today ?? DateTime.now());
  late DateTime _focusMonth = DateTime(_today.year, _today.month);
  late int _pageIndex = _pageSeed + _controller.horizontalIndex;
  PageController? _pages;
  PageController get _pageController =>
      _pages ??= PageController(initialPage: _pageIndex);
  final ValueNotifier<_CalendarScaleDragFeedback?> _scaleDragFeedback =
      ValueNotifier(null);
  final ValueNotifier<CalendarMode?> _scaleConfirmation = ValueNotifier(null);
  Timer? _scaleConfirmationTimer;
  Timer? _scaleSettleTimer;
  int? _scaleDragOriginPage;
  Offset? _scalePointerOrigin;
  Axis? _scalePointerAxis;
  int _flowRevision = 0;
  Future<CalendarData>? _future;
  CalendarData? _lastData;
  int _loadedRevision = -1;
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    calendarHome.addListener(_goHome);
  }

  Future<CalendarData> _loadProduction() async {
    final result = await Future.wait([
      fetchTimeline(_apiClient),
      fetchSkills(_apiClient, coreRecordsOnly: true),
    ]);
    return CalendarData(
      result[0] as List<TimelineItem>,
      result[1] as Map<String, SkillMeta>,
    );
  }

  Future<CalendarData> _futureFor(int revision) {
    final key = revision * 1000 + _retry;
    if (_future == null || key != _loadedRevision) {
      _loadedRevision = key;
      _future = (widget.dataLoader ?? _loadProduction)();
    }
    return _future!;
  }

  void _selectMode(CalendarMode mode) {
    if (mode == CalendarMode.flow && _controller.mode == CalendarMode.flow) {
      _goHome();
      return;
    }
    if (_controller.selectMode(mode)) setState(() {});
    final pages = _pages;
    if (pages != null && pages.hasClients) {
      final targetPage = _nearestPageForMode(mode);
      _pageIndex = targetPage;
      final duration = ThemeV2Motion.duration(
        context,
        ThemeV2MotionToken.fluid,
      );
      if (duration == Duration.zero) {
        pages.jumpToPage(targetPage);
      } else {
        pages.animateToPage(
          targetPage,
          duration: duration,
          curve: ThemeV2Motion.easeFluid,
        );
      }
    }
  }

  bool _handleScaleScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.horizontal) return false;

    final originPage = _scaleDragOriginPage;
    if (originPage == null) return false;

    if (notification is ScrollUpdateNotification) {
      if (_scalePointerOrigin == null) {
        final metrics = notification.metrics;
        final page = metrics.pixels / metrics.viewportDimension;
        final displacement = (page - originPage) * metrics.viewportDimension;
        _updateScaleDragFeedback(displacement);
      }
      return false;
    }

    if (notification is ScrollEndNotification) {
      _scaleDragOriginPage = null;
      _scaleDragFeedback.value = null;
    }
    return false;
  }

  void _handleScalePointerDown(PointerDownEvent event) {
    _scaleSettleTimer?.cancel();
    _scalePointerOrigin = event.localPosition;
    _scalePointerAxis = null;
    _scaleDragOriginPage = _pageIndex;
    _scaleDragFeedback.value = null;
  }

  void _handleScalePointerMove(PointerMoveEvent event) {
    final origin = _scalePointerOrigin;
    if (origin == null) return;
    final delta = event.localPosition - origin;
    final horizontal = delta.dx.abs();
    final vertical = delta.dy.abs();
    if (_scalePointerAxis == null && (horizontal > 12 || vertical > 12)) {
      _scalePointerAxis = horizontal > vertical
          ? Axis.horizontal
          : Axis.vertical;
    }
    if (_scalePointerAxis == Axis.horizontal) {
      // Page coordinates move opposite to the finger.
      final verticalDisplacement = delta.dy.abs() < 3 ? 0.0 : delta.dy * 0.6;
      _updateScaleDragFeedback(
        -delta.dx,
        centerY: origin.dy + verticalDisplacement,
      );
    }
  }

  void _handleScalePointerUp(PointerUpEvent event) {
    final originPage = _scaleDragOriginPage;
    final completedHorizontalDrag =
        _scalePointerAxis == Axis.horizontal && originPage != null;
    _scalePointerOrigin = null;
    if (!completedHorizontalDrag) {
      _scaleDragOriginPage = null;
      _scaleDragFeedback.value = null;
    } else {
      _scaleSettleTimer?.cancel();
      _scaleSettleTimer = Timer(const Duration(milliseconds: 320), () {
        if (!mounted) return;
        _scaleDragOriginPage = null;
        _scaleDragFeedback.value = null;
        if (_pageIndex != originPage) {
          _showScaleConfirmation(
            CalendarMode.values[_pageIndex % CalendarMode.values.length],
          );
        }
      });
    }
    _scalePointerAxis = null;
  }

  void _handleScalePointerCancel(PointerCancelEvent event) {
    _scaleSettleTimer?.cancel();
    _scalePointerOrigin = null;
    _scalePointerAxis = null;
    _scaleDragOriginPage = null;
    _scaleDragFeedback.value = null;
  }

  void _updateScaleDragFeedback(double displacement, {double? centerY}) {
    final originPage = _scaleDragOriginPage;
    final distance = displacement.abs();
    if (originPage == null || distance <= 12) {
      _scaleDragFeedback.value = null;
      return;
    }

    final direction = displacement > 0 ? 1 : -1;
    final targetPage = originPage + direction;
    _scaleDragFeedback.value = _CalendarScaleDragFeedback(
      target: CalendarMode.values[targetPage % CalendarMode.values.length],
      onRightEdge: direction > 0,
      shapeProgress: ((distance - 12) / 26).clamp(0, 1),
      labelProgress: ((distance - 30) / 8).clamp(0, 1),
      centerY: centerY,
    );
  }

  void _showScaleConfirmation(CalendarMode mode) {
    _scaleConfirmationTimer?.cancel();
    _scaleConfirmation.value = mode;
    _scaleConfirmationTimer = Timer(const Duration(milliseconds: 920), () {
      if (mounted && _scaleConfirmation.value == mode) {
        _scaleConfirmation.value = null;
      }
    });
  }

  int _nearestPageForMode(CalendarMode mode) {
    final currentMode = _pageIndex % CalendarMode.values.length;
    var delta = mode.index - currentMode;
    if (delta > 1) delta -= CalendarMode.values.length;
    if (delta < -1) delta += CalendarMode.values.length;
    return _pageIndex + delta;
  }

  void _openDay(DateTime day) {
    final callback = widget.onOpenDay;
    if (callback != null) {
      callback(day);
      return;
    }
    _controller.openDay(day);
    setState(() {});
  }

  void _openRecord(CalendarRecord record) {
    final callback = widget.onOpenRecord;
    if (callback != null) {
      callback(record);
    } else {
      unawaited(
        openCalendarTimelineItem(
          context,
          record.item,
          _currentSkills,
          coreRecordsOnly: true,
        ),
      );
    }
  }

  void _requestManualRecord(DateTime day) {
    _controller.changeDate(day);
    final callback = widget.onRequestManualRecord;
    if (callback != null) {
      callback(day);
      return;
    }
    unawaited(_pickManualRecordSkill(day));
  }

  Future<void> _pickManualRecordSkill(DateTime day) async {
    final option = await showCalendarManualRecordPicker(
      context,
      effectiveDate: day,
      loader: () => fetchCalendarSkillCatalog(_apiClient),
    );
    if (option == null || !mounted) return;
    await openCalendarSkillEditor(context, option, day);
  }

  void _openFlash(DateTime day) {
    final callback = widget.onOpenFlash;
    if (callback != null) {
      callback(day);
      return;
    }
    unawaited(_openFlashSession(day));
  }

  Future<void> _openFlashSession(DateTime day) async {
    final flashes =
        _currentData.byDay[calendarDayOf(day)]
            ?.where((item) => item.kind == 'input_turn')
            .toList() ??
        const <TimelineItem>[];
    if (!mounted || flashes.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CaptureSessionPage(recordingId: calendarDayKey(day)),
      ),
    );
  }

  Map<String, SkillMeta> _currentSkills = const {};
  CalendarData _currentData = CalendarData(const [], const {});
  final Map<DateTime, String> _createdEventIds = {};

  void _goHome() {
    if (!mounted) return;
    _controller
      ..changeDate(_today)
      ..backToOverview()
      ..selectMode(CalendarMode.flow);
    setState(() {
      _focusMonth = DateTime(_today.year, _today.month);
      _flowRevision++;
    });
    final pages = _pages;
    if (pages != null && pages.hasClients) {
      _pageIndex = _nearestPageForMode(CalendarMode.flow);
      pages.jumpToPage(_pageIndex);
    }
  }

  Future<void> _createDraft(CalendarInlineDraft draft) async {
    final callback = widget.onCreateDraft;
    if (callback != null) return callback(draft);
    final eventId = await openCalendarInlineDraftEditor(context, draft);
    if (eventId == null) {
      throw StateError('event editor dismissed');
    }
    _createdEventIds[draft.startAt] = eventId;
  }

  Future<void> _toggleTodo(CalendarRecord record) async {
    await updateThemeV2CalendarTodo(_apiClient, record);
    bumpData();
  }

  void _openDraftEditor(CalendarInlineDraft draft) {
    final callback = widget.onOpenDraftEditor;
    if (callback != null) {
      callback(draft);
    } else {
      final eventId = _createdEventIds[draft.startAt];
      if (eventId != null) {
        unawaited(_openExistingDraftEditor(draft, eventId));
      }
    }
  }

  Future<void> _openExistingDraftEditor(
    CalendarInlineDraft draft,
    String eventId,
  ) async {
    try {
      await openCalendarInlineDraftEditor(context, draft, eventId: eventId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开日程失败：$error')));
    }
  }

  @override
  void dispose() {
    calendarHome.removeListener(_goHome);
    _scaleConfirmationTimer?.cancel();
    _scaleSettleTimer?.cancel();
    _scaleDragFeedback.dispose();
    _scaleConfirmation.dispose();
    _pages?.dispose();
    _ownedApi?.close();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return PopScope(
      canPop: _controller.surface == CalendarSurface.overview,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _controller.back()) setState(() {});
      },
      child: ColoredBox(
        color: tokens.background,
        child: widget.initialData != null
            ? _dataBody(widget.initialData!)
            : ValueListenableBuilder<int>(
                valueListenable: dataRevision,
                builder: (context, revision, _) {
                  return FutureBuilder<CalendarData>(
                    future: _futureFor(revision),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) _lastData = snapshot.data;
                      final data =
                          snapshot.data ??
                          _lastData ??
                          CalendarData(const [], const {});
                      final content = _dataBody(data);
                      if (snapshot.hasError) {
                        return Stack(
                          children: [
                            Positioned.fill(child: content),
                            Positioned.fill(
                              child: _structuralState(
                                ThemeV2AsyncState.error(
                                  title: '日历加载失败',
                                  message: '${snapshot.error}',
                                  onRetry: () => setState(() => _retry++),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      if (!snapshot.hasData && _lastData == null) {
                        return Stack(
                          children: [
                            Positioned.fill(child: content),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: _structuralState(
                                  const ThemeV2AsyncState.loading(
                                    label: '正在加载日历',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      return content;
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _structuralState(Widget state) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.themeV2.border)),
            ),
          ),
        ),
        Positioned.fill(child: state),
      ],
    );
  }

  Widget _dataBody(CalendarData data) {
    _currentSkills = data.skills;
    _currentData = data;
    final selectedDate = _controller.selectedDate;
    if (_controller.surface == CalendarSurface.dayDetail &&
        selectedDate != null) {
      return CalendarDayDetail(
        dayData: data.day(selectedDate),
        skills: data.skills,
        onBack: () => setState(_controller.backToOverview),
        onOpenSchedule: () => setState(_controller.openSchedule),
        onOpenFlash: () => _openFlash(selectedDate),
        onManualRecord: () => _requestManualRecord(selectedDate),
        onOpenRecord: _openRecord,
      );
    }
    if (_controller.surface == CalendarSurface.schedule &&
        selectedDate != null) {
      return _CalendarScheduleRoute(
        day: selectedDate,
        data: data,
        controller: _controller,
        onOpenRecord: _openRecord,
        onToggleTodo: _toggleTodo,
        onCreateDraft: _createDraft,
        onOpenDraftEditor: _openDraftEditor,
        onManualRecord: () => _requestManualRecord(selectedDate),
        onBack: () => setState(_controller.backToDay),
      );
    }
    final pages = PageView.builder(
      key: const ValueKey('calendar-mode-pages'),
      controller: _pageController,
      onPageChanged: (index) {
        _pageIndex = index;
        _controller.setHorizontalIndex(index % CalendarMode.values.length);
      },
      itemBuilder: (context, index) =>
          switch (CalendarMode.values[index % CalendarMode.values.length]) {
            CalendarMode.flow => CalendarFlowView(
              key: ValueKey('calendar-flow-$_flowRevision'),
              data: data,
              controller: _controller,
              today: _today,
              onOpenDay: _openDay,
              onRequestManualRecord: _requestManualRecord,
              onOpenRecord: _openRecord,
              onOpenFlash: _openFlash,
            ),
            CalendarMode.month => CalendarMonthView(
              month: _focusMonth,
              data: data,
              controller: _controller,
              today: _today,
              onOpenDay: _openDay,
              onOpenRecord: _openRecord,
              onMonthChanged: (month) => _focusMonth = month,
            ),
            CalendarMode.year => CalendarYearView(
              focusMonth: _focusMonth,
              data: data,
              today: _today,
              onSelectMonth: (month) {
                _focusMonth = month;
                _selectMode(CalendarMode.month);
              },
            ),
          },
    );
    final calendarOverviewStack = Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleScalePointerDown,
            onPointerMove: _handleScalePointerMove,
            onPointerUp: _handleScalePointerUp,
            onPointerCancel: _handleScalePointerCancel,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScaleScroll,
              child: pages,
            ),
          ),
        ),
        Positioned.fill(
          child: ValueListenableBuilder<_CalendarScaleDragFeedback?>(
            valueListenable: _scaleDragFeedback,
            builder: (context, feedback, _) {
              if (feedback == null) return const SizedBox.shrink();
              return CalendarScaleDragIndicator(
                targetLabel: _calendarScaleLabel(feedback.target),
                onRightEdge: feedback.onRightEdge,
                shapeProgress: feedback.shapeProgress,
                labelProgress: feedback.labelProgress,
                centerY: feedback.centerY,
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: ThemeV2Spacing.md,
          child: IgnorePointer(
            child: ValueListenableBuilder<CalendarMode?>(
              valueListenable: _scaleConfirmation,
              builder: (context, mode, _) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  reverseDuration: const Duration(milliseconds: 180),
                  child: mode == null
                      ? const SizedBox.shrink()
                      : Center(
                          key: ValueKey('calendar-scale-confirmation-$mode'),
                          child: _CalendarScaleConfirmation(mode: mode),
                        ),
                );
              },
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: ThemeV2PageTitle(
            key: ValueKey('theme-v2-page-title-calendar'),
            title: '日历',
          ),
        ),
        Expanded(child: calendarOverviewStack),
      ],
    );
  }
}

@immutable
class _CalendarScaleDragFeedback {
  const _CalendarScaleDragFeedback({
    required this.target,
    required this.onRightEdge,
    required this.shapeProgress,
    required this.labelProgress,
    required this.centerY,
  });

  final CalendarMode target;
  final bool onRightEdge;
  final double shapeProgress;
  final double labelProgress;
  final double? centerY;
}

class _CalendarScaleConfirmation extends StatelessWidget {
  const _CalendarScaleConfirmation({required this.mode});

  final CalendarMode mode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      key: const ValueKey('calendar-scale-confirmation'),
      width: 72,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.95),
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(ThemeV2Radii.sm),
        boxShadow: [
          BoxShadow(
            color: tokens.foreground.withValues(alpha: 0.08),
            offset: const Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Text(
        _calendarScaleLabel(mode),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: tokens.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _calendarScaleLabel(CalendarMode mode) => switch (mode) {
  CalendarMode.flow => '流览',
  CalendarMode.month => '月览',
  CalendarMode.year => '年览',
};

class _CalendarScheduleRoute extends StatelessWidget {
  const _CalendarScheduleRoute({
    required this.day,
    required this.data,
    required this.controller,
    required this.onOpenRecord,
    required this.onToggleTodo,
    required this.onCreateDraft,
    required this.onOpenDraftEditor,
    required this.onManualRecord,
    required this.onBack,
  });

  final DateTime day;
  final CalendarData data;
  final CalendarController controller;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final Future<void> Function(CalendarRecord) onToggleTodo;
  final CalendarDraftMutation onCreateDraft;
  final ValueChanged<CalendarInlineDraft> onOpenDraftEditor;
  final VoidCallback onManualRecord;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return ColoredBox(
      color: tokens.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ThemeV2Spacing.lg,
          ThemeV2Spacing.sm,
          ThemeV2Spacing.lg,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 148,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      height: ThemeV2Sizes.minTouchTarget,
                      child: TextButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('返回每日详情'),
                        style: TextButton.styleFrom(
                          foregroundColor: tokens.muted,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '${day.month}月${day.day}日　·　${_weekday(day)}',
                    style: ThemeV2Typography.mono(
                      fontSize: 10,
                      color: tokens.muted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        '日程',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              color: tokens.foreground,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -1,
                            ),
                      ),
                      const Spacer(),
                      Semantics(
                        label: '${day.month}月${day.day}日，手动记录',
                        button: true,
                        onTap: onManualRecord,
                        child: ExcludeSemantics(
                          child: SizedBox(
                            width: 76,
                            height: ThemeV2Sizes.minTouchTarget,
                            child: OutlinedButton.icon(
                              onPressed: onManualRecord,
                              icon: const Icon(Icons.playlist_add, size: 16),
                              label: const Text('记录'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: tokens.accent,
                                side: BorderSide(color: tokens.border),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ThemeV2Spacing.sm,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ThemeV2Spacing.sm),
                ],
              ),
            ),
            Expanded(
              child: CalendarScheduleGrid(
                day: day,
                records: data.records,
                skills: data.skills,
                controller: controller,
                onOpenRecord: onOpenRecord,
                onToggleTodo: onToggleTodo,
                onCreateDraft: onCreateDraft,
                onOpenDraftEditor: onOpenDraftEditor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _weekday(DateTime day) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][day.weekday - 1];
}
