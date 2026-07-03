import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';

/// §9.2 v4 短按 → 功能菜单. A single **frosted-glass panel** containing all options,
/// opened above/below REKA (like the bubbles) and **tinted by REKA's aura glow**
/// (the same `--mtint` color source the bubbles/popups use). Non-modal: a light
/// scrim, tap-outside dismisses. Picking an item calls [onPick] with its key:
/// 'create' | 'summarize' | 'notifications' | 'tasks' | 'island'.
class RekaRadial extends StatefulWidget {
  final Rect anchor; // ball rect (global)
  final VoidCallback onClose;
  final void Function(String key) onPick;
  final int notifCount;
  final List<Color> glow; // REKA's aura tint (rekaGlow)
  const RekaRadial({
    super.key,
    required this.anchor,
    required this.onClose,
    required this.onPick,
    this.notifCount = 0,
    this.glow = const [Color(0xFF6F9EFF)],
  });

  @override
  State<RekaRadial> createState() => _RekaRadialState();
}

class _Item {
  final String key;
  final IconData icon;
  final String label;
  final bool accent;
  const _Item(this.key, this.icon, this.label, {this.accent = false});
}

// 我的岛 left the dock (dock = 今日/日历/资产) → its entry lives HERE in REKA's
// menu (key 'island' → PetPage, handled in floating_mascot._onPick). The earlier
// "it's a dock tab" note was stale — it isn't, so the entry went missing.
// 任务 temporarily removed — it returns with the 岛屿任务 (§7) spec
// (restore: _Item('tasks', Icons.checklist_rounded, '任务')).
const _items = <_Item>[
  _Item('create', Icons.add, '快创', accent: true),
  _Item(
    'summarize',
    Icons.auto_awesome_outlined,
    '洞察',
  ), // was 总结 (too dry); ✦ matches the 升华 flow
  _Item('notifications', Icons.notifications_none, '通知'),
  _Item('island', Icons.cottage_outlined, '我的岛'),
];

class _RekaRadialState extends State<RekaRadial>
    with SingleTickerProviderStateMixin {
  static const double _panelW = 160; // 2×2 grid for the 4 items
  // v4 timing: panel container .2s; items 28ms stagger.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  Future<void> _dismiss() async {
    try {
      await _c.reverse();
    } finally {
      widget.onClose();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final mq = MediaQuery.of(context);
    final w = mq.size.width, h = mq.size.height;
    final a = widget.anchor;
    final openAbove = a.top > h * 0.46;
    final left = (a.center.dx - _panelW / 2).clamp(8.0, w - _panelW - 8);

    final panel = Positioned(
      left: left,
      width: _panelW,
      top: openAbove
          ? null
          : (a.bottom + 10).clamp(mq.padding.top + 8, h - 120),
      bottom: openAbove ? (h - a.top + 10).clamp(12.0, h - 80) : null,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.96,
          end: 1.0,
        ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
        alignment: openAbove ? Alignment.bottomCenter : Alignment.topCenter,
        child: FadeTransition(opacity: _c, child: _glassPanel(eu)),
      ),
    );

    // Wrap in a transparent Material so the label Text has a Material ancestor —
    // without it, text in a raw Overlay renders with Flutter's yellow debug
    // double-underline (the "下划线" the user saw — an artifact, not a design).
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: FadeTransition(
                  opacity: _c,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
            panel,
          ],
        ),
      ),
    );
  }

  Widget _glassPanel(EurekaColors eu) {
    final t0 = widget.glow.first;
    final t1 = widget.glow.last;
    // dark glass base, tinted by the aura color (mirrors the .rmenu gradient).
    final topC = Color.alphaBlend(
      t0.withValues(alpha: 0.30),
      const Color(0xBC10161E),
    );
    final botC = Color.alphaBlend(
      t1.withValues(alpha: 0.16),
      const Color(0xC70C111E),
    );
    final border = Color.alphaBlend(t0.withValues(alpha: 0.55), eu.border);
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [topC, botC],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 44,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: t0.withValues(alpha: 0.42),
                blurRadius: 30,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (var i = 0; i < _items.length; i++) _item(eu, i)],
          ),
        ),
      ),
    );
  }

  Widget _item(EurekaColors eu, int i) {
    final it = _items[i];
    // 28ms per-item stagger, scale .55→1 (v4).
    final begin = (i * 0.10).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _c,
      curve: Interval(
        begin,
        (begin + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOutBack,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final v = anim.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.scale(scale: 0.55 + 0.45 * v, child: child),
        );
      },
      child: GestureDetector(
        onTap: () {
          widget.onClose();
          widget.onPick(it.key);
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: it.accent
                          ? widget.glow.first.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: it.accent ? 0.0 : 0.16,
                        ),
                      ),
                    ),
                    child: Icon(it.icon, size: 21, color: Colors.white),
                  ),
                  if (it.key == 'notifications' && widget.notifCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        constraints: const BoxConstraints(minWidth: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: eu.accentRed,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF0C1322),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          widget.notifCount > 99
                              ? '99+'
                              : '${widget.notifCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                it.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
