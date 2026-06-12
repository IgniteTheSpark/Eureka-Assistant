import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../auth/auth_controller.dart';
import '../device/device_controller.dart';
import '../pages/connected_apps_page.dart';
import '../pages/device_pairing_page.dart';
import '../pages/my_device_page.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

/// App-wide top bar (Calendar / Library — not the pushed chat route). Holds the
/// genuinely global controls: day/night toggle, notifications, 个人中心 and
/// 设备连接. The last two are upcoming, so they open a 敬请期待 placeholder for now.
/// Per-page headers keep only their page-specific content (segmented / title /
/// refresh).
class GlobalHeaderBar extends StatelessWidget {
  const GlobalHeaderBar({super.key});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 2, 4, 2),
      decoration: BoxDecoration(
        color: eu.bg,
        border: Border(bottom: BorderSide(color: eu.rule)),
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
          const ThemeToggle(),
          // 通知 moved onto REKA (§9.2) — no header bell.
          _GhostButton(
            icon: Icons.person_outline,
            tooltip: '个人中心',
            onTap: () => _openProfile(context),
          ),
          _GhostButton(
            icon: Icons.devices_outlined,
            tooltip: '设备连接',
            onTap: () => _openDevice(context),
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _GhostButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: eu.textMid),
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
                      Text(AuthController.instance.email ?? '已登录',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: eu.textHi, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('UReka 账号', style: TextStyle(color: eu.textMid, fontSize: 12)),
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
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ConnectedAppsPage(),
                ));
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                      child: Text('已连接应用',
                          style: TextStyle(color: eu.textHi, fontSize: 15)),
                    ),
                    Icon(Icons.chevron_right, size: 18, color: eu.textLo),
                  ],
                ),
              ),
            ),
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
                  border: Border.all(color: eu.accentRed.withValues(alpha: 0.28)),
                ),
                child: Text('退出登录',
                    style: TextStyle(
                        color: eu.accentRed, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 设备连接 → 我的设备 if a device is already bound, else the first-run pairing flow.
void _openDevice(BuildContext context) {
  final bound = DeviceController.instance.isBound;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => bound ? const MyDevicePage() : const DevicePairingPage(),
  ));
}
