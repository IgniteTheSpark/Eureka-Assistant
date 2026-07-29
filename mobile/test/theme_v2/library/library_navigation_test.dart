import 'dart:async';

import 'package:eureka/pages/category_detail_page.dart';
import 'package:eureka/pages/library_page.dart';
import 'package:eureka/render/skill_card.dart';
import 'package:eureka/theme/app_theme.dart';
import 'package:eureka/theme/eureka_colors.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_tokens.dart';
import 'package:eureka/theme_v2/asset/asset_card.dart';
import 'package:eureka/theme_v2/library/asset/asset_list_page.dart';
import 'package:eureka/theme_v2/library/container_index.dart';
import 'package:eureka/theme_v2/library/create_skill/theme_v2_skill_wizard.dart';
import 'package:eureka/theme_v2/library/library_components.dart';
import 'package:eureka/theme_v2/library/library_controller.dart';
import 'package:eureka/theme_v2/library/library_hub.dart';
import 'package:eureka/theme_v2/library/library_models.dart';
import 'package:eureka/theme_v2/library/library_navigation.dart';
import 'package:eureka/theme_v2/library/library_repository.dart';
import 'package:eureka/theme_v2/library/library_states.dart';
import 'package:eureka/theme_v2/library/pinned_configuration.dart';
import 'package:eureka/theme_v2/library/theme_v2_library_page.dart';
import 'package:eureka/theme_v2/shell/theme_v2_app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('surface stack preserves origin and exposes canonical chrome', () {
    final navigation = LibraryNavigationController();
    addTearDown(navigation.dispose);

    expect(navigation.surface, LibrarySurface.hub);
    expect(
      navigation.chrome,
      const LibraryChromeSpec(topNav: true, dock: true),
    );

    navigation.open(LibrarySurface.containerIndex);
    navigation.open(LibrarySurface.allContainers);
    expect(
      navigation.chrome,
      const LibraryChromeSpec(topNav: true, dock: false),
    );

    expect(navigation.back(), isTrue);
    expect(navigation.surface, LibrarySurface.containerIndex);

    navigation.open(LibrarySurface.pinnedConfiguration);
    expect(
      navigation.chrome,
      const LibraryChromeSpec(topNav: false, dock: true),
    );
    navigation.home();
    expect(navigation.surface, LibrarySurface.hub);
    expect(navigation.canPop, isFalse);
  });

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

  testWidgets('hub uses canonical title stats and one 50-asset row', (
    tester,
  ) async {
    final controller = await _controller(recentCount: 50);
    var openedIndex = 0;
    var openedAll = 0;
    await _pumpHost(
      tester,
      LibraryHub(
        controller: controller,
        onOpenContainer: (_) {},
        onOpenContainerIndex: () => openedIndex++,
        onOpenAllContainers: () => openedAll++,
        onConfigurePinned: () {},
        onCreateSkill: () {},
      ),
    );

    expect(find.text('资产库'), findsOneWidget);
    expect(find.textContaining('LIBRARY /'), findsNothing);
    expect(find.textContaining('你的记录'), findsNothing);
    expect(find.text('最近生成'), findsOneWidget);
    expect(find.text('50'), findsNothing);

    await tester.tap(find.bySemanticsLabel('打开资产容器索引'));
    await tester.tap(find.bySemanticsLabel('打开全部容器'));
    expect(openedIndex, 1);
    expect(openedAll, 1);

    final horizontal = tester.widgetList<Scrollable>(
      find.descendant(
        of: find.byKey(const PageStorageKey('theme-v2-library-recent-assets')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(horizontal, hasLength(1));
    expect(horizontal.single.axisDirection, AxisDirection.right);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ThemeV2AssetCard &&
            widget.variant == AssetCardVariant.iconTime,
      ),
      findsWidgets,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('library-recent-recent-49')),
      500,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('theme-v2-library-recent-assets')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.byKey(const ValueKey('library-recent-recent-49')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('library-recent-recent-50')),
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
    'recent cells contain assets only and preserve navigation intent',
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
          onOpenRecent: (item) => opened.add(item.skillName),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('library-recent-a1')));
      expect(opened, ['todo']);
      expect(find.byKey(const ValueKey('library-recent-e1')), findsNothing);
      expect(find.byKey(const ValueKey('library-recent-c1')), findsNothing);
      expect(find.byKey(const ValueKey('library-recent-r1')), findsNothing);
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
    'default V2 container route opens schema asset list with V2 theme',
    (tester) async {
      final controller = await _controller();
      await _pumpHost(
        tester,
        ThemeV2LibraryPage(
          controller: controller,
          autoLoad: false,
          onCreateSkill: () {},
        ),
      );

      await tester.tap(find.byKey(const ValueKey('library-pinned-tile-todo')));
      await tester.pumpAndSettle();

      expect(find.byType(ThemeV2AssetListPage), findsOneWidget);
      expect(find.byType(CategoryDetailPage), findsNothing);
      final routeTheme = Theme.of(
        tester.element(find.byType(ThemeV2AssetListPage)),
      );
      expect(routeTheme.extension<ThemeV2Tokens>(), isNotNull);
      expect(
        routeTheme.textTheme.bodyMedium?.fontFamily,
        buildThemeV2Theme(Brightness.light).textTheme.bodyMedium?.fontFamily,
      );
    },
  );

  testWidgets('default recent asset opens direct detail not a container list', (
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

    await tester.tap(find.byKey(const ValueKey('library-recent-a1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme-v2-asset-sheet')), findsOneWidget);
    expect(find.byType(CategoryDetailPage), findsNothing);
    final close = find.byKey(const ValueKey('asset-detail-close'));
    final logicalHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getCenter(close).dy, lessThan(logicalHeight));
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme-v2-asset-sheet')), findsNothing);
  });

  testWidgets('recent detail closes back to the same hub scroll position', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      ThemeV2LibraryPage(controller: controller, autoLoad: false),
      size: const Size(411, 600),
    );
    final hubScroll = find
        .descendant(
          of: find.byKey(const PageStorageKey('theme-v2-library-hub')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('library-recent-a1')),
      280,
      scrollable: hubScroll,
    );
    final before = tester.state<ScrollableState>(hubScroll).position.pixels;

    await tester.tap(find.byKey(const ValueKey('library-recent-a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asset-detail-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const PageStorageKey('theme-v2-library-hub')),
      findsOneWidget,
    );
    expect(
      tester.state<ScrollableState>(hubScroll).position.pixels,
      closeTo(before, 1),
    );
  });

  testWidgets('default create action opens skill builder step one', (
    tester,
  ) async {
    final controller = await _controller();
    await _pumpHost(
      tester,
      ThemeV2LibraryPage(controller: controller, autoLoad: false),
    );

    await tester.tap(find.byKey(const ValueKey('library-create-skill')));
    await tester.pumpAndSettle();

    expect(find.byType(ThemeV2SkillWizardSheet), findsOneWidget);
    expect(find.text('想记录点什么？'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('关闭新技能'));
    await tester.pumpAndSettle();
  });

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

  testWidgets('container index matches canonical hierarchy and geometry', (
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

    expect(find.text('资产容器'), findsOneWidget);
    expect(find.textContaining('LIBRARY /'), findsNothing);
    expect(find.text('你正在使用的容器'), findsNothing);
    expect(find.text('系统容器'), findsOneWidget);
    expect(find.text('自定义技能'), findsOneWidget);
    expect(find.byType(LibrarySystemContainerCard), findsNWidgets(4));
    expect(find.byType(LibraryCustomContainerRow), findsNWidgets(3));
    expect(find.text('查看全部容器'), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('library-index-search'))).height,
      44,
    );
    expect(
      find.byKey(const ValueKey('library-create-skill-compact')),
      findsOneWidget,
    );
  });

  testWidgets(
    'container index search clears and does not leak into all query',
    (tester) async {
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

      await tester.enterText(
        find.byKey(const ValueKey('library-index-search')),
        '网球',
      );
      await tester.pump();
      expect(find.text('网球记录'), findsOneWidget);
      expect(find.text('待办'), findsNothing);
      expect(controller.indexQuery, '网球');
      expect(controller.allQuery, isEmpty);

      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pump();
      expect(find.text('待办'), findsOneWidget);

      expect(find.text('网球记录'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('library-index-search')),
        '不存在',
      );
      await tester.pump();
      expect(find.text('没有匹配的容器'), findsOneWidget);
      await tester.tap(find.text('清除搜索'));
      await tester.pump();
      expect(find.text('待办'), findsOneWidget);

      controller.setIndexQuery('网球');
      await _pumpHost(
        tester,
        AllContainers(
          controller: controller,
          onBack: () {},
          onOpenContainer: (_) {},
          onCreateSkill: () {},
        ),
      );
      expect(find.text('待办'), findsOneWidget);
      expect(controller.indexQuery, '网球');
      expect(controller.allQuery, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('library-all-search')),
        '事件',
      );
      await tester.pump();
      expect(controller.indexQuery, '网球');
      expect(controller.allQuery, '事件');
      expect(find.text('待办'), findsNothing);
      expect(find.text('事件'), findsNWidgets(2));
    },
  );

  testWidgets(
    'all containers uses native directory rows and reachable footer',
    (tester) async {
      final controller = await _controller();
      var backed = 0;
      await _pumpHost(
        tester,
        AllContainers(
          controller: controller,
          onBack: () => backed++,
          onOpenContainer: (_) {},
          onCreateSkill: () {},
        ),
      );

      expect(find.byKey(const ValueKey('library-all-stats')), findsOneWidget);
      expect(find.text('容器'), findsOneWidget);
      expect(find.text('资产'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);
      expect(find.textContaining('LIBRARY /'), findsNothing);
      expect(find.text('查找并管理所有记录入口'), findsNothing);
      expect(
        tester.getSize(find.byKey(const ValueKey('library-all-search'))).height,
        42,
      );
      expect(find.byType(LibraryDirectoryRow), findsNWidgets(7));
      expect(tester.getSize(find.byType(LibraryDirectoryRow).first).height, 54);
      expect(tester.getSize(find.byTooltip('返回')), const Size(44, 44));
      await tester.tap(find.byTooltip('返回'));
      expect(backed, 1);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('library-create-skill-compact')),
        320,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('library-create-skill-compact')),
        findsOneWidget,
      );
      expect(find.text('系统容器'), findsOneWidget);
      expect(find.text('自定义技能'), findsOneWidget);
    },
  );

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
      final tileSemantics = tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.byKey(const ValueKey('library-pinned-tile-todo')),
              matching: find.byType(Semantics),
            ),
          )
          .singleWhere(
            (widget) => widget.properties.label == '待办，5 条，可拖动排序，也可使用移动和移除按钮',
          );
      expect(tileSemantics.properties.button, isFalse);
      expect(tileSemantics.properties.onTap, isNull);

      await tester.tap(find.bySemanticsLabel('移除 待办'));
      await tester.pumpAndSettle();
      expect(
        controller.pinnedContainers.map((item) => item.id),
        isNot(contains('todo')),
      );
      expect(find.bySemanticsLabel('加入 待办'), findsOneWidget);
    },
  );

  testWidgets('pinned configuration matches canonical hierarchy and copy', (
    tester,
  ) async {
    final controller = await _controller();
    var done = 0;
    await _pumpHost(
      tester,
      PinnedConfiguration(controller: controller, onDone: () => done++),
    );

    expect(find.text('资产库'), findsOneWidget);
    expect(find.textContaining('LIBRARY /'), findsNothing);
    expect(find.textContaining('长按拖动常驻容器'), findsNothing);
    expect(find.text('CONFIGURE / 05 · 长按拖动'), findsOneWidget);
    expect(find.text('01'), findsOneWidget);
    expect(find.textContaining('/ A'), findsNothing);
    expect(
      find.byKey(const ValueKey('library-create-skill-configuration')),
      findsOneWidget,
    );
    expect(
      find.byKey(const PageStorageKey('theme-v2-library-pinned-configuration')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('library-pinned-done'))),
      const Size(72, 44),
    );
    expect(tester.widget<Text>(find.text('完成配置')).maxLines, 1);
    await tester.tap(find.text('完成配置'));
    expect(done, 1);
  });

  testWidgets('six pinned containers disable the remaining add tile', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = await _controller(
      pinnedStore: _Store(const [
        'todo',
        'notes',
        'event',
        'contact',
        'tennis',
        'expense',
      ]),
    );
    await _pumpHost(
      tester,
      PinnedConfiguration(controller: controller, onDone: () {}),
    );

    final add = find.bySemanticsLabel('加入 阅读摘录，已达到六个常驻容器上限');
    expect(add, findsOneWidget);
    expect(
      tester.getSemantics(add),
      matchesSemantics(
        label: '加入 阅读摘录，已达到六个常驻容器上限',
        isButton: true,
        isEnabled: false,
        hasEnabledState: true,
        hasTapAction: false,
      ),
    );
    semantics.dispose();
  });

  testWidgets('pinned configuration preserves its vertical position', (
    tester,
  ) async {
    final controller = await _controller();
    final bucket = PageStorageBucket();
    Widget surface() => PageStorage(
      bucket: bucket,
      child: PinnedConfiguration(controller: controller, onDone: () {}),
    );

    await _pumpHost(tester, surface(), size: const Size(411, 480));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(before, greaterThan(0));

    await _pumpHost(tester, surface(), size: const Size(411, 480));
    final restored = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(restored, closeTo(before, 1));
  });

  testWidgets('pending pinned save locks duplicate controls', (tester) async {
    final store = _PendingStore(const [
      'todo',
      'notes',
      'tennis',
      'event',
      'contact',
    ]);
    final controller = await _controller(pinnedStore: store);
    await _pumpHost(
      tester,
      PinnedConfiguration(controller: controller, onDone: () {}),
    );

    await tester.tap(find.bySemanticsLabel('移除 待办'));
    await tester.pump();
    expect(controller.isSavingPins, isTrue);
    expect(find.text('正在保存配置…'), findsOneWidget);
    final locked = tester.getSemantics(find.bySemanticsLabel('移除 笔记'));
    expect(
      locked,
      matchesSemantics(
        label: '移除 笔记',
        isButton: true,
        isEnabled: false,
        hasEnabledState: true,
        hasTapAction: false,
      ),
    );
    await tester.tap(find.bySemanticsLabel('移除 笔记'));
    await tester.pump();
    expect(store.saved, hasLength(1));

    store.pending.single.complete();
    await tester.pumpAndSettle();
    expect(controller.isSavingPins, isFalse);
  });

  testWidgets('failed pinned save restores the mosaic and explains failure', (
    tester,
  ) async {
    final store = _Store(const ['todo', 'notes', 'tennis', 'event', 'contact'])
      ..failNext = true;
    final controller = await _controller(pinnedStore: store);
    await _pumpHost(
      tester,
      PinnedConfiguration(controller: controller, onDone: () {}),
    );

    await tester.tap(find.bySemanticsLabel('移除 待办'));
    await tester.pumpAndSettle();

    expect(controller.pinnedContainers.map((item) => item.id).first, 'todo');
    expect(find.textContaining('保存失败，已恢复原配置'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-pinned-tile-todo')),
      findsOneWidget,
    );
  });

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
    final pending = Completer<LibraryOverview>();
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
    expect(find.byType(LibraryStateView), findsOneWidget);
    expect(find.byKey(const ValueKey('library-state-loading')), findsOneWidget);
    expect(find.bySemanticsLabel('正在加载资产库'), findsOneWidget);

    pending.complete((await _controller()).overview!);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('正在加载资产库'), findsNothing);
    expect(find.text('资产库'), findsOneWidget);
  });

  testWidgets('offline state exposes one retry action then restores the hub', (
    tester,
  ) async {
    final ready = (await _controller()).overview!;
    final repository = _SequenceRepository([
      const LibraryLoadFailure('网络不可用', isOffline: true),
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
    expect(find.byKey(const ValueKey('library-state-error')), findsOneWidget);
    expect(find.text('当前处于离线状态'), findsOneWidget);
    expect(find.bySemanticsLabel('重试'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('重试'));
    await tester.pumpAndSettle();
    expect(find.text('当前处于离线状态'), findsNothing);
    expect(find.byKey(const ValueKey('library-pinned-mosaic')), findsOneWidget);
  });

  testWidgets('partial state keeps hub content and exposes retry banner', (
    tester,
  ) async {
    final ready = (await _controller()).overview!;
    final controller = LibraryController(
      repository: _Repository(
        LibraryOverview(
          systemContainers: ready.systemContainers,
          customContainers: ready.customContainers,
          recentAssets: ready.recentAssets,
          totalAssetCount: ready.totalAssetCount,
          failedSources: const [
            LibrarySourceFailure(source: 'events', isOffline: false),
          ],
        ),
      ),
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

    expect(find.byType(LibraryHub), findsOneWidget);
    expect(
      find.byKey(const ValueKey('library-partial-banner')),
      findsOneWidget,
    );
    expect(find.text('重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('library-create-skill')), findsOneWidget);
  });

  testWidgets('refresh keeps the populated hub interactive', (tester) async {
    final pending = Completer<LibraryOverview>();
    final repository = _RefreshRepository(
      initial: (await _controller()).overview!,
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
      repository: _Repository(LibraryOverview()),
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

  testWidgets('pushed routes retain the originating Theme V2 material theme', (
    tester,
  ) async {
    final controller = await _controller();
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    await _pumpSizedWidget(
      tester,
      ProviderScope(
        overrides: [renderSpecsProvider.overrideWith((ref) async => const {})],
        child: ValueListenableBuilder<Brightness>(
          valueListenable: brightness,
          builder: (context, value, _) {
            final legacyTheme = ThemeData(brightness: value).copyWith(
              textTheme: ThemeData(
                brightness: value,
              ).textTheme.apply(fontFamily: 'LegacyFont'),
            );
            return MaterialApp(
              theme: legacyTheme,
              home: Theme(
                data: buildThemeV2Theme(value),
                child: Scaffold(
                  body: SafeArea(
                    child: ThemeV2LibraryPage(
                      controller: controller,
                      autoLoad: false,
                      onOpenContainer: (_) {},
                      onCreateSkill: () {},
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('打开资产容器索引'));
    await tester.pumpAndSettle();

    final routeTheme = Theme.of(tester.element(find.byType(ContainerIndex)));
    final lightThemeV2 = buildThemeV2Theme(Brightness.light);
    expect(
      routeTheme.textTheme.bodyMedium?.fontFamily,
      lightThemeV2.textTheme.bodyMedium?.fontFamily,
    );
    expect(routeTheme.textTheme.bodyMedium?.fontFamily, isNot('LegacyFont'));
    expect(routeTheme.extension<ThemeV2Tokens>(), isNotNull);

    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();

    final darkRouteTheme = Theme.of(
      tester.element(find.byType(ContainerIndex)),
    );
    expect(darkRouteTheme.brightness, Brightness.dark);
    expect(
      darkRouteTheme.extension<ThemeV2Tokens>()?.background,
      ThemeV2Tokens.dark.background,
    );
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

Future<LibraryController> _controller({
  int recentCount = 1,
  LibraryPinnedStore? pinnedStore,
}) async {
  final now = DateTime(2026, 7, 28, 12);
  final controller = LibraryController(
    repository: _Repository(
      LibraryOverview(
        systemContainers: const [
          LibraryContainerSummary(
            id: 'todo',
            label: '待办',
            mark: '📋',
            type: LibraryContainerType.todo,
            totalCount: 5,
            isSystem: true,
            userSkillId: 's-todo',
          ),
          LibraryContainerSummary(
            id: 'notes',
            label: '笔记',
            mark: '✍️',
            type: LibraryContainerType.notes,
            totalCount: 4,
            isSystem: true,
            userSkillId: 's-notes',
          ),
          LibraryContainerSummary(
            id: 'event',
            label: '事件',
            mark: '📅',
            type: LibraryContainerType.event,
            totalCount: 0,
            isSystem: true,
          ),
          LibraryContainerSummary(
            id: 'contact',
            label: '联系人',
            mark: '👤',
            type: LibraryContainerType.contact,
            totalCount: 0,
            isSystem: true,
          ),
        ],
        customContainers: const [
          LibraryContainerSummary(
            id: 'tennis',
            label: '网球记录',
            mark: '🎾',
            type: LibraryContainerType.custom,
            totalCount: 3,
            isSystem: false,
            userSkillId: 's-tennis',
          ),
          LibraryContainerSummary(
            id: 'expense',
            label: '消费账本',
            mark: '¥',
            type: LibraryContainerType.custom,
            totalCount: 2,
            isSystem: false,
            userSkillId: 's-expense',
          ),
          LibraryContainerSummary(
            id: 'reading',
            label: '阅读摘录',
            mark: '书',
            type: LibraryContainerType.custom,
            totalCount: 1,
            isSystem: false,
            userSkillId: 's-reading',
          ),
        ],
        recentAssets: [
          LibraryRecentAsset(
            id: 'a1',
            skillName: 'todo',
            skillLabel: '待办',
            mark: '📋',
            primaryValue: '提交重构',
            createdAt: now,
            detailCard: const {
              'asset_id': 'a1',
              'user_skill_id': 's-todo',
              'user_skill_name': 'todo',
              'payload': {'title': '提交重构'},
            },
          ),
          for (var index = 1; index < recentCount; index++)
            LibraryRecentAsset(
              id: 'recent-$index',
              skillName: 'tennis',
              skillLabel: '网球记录',
              mark: '🎾',
              primaryValue: '记录 $index',
              createdAt: now.subtract(Duration(minutes: index)),
              detailCard: {
                'asset_id': 'recent-$index',
                'user_skill_name': 'tennis',
                'payload': {'headline': '记录 $index'},
              },
            ),
        ],
        totalAssetCount: 12,
      ),
    ),
    pinnedStore: pinnedStore ?? _Store(),
  );
  await controller.load();
  return controller;
}

Future<void> _pumpHost(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(411, 960),
}) async {
  await _pumpSizedWidget(tester, _host(child, size: size), size: size);
}

Future<void> _pumpSizedWidget(
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
  await tester.pumpWidget(child);
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
  _Repository(this.overview);
  final LibraryOverview overview;

  @override
  Future<LibraryOverview> loadOverview() async => overview;
}

class _PendingRepository implements LibraryRepository {
  _PendingRepository(this.pending);

  final Completer<LibraryOverview> pending;

  @override
  Future<LibraryOverview> loadOverview() => pending.future;
}

class _SequenceRepository implements LibraryRepository {
  _SequenceRepository(this.results);

  final List<Object> results;
  int index = 0;

  @override
  Future<LibraryOverview> loadOverview() async {
    final result = results[index++];
    if (result is LibraryLoadFailure) throw result;
    return result as LibraryOverview;
  }
}

class _RefreshRepository implements LibraryRepository {
  _RefreshRepository({required this.initial, required this.refresh});

  final LibraryOverview initial;
  final Completer<LibraryOverview> refresh;
  int loadCount = 0;

  @override
  Future<LibraryOverview> loadOverview() {
    loadCount += 1;
    return loadCount == 1 ? Future.value(initial) : refresh.future;
  }
}

class _Store implements LibraryPinnedStore {
  _Store([this.value = const ['todo', 'notes', 'tennis', 'event', 'contact']]);

  List<String> value;
  bool failNext = false;

  @override
  Future<List<String>> load() async => value;

  @override
  Future<void> save(List<String> ids) async {
    if (failNext) {
      failNext = false;
      throw StateError('save denied');
    }
    value = List.of(ids);
  }
}

class _PendingStore implements LibraryPinnedStore {
  _PendingStore(this.value);

  List<String> value;
  final List<List<String>> saved = [];
  final List<Completer<void>> pending = [];

  @override
  Future<List<String>> load() async => List.of(value);

  @override
  Future<void> save(List<String> ids) {
    saved.add(List.of(ids));
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future;
  }
}
