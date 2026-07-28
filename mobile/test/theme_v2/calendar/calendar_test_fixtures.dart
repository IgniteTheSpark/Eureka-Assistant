import 'package:eureka/theme_v2/calendar/calendar_models.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const calendarFixtureSize = Size(411, 960);

TimelineItem calendarFixtureItem({
  required String id,
  required DateTime at,
  String title = '',
  String kind = 'event',
  String? skillName,
  DateTime? endAt,
  bool allDay = false,
  bool hasClockTime = false,
  bool hasScheduledTime = false,
  String period = '',
  String? sessionId,
  Map<String, dynamic> payload = const {},
}) {
  return TimelineItem(
    kind: kind,
    id: id,
    effectiveAt: at,
    title: title.isEmpty ? id : title,
    subtitle: '',
    skillName: skillName,
    sessionId: sessionId,
    payload: payload,
    derived: const {},
    endAt: endAt,
    allDay: allDay,
    hasClockTime: hasClockTime,
    hasScheduledTime: hasScheduledTime,
    period: period,
  );
}

CalendarData calendarHandoffOverviewData() {
  final day = DateTime(2026, 7, 3);
  final items = <TimelineItem>[
    calendarFixtureItem(
      id: 'handoff-online',
      title: '线上复盘会',
      at: DateTime(2026, 7, 3, 9),
      endAt: DateTime(2026, 7, 3, 10),
    ),
    calendarFixtureItem(
      id: 'handoff-client',
      title: '客户要求拜访',
      at: DateTime(2026, 7, 3, 9, 30),
      endAt: DateTime(2026, 7, 3, 10, 30),
    ),
    calendarFixtureItem(
      id: 'handoff-water',
      title: '奶 · 150 ml',
      at: DateTime(2026, 7, 3, 10),
      kind: 'asset',
      skillName: 'health',
      hasClockTime: true,
    ),
    calendarFixtureItem(
      id: 'handoff-tennis',
      title: '网球比赛',
      at: DateTime(2026, 7, 3, 11),
      kind: 'asset',
      skillName: 'sport',
      hasClockTime: true,
    ),
    calendarFixtureItem(
      id: 'handoff-training',
      title: '培训',
      at: DateTime(2026, 7, 3, 15),
      kind: 'asset',
      skillName: 'training',
      hasClockTime: true,
    ),
    calendarFixtureItem(
      id: 'handoff-discussion',
      title: '小型讨论会',
      at: DateTime(2026, 7, 3, 15, 30),
      endAt: DateTime(2026, 7, 3, 16, 30),
    ),
    calendarFixtureItem(
      id: 'handoff-shopping',
      title: '35.2 · 买菜',
      at: DateTime(2026, 7, 3, 16),
      kind: 'asset',
      skillName: 'shopping',
      period: '下午',
    ),
    calendarFixtureItem(
      id: 'handoff-interview',
      title: '线上面试',
      at: DateTime(2026, 7, 3, 20),
      endAt: DateTime(2026, 7, 3, 21),
    ),
    calendarFixtureItem(
      id: 'handoff-note',
      title: '整理今日纪要',
      at: DateTime(2026, 7, 3, 21),
      kind: 'asset',
      skillName: 'note',
      period: '晚上',
    ),
    for (var index = 0; index < 5; index++)
      calendarFixtureItem(
        id: 'handoff-flash-$index',
        title: '闪念 ${index + 1}',
        at: day.add(Duration(hours: 12, seconds: index)),
        kind: 'input_turn',
      ),
    calendarFixtureItem(
      id: 'handoff-next-training',
      title: '周末训练',
      at: DateTime(2026, 7, 4, 9),
      kind: 'asset',
      skillName: 'sport',
      hasClockTime: true,
    ),
    calendarFixtureItem(
      id: 'handoff-next-reading',
      title: '整理阅读清单',
      at: DateTime(2026, 7, 4, 15, 30),
      kind: 'asset',
      skillName: 'note',
      hasClockTime: true,
    ),
    for (var index = 0; index < 2; index++)
      calendarFixtureItem(
        id: 'handoff-next-flash-$index',
        title: '次日闪念 ${index + 1}',
        at: DateTime(2026, 7, 4, 12, 0, index),
        kind: 'input_turn',
      ),
  ];
  return CalendarData(items, const {
    'health': SkillMeta('🥛', '健康', 'blue'),
    'sport': SkillMeta('🎾', '运动', 'green'),
    'training': SkillMeta('🎓', '培训', 'purple'),
    'shopping': SkillMeta('🛒', '购物', 'gray'),
    'note': SkillMeta('📚', '笔记', 'amber'),
  });
}

