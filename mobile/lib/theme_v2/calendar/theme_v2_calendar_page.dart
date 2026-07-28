import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../data_revision.dart';
import '../../pages/calendar_page.dart';
import '../../pages/create_asset.dart' show showCreateMenu;
import '../../pages/day_flash_view.dart';
import '../../timeline/timeline.dart';
import '../foundation/theme_v2_motion.dart';
import '../foundation/theme_v2_semantics.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import '../shell/theme_v2_async_state.dart';
import 'calendar_components.dart';
import 'calendar_controller.dart';
import 'calendar_day_detail.dart';
import 'calendar_flow_view.dart';
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
        ThemeV2MotionToken.standard,
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
    showCreateMenu(context, presetDate: day);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return ColoredBox(
      color: tokens.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeV2Spacing.lg,
              ThemeV2Spacing.sm,
              ThemeV2Spacing.sm,
              ThemeV2Spacing.sm,
            ),
            child: Row(
              children: [
                CalendarModeControl(
                  mode: _controller.mode,
                  onSelected: _selectMode,
                ),
                const Spacer(),
                ThemeV2IconButton(
                  semanticLabel: '刷新日历',
                  icon: Icons.refresh,
                  color: tokens.muted,
                  onPressed: () => setState(() => _retry++),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.initialData != null
                ? _dataBody(widget.initialData!)
                : ValueListenableBuilder<int>(
                    valueListenable: dataRevision,
                    builder: (context, revision, _) {
                      return FutureBuilder<CalendarData>(
                        future: _futureFor(revision),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return _structuralState(
                              ThemeV2AsyncState.error(
                                title: '日历加载失败',
                                message: '${snapshot.error}',
                                onRetry: () => setState(() => _retry++),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return _structuralState(
                              const ThemeV2AsyncState.loading(label: '正在加载日历'),
                            );
                          }
                          return _dataBody(snapshot.data!);
                        },
                      );
                    },
                  ),
          ),
        ],
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
        onCreateDraft: _createDraft,
        onOpenDraftEditor: _openDraftEditor,
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
    if (data.items.isNotEmpty) return pages;
    return Stack(
      children: [
        Positioned.fill(child: pages),
        Positioned.fill(
          child: IgnorePointer(
            child: _structuralState(
              const ThemeV2AsyncState.empty(
                title: '还没有日历记录',
                message: '选择日期即可创建第一条日程。',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarScheduleRoute extends StatelessWidget {
  const _CalendarScheduleRoute({
    required this.day,
    required this.data,
    required this.controller,
    required this.onOpenRecord,
    required this.onCreateDraft,
    required this.onOpenDraftEditor,
  });

  final DateTime day;
  final CalendarData data;
  final CalendarController controller;
  final ValueChanged<CalendarRecord> onOpenRecord;
  final CalendarDraftMutation onCreateDraft;
  final ValueChanged<CalendarInlineDraft> onOpenDraftEditor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: tokens.background,
        foregroundColor: tokens.foreground,
        surfaceTintColor: Colors.transparent,
        title: Text('${day.month}月${day.day}日'),
      ),
      body: CalendarScheduleGrid(
        day: day,
        records: data.records,
        skills: data.skills,
        controller: controller,
        onOpenRecord: onOpenRecord,
        onCreateDraft: onCreateDraft,
        onOpenDraftEditor: onOpenDraftEditor,
      ),
    );
  }
}
