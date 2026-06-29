import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../auth/auth_controller.dart';
import '../config.dart';
import '../device/device_controller.dart';
import '../pages/connected_apps_page.dart';
import '../pages/device_pairing_page.dart';
import '../pages/my_device_page.dart';
import '../pages/my_ring_page.dart';
import '../ring/ring_connection.dart';
import '../pages/ring_debug_page.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'toast.dart';

/// App-wide top bar (Calendar / Library — not the pushed chat route). Holds the
/// genuinely global controls: day/night toggle, notifications, 个人中心 and
/// 设备连接. The last two are upcoming, so they open a 敬请期待 placeholder for now.
/// Per-page headers keep only their page-specific content (segmented / title /
/// refresh).
class GlobalHeaderBar extends StatelessWidget {
  const GlobalHeaderBar({super.key, this.onDark = false});

  /// Render against the today page's dark "atmosphere" (tab0): the bar blends
  /// into #0B1220 with light controls instead of the light calendar/library bg.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 2, 4, 2),
      decoration: BoxDecoration(
        color: onDark ? const Color(0xFF0B1220) : eu.bg,
        border: Border(
          bottom: BorderSide(color: onDark ? const Color(0x14FFFFFF) : eu.rule),
        ),
      ),
      child: Row(
        children: [
          // Brand wordmark (official mark + EUREKA), tinted to brand blue so it
          // reads on both light & dark headers (the source SVG is monochrome).
          SvgPicture.asset(
            'assets/logo/eureka_wordmark.svg',
            height: 19,
            colorFilter: ColorFilter.mode(eu.brand, BlendMode.srcIn),
          ),
          const Spacer(),
          ThemeToggle(onDark: onDark),
          // 通知 moved onto REKA (§9.2) — no header bell.
          _GhostButton(
            icon: Icons.person_outline,
            tooltip: '个人中心',
            onDark: onDark,
            onTap: () => _openProfile(context),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([
              DeviceController.instance,
              RingConnection.instance,
            ]),
            builder: (context, _) {
              final dev = DeviceController.instance;
              final cardConnected =
                  dev.state == DeviceConnState.connected && dev.isBound;
              final ringConnected = RingConnection.instance.isConnected;
              // Distinguish which device is connected (ring takes precedence in the icon).
              final IconData icon;
              final String tooltip;
              final Color? color;
              if (ringConnected) {
                icon = Icons.panorama_fish_eye; // 小戒指(环形)
                tooltip = '戒指已连接';
                color = eu.accentGreen;
              } else if (cardConnected) {
                icon = Icons.credit_card; // 小卡片
                tooltip = '录音卡已连接';
                color = eu.accentGreen;
              } else {
                icon = Icons.devices_outlined;
                tooltip = '设备连接';
                color = null;
              }
              return _GhostButton(
                icon: icon,
                tooltip: tooltip,
                color: color,
                onDark: onDark,
                onTap: () => _openDevice(context),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final bool onDark;
  final VoidCallback onTap;
  const _GhostButton({
    required this.icon,
    required this.tooltip,
    this.color,
    this.onDark = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: color ?? (onDark ? Colors.white70 : eu.textMid)),
    );
  }
}

/// 个人中心 — current account + 退出登录 (the rest is upcoming).
void _openProfile(BuildContext context) {
  final eu = context.eu;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: eu.surfaceRaised,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: eu.brand.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: eu.brand.withValues(alpha: 0.28)),
                  ),
                  child: Icon(Icons.person_outline, color: eu.brand, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AuthController.instance.email ?? '已登录',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: eu.textHi,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Eureka 账号',
                        style: TextStyle(color: eu.textMid, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // 已连接应用 (Connected Apps) — external app connections.
            GestureDetector(
              onTap: () {
                Navigator.of(sheetCtx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ConnectedAppsPage()),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: eu.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: eu.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hub_outlined, size: 19, color: eu.textMid),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '已连接应用',
                        style: TextStyle(color: eu.textHi, fontSize: 15),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: eu.textLo),
                  ],
                ),
              ),
            ),
            if (AppConfig.showRingDebug) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RingDebugPage()),
                  );
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: eu.bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: eu.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bluetooth_audio_outlined,
                        size: 19,
                        color: eu.textMid,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '[Debug] Ring 调试',
                          style: TextStyle(color: eu.textHi, fontSize: 15),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: eu.textLo),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Navigator.of(sheetCtx).pop();
                AuthController.instance.logout(); // gate rebuilds to login
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: eu.accentRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: eu.accentRed.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  '退出登录',
                  style: TextStyle(
                    color: eu.accentRed,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 设备连接 → 先判断蓝牙与真实连接态，再进入我的设备或扫描页。
void _openDevice(BuildContext context) {
  unawaited(_openDeviceResolved(context));
}

Future<void> _openDeviceResolved(BuildContext context) async {
  try {
    final target = await DeviceController.instance.resolveEntryTarget();
    if (!context.mounted) return;
    // No card device bound but a ring is connected → show the ring detail page.
    if (target != DeviceEntryTarget.myDevice &&
        RingConnection.instance.isConnected) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MyRingPage()));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => target == DeviceEntryTarget.myDevice
            ? const MyDevicePage()
            : const DevicePairingPage(),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    final message = e is DeviceOperationException
        ? e.message
        : '设备状态检查失败，请稍后重试';
    showToast(context, message, error: true);
  }
}
