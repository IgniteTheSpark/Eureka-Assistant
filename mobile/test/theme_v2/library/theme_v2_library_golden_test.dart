import 'dart:io';

import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme/theme_controller.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/library/container_index.dart';
import 'package:eureka/theme_v2/library/library_controller.dart';
import 'package:eureka/theme_v2/library/library_hub.dart';
import 'package:eureka/theme_v2/library/library_models.dart';
import 'package:eureka/theme_v2/library/library_navigation.dart';
import 'package:eureka/theme_v2/library/library_repository.dart';
import 'package:eureka/theme_v2/library/pinned_configuration.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:eureka/theme_v2/shell/theme_v2_floating_dock.dart';
import 'package:eureka/theme_v2/shell/theme_v2_global_top_nav.dart';
import 'package:eureka/theme_v2/shell/theme_v2_page_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const surface = ValueKey('library-golden-surface');

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

  Future<void> pumpGolden(
    WidgetTester tester, {
    required Widget Function(LibraryController controller) builder,
    required Brightness brightness,
    required LibrarySurface librarySurface,
    Size size = const Size(411, 960),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = await _fixtureController();
    addTearDown(controller.dispose);
    final navigation = LibraryNavigationController();
    addTearDown(navigation.dispose);
    if (librarySurface != LibrarySurface.hub) {
      navigation.open(librarySurface);
    }
    final theme = buildThemeV2Theme(brightness);
    final legacy = brightness == Brightness.dark
        ? EurekaColors.dark
        : EurekaColors.light;
    final previousThemeMode = themeModeNotifier.value;
    themeModeNotifier.value = brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
    addTearDown(() => themeModeNotifier.value = previousThemeMode);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [renderSpecsProvider.overrideWith((ref) async => const {})],
        child: MaterialApp(
          theme: theme.copyWith(
            extensions: [...theme.extensions.values, EurekaTheme(legacy)],
          ),
          home: MediaQuery(
            data: MediaQueryData.fromView(
              tester.view,
            ).copyWith(disableAnimations: true),
            child: RepaintBoundary(
              key: surface,
              child: ThemeV2PageScaffold(
                showTopNav: navigation.chrome.topNav,
                showDock: navigation.chrome.dock,
                topNav: ThemeV2GlobalTopNav(
                  deviceStatus: const DeviceStatusSummary.disconnected(),
                  onDevicePressed: () {},
                  onNotificationsPressed: () {},
                ),
                dock: ThemeV2FloatingDock(
                  selectedIndex: 2,
                  onDestinationSelected: (_) {},
                ),
                body: ColoredBox(
                  color: ThemeV2Tokens.forBrightness(brightness).background,
                  child: builder(controller),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    final suffix = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('hub 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        librarySurface: LibrarySurface.hub,
        builder: (controller) => LibraryHub(
          controller: controller,
          onOpenContainer: (_) {},
          onOpenContainerIndex: () {},
          onOpenAllContainers: () {},
          onConfigurePinned: () {},
          onCreateSkill: () {},
          onOpenRecent: (_) {},
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/library-hub-411-$suffix.png'),
      );
    });

    testWidgets('container index 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        librarySurface: LibrarySurface.containerIndex,
        builder: (controller) => ContainerIndex(
          controller: controller,
          onBack: () {},
          onOpenContainer: (_) {},
          onOpenAllContainers: () {},
          onCreateSkill: () {},
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/library-index-411-$suffix.png'),
      );
    });

    testWidgets('all containers 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        librarySurface: LibrarySurface.allContainers,
        builder: (controller) => AllContainers(
          controller: controller,
          onBack: () {},
          onOpenContainer: (_) {},
          onCreateSkill: () {},
        ),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/library-all-411-$suffix.png'),
      );
    });

    testWidgets('pinned configure 411 $suffix', (tester) async {
      await pumpGolden(
        tester,
        brightness: brightness,
        librarySurface: LibrarySurface.pinnedConfiguration,
        builder: (controller) =>
            PinnedConfiguration(controller: controller, onDone: () {}),
      );
      await expectLater(
        find.byKey(surface),
        matchesGoldenFile('goldens/library-pinned-411-$suffix.png'),
      );
    });
  }

  testWidgets('hub 360 light', (tester) async {
    await pumpGolden(
      tester,
      brightness: Brightness.light,
      librarySurface: LibrarySurface.hub,
      size: const Size(360, 800),
      builder: (controller) => LibraryHub(
        controller: controller,
        onOpenContainer: (_) {},
        onOpenContainerIndex: () {},
        onOpenAllContainers: () {},
        onConfigurePinned: () {},
        onCreateSkill: () {},
        onOpenRecent: (_) {},
      ),
    );
    await expectLater(
      find.byKey(surface),
      matchesGoldenFile('goldens/library-hub-360-light.png'),
    );
  });
}

Future<LibraryController> _fixtureController() async {
  final now = DateTime(2026, 7, 28, 21, 34);
  final overview = LibraryOverview(
    systemContainers: const [
      LibraryContainerSummary(
        id: 'todo',
        label: '待办',
        mark: '待',
        type: LibraryContainerType.todo,
        totalCount: 48,
        isSystem: true,
        userSkillId: 's-todo',
      ),
      LibraryContainerSummary(
        id: 'notes',
        label: '笔记',
        mark: '记',
        type: LibraryContainerType.notes,
        totalCount: 16,
        isSystem: true,
        userSkillId: 's-notes',
      ),
      LibraryContainerSummary(
        id: 'event',
        label: '事件',
        mark: '日',
        type: LibraryContainerType.event,
        totalCount: 1,
        isSystem: true,
      ),
      LibraryContainerSummary(
        id: 'contact',
        label: '联系人',
        mark: '人',
        type: LibraryContainerType.contact,
        totalCount: 1,
        isSystem: true,
      ),
    ],
    customContainers: const [
      LibraryContainerSummary(
        id: 'tennis',
        label: '网球记录',
        mark: '球',
        type: LibraryContainerType.custom,
        totalCount: 9,
        isSystem: false,
        userSkillId: 's-tennis',
      ),
      LibraryContainerSummary(
        id: 'expense',
        label: '消费账本',
        mark: '¥',
        type: LibraryContainerType.custom,
        totalCount: 27,
        isSystem: false,
        userSkillId: 's-expense',
      ),
      LibraryContainerSummary(
        id: 'running',
        label: '跑步记录',
        mark: '跑',
        type: LibraryContainerType.custom,
        totalCount: 14,
        isSystem: false,
        userSkillId: 's-running',
      ),
      LibraryContainerSummary(
        id: 'water',
        label: '喝水记录',
        mark: '水',
        type: LibraryContainerType.custom,
        totalCount: 32,
        isSystem: false,
        userSkillId: 's-water',
      ),
    ],
    recentAssets: [
      LibraryRecentAsset(
        id: 'a1',
        skillName: 'todo',
        skillLabel: '待办',
        mark: '待',
        primaryValue: '提交 UI 重构',
        createdAt: now,
        detailCard: const {
          'asset_id': 'a1',
          'user_skill_name': 'todo',
          'payload': {'title': '提交 UI 重构'},
        },
      ),
      LibraryRecentAsset(
        id: 'a2',
        skillName: 'notes',
        skillLabel: '笔记',
        mark: '记',
        primaryValue: '资产库交互记录',
        createdAt: now.subtract(const Duration(minutes: 16)),
        detailCard: const {
          'asset_id': 'a2',
          'user_skill_name': 'notes',
          'payload': {'content': '资产库交互记录'},
        },
      ),
    ],
    totalAssetCount: 100,
  );
  final controller = LibraryController(
    repository: _GoldenRepository(overview),
    pinnedStore: const _GoldenPinnedStore(),
  );
  await controller.load();
  return controller;
}

class _GoldenRepository implements LibraryRepository {
  const _GoldenRepository(this.overview);

  final LibraryOverview overview;

  @override
  Future<LibraryOverview> loadOverview() async => overview;
}

class _GoldenPinnedStore implements LibraryPinnedStore {
  const _GoldenPinnedStore();

  @override
  Future<List<String>> load() async => const [
    'todo',
    'notes',
    'tennis',
    'expense',
    'event',
    'contact',
  ];

  @override
  Future<void> save(List<String> ids) async {}
}
