import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../device/device_controller.dart';
import '../pages/device_pairing_page.dart';
import '../pages/my_device_page.dart';
import '../pages/my_ring_page.dart';
import '../ring/ring_connection.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../theme_v2/account/theme_v2_account_page.dart';
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
          // The brand wordmark is also the account entry point. Keep personal
          // center out of the trailing action row so the header stays quiet.
          Semantics(
            button: true,
            label: '个人中心',
            child: GestureDetector(
              onTap: () => _openProfile(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SvgPicture.asset(
                  'assets/logo/eureka_wordmark.svg',
                  height: 19,
                  colorFilter: ColorFilter.mode(eu.brand, BlendMode.srcIn),
                ),
              ),
            ),
          ),
          const Spacer(),
          ThemeToggle(onDark: onDark),
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

/// Open the full account center from the brand wordmark.
void _openProfile(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ThemeV2AccountPage()));
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
