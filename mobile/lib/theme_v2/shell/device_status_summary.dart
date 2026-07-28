import 'package:flutter/foundation.dart';

/// Stable, view-only device summary consumed by the global navigation.
///
/// Task 13 owns mapping live device controllers into this contract. Until
/// then, production uses [DeviceStatusSummary.disconnected] and the Theme V2
/// rollout remains off by default.
enum DeviceStatusSummaryKind { disconnected, connected, attention }

@immutable
class DeviceStatusSummary {
  const DeviceStatusSummary({required this.kind, required this.label});

  const DeviceStatusSummary.disconnected({this.label = '未连接'})
    : kind = DeviceStatusSummaryKind.disconnected;

  const DeviceStatusSummary.connected({this.label = '已连接'})
    : kind = DeviceStatusSummaryKind.connected;

  const DeviceStatusSummary.attention({this.label = '需要处理'})
    : kind = DeviceStatusSummaryKind.attention;

  final DeviceStatusSummaryKind kind;
  final String label;

  bool get isConnected => kind == DeviceStatusSummaryKind.connected;
}
