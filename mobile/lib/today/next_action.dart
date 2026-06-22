import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/asset_detail_sheet.dart' show showAssetDetail;
import '../render/render_spec.dart' show RenderSpec, buildCard, synthesizeSpec;
import '../render/skill_card.dart' show SkillCard, renderSpecsProvider;
import '../theme/app_theme.dart'; // context.eu
import '../theme/domains.dart' show domainColor;
import '../theme/eureka_colors.dart';
import 'today_data.dart';
import 'today_palette.dart';

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

/// Part 1 — the swipeable stack of upcoming timed actions + the no-time todo
/// list. Floats (frosted) over the bubble pool. Tokens = prototype "Next Action
/// panel"; logic = §4.5.0. [chain] is upcoming-timed (sorted), [noTimeTodos] the
/// no-clock todos. Both come from [loadToday]; completing/advancing calls
/// [bumpData] so TodayPage re-fetches.
class NextActionPanel extends ConsumerStatefulWidget {
  const NextActionPanel({
    super.key,
    required this.chain,
    required this.noTimeTodos,
  });

  final List<ChainItem> chain;
  final List<ChainItem> noTimeTodos;

  @override
  ConsumerState<NextActionPanel> createState() => _NextActionPanelState();
}

class _NextActionPanelState extends ConsumerState<NextActionPanel>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = ApiClient();
  bool _open = true;
  bool _noTimeOpen = false;
  int _index = 0;
  final Set<String> _completing = {}; // ids mid-PUT (avoid double-tap)

  // Tinder-style swipe on the focal card.
  Offset _drag = Offset.zero;
  late final AnimationController _fly;
  Offset _flyFrom = Offset.zero, _flyTo = Offset.zero;
  int _pendingDelta = 0; // index change applied when a fly-off finishes
  late TodayPalette _p; // light/dark token set, refreshed each build

  @override
  void initState() {
    super.initState();
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
                // allow n = the end card (one past the last); 0 = first.
                if (n > 0) _index = (_index + _pendingDelta).clamp(0, n);
              }
              _drag = Offset.zero;
              _pendingDelta = 0;
            });
          });
  }

  @override
  void dispose() {
    _fly.dispose();
    _api.close();
    super.dispose();
  }

  /// On release: past the threshold (or a flick), fly the focal off-screen then
  /// advance; otherwise spring it back to center.
  void _releaseDrag(List<ChainItem> chain, int idx, double vx) {
    // allow reaching idx == chain.length (the 暂时没有了 end card); swipe back returns.
    final goNext = (_drag.dx < -90 || vx < -700) && idx < chain.length;
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

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    _p = TodayPalette.of(context);
    final chain = widget.chain;
    final hasChain = chain.isNotEmpty;
    // idx can reach chain.length = the "暂时没有了" end card (one past the last).
    final idx = hasChain ? _index.clamp(0, chain.length) : 0;
    final atEnd = idx >= chain.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      decoration: BoxDecoration(
        color: _p.panelBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _p.panelBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(
            atEnd ? null : (hasChain ? chain[idx] : null),
            idx,
            chain.length,
          ),
          if (_open) ...[
            if (hasChain) _deck(chain, idx) else _emptyDeck(),
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
                  ? Text(
                      '接下来',
                      style: TextStyle(
                        color: _p.faint,
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Text(
                      focal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _p.title,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  idx >= total ? '$total / $total' : '${idx + 1} / $total',
                  style: TextStyle(
                    color: _p.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            Icon(
              _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 20,
              color: _p.faint,
            ),
          ],
        ),
      ),
    );
  }

  // ── deck (Tinder-style card stack) ──────────────────────────────────────────
  Widget _deck(List<ChainItem> chain, int idx) {
    final progress = (_drag.dx.abs() / 130).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: SizedBox(
        height: 108,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // the visible stack behind the focal; the next shell rises toward the
            // focal as the focal is dragged away.
            if (idx + 2 < chain.length) _stackShell(2, 0),
            if (idx + 1 < chain.length) _stackShell(1, progress),
            // focal — draggable: follows the finger, tilts, flies off on release.
            // Tap → the global detail sheet; swipe → cycle.
            Transform.translate(
              offset: _drag,
              child: Transform.rotate(
                angle: _drag.dx / 1500,
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: idx < chain.length
                      ? () => _openDetail(chain[idx])
                      : null,
                  onPanUpdate: (d) {
                    if (_fly.isAnimating) return;
                    setState(() => _drag += d.delta);
                  },
                  onPanEnd: (d) =>
                      _releaseDrag(chain, idx, d.velocity.pixelsPerSecond.dx),
                  child: idx < chain.length
                      ? _focalCard(chain[idx])
                      : _endCard(),
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
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_p.shellTop, _p.shellBottom],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _p.panelBorder),
            ),
          ),
        ),
      ),
    );
  }

  /// The focal card = the **same global unified card** as 资产库 / 日历
  /// (SkillCard, 'horizontal'). Wrapped in IgnorePointer so its own tap /
  /// checkbox / swipe-to-delete don't fight the deck's drag-to-cycle; the deck
  /// owns tap (→ detail) + swipe itself.
  Widget _focalCard(ChainItem it) {
    return SizedBox(
      width: double.infinity,
      child: IgnorePointer(
        child: SkillCard(it.card, layoutOverride: 'horizontal'),
      ),
    );
  }

  /// Open the same detail sheet a SkillCard tap opens: resolve the skill spec
  /// from the registry (entities use a synthesized spec), then showAssetDetail.
  void _openDetail(ChainItem it) {
    final specs =
        ref.read(renderSpecsProvider).valueOrNull ??
        const <String, RenderSpec>{};
    final card = it.card;
    final type = card['card_type'] as String?;
    final isEntity = type == 'event' || type == 'contact' || type == 'task';
    final payload = isEntity
        ? card
        : ((card['payload'] as Map?)?.cast<String, dynamic>() ?? const {});
    final cardType = type ?? (card['user_skill_name'] as String?) ?? 'asset';
    final skill = card['user_skill_name'] as String?;
    final spec = skill != null ? specs[skill] : null;
    var data = isEntity
        ? buildCard(
            payload: card,
            spec: synthesizeSpec(type!),
            displayName: type,
          )
        : buildCard(payload: payload, spec: spec, displayName: cardType);
    data = data.copyWith(domain: card['domain'] as String?);
    showAssetDetail(
      context,
      data: data,
      payload: payload,
      cardType: cardType,
      assetId: (card['asset_id'] ?? card['id']) as String?,
      sessionId: card['session_id'] as String?,
      spec: spec,
    );
  }

  /// Past-the-last end state. Swipe right returns to the last card; the ↺ pill
  /// restarts at the first.
  Widget _endCard() {
    return Container(
      height: 154,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_p.cardTop, _p.cardBottom],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _p.cardBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text(
            '暂时没有了',
            style: TextStyle(
              color: _p.title,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() {
              _index = 0;
              _drag = Offset.zero;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _p.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _p.accent.withValues(alpha: 0.42)),
              ),
              child: Text(
                '↺ 回到开头',
                style: TextStyle(
                  color: _p.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
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
                    style: TextStyle(color: _p.muted, fontSize: 12),
                  ),
                  Icon(
                    _noTimeOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: _p.faint,
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
        color: _p.inset,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _p.panelBorder),
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
                        color: it.done ? _p.muted : _p.body,
                        fontSize: 14,
                        decoration: it.done ? TextDecoration.lineThrough : null,
                        decorationColor: _p.muted,
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
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: _p.accent,
                                ),
                              )
                            : Container(
                                width: 19,
                                height: 19,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: it.done ? _p.accent : null,
                                  border: Border.all(
                                    color: it.done ? _p.accent : _p.faint,
                                  ),
                                ),
                                child: it.done
                                    ? Icon(
                                        Icons.check,
                                        size: 13,
                                        color: _p.onAccent,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      child: Column(
        children: [
          const Text('🌤️', style: TextStyle(fontSize: 30)),
          SizedBox(height: 8),
          Text(
            '今天还没有日程或待办',
            style: TextStyle(
              color: _p.title,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
