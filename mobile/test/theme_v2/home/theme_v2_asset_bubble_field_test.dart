import 'dart:async';

import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/theme_v2_asset_bubble_field.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final asset = PoolAsset(
    id: 'asset-1',
    type: 'contact',
    domain: 'work',
    title: 'Kevin',
    payload: const {'name': 'Kevin'},
    createdAt: DateTime(2026, 8, 3, 10),
  );

  test('acceleration maps to fixed-magnitude screen gravity', () {
    expect(themeV2GravityForAcceleration(0, 0), const Offset(0, 20));
    expect(themeV2GravityForAcceleration(-9.8, 0).dx, closeTo(20, 0.01));
  });

  testWidgets('active physics moves a bubble under gravity', (tester) async {
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getCenter(bubble).dy, greaterThan(before.dy));
  });

  testWidgets('Reduce Motion keeps a stable settled bubble', (tester) async {
    await _pumpField(tester, assets: [asset], disableAnimations: true);
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(seconds: 1));

    expect(tester.getCenter(bubble), before);
  });

  testWidgets('inactive Home pauses bubble motion', (tester) async {
    await _pumpField(
      tester,
      assets: [asset],
      active: false,
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(seconds: 1));

    expect(tester.getCenter(bubble), before);
  });

  testWidgets('gravity stream redirects active bubble motion', (tester) async {
    final gravity = StreamController<Offset>();
    addTearDown(gravity.close);
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: gravity.stream,
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    gravity.add(const Offset(20, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getCenter(bubble).dx, greaterThan(before.dx));
  });

  testWidgets('sensor failure falls back to default downward gravity', (
    tester,
  ) async {
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: Stream<Offset>.error(StateError('sensor unavailable')),
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(tester.getCenter(bubble).dy, greaterThan(before.dy));
  });

  testWidgets('bubble keeps semantics and opens the exact asset', (
    tester,
  ) async {
    PoolAsset? opened;
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: true,
      onOpenAsset: (value) => opened = value,
    );

    final target = find.bySemanticsLabel('打开资产 Kevin');
    expect(target, findsOneWidget);
    expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    await tester.tap(target);

    expect(opened?.id, 'asset-1');
  });

  testWidgets('drag releases with throw velocity', (tester) async {
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
      onOpenAsset: (_) {},
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    final gesture = await tester.startGesture(before);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    final atRelease = tester.getCenter(bubble);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(atRelease.dx, greaterThan(before.dx));
    expect(tester.getCenter(bubble).dx, greaterThan(atRelease.dx));
  });

  testWidgets('app background pauses bubble motion', (tester) async {
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final before = tester.getCenter(bubble);
    await tester.pump(const Duration(seconds: 1));

    expect(tester.getCenter(bubble), before);
  });

  testWidgets('asset refresh removes stale bubbles and adds new bubbles', (
    tester,
  ) async {
    final replacement = PoolAsset(
      id: 'asset-2',
      type: 'note',
      domain: 'work',
      title: '会议笔记',
      payload: const {'content': '会议笔记'},
      createdAt: DateTime(2026, 8, 3, 11),
    );
    await _pumpField(tester, assets: [asset], disableAnimations: true);

    await _pumpField(tester, assets: [replacement], disableAnimations: true);

    expect(
      find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('theme-v2-asset-bubble-asset-2')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpField(
  WidgetTester tester, {
  required List<PoolAsset> assets,
  required bool disableAnimations,
  bool active = true,
  Stream<Offset>? gravityStream,
  ValueChanged<PoolAsset>? onOpenAsset,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(395, 790);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: SizedBox(
          width: 395,
          height: 790,
          child: ThemeV2AssetBubbleField(
            assets: assets,
            trueCount: assets.length,
            active: active,
            gravityStream: gravityStream,
            onOpenAsset: onOpenAsset,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
