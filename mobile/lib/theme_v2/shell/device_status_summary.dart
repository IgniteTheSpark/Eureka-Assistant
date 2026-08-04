import 'package:flutter/foundation.dart';

/// Stable, view-only device summary consumed by the global navigation.
///
/// Live hardware controllers are mapped into this contract at the Theme V2
/// shell boundary, keeping connection ownership out of presentation widgets.
enum DeviceStatusSummaryKind { disconnected, connected, attention }

enum ThemeV2DevicePresence { none, card, ring, both }

enum ThemeV2DeviceTarget { pairing, card, ring }

@immutable
class DeviceStatusSummary {
  const DeviceStatusSummary({
    required this.kind,
    required this.label,
    required this.presence,
  });

  const DeviceStatusSummary.disconnected({this.label = '未连接'})
    : kind = DeviceStatusSummaryKind.disconnected,
      presence = ThemeV2DevicePresence.none;

  const DeviceStatusSummary.connected({
    required this.presence,
    this.label = '已连接',
  }) : kind = DeviceStatusSummaryKind.connected;

  const DeviceStatusSummary.attention({
    required this.presence,
    this.label = '需要处理',
  }) : kind = DeviceStatusSummaryKind.attention;

  final DeviceStatusSummaryKind kind;
  final String label;
  final ThemeV2DevicePresence presence;

  ThemeV2DeviceTarget? get directTarget => switch (presence) {
    ThemeV2DevicePresence.none => ThemeV2DeviceTarget.pairing,
    ThemeV2DevicePresence.card => ThemeV2DeviceTarget.card,
    ThemeV2DevicePresence.ring => ThemeV2DeviceTarget.ring,
    ThemeV2DevicePresence.both => null,
  };

  bool get isConnected => kind == DeviceStatusSummaryKind.connected;
}
