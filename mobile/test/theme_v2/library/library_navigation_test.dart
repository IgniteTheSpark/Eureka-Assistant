import 'dart:async';

import 'package:eureka/assets/assets.dart';
import 'package:eureka/pages/category_detail_page.dart';
import 'package:eureka/pages/entity_list_page.dart';
import 'package:eureka/pages/library_page.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/container_index.dart';
import 'package:eureka/theme_v2/library/library_controller.dart';
import 'package:eureka/theme_v2/library/library_hub.dart';
import 'package:eureka/theme_v2/library/pinned_configuration.dart';
import 'package:eureka/theme_v2/library/theme_v2_library_page.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hub exposes four distinct IA entry types from controller data', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      LibraryHub(
        controller: controller,
        onOpenContainer: (_) {},
        onOpenContainerIndex: () {},
        onOpenAllContainers: () {},
        onConfigurePinned: () {},
        onCreateSkill: () {},
      ),
    );

    expect(find.byKey(const ValueKey('library-stats-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-pinned-mosaic')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-create-skill')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-recent-items')), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('12'), findsWidgets);
    expect(find.text('创建新技能'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('library-pinned-mosaic')),
        matching: find.byKey(const ValueKey('library-create-skill')),
      ),
      findsNothing,
    );
  });

  testWidgets('hub pinned mosaic is non-uniform and every tile is tappable', (
    tester,
  ) async {
    final controller = await _controller();
    String? opened;
    await _pumpHost(
      tester,
      LibraryHub(
        controller: controller,
        onOpenContainer: (container) => opened = container.id,
        onOpenContainerIndex: () {},
        onOpenAllContainers: () {},
        onConfigurePinned: () {},
        onCreateSkill: () {},
      ),
    );

    final first = tester.getSize(
      find.byKey(const ValueKey('library-pinned-tile-todo')),
    );
    final second = tester.getSize(
      find.byKey(const ValueKey('library-pinned-tile-notes')),
    );
    expect(first.width, greaterThan(second.width));
    expect(first.height, greaterThanOrEqualTo(44));

    await tester.tap(find.byKey(const ValueKey('library-pinned-tile-todo')));
    expect(opened, 'todo');
  });

  testWidgets(
    'recent asset event contact and report cells preserve navigation intent',
    (tester) async {
      final controller = await _controller();
      final opened = <String>[];
      await _pumpHost(
        tester,
        LibraryHub(
          controller: controller,
          onOpenContainer: (_) {},
          onOpenContainerIndex: () {},
          onOpenAllContainers: () {},
          onConfigurePinned: () {},
          onCreateSkill: () {},
          onOpenRecent: (item) => opened.add(item.containerId),
        ),
      );

      for (final id in ['todo', 'event', 'contact', 'report']) {
        await tester.tap(
          find.byKey(
            ValueKey(switch (id) {
              'todo' => 'library-recent-todo-a1',
              'event' => 'library-recent-event-e1',
              'contact' => 'library-recent-contact-c1',
              _ => 'library-recent-report-r1',
            }),
          ),
        );
      }
      expect(opened, ['todo', 'event', 'contact', 'report']);
    },
  );

  testWidgets('hub pinned tile long press opens pinned configuration', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      ThemeV2LibraryPage(
        controller: controller,
        autoLoad: false,
        onOpenContainer: (_) {},
        onCreateSkill: () {},
      ),
    );

    await tester.longPress(
      find.byKey(const ValueKey('library-pinned-tile-todo')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PinnedConfiguration), findsOneWidget);
  });

  testWidgets(
    'default recent asset and event open direct detail not container lists',
    (tester) async {
      final controller = await _controller();
      await _pumpHost(
        tester,
        ThemeV2LibraryPage(
          controller: controller,
          autoLoad: false,
          onOpenContainer: (_) {},
          onCreateSkill: () {},
        ),
      );

      await tester.tap(find.byKey(const ValueKey('library-recent-todo-a1')));
      await tester.pump();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byType(CategoryDetailPage), findsNothing);
      await tester.tapAt(const Offset(8, 80));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library-recent-event-e1')));
      await tester.pump();
      expect(find.byType(DraggableScrollableSheet), findsOneWidget);
      expect(find.byType(EntityListPage), findsNothing);
    },
  );

  testWidgets('page routes hub to index all containers and pinned configure', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      ThemeV2LibraryPage(
        controller: controller,
        autoLoad: false,
        onOpenContainer: (_) {},
        onCreateSkill: () {},
      ),
    );

    await tester.tap(find.bySemanticsLabel('打开资产容器索引'));
    await tester.pumpAndSettle();
    expect(find.byType(ContainerIndex), findsOneWidget);
    expect(find.text('资产容器'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('打开全部容器'));
    await tester.pumpAndSettle();
    expect(find.byType(AllContainers), findsOneWidget);
    expect(find.text('全部容器'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-configure-pinned')));
    await tester.pumpAndSettle();
    expect(find.byType(PinnedConfiguration), findsOneWidget);
    expect(find.text('完成配置'), findsOneWidget);
  });

  testWidgets('container index searches and separates system from custom', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      ContainerIndex(
        controller: controller,
        onBack: () {},
        onOpenContainer: (_) {},
        onOpenAllContainers: () {},
        onCreateSkill: () {},
      ),
    );

    expect(find.text('系统容器'), findsOneWidget);
    expect(find.text('自定义技能'), findsOneWidget);
    expect(find.text('网球记录'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('library-container-search')),
      '网球',
    );
    await tester.pump();
    expect(find.text('待办'), findsNothing);
    expect(find.text('网球记录'), findsOneWidget);
  });

  testWidgets('all containers shows three stats and grouped rows', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      AllContainers(
        controller: controller,
        onBack: () {},
        onOpenContainer: (_) {},
        onCreateSkill: () {},
      ),
    );

    expect(find.byKey(const ValueKey('library-all-stats')), findsOneWidget);
    expect(find.text('容器'), findsOneWidget);
    expect(find.text('资产'), findsOneWidget);
    expect(find.text('自定义'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-container-search')),
      findsOneWidget,
    );
    expect(find.text('系统容器'), findsOneWidget);
    expect(find.text('自定义技能'), findsOneWidget);
  });

  testWidgets(
    'configure reuses mosaic and exposes reorder remove and add actions',
    (tester) async {
      final controller = await _controller();
      await _pumpHost(
        tester,
        PinnedConfiguration(controller: controller, onDone: () {}),
      );

      expect(
        find.byKey(const ValueKey('library-pinned-mosaic')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('向后移动 待办'), findsOneWidget);
      expect(find.bySemanticsLabel('移除 待办'), findsOneWidget);
      expect(
        tester.getSize(find.bySemanticsLabel('向后移动 待办')).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.bySemanticsLabel('移除 待办')).width,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.bySemanticsLabel('移除 待办'));
      await tester.pumpAndSettle();
      expect(
        controller.pinnedContainers.map((item) => item.id),
        isNot(contains('todo')),
      );
      expect(find.bySemanticsLabel('加入 待办'), findsOneWidget);
    },
  );

  testWidgets('configure long press drag reorders the shared mosaic', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      PinnedConfiguration(controller: controller, onDone: () {}),
    );

    final from = tester.getCenter(
      find.byKey(const ValueKey('library-pinned-tile-todo')),
    );
    final to = tester.getCenter(
      find.byKey(const ValueKey('library-pinned-tile-notes')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 580));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.pinnedContainers.map((item) => item.id).take(2), [
      'notes',
      'todo',
    ]);
  });

  testWidgets('360 width keeps primary actions reachable without overflow', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      LibraryHub(
        controller: controller,
        onOpenContainer: (_) {},
        onOpenContainerIndex: () {},
        onOpenAllContainers: () {},
        onConfigurePinned: () {},
        onCreateSkill: () {},
      ),
      size: const Size(360, 800),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('library-create-skill'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('initial loading presents one structural state before the hub', (
    tester,
  ) async {
    final pending = Completer<LibrarySnapshot>();
    final controller = LibraryController(
      repository: _PendingRepository(pending),
      pinnedStore: _Store(),
    );
    await _pumpHost(
      tester,
      ThemeV2LibraryPage(
        controller: controller,
        onOpenContainer: (_) {},
        onCreateSkill: () {},
      ),
    );
    await tester.pump();

    expect(find.byType(LibraryHub), findsNothing);
    expect(find.text('正在加载资产库'), findsOneWidget);

    pending.complete((await _controller()).snapshot!);
    await tester.pumpAndSettle();
    expect(find.text('正在加载资产库'), findsNothing);
    expect(find.text('资产库'), findsOneWidget);
  });

  testWidgets('offline state exposes one retry action then restores the hub', (
    tester,
  ) async {
    final ready = (await _controller()).snapshot!;
    final repository = _SequenceRepository([
      const LibraryLoadFailure.offline(),
      ready,
    ]);
    final controller = LibraryController(
      repository: repository,
      pinnedStore: _Store(),
    );
    await _pumpHost(
      tester,
      ThemeV2LibraryPage(
        controller: controller,
        onOpenContainer: (_) {},
        onCreateSkill: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibraryHub), findsNothing);
    expect(find.text('当前处于离线状态'), findsOneWidget);
    expect(find.bySemanticsLabel('重试'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('重试'));
    await tester.pumpAndSettle();
    expect(find.text('当前处于离线状态'), findsNothing);
    expect(find.byKey(const ValueKey('library-pinned-mosaic')), findsOneWidget);
  });

  testWidgets('refresh keeps the populated hub interactive', (tester) async {
    final pending = Completer<LibrarySnapshot>();
    final repository = _RefreshRepository(
      initial: (await _controller()).snapshot!,
      refresh: pending,
    );
    final controller = LibraryController(
      repository: repository,
      pinnedStore: _Store(),
    );
    await controller.load();
    await _pumpHost(
      tester,
      ThemeV2LibraryPage(
        controller: controller,
        autoLoad: false,
        onOpenContainer: (_) {},
        onCreateSkill: () {},
      ),
    );

    controller.load();
    await tester.pump();

    expect(find.byType(LibraryHub), findsOneWidget);
    expect(find.bySemanticsLabel('正在刷新资产库'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-create-skill')), findsOneWidget);

    pending.complete(repository.initial);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('正在刷新资产库'), findsNothing);
  });

  testWidgets('zero-container state still exposes the independent AI action', (
    tester,
  ) async {
    final controller = LibraryController(
      repository: _Repository(const LibrarySnapshot()),
      pinnedStore: _Store(),
    );
    await controller.load();
    await _pumpHost(
      tester,
      ThemeV2LibraryPage(
        controller: controller,
        autoLoad: false,
        onOpenContainer: (_) {},
        onCreateSkill: () {},
      ),
    );

    expect(find.text('还没有常驻容器，点击配置'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-create-skill')), findsOneWidget);
  });

  testWidgets(
    'Theme V2 shell mounts the V2 library while legacy page is absent',
    (tester) async {
      await _pumpHost(
        tester,
        const ThemeV2AppShell(initialIndex: 2, showStartupOverlays: false),
      );
      await tester.pump();

      expect(find.byType(ThemeV2LibraryPage), findsOneWidget);
      expect(find.byType(LibraryPage), findsNothing);
    },
  );
}

Future<LibraryController> _controller() async {
  final now = DateTime(2026, 7, 28, 12);
  final controller = LibraryController(
    repository: _Repository(
      LibrarySnapshot(
        assets: [
          AssetItem(
            id: 'a1',
            skillName: 'todo',
            payload: const {'title': '提交重构'},
            createdAt: now,
          ),
        ],
        skills: const {
          'todo': SkillMeta('📋', '待办', 'blue', 's-todo'),
          'notes': SkillMeta('✍️', '笔记', 'amber', 's-notes'),
          'tennis': SkillMeta('🎾', '网球记录', 'green', 's-tennis'),
        },
        events: [
          {
            'event_id': 'e1',
            'title': '评审',
            'created_at': '2026-07-28T11:00:00',
          },
        ],
        contacts: [
          {'id': 'c1', 'name': '小王', 'created_at': '2026-07-28T10:00:00'},
        ],
        reports: [
          {'id': 'r1', 'title': '日报', 'created_at': '2026-07-28T09:00:00'},
        ],
        assetCounts: const {'todo': 5, 'notes': 4, 'tennis': 3},
        availableSources: const {
          'assets',
          'skills',
          'events',
          'contacts',
          'reports',
          'counts',
        },
      ),
    ),
    pinnedStore: _Store(),
  );
  await controller.load();
  return controller;
}

Future<void> _pumpHost(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(411, 960),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(_host(child, size: size));
}

Widget _host(Widget child, {Size size = const Size(411, 960)}) {
  final themeV2 = buildThemeV2Theme(Brightness.light);
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      devicePixelRatio: 1,
      disableAnimations: true,
      textScaler: TextScaler.noScaling,
    ),
    child: ProviderScope(
      overrides: [renderSpecsProvider.overrideWith((ref) async => const {})],
      child: MaterialApp(
        theme: themeV2.copyWith(
          extensions: [
            ...themeV2.extensions.values,
            const EurekaTheme(EurekaColors.light),
          ],
        ),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    ),
  );
}

class _Repository implements LibraryRepository {
  _Repository(this.snapshot);
  final LibrarySnapshot snapshot;

  @override
  Future<LibrarySnapshot> load() async => snapshot;
}

class _PendingRepository implements LibraryRepository {
  _PendingRepository(this.pending);

  final Completer<LibrarySnapshot> pending;

  @override
  Future<LibrarySnapshot> load() => pending.future;
}

class _SequenceRepository implements LibraryRepository {
  _SequenceRepository(this.results);

  final List<Object> results;
  int index = 0;

  @override
  Future<LibrarySnapshot> load() async {
    final result = results[index++];
    if (result is LibraryLoadFailure) throw result;
    return result as LibrarySnapshot;
  }
}

class _RefreshRepository implements LibraryRepository {
  _RefreshRepository({required this.initial, required this.refresh});

  final LibrarySnapshot initial;
  final Completer<LibrarySnapshot> refresh;
  int loadCount = 0;

  @override
  Future<LibrarySnapshot> load() {
    loadCount += 1;
    return loadCount == 1 ? Future.value(initial) : refresh.future;
  }
}

class _Store implements LibraryPinnedStore {
  List<String> value = const ['todo', 'notes', 'tennis', 'event', 'contact'];

  @override
  Future<List<String>> load() async => value;

  @override
  Future<void> save(List<String> ids) async => value = List.of(ids);
}
