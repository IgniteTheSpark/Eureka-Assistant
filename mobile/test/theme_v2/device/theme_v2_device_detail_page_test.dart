import 'dart:async';

import 'package:eureka/device/device_controller.dart';
import 'package:eureka/ring/ring_device_service.dart';
import 'package:eureka/theme_v2/device/theme_v2_card_device_detail_page.dart';
import 'package:eureka/theme_v2/device/theme_v2_device_route.dart';
import 'package:eureka/theme_v2/device/theme_v2_ring_device_detail_page.dart';
import 'package:eureka/theme_v2/foundation/theme_v2_theme.dart';
import 'package:eureka/theme_v2/shell/device_status_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed detail mapping keeps card and ring destinations distinct', () {
    expect(
      themeV2DeviceDetailPage(ThemeV2DeviceTarget.card),
      isA<ThemeV2CardDeviceDetailPage>(),
    );
    expect(
      themeV2DeviceDetailPage(ThemeV2DeviceTarget.ring),
      isA<ThemeV2RingDeviceDetailPage>(),
    );
    expect(
      () => themeV2DeviceDetailPage(ThemeV2DeviceTarget.pairing),
      throwsArgumentError,
    );
  });

  group('Theme V2 card device detail', () {
    testWidgets('renders card fields and only the supported action', (
      tester,
    ) async {
      final transport = _CardTransport();
      final controller = _cardController(transport);
      addTearDown(controller.dispose);

      await _pumpDetailRoute(
        tester,
        ThemeV2CardDeviceDetailPage(
          controller: controller,
          refreshOnLoad: false,
        ),
      );

      expect(find.text('SN-001'), findsOneWidget);
      expect(find.text('86%'), findsOneWidget);
      expect(find.text('3.5GB / 64GB'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('解除绑定'), findsOneWidget);
      expect(find.text('MAC'), findsNothing);
      expect(find.text('设备设置'), findsNothing);
      expect(find.text('固件更新'), findsNothing);
      expect(find.text('录音管理'), findsNothing);
    });

    for (final storage in const [
      (used: null, total: 64.0, expected: '-- / 64GB'),
      (used: 3.5, total: null, expected: '3.5GB / --'),
      (used: null, total: null, expected: '-- / --'),
    ]) {
      testWidgets(
        'formats storage sides independently as ${storage.expected}',
        (tester) async {
          final transport = _CardTransport();
          final controller = _cardController(
            transport,
            device: _cardWithStorage(storage.used, storage.total),
          );
          addTearDown(controller.dispose);

          await _pumpDetailRoute(
            tester,
            ThemeV2CardDeviceDetailPage(
              controller: controller,
              refreshOnLoad: false,
            ),
          );

          expect(find.text(storage.expected), findsOneWidget);
        },
      );
    }

    for (final choice in const [
      (label: '仅解除绑定，保留录音', deleteData: false),
      (label: '解除绑定并删除录音', deleteData: true),
    ]) {
      testWidgets(
        '${choice.label} maps confirmation and stops reconnect first',
        (tester) async {
          final operations = <String>[];
          final transport = _CardTransport(operations: operations);
          final controller = _cardController(transport);
          addTearDown(controller.dispose);

          await _pumpDetailRoute(
            tester,
            ThemeV2CardDeviceDetailPage(
              controller: controller,
              refreshOnLoad: false,
              stopSilentReconnect: () async => operations.add('stop-reconnect'),
            ),
          );

          await tester.tap(find.text('解除绑定'));
          await tester.pumpAndSettle();
          expect(find.text('仅解除绑定，保留录音'), findsOneWidget);
          expect(find.text('解除绑定并删除录音'), findsOneWidget);

          await tester.tap(find.text(choice.label));
          await tester.pumpAndSettle();

          expect(operations, ['stop-reconnect', 'unbind:${choice.deleteData}']);
          expect(find.text('route home'), findsOneWidget);
        },
      );
    }

    testWidgets('hardware failure keeps detail open and renders the error', (
      tester,
    ) async {
      final transport = _CardTransport(
        unbindError: const DeviceOperationException('硬件解绑失败'),
      );
      final controller = _cardController(transport);
      addTearDown(controller.dispose);

      await _pumpDetailRoute(
        tester,
        ThemeV2CardDeviceDetailPage(
          controller: controller,
          refreshOnLoad: false,
          stopSilentReconnect: () async {},
        ),
      );

      await tester.tap(find.text('解除绑定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅解除绑定，保留录音'));
      await tester.pumpAndSettle();

      expect(find.text('硬件解绑失败'), findsOneWidget);
      expect(find.text('route home'), findsNothing);
      expect(find.text('解除绑定'), findsOneWidget);
    });

    testWidgets('busy unbind disables duplicate action', (tester) async {
      final completer = Completer<DeviceUnbindResult>();
      final transport = _CardTransport(unbindCompleter: completer);
      final controller = _cardController(transport);
      addTearDown(controller.dispose);

      await _pumpDetailRoute(
        tester,
        ThemeV2CardDeviceDetailPage(
          controller: controller,
          refreshOnLoad: false,
          stopSilentReconnect: () async {},
        ),
      );

      await tester.tap(find.text('解除绑定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅解除绑定，保留录音'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      expect(transport.unbindCalls, 1);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      expect(transport.unbindCalls, 1);

      completer.complete(const DeviceUnbindResult.complete());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'pending card unbind blocks app-bar and system back until success',
      (tester) async {
        final completer = Completer<DeviceUnbindResult>();
        final transport = _CardTransport(unbindCompleter: completer);
        final controller = _cardController(transport);
        addTearDown(controller.dispose);

        await _pumpDetailRoute(
          tester,
          ThemeV2CardDeviceDetailPage(
            controller: controller,
            refreshOnLoad: false,
            stopSilentReconnect: () async {},
          ),
        );

        await tester.tap(find.text('解除绑定'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('仅解除绑定，保留录音'));
        await tester.pump();

        await tester.tap(find.byType(BackButton));
        await tester.pump();
        expect(find.text('录音卡详情'), findsOneWidget);
        expect(find.text('route home'), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('录音卡详情'), findsOneWidget);
        expect(find.text('route home'), findsNothing);

        completer.complete(const DeviceUnbindResult.complete());
        await tester.pumpAndSettle();
        expect(find.text('route home'), findsOneWidget);
      },
    );
  });

  group('Theme V2 ring device detail', () {
    testWidgets('renders ring fields without a serial-number row', (
      tester,
    ) async {
      final connection = ValueNotifier<bool>(true);
      addTearDown(connection.dispose);

      await _pumpDetailRoute(
        tester,
        ThemeV2RingDeviceDetailPage(
          service: _ringService(
            mac: 'CC:DD',
            battery: 72,
            version: const {'fw': '1.2.3', 'hw': 'A3'},
          ),
          connection: connection,
        ),
      );

      expect(find.text('CC:DD'), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);
      expect(find.text('1.2.3'), findsOneWidget);
      expect(find.text('A3'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('SN'), findsNothing);
    });

    testWidgets('renders -- for every missing ring field', (tester) async {
      final connection = ValueNotifier<bool>(false);
      addTearDown(connection.dispose);

      await _pumpDetailRoute(
        tester,
        ThemeV2RingDeviceDetailPage(
          service: _ringService(),
          connection: connection,
        ),
      );

      expect(find.text('--'), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('confirming ring unbind invokes the service once and closes', (
      tester,
    ) async {
      final gateway = _RingGateway();
      final connection = ValueNotifier<bool>(true);
      addTearDown(connection.dispose);

      await _pumpDetailRoute(
        tester,
        ThemeV2RingDeviceDetailPage(
          service: _ringService(gateway: gateway, mac: 'CC:DD'),
          connection: connection,
        ),
      );

      await tester.tap(find.text('解除绑定'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '解除绑定'));
      await tester.pumpAndSettle();

      expect(gateway.disconnectCalls, 1);
      expect(find.text('route home'), findsOneWidget);
    });

    testWidgets('warning survives route pop through the ScaffoldMessenger', (
      tester,
    ) async {
      final gateway = _RingGateway(
        disconnectError: StateError('bluetooth already lost'),
      );
      final connection = ValueNotifier<bool>(true);
      addTearDown(connection.dispose);

      await _pumpDetailRoute(
        tester,
        ThemeV2RingDeviceDetailPage(
          service: _ringService(gateway: gateway, mac: 'CC:DD'),
          connection: connection,
        ),
      );

      await tester.tap(find.text('解除绑定'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '解除绑定'));
      await tester.pumpAndSettle();

      expect(find.text('route home'), findsOneWidget);
      expect(find.text('本地绑定已解除，蓝牙断开可能未完成'), findsOneWidget);
    });

    testWidgets(
      'pending ring unbind blocks app-bar and system back until warning closes',
      (tester) async {
        final disconnect = Completer<void>();
        final gateway = _RingGateway(
          disconnectCompleter: disconnect,
          disconnectError: StateError('bluetooth already lost'),
        );
        final connection = ValueNotifier<bool>(true);
        addTearDown(connection.dispose);

        await _pumpDetailRoute(
          tester,
          ThemeV2RingDeviceDetailPage(
            service: _ringService(gateway: gateway, mac: 'CC:DD'),
            connection: connection,
          ),
        );

        await tester.tap(find.text('解除绑定'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '解除绑定'));
        await tester.pump();

        await tester.tap(find.byType(BackButton));
        await tester.pump();
        expect(find.text('戒指详情'), findsOneWidget);
        expect(find.text('route home'), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('戒指详情'), findsOneWidget);
        expect(find.text('route home'), findsNothing);

        disconnect.complete();
        await tester.pumpAndSettle();
        expect(find.text('route home'), findsOneWidget);
        expect(find.text('本地绑定已解除，蓝牙断开可能未完成'), findsOneWidget);
      },
    );
  });
}

const _card = DeviceInfo(
  id: 'card-1',
  bindingId: 'binding-1',
  name: 'UReka 录音卡',
  serial: 'SN-001',
  cardDeviceUuid: 'device-uuid',
  cardAppUuid: 'app-uuid',
  cardMac: 'AA:BB',
  batteryPct: 86,
  storageUsedGb: 3.5,
  storageTotalGb: 64,
);

DeviceInfo _cardWithStorage(double? used, double? total) => DeviceInfo(
  id: _card.id,
  bindingId: _card.bindingId,
  name: _card.name,
  serial: _card.serial,
  cardDeviceUuid: _card.cardDeviceUuid,
  cardAppUuid: _card.cardAppUuid,
  cardMac: _card.cardMac,
  batteryPct: _card.batteryPct,
  storageUsedGb: used,
  storageTotalGb: total,
);

DeviceController _cardController(
  _CardTransport transport, {
  DeviceInfo device = _card,
}) => DeviceController(transport)
  ..device = device
  ..state = DeviceConnState.connected;

Future<void> _pumpDetailRoute(WidgetTester tester, Widget detail) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      initialRoute: '/detail',
      routes: {
        '/': (_) => const Scaffold(body: Text('route home')),
        '/detail': (_) => detail,
      },
    ),
  );
  await tester.pumpAndSettle();
}

class _CardTransport implements DeviceTransport {
  _CardTransport({this.operations, this.unbindError, this.unbindCompleter});

  final List<String>? operations;
  final Object? unbindError;
  final Completer<DeviceUnbindResult>? unbindCompleter;
  var unbindCalls = 0;

  @override
  Stream<String> get bluetoothStateStream => const Stream.empty();

  @override
  Stream<bool> get connectionStateStream => const Stream.empty();

  @override
  Future<DeviceInfo> connect(DiscoveredDevice device) async => _card;

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> ensurePermissionReady() async {}

  @override
  Future<bool> isBluetoothPoweredOn() async => true;

  @override
  Future<bool> isDeviceConnected() async => true;

  @override
  Future<DeviceInfo?> loadBoundDevice() async => _card;

  @override
  Stream<List<DiscoveredDevice>> scan() => const Stream.empty();

  @override
  Future<DeviceUnbindResult> unbind(
    DeviceInfo device, {
    required bool deleteData,
  }) async {
    unbindCalls += 1;
    operations?.add('unbind:$deleteData');
    if (unbindError case final error?) throw error;
    final pending = unbindCompleter;
    if (pending != null) return pending.future;
    return const DeviceUnbindResult.complete();
  }
}

RingDeviceService _ringService({
  _RingGateway? gateway,
  String? mac,
  int? battery,
  Map? version,
}) {
  return RingDeviceService(
    gateway: gateway ?? _RingGateway(battery: battery, version: version),
    bindingStore: _RingStore(mac),
    forgetReconnect: () {},
    markUnbound: () {},
  );
}

class _RingGateway implements RingDeviceGateway {
  _RingGateway({
    this.battery,
    this.version,
    this.disconnectError,
    this.disconnectCompleter,
  });

  final int? battery;
  final Map? version;
  final Object? disconnectError;
  final Completer<void>? disconnectCompleter;
  var disconnectCalls = 0;

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
    await disconnectCompleter?.future;
    if (disconnectError case final error?) throw error;
  }

  @override
  Future<int?> getBattery() async => battery;

  @override
  Future<Map?> getVersion() async => version;
}

class _RingStore implements RingBindingStore {
  _RingStore(this.mac);

  String? mac;

  @override
  Future<void> clearMac() async => mac = null;

  @override
  Future<String?> readMac() async => mac;
}
