import 'dart:math' as math;

import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/library/create_skill_action.dart';
import 'package:eureka/theme_v2/library/library_components.dart';
import 'package:eureka/theme_v2/library/library_models.dart';
import 'package:eureka/theme_v2/library/library_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pinned mosaic matches canonical 375 geometry and ordinals', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 375,
          child: LibraryPinnedMosaic(containers: _containers),
        ),
      ),
    );

    final first = tester.getRect(
      find.byKey(const ValueKey('library-pinned-tile-todo')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('library-pinned-tile-notes')),
    );
    final third = tester.getRect(
      find.byKey(const ValueKey('library-pinned-tile-tennis')),
    );
    final fourth = tester.getRect(
      find.byKey(const ValueKey('library-pinned-tile-expense')),
    );

    expect(first.size, const Size(247, 156));
    expect(second.size, const Size(122, 156));
    expect(second.left - first.right, 6);
    expect(third.size, const Size(186, 178));
    expect(fourth.size, const Size(183, 54));
    expect(fourth.left - third.right, 6);
    expect(find.text('01'), findsOneWidget);
    expect(find.textContaining('/ A'), findsNothing);
    expect(
      find.byKey(const ValueKey('library-pinned-mark-todo')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('library-pinned-mark-expense')),
      findsNothing,
    );
  });

  testWidgets('pinned tile press scales unless Reduce Motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 375,
          child: LibraryPinnedMosaic(containers: _containers, onTap: (_) {}),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('library-pinned-tile-todo'))),
    );
    await tester.pump();
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('library-pinned-press-transform-todo')),
          )
          .scale,
      .98,
    );
    await gesture.up();

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 375,
          child: LibraryPinnedMosaic(containers: _containers, onTap: (_) {}),
        ),
        disableAnimations: true,
      ),
    );
    final reducedGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('library-pinned-tile-todo'))),
    );
    await tester.pump();
    expect(
      tester
          .widget<AnimatedScale>(
            find.byKey(const ValueKey('library-pinned-press-transform-todo')),
          )
          .scale,
      1,
    );
    await reducedGesture.up();
  });

  testWidgets('configure mode uses bounded staggered micro-motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 375,
          child: LibraryPinnedMosaic(containers: _containers, configure: true),
        ),
      ),
    );

    final firstFinder = find.byKey(
      const ValueKey('library-pinned-wiggle-todo'),
    );
    final secondFinder = find.byKey(
      const ValueKey('library-pinned-wiggle-notes'),
    );
    final firstBefore = tester.widget<Transform>(firstFinder).transform;
    final secondBefore = tester.widget<Transform>(secondFinder).transform;
    expect(firstBefore, isNot(equals(secondBefore)));

    await tester.pump(const Duration(milliseconds: 170));
    final firstAfter = tester.widget<Transform>(firstFinder).transform;
    expect(firstAfter, isNot(equals(firstBefore)));
    _expectBoundedWiggle(firstAfter);
    _expectBoundedWiggle(tester.widget<Transform>(secondFinder).transform);

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 375,
          child: LibraryPinnedMosaic(containers: _containers),
        ),
      ),
    );
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey('library-pinned-wiggle-todo')),
          )
          .transform,
      Matrix4.identity(),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('Reduce Motion keeps configure tiles static without a ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 375,
          child: LibraryPinnedMosaic(containers: _containers, configure: true),
        ),
        disableAnimations: true,
      ),
    );

    final finder = find.byKey(const ValueKey('library-pinned-wiggle-todo'));
    expect(tester.widget<Transform>(finder).transform, Matrix4.identity());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<Transform>(finder).transform, Matrix4.identity());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('container row variants keep canonical heights and semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LibrarySystemContainerCard(container: _containers[0], onTap: () {}),
            LibraryCustomContainerRow(container: _containers[2], onTap: () {}),
            LibraryDirectoryRow(container: _containers[3], onTap: () {}),
          ],
        ),
      ),
    );

    expect(tester.getSize(find.byType(LibrarySystemContainerCard)).height, 56);
    expect(tester.getSize(find.byType(LibraryCustomContainerRow)).height, 50);
    expect(tester.getSize(find.byType(LibraryDirectoryRow)).height, 54);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('library-directory-mark-expense')))
          .width,
      34,
    );
    expect(find.bySemanticsLabel('打开待办，12 条'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('disabled available tile explains the six-item limit', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var tapped = false;
    await tester.pumpWidget(
      _host(
        LibraryAvailableContainerTile(
          container: _containers[3],
          enabled: false,
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.bySemanticsLabel('无法加入消费账本，常驻容器最多 6 个'), findsOneWidget);
    await tester.tap(find.byType(LibraryAvailableContainerTile));
    expect(tapped, isFalse);
    semantics.dispose();
  });

  testWidgets('empty search state clears the active query', (tester) async {
    var cleared = false;
    await tester.pumpWidget(
      _host(LibraryStateView.emptySearch(onClear: () => cleared = true)),
    );

    await tester.tap(find.text('清除搜索'));

    expect(cleared, isTrue);
  });

  testWidgets('create skill variants expose context-specific copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CreateSkillAction.primary(onPressed: () {}),
            CreateSkillAction.compact(onPressed: () {}),
            CreateSkillAction.configuration(onPressed: () {}),
          ],
        ),
      ),
    );

    expect(find.text('创建新技能'), findsNWidgets(2));
    expect(find.text('描述你想长期记录的内容'), findsOneWidget);
    expect(find.text('新建技能容器'), findsOneWidget);
  });
}

Widget _host(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: buildThemeV2Theme(Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(411, 960),
      disableAnimations: disableAnimations,
      textScaler: TextScaler.noScaling,
    ),
    child: Scaffold(body: Center(child: child)),
  ),
);

void _expectBoundedWiggle(Matrix4 transform) {
  final storage = transform.storage;
  final radians = math.atan2(storage[1], storage[0]);
  expect(radians.abs(), lessThanOrEqualTo(.6 * math.pi / 180 + .000001));
  expect(storage[12].abs(), lessThanOrEqualTo(1));
  expect(storage[13].abs(), lessThanOrEqualTo(1));
}

const _containers = [
  LibraryContainerSummary(
    id: 'todo',
    label: '待办',
    mark: '☑',
    type: LibraryContainerType.todo,
    totalCount: 12,
    isSystem: true,
  ),
  LibraryContainerSummary(
    id: 'notes',
    label: '随记',
    mark: '✎',
    type: LibraryContainerType.notes,
    totalCount: 8,
    isSystem: true,
  ),
  LibraryContainerSummary(
    id: 'tennis',
    label: '网球比赛',
    mark: '球',
    type: LibraryContainerType.custom,
    totalCount: 4,
    isSystem: false,
  ),
  LibraryContainerSummary(
    id: 'expense',
    label: '消费账本',
    mark: '¥',
    type: LibraryContainerType.custom,
    totalCount: 18,
    isSystem: false,
  ),
];
