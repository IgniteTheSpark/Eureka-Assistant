import 'dart:io';
import 'dart:ui';

import 'package:eureka/theme_v2/calendar/calendar_controller.dart';
import 'package:eureka/theme_v2/calendar/calendar_manual_record_picker.dart';
import 'package:eureka/theme_v2/calendar/theme_v2_calendar_page.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  const surface = ValueKey('calendar-manual-picker-golden-surface');
  final today = DateTime(2026, 7, 3);

  setUpAll(() async {
    await (FontLoader(
      'Geist',
    )..addFont(rootBundle.load('assets/fonts/Geist/Geist-Regular.ttf'))).load();
    await (FontLoader('Geist Mono')..addFont(
          rootBundle.load('assets/fonts/GeistMono/GeistMono-Regular.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();

    final pingFang = File('/System/Library/Fonts/PingFang.ttc');
    if (pingFang.existsSync()) {
      await (FontLoader(
        'PingFang SC',
      )..addFont(pingFang.readAsBytes().then(ByteData.sublistView))).load();
    }
  });

  Widget manualPickerState(Brightness brightness) {
    final base = ThemeV2PageScaffold(
      body: ThemeV2CalendarPage(
        active: false,
        controller: CalendarController(),
        today: today,
        initialData: calendarHandoffOverviewData(),
        onOpenRecord: (_) {},
        onCreateDraft: (_) async {},
        onOpenDraftEditor: (_) {},
      ),
      topNav: ThemeV2GlobalTopNav(
        deviceStatus: const DeviceStatusSummary.disconnected(),
        onDeviceSelected: (_) {},
        onNotificationsPressed: () {},
      ),
      dock: ThemeV2FloatingDock(
        selectedIndex: 1,
        onDestinationSelected: (_) {},
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: base),
        Positioned.fill(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: ColoredBox(
                color: Colors.black.withValues(
                  alpha: brightness == Brightness.dark ? 0.38 : 0.28,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: CalendarManualRecordPicker(
            effectiveDate: today,
            loader: () async => const CalendarSkillCatalog(
              options: [
                CalendarSkillOption.event(),
                CalendarSkillOption.asset(
                  name: 'todo',
                  displayName: '待办',
                  icon: '📋',
                  userSkillId: 'todo',
                ),
                CalendarSkillOption.asset(
                  name: 'note',
                  displayName: '笔记',
                  icon: '📝',
                  userSkillId: 'note',
                ),
                CalendarSkillOption.contact(
                  displayName: '联系人',
                  icon: '👤',
                  userSkillId: 'contact',
                ),
                CalendarSkillOption.asset(
                  name: 'running',
                  displayName: '跑步训练',
                  icon: '🏃',
                  userSkillId: 'running',
                ),
                CalendarSkillOption.asset(
                  name: 'coffee',
                  displayName: '咖啡记录',
                  icon: '☕',
                  userSkillId: 'coffee',
                ),
              ],
              recentNames: ['coffee', 'running', 'note', 'todo'],
            ),
            onSelected: (_) {},
            onClose: () {},
          ),
        ),
      ],
    );
  }

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('Manual Record Picker 411 $suffix', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = calendarFixtureSize;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        calendarTestHost(
          RepaintBoundary(key: surface, child: manualPickerState(brightness)),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/calendar-manual-picker-411-$suffix.png'),
      );
    });
  }
}
