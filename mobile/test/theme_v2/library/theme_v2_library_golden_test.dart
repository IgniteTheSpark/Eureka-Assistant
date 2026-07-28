import 'dart:io';

import 'package:eureka/assets/assets.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/library/container_index.dart';
import 'package:eureka/theme_v2/library/library_controller.dart';
import 'package:eureka/theme_v2/library/library_hub.dart';
import 'package:eureka/theme_v2/library/pinned_configuration.dart';
import 'package:eureka/timeline/timeline.dart';
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
    Size size = const Size(411, 960),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = await _fixtureController();
    final theme = buildThemeV2Theme(brightness);
    final legacy = brightness == Brightness.dark
        ? EurekaColors.dark
        : EurekaColors.light;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [renderSpecsProvider.overrideWith((ref) async => const {})],
        child: MaterialApp(
          theme: theme.copyWith(
            extensions: [...theme.extensions.values, EurekaTheme(legacy)],
          ),
          home: Scaffold(
            body: SafeArea(
              child: RepaintBoundary(
                key: surface,
                child: ColoredBox(
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
  final snapshot = LibrarySnapshot(
    assets: [
      AssetItem(
        id: 'a1',
        skillName: 'todo',
        payload: const {'title': '提交 UI 重构'},
        createdAt: now,
      ),
      AssetItem(
        id: 'a2',
        skillName: 'notes',
        payload: const {'content': '资产库交互记录'},
        createdAt: now.subtract(const Duration(minutes: 16)),
      ),
    ],
    skills: const {
      'todo': SkillMeta('📋', '待办', 'blue', 's-todo'),
      'notes': SkillMeta('✍️', '笔记', 'amber', 's-notes'),
      'tennis': SkillMeta('🎾', '网球记录', 'green', 's-tennis'),
      'expense': SkillMeta('💰', '消费账本', 'green', 's-expense'),
    },
    events: [
      {
        'event_id': 'e1',
        'title': '设计评审',
        'created_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      },
    ],
    contacts: [
      {
        'id': 'c1',
        'name': '王小明',
        'created_at': now.subtract(const Duration(hours: 3)).toIso8601String(),
      },
    ],
    reports: [
      {
        'id': 'r1',
        'title': '周报',
        'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      },
    ],
    assetCounts: const {'todo': 48, 'notes': 16, 'tennis': 9, 'expense': 27},
    availableSources: const {
      'assets',
      'skills',
      'events',
      'contacts',
      'reports',
      'counts',
    },
  );
  final controller = LibraryController(
    repository: _GoldenRepository(snapshot),
    pinnedStore: const _GoldenPinnedStore(),
  );
  await controller.load();
  return controller;
}

class _GoldenRepository implements LibraryRepository {
  const _GoldenRepository(this.snapshot);

  final LibrarySnapshot snapshot;

  @override
  Future<LibrarySnapshot> load() async => snapshot;
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
