import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../pages/calendar_page.dart' show DayDetailPage;
import '../theme/app_theme.dart'; // context.eu
import '../theme/domains.dart' show domainColor;
import '../theme/eureka_colors.dart';
import 'today_data.dart';

/// Format a countdown [d] for the focal card: "1 时 05 分" once ≥1h, else
/// "23 分 00 秒". Clamps negatives to zero. Pure → unit-tested
/// (test/next_action_fmt_test.dart).
String fmtCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return h > 0 ? '$h 时 ${two(m)} 分' : '${two(m)} 分 ${two(s)} 秒';
}

// ── prototype dark tokens (the page is its own dark "atmosphere", not eu) ──────
const _panelBg = Color(0xA80F1728); // rgba(15,23,40,.66)
const _panelBorder = Color(0x17FFFFFF); // rgba(255,255,255,.09)
const _accent = Color(0xFF8AB4FF);
const _titleColor = Color(0xFFE6EDF3);
const _muted = Color(0x80FFFFFF); // white .5
const _muted40 = Color(0x66FFFFFF);

/// Part 1 — the swipeable stack of upcoming timed actions + the no-time todo
/// list. Floats (frosted) over the bubble pool. Tokens = prototype "Next Action
/// panel"; logic = §4.5.0. [chain] is upcoming-timed (sorted), [noTimeTodos] the
/// no-clock todos. Both come from [loadToday]; completing/advancing calls
/// [bumpData] so TodayPage re-fetches.
class NextActionPanel extends StatefulWidget {
  const NextActionPanel({
    super.key,
    required this.chain,
    required this.noTimeTodos,
  });

  final List<ChainItem> chain;
  final List<ChainItem> noTimeTodos;

  @override
  State<NextActionPanel> createState() => _NextActionPanelState();
}

