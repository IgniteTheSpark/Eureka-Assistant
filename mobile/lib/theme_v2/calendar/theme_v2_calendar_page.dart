import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../data_revision.dart';
import '../../pages/calendar_page.dart';
import '../../pages/day_flash_view.dart';
import '../../render/render_spec.dart';
import '../../timeline/timeline.dart';
import '../foundation/theme_v2_motion.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../foundation/theme_v2_typography.dart';
import '../shell/theme_v2_async_state.dart';
import 'calendar_controller.dart';
import 'calendar_day_detail.dart';
import 'calendar_editor_router.dart';
import 'calendar_flow_view.dart';
import 'calendar_manual_record_picker.dart';
import 'calendar_mode_state.dart';
import 'calendar_models.dart';
import 'calendar_month_view.dart';
import 'calendar_schedule_grid.dart';
import 'calendar_year_view.dart';

typedef CalendarDataLoader = Future<CalendarData> Function();

class ThemeV2CalendarPage extends StatefulWidget {
  const ThemeV2CalendarPage({
    super.key,
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
  ApiClient? _api;
  ApiClient get _apiClient => _api ??= ApiClient();
  late final bool _ownsController = widget.controller == null;
  late final CalendarController _controller =
      widget.controller ??
      CalendarController(modeState: CalendarModeState.fromStartDefine());
  late final DateTime _today = calendarDayOf(widget.today ?? DateTime.now());
  late DateTime _focusMonth = DateTime(_today.year, _today.month);
  PageController? _pages;
  PageController get _pageController =>
      _pages ??= PageController(initialPage: _controller.horizontalIndex);
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
      fetchSkills(_apiClient),
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
      final duration = ThemeV2Motion.duration(
        context,
        ThemeV2MotionToken.fluid,
      );
      if (duration == Duration.zero) {
        pages.jumpToPage(mode.index);
      } else {
        pages.animateToPage(
          mode.index,
          duration: duration,
          curve: ThemeV2Motion.easeFluid,
        );
      }
    }
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
      unawaited(openCalendarTimelineItem(context, record.item, _currentSkills));
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
      loader: () => fetchCalendarSkillOptions(_apiClient),
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
    final flashes =
        _currentData.byDay[calendarDayOf(day)]
            ?.where((item) => item.kind == 'input_turn')
            .toList() ??
        const <TimelineItem>[];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DayFlashView(day: day, flashes: flashes, skills: _currentSkills),
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
    if (pages != null && pages.hasClients) pages.jumpToPage(0);
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
    final next = !todoPayloadIsDone(record.item.payload);
    await _apiClient.putJson('/api/assets/${record.id}', {
      'payload_patch': {'status': next ? 'done' : 'pending'},
    });
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
    _pages?.dispose();
    _api?.close();
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
      );
    }
    final pages = PageView(
      key: const ValueKey('calendar-mode-pages'),
      controller: _pageController,
      onPageChanged: (index) {
        if (_controller.setHorizontalIndex(index)) setState(() {});
      },
      children: [
        CalendarFlowView(
          key: ValueKey('calendar-flow-$_flowRevision'),
          data: data,
          controller: _controller,
          today: _today,
          onOpenDay: _openDay,
          onRequestManualRecord: _requestManualRecord,
          onOpenRecord: _openRecord,
          onOpenFlash: _openFlash,
        ),
        CalendarMonthView(
          month: _focusMonth,
          data: data,
          controller: _controller,
          today: _today,
          onOpenDay: _openDay,
          onOpenRecord: _openRecord,
          onMonthChanged: (month) => _focusMonth = month,
        ),
        CalendarYearView(
          focusMonth: _focusMonth,
          data: data,
          today: _today,
          onSelectMonth: (month) {
            _focusMonth = month;
            _selectMode(CalendarMode.month);
          },
        ),
      ],
    );
    return pages;
  }
}

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
  });

  final DateTime day;
  final CalendarData data;
  final CalendarController controller;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final Future<void> Function(CalendarRecord) onToggleTodo;
  final CalendarDraftMutation onCreateDraft;
  final ValueChanged<CalendarInlineDraft> onOpenDraftEditor;
  final VoidCallback onManualRecord;

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
              height: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
