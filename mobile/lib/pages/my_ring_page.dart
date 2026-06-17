import 'dart:async';

import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ring/ring_connection.dart';
import '../theme/app_theme.dart';

/// 我的戒指 — connected ring status + 解除绑定. Mirrors MyDevicePage for the W2 card.
class MyRingPage extends StatefulWidget {
  const MyRingPage({super.key});

  @override
  State<MyRingPage> createState() => _MyRingPageState();
}

class _MyRingPageState extends State<MyRingPage> {
  final _ring = ChipletRing();

  Future<void> _unbind() async {
    // Disconnect and forget the saved MAC so auto-reconnect stops.
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
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        elevation: 0,
        title: const Text('我的戒指'),
      ),
      body: AnimatedBuilder(
        animation: RingConnection.instance,
        builder: (context, _) {
          final connected = RingConnection.instance.isConnected;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: eu.surfaceRaised,
                        border: Border.all(
                          color: connected ? eu.accentGreen : eu.border,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.bluetooth_audio,
                        size: 40,
                        color: connected ? eu.accentGreen : eu.textLo,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      connected ? '戒指已连接' : '戒指未连接',
                      style: TextStyle(
                        color: eu.textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      connected ? '双击戒指即可开始/停止录音' : '请重新连接戒指',
                      style: TextStyle(color: eu.textMid, fontSize: 13),
                    ),
                  ),
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
          );
        },
      ),
    );
  }
}