class _NextActionPanelState extends State<NextActionPanel>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  bool _open = true;
  bool _noTimeOpen = false;
  int _index = 0;
  DateTime _now = DateTime.now();
  Timer? _tick;
  final Set<String> _completing = {}; // ids mid-PUT (avoid double-tap)

  // Tinder-style swipe on the focal card.
  Offset _drag = Offset.zero;
  late final AnimationController _fly;
  Offset _flyFrom = Offset.zero, _flyTo = Offset.zero;
  int _pendingDelta = 0; // index change applied when a fly-off finishes

  @override
  void initState() {
    super.initState();
    // 1s tick for the live countdown (cheap; cancelled in dispose).
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _fly =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 260),
          )
          ..addListener(() {
            final t = Curves.easeOut.transform(_fly.value);
            setState(() => _drag = Offset.lerp(_flyFrom, _flyTo, t)!);
          })
          ..addStatusListener((s) {
            if (s != AnimationStatus.completed) return;
            setState(() {
              if (_pendingDelta != 0) {
                final n = widget.chain.length;
                if (n > 0) _index = (_index + _pendingDelta).clamp(0, n - 1);
              }
              _drag = Offset.zero;
              _pendingDelta = 0;
            });
          });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _fly.dispose();
    _api.close();
    super.dispose();
  }

  /// On release: past the threshold (or a flick), fly the focal off-screen then
  /// advance; otherwise spring it back to center.
  void _releaseDrag(List<ChainItem> chain, int idx, double vx) {
    final goNext = (_drag.dx < -90 || vx < -700) && idx < chain.length - 1;
    final goPrev = (_drag.dx > 90 || vx > 700) && idx > 0;
    _flyFrom = _drag;
    if (goNext || goPrev) {
      _pendingDelta = goNext ? 1 : -1;
      _flyTo = Offset((goNext ? -1 : 1) * 460, _drag.dy + 40);
      _fly.duration = const Duration(milliseconds: 220);
    } else {
      _pendingDelta = 0;
      _flyTo = Offset.zero;
      _fly.duration = const Duration(milliseconds: 280);
    }
    _fly.forward(from: 0);
  }

  Future<void> _setDone(String id, bool done) async {
    if (_completing.contains(id)) return;
    setState(() => _completing.add(id));
    try {
      await _api.putJson('/api/assets/$id', {
        'payload_patch': {'status': done ? 'done' : 'pending'},
      });
      bumpData(); // TodayPage re-fetches; timed todos advance, 待安排 stay (struck)
    } catch (_) {
      if (mounted) setState(() => _completing.remove(id));
    }
  }

  void _openCalendar(ChainItem it) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            DayDetailPage(day: DateTime(it.at.year, it.at.month, it.at.day)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final chain = widget.chain;
    final hasChain = chain.isNotEmpty;
    final idx = hasChain ? _index.clamp(0, chain.length - 1) : 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      decoration: BoxDecoration(
        color: _panelBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _panelBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(hasChain ? chain[idx] : null, idx, chain.length),
          if (_open) ...[
            if (hasChain) _deck(eu, chain, idx) else _emptyDeck(),
            _counterRow(),
            if (_noTimeOpen) _noTimeList(eu),
          ],
        ],
      ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────────
  Widget _header(ChainItem? focal, int idx, int total) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(
          children: [
            Expanded(
              child: _open || focal == null
                  ? const Text(
                      '接下来',
                      style: TextStyle(
                        color: _muted40,
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Text(
                      focal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _titleColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${idx + 1} / $total',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            Icon(
              _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 20,
              color: _muted40,
            ),
          ],
        ),
      ),
    );
  }

  // ── deck (Tinder-style card stack) ──────────────────────────────────────────
  Widget _deck(EurekaColors eu, List<ChainItem> chain, int idx) {
    final progress = (_drag.dx.abs() / 130).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      child: SizedBox(
        height: 170,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // the visible stack behind the focal; the next shell rises toward the
            // focal as the focal is dragged away.
            if (idx + 2 < chain.length) _stackShell(2, 0),
            if (idx + 1 < chain.length) _stackShell(1, progress),
            // focal — draggable: follows the finger, tilts, flies off on release.
            Transform.translate(
              offset: _drag,
              child: Transform.rotate(
                angle: _drag.dx / 1500,
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onPanUpdate: (d) {
                    if (_fly.isAnimating) return;
                    setState(() => _drag += d.delta);
                  },
                  onPanEnd: (d) =>
                      _releaseDrag(chain, idx, d.velocity.pixelsPerSecond.dx),
                  child: _focalCard(eu, chain[idx]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A card shell behind the focal (the visible stack). [t] (0→1) rises the
  /// depth-1 shell toward the focal as the focal is dragged away.
  Widget _stackShell(int depth, double t) {
    final scale = (1 - depth * 0.05) + (depth == 1 ? t * 0.05 : 0);
    final dy = depth * 12.0 - (depth == 1 ? t * 12.0 : 0);
    return Positioned(
      top: dy,
      left: 0,
      right: 0,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topCenter,
        child: Opacity(
          opacity: 1 - depth * 0.16,
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF51E2C4A), Color(0xF5141E36)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _focalCard(EurekaColors eu, ChainItem it) {
    final isEvent = it.kind == 'event';
    final dot = domainColor(eu, it.domain);
    return Container(
      height: 154,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF522304E), Color(0xF5162139)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x26FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: dot.withValues(alpha: .6), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEvent ? (it.sub == '事件' ? '事件' : '事件 · ${it.sub}') : '待办',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              Text(
                _hm(it.at),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            it.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _titleColor,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (isEvent) _eventBottom(it) else _todoBottom(it),
        ],
      ),
    );
  }

  Widget _eventBottom(ChainItem it) {
    final start = it.at;
    final end = it.dur != null ? start.add(it.dur!) : start;
    final started = !_now.isBefore(start);
    final total = it.dur?.inSeconds ?? 0;
    final elapsed = _now.difference(start).inSeconds.clamp(0, total);
    final frac = total > 0 ? elapsed / total : 0.0;
    final label = started
        ? (total > 0 ? '进行中 · 还剩 ${fmtCountdown(end.difference(_now))}' : '进行中')
        : '⏳ ${fmtCountdown(start.difference(_now))}后';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _accent,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: started ? frac.toDouble() : 0,
            minHeight: 5,
            backgroundColor: const Color(0x1AFFFFFF),
            valueColor: const AlwaysStoppedAnimation(_accent),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => _openCalendar(it),
            child: const Text(
              '在日历看 ›',
              style: TextStyle(
                color: _accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _todoBottom(ChainItem it) {
    final busy = _completing.contains(it.id);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            it.note ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: busy ? null : () => _setDone(it.id, true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x246F9EFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x666F9EFF)),
            ),
            child: busy
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  )
                : const Text(
                    '完成 ✓',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── counter row + no-time list ──────────────────────────────────────────────
  Widget _counterRow() {
    final n = widget.noTimeTodos.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 14, 12),
      child: Row(
        children: [
          const Spacer(),
          if (n > 0)
            GestureDetector(
              onTap: () => setState(() => _noTimeOpen = !_noTimeOpen),
              child: Row(
                children: [
                  Text(
                    '🕒 无时间待办 $n',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  Icon(
                    _noTimeOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: _muted40,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _noTimeList(EurekaColors eu) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xB3080E1A),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Column(
        children: [
          for (final it in widget.noTimeTodos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: domainColor(
                        eu,
                        it.domain,
                      ).withValues(alpha: it.done ? .4 : 1),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: it.done ? _muted : const Color(0xD0FFFFFF),
                        fontSize: 14,
                        decoration: it.done ? TextDecoration.lineThrough : null,
                        decorationColor: _muted,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _completing.contains(it.id)
                        ? null
                        : () => _setDone(it.id, !it.done),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                        child: _completing.contains(it.id)
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: _accent,
                                ),
                              )
                            : Container(
                                width: 19,
                                height: 19,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: it.done ? _accent : null,
                                  border: Border.all(
                                    color: it.done
                                        ? _accent
                                        : const Color(0x66FFFFFF),
                                  ),
                                ),
                                child: it.done
                                    ? const Icon(
                                        Icons.check,
                                        size: 13,
                                        color: Color(0xFF0B1220),
                                      )
                                    : null,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── empty ───────────────────────────────────────────────────────────────────
  Widget _emptyDeck() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: Column(
        children: [
          Text('🌤️', style: TextStyle(fontSize: 30)),
          SizedBox(height: 8),
          Text(
            '今天还没有日程或待办',
            style: TextStyle(
              color: _titleColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