CalendarData calendarHandoffScheduleData() {
  final day = DateTime(2026, 7, 3);
  final items = <TimelineItem>[
    calendarFixtureItem(
      id: 'release',
      title: '🚀 产品发布日',
      at: day,
      allDay: true,
    ),
    calendarFixtureItem(
      id: 'schedule-online',
      title: '线上复盘会',
      at: DateTime(2026, 7, 3, 9),
      endAt: DateTime(2026, 7, 3, 10),
    ),
    calendarFixtureItem(
      id: 'schedule-client',
      title: '客户拜访',
      at: DateTime(2026, 7, 3, 9, 30),
      endAt: DateTime(2026, 7, 3, 10, 30),
    ),
    calendarFixtureItem(
      id: 'schedule-tennis',
      title: '网球比赛',
      at: DateTime(2026, 7, 3, 11),
      endAt: DateTime(2026, 7, 3, 12, 30),
    ),
    calendarFixtureItem(
      id: 'schedule-discussion',
      title: '小型讨论会',
      at: DateTime(2026, 7, 3, 14),
      endAt: DateTime(2026, 7, 3, 16),
    ),
    calendarFixtureItem(
      id: 'schedule-training',
      title: '培训',
      at: DateTime(2026, 7, 3, 14, 30),
      endAt: DateTime(2026, 7, 3, 15, 30),
    ),
    for (var index = 0; index < 3; index++)
      calendarFixtureItem(
        id: 'schedule-todo-$index',
        title: const ['确认计划', '补充记录', '回复合作方'][index],
        at: DateTime(2026, 7, 3, 15, 0, index),
        kind: 'asset',
        skillName: 'todo',
        hasScheduledTime: true,
      ),
    for (var index = 0; index < 5; index++)
      calendarFixtureItem(
        id: 'schedule-unscheduled-$index',
        title: const ['准备发布材料', '回复合作方', '整理演示备注', '更新看板', '确认名单'][index],
        at: day.add(Duration(minutes: index)),
        kind: 'asset',
        skillName: 'todo',
        payload: {'status': index == 0 ? 'done' : 'pending'},
      ),
  ];
  return CalendarData(items, const {'todo': SkillMeta('✅', '待办', 'green')});
}

CalendarData calendarHandoffAssetEmptyData() {
  final day = DateTime(2026, 7, 3);
  return CalendarData([
    for (var index = 0; index < 5; index++)
      calendarFixtureItem(
        id: 'empty-flash-$index',
        title: '闪念 ${index + 1}',
        at: day.add(Duration(hours: 12, seconds: index)),
        kind: 'input_turn',
      ),
  ], const {});
}

CalendarData calendarFixtureData() {
  final july3 = DateTime(2026, 7, 3);
  return CalendarData(
    [
      calendarFixtureItem(
        id: 'event-a',
        title: '线上复盘会',
        at: july3.add(const Duration(hours: 9)),
        endAt: july3.add(const Duration(hours: 10)),
      ),
      calendarFixtureItem(
        id: 'event-b',
        title: '客户拜访',
        at: july3.add(const Duration(hours: 9, minutes: 30)),
        endAt: july3.add(const Duration(hours: 10, minutes: 30)),
      ),
      calendarFixtureItem(
        id: 'todo-a',
        title: '回访客户',
        at: july3.add(const Duration(hours: 15, minutes: 30)),
        kind: 'asset',
        skillName: 'todo',
        hasScheduledTime: true,
      ),
      calendarFixtureItem(
        id: 'todo-b',
        title: '整理纪要',
        at: july3.add(const Duration(hours: 15, minutes: 30, seconds: 20)),
        kind: 'asset',
        skillName: 'todo',
        hasScheduledTime: true,
      ),
      calendarFixtureItem(
        id: 'adjacent-event',
        title: '十五分钟后开始',
        at: july3.add(const Duration(hours: 15, minutes: 45)),
        endAt: july3.add(const Duration(hours: 16)),
      ),
      calendarFixtureItem(
        id: 'later-event',
        title: '线上面试',
        at: july3.add(const Duration(hours: 16)),
        endAt: july3.add(const Duration(hours: 17)),
      ),
      calendarFixtureItem(
        id: 'untimed',
        title: '买菜',
        at: july3.add(const Duration(hours: 16, minutes: 20)),
        kind: 'asset',
        skillName: 'todo',
        period: '下午',
      ),
      calendarFixtureItem(
        id: 'next-day',
        title: '周末训练',
        at: DateTime(2026, 7, 4, 9),
        endAt: DateTime(2026, 7, 4, 10),
      ),
    ],
    const {'todo': SkillMeta('📋', '待办', 'blue')},
  );
}

Widget calendarTestHost(
  Widget child, {
  Brightness brightness = Brightness.light,
  Size size = calendarFixtureSize,
  bool disableAnimations = true,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      devicePixelRatio: 1,
      platformBrightness: brightness,
      disableAnimations: disableAnimations,
      textScaler: TextScaler.noScaling,
    ),
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      theme: buildThemeV2Theme(Brightness.light),
      darkTheme: buildThemeV2Theme(Brightness.dark),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
}

/// Route-level Calendar tests also exercise mature legacy surfaces such as
/// EventForm and DayFlashView, so their host mirrors the production theme,
/// which carries both EurekaTheme and ThemeV2Tokens extensions.
Widget calendarLegacyRouteTestHost(
  Widget child, {
  Size size = calendarFixtureSize,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      devicePixelRatio: 1,
      platformBrightness: Brightness.light,
      disableAnimations: true,
      textScaler: TextScaler.noScaling,
    ),
    child: ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        theme: buildEurekaTheme(EurekaColors.light),
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
}
