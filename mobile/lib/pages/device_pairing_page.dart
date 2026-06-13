import 'dart:async';

import 'package:flutter/material.dart';

import '../device/device_controller.dart';
import '../device/device_silent_reconnect.dart';
import '../theme/app_theme.dart';
import 'my_device_page.dart';

/// First-run pairing flow for the UReka 录音卡.
/// Top search pill + a 2-step onboarding pager; when the scan surfaces a device
/// a 发现设备 sheet slides up to confirm + 连接 → 我的设备.
class DevicePairingPage extends StatefulWidget {
  const DevicePairingPage({super.key});

  @override
  State<DevicePairingPage> createState() => _DevicePairingPageState();
}

class _DevicePairingPageState extends State<DevicePairingPage> {
  static const _scanDelay = Duration(seconds: 2);

  final _dev = DeviceController.instance;
  final _pager = PageController();
  Timer? _startScanTimer;
  int _page = 0;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    unawaited(DeviceSilentReconnect.instance.stop());
    _dev.addListener(_onDevice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startScanTimer?.cancel();
      _startScanTimer = Timer(_scanDelay, () {
        if (!mounted) return;
        unawaited(_dev.ensurePermissionAndStartScan());
      });
    });
  }

  @override
  void dispose() {
    _startScanTimer?.cancel();
    _dev.removeListener(_onDevice);
    _dev.stopScan();
    _pager.dispose();
    super.dispose();
  }

  void _onDevice() {
    if (!mounted) return;
    if (_dev.discovered.isNotEmpty && !_sheetOpen && !_dev.isBound) {
      _showDiscoverSheet();
    }
    setState(() {});
  }

  Future<void> _showDiscoverSheet() async {
    _sheetOpen = true;
    final connected = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      isDismissible: false,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => const _DiscoverSheet(),
    );
    _sheetOpen = false;
    if (connected == true && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MyDevicePage()),
      );
    } else if (connected == false && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: eu.textMid,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: eu.textMid),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _SearchPill(scanning: _dev.state == DeviceConnState.scanning),
            if (_dev.errorMessage != null && _dev.discovered.isEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  _dev.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: eu.accentRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            Expanded(
              child: PageView(
                controller: _pager,
                onPageChanged: (i) => setState(() => _page = i),
                children: const [
                  _PairStep(
                    art: _DeviceArt(showButtonHint: true),
                    title: '开启设备',
                    lines: ['按住电源键 5 秒。', '首次设置时只需执行一次。'],
                  ),
                  _PairStep(
                    art: _DeviceArt(connected: true, battery: 80),
                    title: '开始蓝牙配对',
                    lines: ['按一次电源键。', '屏幕亮起后，请将设备保持在附近。'],
                  ),
                ],
              ),
            ),
            _Dots(count: 2, index: _page),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '需要帮助？',
                      style: TextStyle(color: eu.textLo, fontSize: 13),
                    ),
                    TextSpan(
                      text: '联系客服',
                      style: TextStyle(
                        color: eu.brand,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  final bool scanning;
  const _SearchPill({required this.scanning});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: eu.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_searching, size: 18, color: eu.brand),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              scanning ? '正在搜索你的 UReka 设备…' : '准备搜索…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: eu.textHi,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairStep extends StatelessWidget {
  final Widget art;
  final String title;
  final List<String> lines;
  const _PairStep({
    required this.art,
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          art,
          const SizedBox(height: 28),
          Text(
            title,
            style: TextStyle(
              color: eu.brand,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final l in lines)
            Text(
              l,
              textAlign: TextAlign.center,
              style: TextStyle(color: eu.textMid, fontSize: 15, height: 1.5),
            ),
        ],
      ),
    );
  }
}

/// Stylized stand-in for the orange/black W2 card render (real photoreal asset
/// can replace this). Shows a power-button hint, or a connected screen state.
class _DeviceArt extends StatelessWidget {
  final bool showButtonHint;
  final bool connected;
  final int battery;
  const _DeviceArt({
    this.showButtonHint = false,
    this.connected = false,
    this.battery = 0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 250,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1A1A1E),
                  Color(0xFF2A2024),
                  Color(0xFFE5621B),
                ],
                stops: [0.0, 0.28, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE5621B).withValues(alpha: 0.30),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              children: [
                // Top black screen area
                Container(
                  height: 78,
                  margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A0C),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: connected
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'UReka',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '$battery%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  Icons.battery_full,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                            const Spacer(),
                            const Row(
                              children: [
                                Icon(
                                  Icons.bluetooth,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Bluetooth Connected',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: Color(0xFF222226),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                ),
                const Spacer(),
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'UReka',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showButtonHint)
            const Positioned(
              right: 24,
              top: 46,
              child: Icon(Icons.touch_app, size: 30, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  const _Dots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? eu.brand : eu.textLo.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

/// 发现设备 sheet — confirm the discovered device's SN, then 连接.
class _DiscoverSheet extends StatefulWidget {
  const _DiscoverSheet();

  @override
  State<_DiscoverSheet> createState() => _DiscoverSheetState();
}

class _DiscoverSheetState extends State<_DiscoverSheet> {
  final _dev = DeviceController.instance;

  @override
  void initState() {
    super.initState();
    _dev.addListener(_onChange);
  }

  @override
  void dispose() {
    _dev.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    if (_dev.state == DeviceConnState.connected) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final connecting = _dev.state == DeviceConnState.connecting;
    final devices = _dev.discovered;
    final error = _dev.errorMessage;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.8;
    return SafeArea(
      top: false,
      child: Container(
        height: sheetHeight,
        decoration: BoxDecoration(
          color: eu.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        padding: EdgeInsets.fromLTRB(20, 18, 20, 24 + bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '发现设备',
                  style: TextStyle(
                    color: eu.textHi,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    _dev.stopScan(clearDiscovered: true);
                    Navigator.of(context).maybePop(false);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.close, color: eu.textMid),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '连接前请确认设备屏幕上显示的序列号。',
              style: TextStyle(color: eu.textMid, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                primary: false,
                itemCount: devices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return _DiscoveredDeviceTile(
                    key: ValueKey(device.serial),
                    device: device,
                    connecting: connecting,
                    onConnect: () => _dev.connect(device),
                  );
                },
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: TextStyle(
                  color: eu.accentRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DiscoveredDeviceTile extends StatelessWidget {
  final DiscoveredDevice device;
  final bool connecting;
  final VoidCallback onConnect;

  const _DiscoveredDeviceTile({
    required this.device,
    required this.connecting,
    required this.onConnect,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A1A1E), Color(0xFFE5621B)],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: eu.textHi,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SN:${device.serial}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: euMono(fontSize: 11, color: eu.textLo),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: connecting ? null : onConnect,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 68,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: connecting ? eu.textLo : eu.brand,
                borderRadius: BorderRadius.circular(999),
              ),
              child: connecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '连接',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
