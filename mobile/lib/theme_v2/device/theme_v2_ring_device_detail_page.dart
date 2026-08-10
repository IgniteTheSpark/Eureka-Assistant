import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../config.dart';
import '../../pages/ring_debug_page.dart';
import '../../ring/ring_art.dart';
import '../../ring/ring_connection.dart';
import '../../ring/ring_device_service.dart';
import '../foundation/theme_v2_theme.dart';
import 'theme_v2_device_detail_scaffold.dart';

class ThemeV2RingDeviceDetailPage extends StatefulWidget {
  const ThemeV2RingDeviceDetailPage({super.key, this.service, this.connection});

  final RingDeviceService? service;
  final Listenable? connection;

  @override
  State<ThemeV2RingDeviceDetailPage> createState() =>
      _ThemeV2RingDeviceDetailPageState();
}

class _ThemeV2RingDeviceDetailPageState
    extends State<ThemeV2RingDeviceDetailPage> {
  late RingDeviceService _service;
  late Listenable _connection;
  RingDeviceInfo? _info;
  String? _error;
  var _unbinding = false;
  var _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _attachDependencies();
    _loadInfo();
  }

  @override
  void didUpdateWidget(covariant ThemeV2RingDeviceDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final connectionChanged = oldWidget.connection != widget.connection;
    final serviceChanged = oldWidget.service != widget.service;
    if (!connectionChanged && !serviceChanged) return;
    _connection.removeListener(_handleConnectionChanged);
    _attachDependencies();
    if (serviceChanged) _loadInfo();
  }

  void _attachDependencies() {
    _service = widget.service ?? RingDeviceService.production();
    _connection = widget.connection ?? RingConnection.instance;
    _connection.addListener(_handleConnectionChanged);
  }

  void _handleConnectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInfo() async {
    final revision = ++_loadRevision;
    try {
      final info = await _service.loadInfo();
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _info = info;
        _error = null;
      });
    } catch (error) {
      if (!mounted || revision != _loadRevision) return;
      setState(() => _error = error.toString());
    }
  }

  Future<bool> _confirmUnbind() async {
    final tokens = context.themeV2;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('解除绑定？'),
            content: const Text('解除后需要重新配对才能使用这枚戒指。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: tokens.critical),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('解除绑定'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _unbind() async {
    if (_unbinding || !await _confirmUnbind() || !mounted) return;

    final route = ModalRoute.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _unbinding = true;
      _error = null;
    });

    try {
      final result = await _service.unbind();
      if (!mounted || route?.isCurrent != true) return;
      if (result.warning != null) {
        messenger.showSnackBar(SnackBar(content: Text(result.warning!)));
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted && route?.isCurrent == true) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && (route == null || route.isCurrent)) {
        setState(() => _unbinding = false);
      }
    }
  }

  bool get _connected {
    final connection = _connection;
    if (connection is RingConnection) return connection.isConnected;
    if (connection is ValueListenable<bool>) return connection.value;
    return false;
  }

  @override
  void dispose() {
    _loadRevision++;
    _connection.removeListener(_handleConnectionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return PopScope(
      canPop: !_unbinding,
      child: ThemeV2DeviceDetailScaffold(
        title: '戒指详情',
        deviceName: 'UReka 智能戒指',
        connected: _connected,
        hero: const RingArt(size: 132),
        information: [
          ThemeV2DeviceInfoRow(label: 'MAC', value: _fallback(info?.mac)),
          ThemeV2DeviceInfoRow(
            label: '电量',
            value: info?.batteryPct == null ? '--' : '${info!.batteryPct}%',
          ),
          ThemeV2DeviceInfoRow(
            label: '固件版本',
            value: _fallback(info?.firmwareVersion),
          ),
          ThemeV2DeviceInfoRow(
            label: '硬件版本',
            value: _fallback(info?.hardwareVersion),
          ),
          if (_error != null) ThemeV2DeviceInfoRow(label: '异常', value: _error!),
        ],
        unbinding: _unbinding,
        onUnbind: _unbind,
        extraChildren: [
          if (AppConfig.showRingDebug) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const RingDebugPage())),
              icon: const Icon(Icons.science_outlined),
              label: const Text('[Debug] 戒指能力探针'),
            ),
          ],
        ],
      ),
    );
  }
}

String _fallback(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? '--' : normalized;
}
