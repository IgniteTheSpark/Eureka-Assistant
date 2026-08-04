import 'dart:async';

import 'package:flutter/material.dart';

import '../../device/device_controller.dart';
import '../../device/device_silent_reconnect.dart';
import '../foundation/theme_v2_theme.dart';
import '../foundation/theme_v2_tokens.dart';
import 'theme_v2_device_detail_scaffold.dart';

class ThemeV2CardDeviceDetailPage extends StatefulWidget {
  const ThemeV2CardDeviceDetailPage({
    super.key,
    this.controller,
    this.stopSilentReconnect,
    this.refreshOnLoad = true,
  });

  final DeviceController? controller;
  final Future<void> Function()? stopSilentReconnect;
  final bool refreshOnLoad;

  @override
  State<ThemeV2CardDeviceDetailPage> createState() =>
      _ThemeV2CardDeviceDetailPageState();
}

class _ThemeV2CardDeviceDetailPageState
    extends State<ThemeV2CardDeviceDetailPage> {
  late DeviceController _controller;
  var _unbinding = false;

  @override
  void initState() {
    super.initState();
    _attachController();
    if (widget.refreshOnLoad) {
      unawaited(_controller.refreshBoundDevice());
    }
  }

  @override
  void didUpdateWidget(covariant ThemeV2CardDeviceDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _controller.removeListener(_handleControllerChanged);
    _attachController();
    if (widget.refreshOnLoad) {
      unawaited(_controller.refreshBoundDevice());
    }
  }

  void _attachController() {
    _controller = widget.controller ?? DeviceController.instance;
    _controller.addListener(_handleControllerChanged);
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  Future<bool?> _confirmUnbind() {
    final tokens = context.themeV2;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解除绑定？'),
        content: const Text('选择是否同时删除录音卡中的录音。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('仅解除绑定，保留录音'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: tokens.critical),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('解除绑定并删除录音'),
          ),
        ],
      ),
    );
  }

  Future<void> _unbind() async {
    if (_unbinding) return;
    final deleteData = await _confirmUnbind();
    if (deleteData == null || !mounted) return;

    final route = ModalRoute.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _unbinding = true);

    try {
      final stop =
          widget.stopSilentReconnect ?? DeviceSilentReconnect.instance.stop;
      await stop();
      final result = await _controller.unbind(deleteData: deleteData);
      if (result == null || !mounted || route?.isCurrent != true) return;
      if (!result.serverSynced && result.message != null) {
        messenger.showSnackBar(SnackBar(content: Text(result.message!)));
      }
      Navigator.of(context).pop();
    } finally {
      if (mounted && (route == null || route.isCurrent)) {
        setState(() => _unbinding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _controller.device;
    final error = _controller.errorMessage;
    return ThemeV2DeviceDetailScaffold(
      title: '录音卡详情',
      deviceName: device?.name ?? 'UReka 录音卡',
      connected:
          device != null && _controller.state == DeviceConnState.connected,
      hero: const _CardDeviceIllustration(),
      information: [
        ThemeV2DeviceInfoRow(label: 'SN', value: _fallback(device?.serial)),
        ThemeV2DeviceInfoRow(label: 'MAC', value: _fallback(device?.cardMac)),
        ThemeV2DeviceInfoRow(
          label: '电量',
          value: device?.batteryPct == null ? '--' : '${device!.batteryPct}%',
        ),
        ThemeV2DeviceInfoRow(label: '存储空间', value: _formatStorage(device)),
        if (error != null) ThemeV2DeviceInfoRow(label: '异常', value: error),
      ],
      unbinding: _unbinding,
      onUnbind: device == null ? null : _unbind,
    );
  }
}

class _CardDeviceIllustration extends StatelessWidget {
  const _CardDeviceIllustration();

  @override
  Widget build(BuildContext context) {
    final tokens = context.themeV2;
    return Container(
      width: 136,
      height: 88,
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(ThemeV2Radii.lg),
        boxShadow: [
          BoxShadow(
            color: tokens.foreground.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(Icons.contactless_outlined, size: 42, color: tokens.accent),
    );
  }
}

String _fallback(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? '--' : normalized;
}

String _formatStorage(DeviceInfo? device) {
  final used = device?.storageUsedGb;
  final total = device?.storageTotalGb;
  if (used == null || total == null) return '--';
  return '${_formatGb(used)}GB / ${_formatGb(total)}GB';
}

String _formatGb(double value) => value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();
