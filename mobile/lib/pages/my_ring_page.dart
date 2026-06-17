import 'dart:async';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ring/ring_art.dart';
import '../ring/ring_connection.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// 我的戒指 — connected ring status + battery/firmware/MAC + 解除绑定.
/// Mirrors MyDevicePage for the W2 card.
class MyRingPage extends StatefulWidget {
  const MyRingPage({super.key});

  @override
  State<MyRingPage> createState() => _MyRingPageState();
}

class _MyRingPageState extends State<MyRingPage> {
  final _ring = ChipletRing();
  int? _battery;
  String? _firmware;
  String? _mac;

  @override
  void initState() {
    super.initState();
    RingConnection.instance.ensureStarted();
    RingConnection.instance.addListener(_onConn);
    _loadInfo();
  }

  @override
  void dispose() {
    RingConnection.instance.removeListener(_onConn);
    super.dispose();
  }

  void _onConn() {
    if (!mounted) return;
    setState(() {});
    if (RingConnection.instance.isConnected) _loadInfo();
  }

  Future<void> _loadInfo() async {
    final sp = await SharedPreferences.getInstance();
    if (mounted) setState(() => _mac = sp.getString('ring_mac'));
    if (!RingConnection.instance.isConnected) return;
    final battery = await _ring.getBattery();
    final version = await _ring.getVersion();
    if (!mounted) return;
    setState(() {
      _battery = battery;
      _firmware = (version?['fw'] as String?)?.trim();
    });
  }

  Future<void> _unbind() async {
    try {
      await _ring.disconnect();
    } catch (_) {}
    final sp = await SharedPreferences.getInstance();
    await sp.remove('ring_mac');
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final connected = RingConnection.instance.isConnected;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        elevation: 0,
        title: const Text('我的戒指'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Center(child: RingArt(size: 150)),
              const SizedBox(height: 16),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      size: 18,
                      color: connected ? eu.accentGreen : eu.textLo,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connected ? '戒指已连接' : '戒指未连接',
                      style: TextStyle(
                        color: connected ? eu.accentGreen : eu.textMid,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel(eu, '设备信息'),
              _infoRow(eu, Icons.battery_5_bar_outlined, '电量',
                  _battery == null ? '--' : '$_battery%'),
              _infoRow(eu, Icons.memory_outlined, '固件版本', _firmware ?? '--'),
              _infoRow(eu, Icons.fingerprint, 'MAC', _mac ?? '--'),
              const Spacer(),
              GestureDetector(
                onTap: _unbind,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: eu.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: eu.border),
                  ),
                  child: Text(
                    '解除绑定',
                    style: TextStyle(
                      color: eu.accentRed,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(EurekaColors eu, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: TextStyle(
            color: eu.textLo,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _infoRow(EurekaColors eu, IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: eu.textMid),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: eu.textHi, fontSize: 15)),
          const Spacer(),
          Text(value, style: euMono(fontSize: 14, color: eu.textMid)),
        ],
      ),
    );
  }
}
