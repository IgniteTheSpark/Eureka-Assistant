import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Global "正在聆听" overlay — shown over the whole app while the W1/W2 card's
/// flash-memo button is held (driven by the SSE `listening` event). Mirrors the
/// web ListeningOverlay: a breathing gradient mic + waveform centered on a dim
/// scrim. Non-interactive (the hardware button controls start/stop).
class GlobalListeningOverlay extends StatefulWidget {
  const GlobalListeningOverlay({super.key});

  @override
  State<GlobalListeningOverlay> createState() => _GlobalListeningOverlayState();
}

class _GlobalListeningOverlayState extends State<GlobalListeningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: const TextStyle(decoration: TextDecoration.none),
          child: Container(
            color: eu.bg.withValues(alpha: 0.86),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) {
                    final breathe =
                        1 + 0.06 * math.sin(_ctrl.value * 2 * math.pi);
                    return Transform.scale(
                      scale: breathe,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [eu.brand, eu.accentPurple],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: eu.brand.withValues(alpha: 0.5),
                              blurRadius: 44,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 7; i++) ...[
                              _bar(i),
                              if (i < 6) const SizedBox(width: 4),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Text(
                  '正在聆听…',
                  style: TextStyle(
                    color: eu.textHi,
                    decoration: TextDecoration.none,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '硬件录音中',
                  style: TextStyle(
                    color: eu.textMid,
                    decoration: TextDecoration.none,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(int i) {
    final phase = (_ctrl.value * 2 * math.pi) + i * 0.7;
    final h = 14 + 22 * (0.5 + 0.5 * math.sin(phase));
    return Container(
      width: 5,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
