import 'package:flutter/material.dart';

import '../device/device_controller.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// 我的设备 — connected device status (battery / storage) + 解除绑定. Shown by the
/// header's 设备连接 entry when a device is bound.
class MyDevicePage extends StatefulWidget {
  const MyDevicePage({super.key});

  @override
  State<MyDevicePage> createState() => _MyDevicePageState();
}

class _MyDevicePageState extends State<MyDevicePage> {
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
    // Unbound (e.g. via the sheet) → leave this page.
    if (!_dev.isBound) {
      Navigator.of(context).maybePop();
    } else {
      setState(() {});
    }
  }

  Future<void> _unbind() async {
    final eu = context.eu;
    final d = _dev.device;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: eu.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '解除绑定 ${d?.name ?? '设备'}？',
                      style: TextStyle(
                        color: eu.textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    behavior: HitTestBehavior.opaque,
                    child: Icon(Icons.close, color: eu.textMid),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '请选择是否保留设备上的录音。',
                style: TextStyle(color: eu.textMid, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _sheetAction(
                eu,
                '仅解除绑定，保留数据',
                () => Navigator.pop(ctx, 'keep'),
                color: eu.textHi,
              ),
              Divider(height: 1, color: eu.rule),
              _sheetAction(
                eu,
                '解除绑定并删除数据',
                () => Navigator.pop(ctx, 'delete'),
                color: eu.accentRed,
              ),
              const SizedBox(height: 8),
              _sheetAction(
                eu,
                '取消',
                () => Navigator.pop(ctx),
                color: eu.textMid,
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'keep') {
      await _dev.unbind(deleteData: false);
    } else if (choice == 'delete') {
      await _dev.unbind(deleteData: true);
    }
    final err = _dev.errorMessage;
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    // _onChange pops the page once isBound flips false.
  }

  Widget _sheetAction(
    EurekaColors eu,
    String label,
    VoidCallback onTap, {
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final d = _dev.device;
    final batteryText = d?.batteryPct == null ? '--' : '${d!.batteryPct}%';
    final storageText = d?.storageUsedGb == null || d?.storageTotalGb == null
        ? '--'
        : '${d!.storageUsedGb!.toStringAsFixed(1)}GB/${d.storageTotalGb!.toStringAsFixed(0)}GB';
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        centerTitle: true,
        title: const Text('我的设备'),
      ),
      body: d == null
          ? Center(
              child: Text('未连接设备', style: TextStyle(color: eu.textMid)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                // Connected device card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: eu.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: eu.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: eu.brand.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: eu.brand.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Icon(
                          Icons.devices_outlined,
                          color: eu.brand,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name,
                              style: TextStyle(
                                color: eu.textHi,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'SN：${d.serial}',
                              style: euMono(fontSize: 11, color: eu.textLo),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: eu.accentGreen.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '已连接',
                          style: TextStyle(
                            color: eu.accentGreen,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _sectionLabel(eu, '设备信息'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: eu.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: eu.border),
                  ),
                  child: Column(
                    children: [
                      _infoRow(
                        eu,
                        Icons.battery_5_bar_outlined,
                        '电量',
                        batteryText,
                      ),
                      Divider(
                        height: 1,
                        color: eu.rule,
                        indent: 16,
                        endIndent: 16,
                      ),
                      _infoRow(
                        eu,
                        Icons.sd_storage_outlined,
                        '存储空间',
                        storageText,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _sectionLabel(eu, '设备管理'),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _unbind,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: eu.surfaceRaised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: eu.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.link_off, color: eu.accentRed, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          '解除设备绑定',
                          style: TextStyle(
                            color: eu.accentRed,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right, color: eu.textLo, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionLabel(EurekaColors eu, String text) => Text(
    text,
    style: TextStyle(
      color: eu.textHi,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _infoRow(EurekaColors eu, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: eu.textMid, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: eu.textHi, fontSize: 15)),
          const Spacer(),
          Text(value, style: euMono(fontSize: 14, color: eu.textMid)),
        ],
      ),
    );
  }
}
