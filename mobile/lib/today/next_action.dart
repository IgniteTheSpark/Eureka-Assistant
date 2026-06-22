import 'dart:async';
import 'dart:math' as math;

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
  const NextActionPanel(
      {super.key, required this.chain, required this.noTimeTodos});

  final List<ChainItem> chain;
  final List<ChainItem> noTimeTodos;

  @override
  State<NextActionPanel> createState() => _NextActionPanelState();
}

class _NextActionPanelState extends State<NextActionPanel> {
  final ApiClient _api = ApiClient();
  bool _open = true;
  bool _noTimeOpen = false;
  int _index = 0;
  DateTime _now = DateTime.now();
  Timer? _tick;
  final Set<String> _completing = {}; // ids mid-PUT (avoid double-tap)

  @override
  void initState() {
    super.initState();
    // 1s tick for the live countdown (cheap; cancelled in dispose).
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _api.close();
    super.dispose();
  }

  Future<void> _toggleDone(String id) async {
    if (_completing.contains(id)) return;
    setState(() => _completing.add(id));
    try {
      await _api.putJson('/api/assets/$id', {
        'payload_patch': {'status': 'done'},
      });
      bumpData(); // TodayPage re-fetches → completed todo drops out
    } catch (_) {
      if (mounted) setState(() => _completing.remove(id));
    }
  }

  void _openCalendar(ChainItem it) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          DayDetailPage(day: DateTime(it.at.year, it.at.month, it.at.day)),
    ));
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
            if (hasChain)
              _deck(eu, chain, idx)
            else
              _emptyDeck(),
            _counterRow(eu, chain.length),
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
                  ? const Text('接下来',
                      style: TextStyle(
                        color: _muted40,
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w600,
                      ))
                  : Text(focal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _titleColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('${idx + 1} / $total',
                    style: const TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ),
            Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 20, color: _muted40),
          ],
        ),
      ),
    );
  }

  // ── deck (C-fan) ────────────────────────────────────────────────────────────
  Widget _deck(EurekaColors eu, List<ChainItem> chain, int idx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: SizedBox(
        height: 162,
        child: GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -120 && idx < chain.length - 1) {
              setState(() => _index = idx + 1);
            } else if (v > 120 && idx > 0) {
              setState(() => _index = idx - 1);
            }
          },
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              if (chain.length > idx + 2) _peek(1.5, 0.86, 14),
              if (chain.length > idx + 1) _peek(-2.2, 0.92, 8),
              _focalCard(eu, chain[idx]),
            ],
          ),
        ),
      ),
    );
  }

  /// A faint rotated card shell behind the focal one (depth illusion).
  Widget _peek(double deg, double scale, double topInset) {
    return Positioned(
      top: topInset,
      left: 18,
      right: 18,
      child: Transform.rotate(
        angle: deg * math.pi / 180,
        child: Opacity(
          opacity: 0.5,
          child: Container(
            height: 110,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF522304E), Color(0xF5162139)],
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
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
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
                offset: Offset(0, 14)),
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
                    isEvent
                        ? (it.sub == '事件' ? '事件' : '事件 · ${it.sub}')
                        : '待办',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                Text(_hm(it.at),
                    style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ),
            const SizedBox(height: 8),
            Text(it.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: _titleColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (isEvent) _eventBottom(it) else _todoBottom(it),
          ],
        ),
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
        Text(label,
            style: const TextStyle(
                color: _accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()])),
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
        Row(
          children: [
            const Text('🔔 到点提醒你',
                style: TextStyle(color: _muted, fontSize: 11)),
            const Spacer(),
            GestureDetector(
              onTap: () => _openCalendar(it),
              child: const Text('在日历看 ›',
                  style: TextStyle(
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
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
          child: Text(it.note ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: busy ? null : () => _toggleDone(it.id),
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
                        strokeWidth: 2, color: _accent))
                : const Text('完成 ✓',
                    style: TextStyle(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  // ── counter row + no-time list ──────────────────────────────────────────────
  Widget _counterRow(EurekaColors eu, int chainLen) {
    final n = widget.noTimeTodos.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 14, 12),
      child: Row(
        children: [
          if (chainLen > 1)
            const Text('左右滑切换',
                style: TextStyle(color: _muted40, fontSize: 11)),
          const Spacer(),
          if (n > 0)
            GestureDetector(
              onTap: () => setState(() => _noTimeOpen = !_noTimeOpen),
              child: Row(
                children: [
                  Text('🕒 无时间待办 $n',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  Icon(
                      _noTimeOpen
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: _muted40),
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
                        color: domainColor(eu, it.domain),
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xD0FFFFFF), fontSize: 14)),
                  ),
                  GestureDetector(
                    onTap: _completing.contains(it.id)
                        ? null
                        : () => _toggleDone(it.id),
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x66FFFFFF)),
                      ),
                      child: _completing.contains(it.id)
                          ? const Padding(
                              padding: EdgeInsets.all(3),
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: _accent))
                          : null,
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
          Text('今天还没有日程或待办',
              style: TextStyle(
                  color: _titleColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('新的一天 —— 说一句话，Reka 就能帮你记下安排',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
