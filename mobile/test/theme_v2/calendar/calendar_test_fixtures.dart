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
}) {
  return TimelineItem(
    kind: kind,
    id: id,
    effectiveAt: at,
    title: title.isEmpty ? id : title,
    subtitle: '',
    skillName: skillName,
    sessionId: null,
    derived: const {},
    endAt: endAt,
    allDay: allDay,
    hasClockTime: hasClockTime,
    hasScheduledTime: hasScheduledTime,
    period: period,
  );
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
