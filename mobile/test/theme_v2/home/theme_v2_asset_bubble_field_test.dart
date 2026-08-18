import 'dart:async';

import 'package:eureka/theme_v2/asset_detail/asset_entity_ref.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/home/theme_v2_asset_bubble_field.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_dither_field.dart';
import 'package:eureka/theme_v2/home/today_dither_material.dart';
import 'package:eureka/theme_v2/home/today_region_watermark.dart';
import 'package:eureka/timeline/timeline.dart';
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

  test('pool bubbles preserve the canonical entity route', () {
    final event = PoolAsset(
      id: 'event-1',
      entityKind: 'event',
      type: 'event',
      domain: '',
      title: '产品评审',
      payload: const {},
      createdAt: DateTime(2026, 8, 5, 10),
    );

    expect(assetEntityRefForPoolAsset(event).kind, AssetEntityKind.event);
    expect(assetEntityRefForPoolAsset(asset).kind, AssetEntityKind.asset);
    expect(assetEntityRefForPoolAsset(event).id, 'event-1');
  });

  testWidgets('bubble renders canonical and custom skill glyphs', (
    tester,
  ) async {
    final expense = PoolAsset(
      id: 'expense-1',
      type: 'expense',
      domain: 'life',
      title: '午餐',
      payload: const {'amount': 88},
      createdAt: DateTime(2026, 8, 3, 11),
    );
    final tennis = PoolAsset(
      id: 'tennis-1',
      type: 'tennis',
      domain: 'sport',
      title: '晚间网球',
      payload: const {'duration': 60},
      createdAt: DateTime(2026, 8, 3, 12),
    );

    await _pumpField(
      tester,
      assets: [expense, tennis],
      disableAnimations: true,
      skills: const {'tennis': SkillMeta('🎾', '网球记录', 'green')},
    );

    expect(find.text('💳'), findsOneWidget);
    expect(find.text('🎾'), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_outlined), findsNothing);
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

  testWidgets(
    'fresh variable-size bubbles do not eject one above the ceiling',
    (tester) async {
      final assets = _assets(5);
      await _pumpField(
        tester,
        assets: assets,
        disableAnimations: false,
        size: const Size(359, 340),
        gravityStream: const Stream<Offset>.empty(),
      );
      final initialRects = [
        for (final asset in assets)
          tester.getRect(
            find.byKey(ValueKey('theme-v2-asset-bubble-rotation-${asset.id}')),
          ),
      ];
      for (var index = 0; index < initialRects.length; index++) {
        for (var other = index + 1; other < initialRects.length; other++) {
          expect(
            initialRects[index].overlaps(initialRects[other]),
            isFalse,
            reason: 'initial bubbles $index and $other overlap',
          );
        }
      }
      await _pumpFrames(tester, 240);

      final fieldRect = tester.getRect(find.byType(ThemeV2AssetBubbleField));
      for (final asset in assets) {
        final visual = find.byKey(
          ValueKey('theme-v2-asset-bubble-rotation-${asset.id}'),
        );
        final visualRect = tester.getRect(visual);
        expect(
          visualRect.top,
          greaterThanOrEqualTo(fieldRect.top),
          reason: '${asset.id} escaped through the ceiling',
        );
        expect(
          visualRect.bottom,
          lessThanOrEqualTo(fieldRect.bottom),
          reason: '${asset.id} escaped through the floor',
        );
      }
    },
  );

  testWidgets('Reduce Motion keeps a stable settled bubble', (tester) async {
    await _pumpField(tester, assets: [asset], disableAnimations: true);
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final before = tester.getCenter(bubble);

    await tester.pump(const Duration(seconds: 1));

    expect(tester.getCenter(bubble), before);
  });

  testWidgets(
    'Reduce Motion sizes 50-asset rows from each supported field width',
    (tester) async {
      final assets = _assets(50);
      var gravityListenCount = 0;
      final gravity = StreamController<Offset>(
        onListen: () => gravityListenCount++,
      );
      addTearDown(() => unawaited(gravity.close()));

      for (final width in [395.0, 344.0, 304.0]) {
        await _pumpField(
          tester,
          assets: assets,
          disableAnimations: true,
          gravityStream: gravity.stream,
          size: Size(width, 790),
        );
        final fieldRect = tester.getRect(find.byType(ThemeV2AssetBubbleField));
        final visibleTargets = _visibleAssetTargetRects(
          tester,
          assets,
          fieldRect,
        );
        final firstTop = visibleTargets.first.top;
        final firstRowCount = visibleTargets
            .where((rect) => (rect.top - firstTop).abs() < 0.01)
            .length;

        expect(firstRowCount, (width / 44).floor(), reason: '$width px');
        _expectSeparateTargetsInside(visibleTargets, fieldRect);
        expect(find.text('50'), findsOneWidget);
        expect(find.text('Reka 生成'), findsOneWidget);
        expect(gravityListenCount, 0);
      }

      await tester.pump(const Duration(seconds: 1));
      expect(gravityListenCount, 0);
    },
  );

  testWidgets(
    'short Reduce Motion chamber fits and opens all 50 assets without scrolling',
    (tester) async {
      final assets = _assets(50);
      PoolAsset? opened;
      var activationCount = 0;
      await _pumpField(
        tester,
        assets: assets,
        disableAnimations: true,
        size: const Size(304, 480),
        onOpenAsset: (value) {
          opened = value;
          activationCount++;
        },
      );
      final field = find.byType(ThemeV2AssetBubbleField);
      final fieldRect = tester.getRect(field);
      final scrollable = find.descendant(
        of: field,
        matching: find.byType(Scrollable),
      );
      const lastKey = ValueKey('theme-v2-asset-bubble-asset-49');

      expect(scrollable, findsNothing);
      expect(
        _visibleAssetTargetRects(tester, assets, fieldRect),
        hasLength(50),
      );
      final last = find.byKey(lastKey);
      final lastRect = tester.getRect(last);
      _expectFullTargetInside(lastRect, fieldRect);
      await tester.tap(last);
      await tester.pump();

      expect(opened?.id, 'asset-49');
      expect(activationCount, 1);
    },
  );

  testWidgets(
    'empty chamber keeps its watermark actionable without empty copy',
    (tester) async {
      var openLibraryCalls = 0;
      await _pumpField(
        tester,
        assets: const [],
        disableAnimations: true,
        onOpenLibrary: () => openLibraryCalls++,
      );

      expect(find.text('0'), findsOneWidget);
      expect(find.text('Reka 生成'), findsOneWidget);
      expect(find.bySemanticsLabel('打开资产库'), findsOneWidget);
      expect(find.text('今天生成的资产会落在这里'), findsNothing);
      await tester.tap(find.text('Reka 生成'));
      expect(openLibraryCalls, 1);
    },
  );

  testWidgets('generated watermark opens the Asset Library', (tester) async {
    var openLibraryCalls = 0;
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: true,
      onOpenLibrary: () => openLibraryCalls++,
    );

    expect(find.bySemanticsLabel('打开资产库'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('打开资产库'));
    await tester.pump();
    expect(openLibraryCalls, 1);
  });

  testWidgets('Asset dither and watermark use brightness-specific contrast', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await _pumpField(
        tester,
        assets: [asset],
        disableAnimations: true,
        brightness: brightness,
      );
      final field = tester.widget<ThemeV2DitherField>(
        find.byKey(const ValueKey('today-asset-dither-field')),
      );
      final count = tester.widget<Text>(find.text('1'));
      final label = tester.widget<Text>(find.text('Reka 生成'));
      final watermark = tester.widget<TodayRegionWatermark>(
        find.byType(TodayRegionWatermark),
      );
      final dark = brightness == Brightness.dark;

      expect(field.config.opacity, dark ? .30 : .38);
      expect(count.style!.color!.a, closeTo(dark ? .18 : .10, .01));
      expect(label.style!.fontSize, greaterThanOrEqualTo(14));
      expect(label.style!.fontWeight, FontWeight.w700);
      expect(label.style!.color!.a, greaterThanOrEqualTo(dark ? .72 : .56));
      expect(watermark.padding.top, 8);
      expect(watermark.labelFirst, isTrue);
    }
  });

  testWidgets('asset bubble keeps its outline over a faint matching glass', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await _pumpField(
        tester,
        assets: [asset],
        disableAnimations: true,
        brightness: brightness,
      );
      final outline = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('theme-v2-asset-bubble-outline-asset-1')),
      );
      final decoration = outline.decoration as BoxDecoration;
      final borderColor = (decoration.border! as Border).top.color;
      final glass = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('theme-v2-asset-bubble-glass-asset-1')),
      );

      expect(glass.color.r, closeTo(borderColor.r, .001));
      expect(glass.color.g, closeTo(borderColor.g, .001));
      expect(glass.color.b, closeTo(borderColor.b, .001));
      expect(glass.color.a, brightness == Brightness.dark ? .09 : .05);
      expect(borderColor.a, greaterThan(glass.color.a));
    }
  });

  testWidgets('asset chamber uses one shared displaced dither field', (
    tester,
  ) async {
    const motion = AlwaysStoppedAnimation<double>(.35);
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: true,
      motion: motion,
    );

    final field = tester.widget<ThemeV2DitherField>(
      find.byKey(const ValueKey('today-asset-dither-field')),
    );
    expect(field.sources, hasLength(1));
    expect(field.sources.single.shape, ThemeV2DitherSourceShape.circle);
    expect(identical(field.motion, motion), isTrue);
    expect(field.config.opacity, greaterThanOrEqualTo(.28));
    final stack = tester.widget<Stack>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Stack &&
            widget.children.any((child) => child is TodayRegionWatermark),
      ),
    );
    final watermarkIndex = stack.children.indexWhere(
      (child) => child is TodayRegionWatermark,
    );
    final bubbleLayerIndex = stack.children.indexWhere(
      (child) => child is Positioned && child.child is GestureDetector,
    );
    expect(watermarkIndex, greaterThan(0));
    expect(watermarkIndex, lessThan(bubbleLayerIndex));
    final outline = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('theme-v2-asset-bubble-outline-asset-1')),
    );
    final decoration = outline.decoration as BoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.border, isNotNull);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TodayDitherMaterial &&
            widget.shape == TodayDitherShape.circle,
      ),
      findsNothing,
    );
  });

  testWidgets('dragging a bubble deepens its shared dither pressure', (
    tester,
  ) async {
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
      motion: const AlwaysStoppedAnimation<double>(.2),
    );
    ThemeV2DitherField field() => tester.widget<ThemeV2DitherField>(
      find.byKey(const ValueKey('today-asset-dither-field')),
    );
    final restingEnergy = field().sources.single.energy;
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final gesture = await tester.startGesture(tester.getCenter(bubble));
    await gesture.moveBy(const Offset(24, -12));
    await tester.pump(const Duration(milliseconds: 16));

    expect(field().sources.single.energy, greaterThan(restingEnergy));
    await gesture.up();
  });

  testWidgets('compact metadata refresh opens the updated same-id asset', (
    tester,
  ) async {
    final assets = _assets(50);
    PoolAsset? opened;
    await _pumpField(
      tester,
      assets: assets,
      disableAnimations: true,
      onOpenAsset: (value) => opened = value,
    );
    final updated = PoolAsset(
      id: assets.first.id,
      type: 'expense',
      domain: 'life',
      title: 'Updated Contact 0',
      payload: const {'amount': 88},
      createdAt: assets.first.createdAt,
    );

    await _pumpField(
      tester,
      assets: [updated, ...assets.skip(1)],
      disableAnimations: true,
      onOpenAsset: (value) => opened = value,
    );
    final target = find.bySemanticsLabel('打开资产 Updated Contact 0');
    expect(target, findsOneWidget);
    await tester.tap(target);
    await tester.pump();

    expect(identical(opened, updated), isTrue);
    expect(opened?.payload['amount'], 88);
  });

  testWidgets(
    'Reduce Motion overflow transition compacts then restores body diameters',
    (tester) async {
      final assets = _assets(23);
      const firstRotation = ValueKey('theme-v2-asset-bubble-rotation-asset-0');
      await _pumpField(
        tester,
        assets: assets.take(22).toList(),
        disableAnimations: true,
      );
      expect(tester.getSize(find.byKey(firstRotation)), const Size.square(70));

      await _pumpField(tester, assets: assets, disableAnimations: true);
      expect(tester.getSize(find.byKey(firstRotation)), const Size.square(36));

      await _pumpField(
        tester,
        assets: assets.take(22).toList(),
        disableAnimations: true,
      );
      expect(tester.getSize(find.byKey(firstRotation)), const Size.square(70));

      await _pumpField(tester, assets: assets, disableAnimations: false);
      expect(tester.getSize(find.byKey(firstRotation)), const Size.square(70));
    },
  );

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
    final gravity = StreamController<Offset>();
    addTearDown(gravity.close);
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: gravity.stream,
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));

    gravity.add(const Offset(20, 0));
    await tester.pump();
    final horizontalStart = tester.getCenter(bubble);
    await _pumpFrames(tester, 12);
    final horizontalEnd = tester.getCenter(bubble);
    expect(horizontalEnd.dx, greaterThan(horizontalStart.dx));

    await _pumpFrames(tester, 12);
    final driftEnd = tester.getCenter(bubble);
    final horizontalVerticalDrift = driftEnd.dy - horizontalEnd.dy;

    gravity.addError(StateError('sensor unavailable'));
    await tester.pump();
    final fallbackStart = tester.getCenter(bubble);
    await _pumpFrames(tester, 12);
    final fallbackEnd = tester.getCenter(bubble);

    expect(tester.takeException(), isNull);
    expect(
      fallbackEnd.dy - fallbackStart.dy,
      greaterThan(horizontalVerticalDrift + 8),
    );
  });

  testWidgets('bubble keeps semantics and opens the exact asset', (
    tester,
  ) async {
    PoolAsset? opened;
    var activationCount = 0;
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: true,
      onOpenAsset: (value) {
        activationCount++;
        opened = value;
      },
    );

    final target = find.bySemanticsLabel('打开资产 Kevin');
    expect(target, findsOneWidget);
    expect(tester.getSize(target).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    await tester.tap(target);

    expect(opened?.id, 'asset-1');
    expect(activationCount, 1);

    tester.semantics.tap(find.semantics.byLabel('打开资产 Kevin'));
    await tester.pump();

    expect(opened?.id, 'asset-1');
    expect(activationCount, 2);
  });

  testWidgets('bubble artwork rotates inside its stationary semantics target', (
    tester,
  ) async {
    await _pumpField(tester, assets: [asset], disableAnimations: true);

    final rotation = find.byKey(
      const ValueKey('theme-v2-asset-bubble-rotation-asset-1'),
    );
    expect(rotation, findsOneWidget);
    expect(
      find.ancestor(
        of: rotation,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '打开资产 Kevin',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(find.bySemanticsLabel('打开资产 Kevin')).width, 70);
  });

  testWidgets('small bubble opens from the unrotated outer hit target once', (
    tester,
  ) async {
    final assets = List.generate(
      20,
      (index) => PoolAsset(
        id: 'asset-$index',
        type: 'contact',
        domain: 'work',
        title: 'Contact $index',
        payload: {'name': 'Contact $index'},
        createdAt: DateTime(2026, 8, 3, 10, index),
      ),
    );
    PoolAsset? opened;
    var activationCount = 0;
    await _pumpField(
      tester,
      assets: assets,
      disableAnimations: true,
      onOpenAsset: (value) {
        opened = value;
        activationCount++;
      },
    );
    final smallBubble = find.byKey(
      const ValueKey('theme-v2-asset-bubble-asset-19'),
    );
    final center = tester.getCenter(smallBubble);

    expect(tester.getSize(smallBubble), const Size.square(44));
    await tester.tapAt(center + const Offset(20, 0));
    await tester.pump();

    expect(opened?.id, 'asset-19');
    expect(activationCount, 1);
  });

  testWidgets(
    'small bubble keeps a full clamped target at both physical side walls',
    (tester) async {
      final assets = _assets(20);
      final smallAsset = assets[19];
      final gravity = StreamController<Offset>();
      addTearDown(gravity.close);
      PoolAsset? opened;
      var activationCount = 0;

      // Seed the normal diameter cache, then retain only the 30px body.
      await _pumpField(tester, assets: assets, disableAnimations: true);
      await _pumpField(
        tester,
        assets: [smallAsset],
        disableAnimations: false,
        trueCount: 0,
        gravityStream: gravity.stream,
        onOpenAsset: (value) {
          opened = value;
          activationCount++;
        },
      );
      final fieldRect = tester.getRect(find.byType(ThemeV2AssetBubbleField));
      final target = find.bySemanticsLabel('打开资产 ${smallAsset.title}');
      final visual = find.byKey(
        ValueKey('theme-v2-asset-bubble-rotation-${smallAsset.id}'),
      );

      gravity.add(const Offset(-20, 0));
      await tester.pump();
      await _pumpFrames(tester, 180);
      final leftVisualCenter = tester.getCenter(visual);
      final leftTarget = tester.getRect(target);
      expect(leftVisualCenter.dx - fieldRect.left, closeTo(15, 0.6));
      _expectFullTargetInside(leftTarget, fieldRect);
      final leftOuterPoint = Offset(fieldRect.left + 40, leftVisualCenter.dy);
      expect(leftOuterPoint.dx, greaterThan(leftVisualCenter.dx + 15));
      await tester.tapAt(leftOuterPoint);
      await tester.pump();
      expect(opened?.id, smallAsset.id);
      expect(activationCount, 1);

      gravity.add(const Offset(20, 0));
      await tester.pump();
      await _pumpFrames(tester, 240);
      final rightVisualCenter = tester.getCenter(visual);
      final rightTarget = tester.getRect(target);
      expect(fieldRect.right - rightVisualCenter.dx, closeTo(15, 0.6));
      _expectFullTargetInside(rightTarget, fieldRect);
      final rightOuterPoint = Offset(
        fieldRect.right - 40,
        rightVisualCenter.dy,
      );
      expect(rightOuterPoint.dx, lessThan(rightVisualCenter.dx - 15));
      await tester.tapAt(rightOuterPoint);
      await tester.pump();
      expect(opened?.id, smallAsset.id);
      expect(activationCount, 2);
    },
  );

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

  testWidgets('the 51st asset retires the oldest visible body in place', (
    tester,
  ) async {
    final firstFifty = _assets(50);
    final newestFifty = _assets(51).skip(1).toList();
    const retiredKey = ValueKey('theme-v2-retiring-bubble-asset-0');
    await _pumpField(
      tester,
      assets: firstFifty,
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );

    await _pumpField(
      tester,
      assets: newestFifty,
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );

    expect(find.byKey(retiredKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-v2-asset-bubble-asset-50')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('打开资产 Contact 0'), findsNothing);

    await tester.pump(const Duration(milliseconds: 280));
    expect(find.byKey(retiredKey), findsNothing);
  });

  testWidgets('replacement waits until the retiring ball is released', (
    tester,
  ) async {
    final oldAsset = _assets(1).single;
    final newAsset = PoolAsset(
      id: 'asset-50',
      type: 'notes',
      domain: 'work',
      title: 'Contact 50',
      payload: const {},
      createdAt: DateTime(2026, 8, 3, 11),
    );
    const oldKey = ValueKey('theme-v2-asset-bubble-asset-0');
    const oldVisualKey = ValueKey('theme-v2-asset-bubble-rotation-asset-0');
    const newKey = ValueKey('theme-v2-asset-bubble-asset-50');
    const retiredKey = ValueKey('theme-v2-retiring-bubble-asset-0');
    await _pumpField(
      tester,
      assets: [oldAsset],
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(oldVisualKey)),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));

    await _pumpField(
      tester,
      assets: [newAsset],
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );

    expect(find.byKey(oldKey), findsOneWidget);
    expect(find.byKey(newKey), findsNothing);
    expect(find.byKey(retiredKey), findsNothing);

    await gesture.up();
    await tester.pump();

    expect(find.byKey(oldKey), findsNothing);
    expect(find.byKey(newKey), findsOneWidget);
    expect(find.byKey(retiredKey), findsOneWidget);
  });

  testWidgets('Reduce Motion replaces the oldest body immediately', (
    tester,
  ) async {
    await _pumpField(tester, assets: _assets(50), disableAnimations: true);

    await _pumpField(
      tester,
      assets: _assets(51).skip(1).toList(),
      disableAnimations: true,
    );

    expect(
      find.byKey(const ValueKey('theme-v2-asset-bubble-asset-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('theme-v2-asset-bubble-asset-50')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('theme-v2-retiring-bubble-asset-0')),
      findsNothing,
    );
  });

  testWidgets('backgrounding clears an in-flight retirement immediately', (
    tester,
  ) async {
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await _pumpField(
      tester,
      assets: _assets(50),
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );
    await _pumpField(
      tester,
      assets: _assets(51).skip(1).toList(),
      disableAnimations: false,
      gravityStream: const Stream<Offset>.empty(),
    );
    const retiredKey = ValueKey('theme-v2-retiring-bubble-asset-0');
    expect(find.byKey(retiredKey), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(find.byKey(retiredKey), findsNothing);
  });

  testWidgets(
    'same-id metadata refresh keeps body position and opens new data',
    (tester) async {
      final gravity = StreamController<Offset>();
      addTearDown(gravity.close);
      PoolAsset? opened;
      await _pumpField(
        tester,
        assets: [asset],
        disableAnimations: false,
        gravityStream: gravity.stream,
        onOpenAsset: (value) => opened = value,
      );
      final bubble = find.byKey(
        const ValueKey('theme-v2-asset-bubble-asset-1'),
      );
      gravity.add(const Offset(20, 0));
      await tester.pump();
      await _pumpFrames(tester, 12);

      await _pumpField(
        tester,
        assets: [asset],
        active: false,
        disableAnimations: false,
        gravityStream: gravity.stream,
        onOpenAsset: (value) => opened = value,
      );
      final beforeRefresh = tester.getCenter(bubble);
      final updated = PoolAsset(
        id: asset.id,
        type: 'expense',
        domain: 'life',
        title: '更新后的 Kevin',
        payload: const {'amount': 88},
        createdAt: asset.createdAt,
      );

      await _pumpField(
        tester,
        assets: [updated],
        active: false,
        disableAnimations: false,
        gravityStream: gravity.stream,
        onOpenAsset: (value) => opened = value,
      );

      expect(tester.getCenter(bubble), beforeRefresh);
      expect(find.bySemanticsLabel('打开资产 Kevin'), findsNothing);
      final updatedTarget = find.bySemanticsLabel('打开资产 更新后的 Kevin');
      expect(updatedTarget, findsOneWidget);
      await tester.tap(updatedTarget);
      expect(identical(opened, updated), isTrue);
      expect(opened?.type, 'expense');
      expect(opened?.payload['amount'], 88);
    },
  );

  testWidgets('removing a grabbed asset safely releases the destroyed body', (
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
    const gravity = Stream<Offset>.empty();
    await _pumpField(
      tester,
      assets: [asset],
      disableAnimations: false,
      gravityStream: gravity,
      onOpenAsset: (_) {},
    );
    final bubble = find.byKey(const ValueKey('theme-v2-asset-bubble-asset-1'));
    final gesture = await tester.startGesture(tester.getCenter(bubble));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));

    await _pumpField(
      tester,
      assets: [replacement],
      disableAnimations: false,
      gravityStream: gravity,
      onOpenAsset: (_) {},
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
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

List<PoolAsset> _assets(int count) => List.generate(
  count,
  (index) => PoolAsset(
    id: 'asset-$index',
    type: 'contact',
    domain: 'work',
    title: 'Contact $index',
    payload: {'name': 'Contact $index'},
    createdAt: DateTime(2026, 8, 3, 10).add(Duration(minutes: index)),
  ),
);

List<Rect> _visibleAssetTargetRects(
  WidgetTester tester,
  List<PoolAsset> assets,
  Rect field,
) => [
  for (final asset in assets)
    if (find
        .byKey(ValueKey('theme-v2-asset-bubble-${asset.id}'))
        .evaluate()
        .isNotEmpty)
      tester.getRect(find.byKey(ValueKey('theme-v2-asset-bubble-${asset.id}'))),
].where((rect) => rect.overlaps(field)).toList(growable: false);

void _expectSeparateTargetsInside(List<Rect> targets, Rect field) {
  expect(targets, isNotEmpty);
  const epsilon = 0.01;
  for (var index = 0; index < targets.length; index++) {
    final rect = targets[index];
    expect(rect.width, greaterThanOrEqualTo(44), reason: 'target $index');
    expect(rect.height, greaterThanOrEqualTo(44), reason: 'target $index');
    expect(rect.left, greaterThanOrEqualTo(field.left - epsilon));
    expect(rect.top, greaterThanOrEqualTo(field.top - epsilon));
    expect(rect.right, lessThanOrEqualTo(field.right + epsilon));
    expect(rect.bottom, lessThanOrEqualTo(field.bottom + epsilon));
    for (var other = index + 1; other < targets.length; other++) {
      expect(
        rect.overlaps(targets[other]),
        isFalse,
        reason: 'target $index overlaps target $other',
      );
    }
  }
}

void _expectFullTargetInside(Rect target, Rect field) {
  expect(target.width, greaterThanOrEqualTo(44));
  expect(target.height, greaterThanOrEqualTo(44));
  expect(target.left, greaterThanOrEqualTo(field.left));
  expect(target.top, greaterThanOrEqualTo(field.top));
  expect(target.right, lessThanOrEqualTo(field.right));
  expect(target.bottom, lessThanOrEqualTo(field.bottom));
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _pumpField(
  WidgetTester tester, {
  required List<PoolAsset> assets,
  required bool disableAnimations,
  bool active = true,
  Size size = const Size(395, 790),
  Stream<Offset>? gravityStream,
  Map<String, SkillMeta> skills = const {},
  ValueChanged<PoolAsset>? onOpenAsset,
  VoidCallback? onOpenLibrary,
  Animation<double>? motion,
  Brightness brightness = Brightness.light,
  int? trueCount,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildThemeV2Theme(brightness),
      themeAnimationDuration: Duration.zero,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ThemeV2AssetBubbleField(
            assets: assets,
            trueCount: trueCount ?? assets.length,
            skills: skills,
            active: active,
            gravityStream: gravityStream,
            onOpenAsset: onOpenAsset,
            onOpenLibrary: onOpenLibrary,
            motion: motion,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
