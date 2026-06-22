import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/asset_detail_sheet.dart';
import '../render/day_render.dart';
import '../render/render_spec.dart';
import '../theme/app_theme.dart';
import '../theme/domains.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';
import 'create_asset.dart';
import 'day_flash_view.dart';
import 'session_detail_page.dart';

/// Open a flash capture's session as a read-only replay (web parity: tapping a
/// ⚡ row opens the capture session). No-op when the item has no session.
void _openFlashSession(BuildContext context, TimelineItem item) {
  final sid = item.sessionId;
  if (sid == null || sid.isEmpty) return;
  final d = item.effectiveAt;
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => SessionDetailPage(sessionId: sid, title: '${d.month}月${d.day}日 闪念'),
  ));
}

/// Dispatch a tapped timeline item to the right detail surface (web
/// handleItemTap): input_turn → capture session; event/contact/asset → fetch
/// the record and open the shared asset-detail sheet.
Future<void> _openTimelineItem(
    BuildContext context, TimelineItem item, Map<String, SkillMeta> skills) async {
  if (item.kind == 'input_turn') {
    _openFlashSession(context, item);
    return;
  }
  final api = ApiClient();
  try {
    final (String path, String wrapKey) = switch (item.kind) {
      'event' => ('/api/events/${item.id}', 'event'),
      'contact' => ('/api/contacts/${item.id}', 'contact'),
      _ => ('/api/assets/${item.id}', 'asset'),
    };
    final res = await api.getJson(path);
    final raw = res is Map ? (res[wrapKey] ?? res) : res;
    final record = (raw as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final isAsset = item.kind != 'event' && item.kind != 'contact';
    // event/contact PUT flat fields → cardType is the kind; assets carry a
    // payload and are keyed by their skill name (so edit/delete route to /api/assets).
    final cardType = isAsset ? (item.skillName ?? 'misc') : item.kind;
    // Pull the skill's render_spec (field labels + full schema) so the detail
    // sheet + editor show 中文 labels and every field — not English fallbacks /
    // only-the-present-fields (the timeline path used to pass no spec).
    RenderSpec? spec;
    if (isAsset) {
      try {
        spec = (await fetchRenderSpecs(api))[cardType];
      } catch (_) {/* fall back to label dict */}
    }
    if (!context.mounted) return;

    final payload = isAsset
        ? ((record['payload'] as Map?)?.cast<String, dynamic>() ?? const {})
        : record;
    final assetId =
        (record['${item.kind}_id'] ?? record['id'] ?? item.id) as String?;
    showAssetDetail(
      context,
      // carry the asset's domain so the hero shows the 领域 chip (was empty).
      data: _timelineCardData(item, skills).copyWith(domain: record['domain'] as String?),
      payload: payload,
      cardType: cardType,
      assetId: assetId,
      sessionId: (record['session_id'] as String?) ?? item.sessionId,
      spec: spec,
    );
  } catch (_) {
    // Couldn't load the record — fall back to its source session if any.
    if (context.mounted && (item.sessionId?.isNotEmpty ?? false)) {
      _openFlashSession(context, item);
    }
  } finally {
    api.close();
  }
}

/// Minimal CardData for the detail-sheet hero, from the timeline item's
/// backend-computed title/subtitle + the kind's icon/accent.
CardData _timelineCardData(TimelineItem item, Map<String, SkillMeta> skills) {
  final String icon;
  final String accent;
  switch (item.kind) {
    case 'event':
      icon = '📅';
      accent = 'purple';
    case 'contact':
      icon = '👤';
      accent = 'neutral';
    default:
      final m = resolveMeta(item.skillName ?? 'misc', skills);
      icon = m.icon;
      accent = m.accentColor;
  }
  return CardData(
    layout: 'horizontal',
    icon: icon,
    accentColor: accent,
    title: item.title.isEmpty ? '记录' : item.title,
    subtitle: item.subtitle,
    metaFields: const [],
  );
}

/// Calendar surface with a 流 / 月 / 年 segmented control over GET /api/timeline.
/// 流 = schedule list (flash captures render as ⚡ + derived breakdown);
/// 月 = dot grid + selected-day list; 年 = 12-month grid.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalData {
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final Map<DateTime, List<TimelineItem>> byDay;
  _CalData(this.items, this.skills) : byDay = _bucket(items);

  static Map<DateTime, List<TimelineItem>> _bucket(List<TimelineItem> items) {
    final m = <DateTime, List<TimelineItem>>{};
    for (final it in items) {
      final d = DateTime(it.effectiveAt.year, it.effectiveAt.month, it.effectiveAt.day);
      m.putIfAbsent(d, () => []).add(it);
    }
    for (final v in m.values) {
      v.sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));
    }
    return m;
  }
}

/// Bumped by the shell when the 今天 tab is (re)selected → the calendar resets
/// to 流(timeline) and the stream jumps to today (默认「流 · 今天」).
final ValueNotifier<int> calendarHome = ValueNotifier<int>(0);

class _CalendarPageState extends State<CalendarPage> {
  final _api = ApiClient();
  // Revision-keyed fetch (see LibraryPage): build() re-subscribes to
  // `dataRevision` so a data change always re-fetches, and it survives
  // hot-reload (no initState-registered listener to miss).
  int _loadedRev = -1;
  Future<_CalData>? _future;
  _CalData? _lastData; // keep last data on screen during a refetch (no spinner flash)

  Future<_CalData> _futureFor(int rev) {
    if (rev != _loadedRev || _future == null) {
      _loadedRev = rev;
      _future = _load();
    }
    return _future!;
  }

  // START_CAL_MODE lets a build boot into a specific calendar mode for
  // screenshot/visual verification (timeline | month | year). Default = 流
  // (timeline · 今天) — the home view (产品决策 2026-06).
  String _mode = const String.fromEnvironment('START_CAL_MODE', defaultValue: 'timeline');
  late DateTime _focusMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // 流/月/年 are swipeable (PageView) + tappable (segmented), kept in sync.
  static const _modes = ['timeline', 'month', 'year'];
  int get _modeIndex => _modes.indexOf(_mode).clamp(0, 2);
  late final PageController _pager = PageController(initialPage: _modeIndex);

  void _switchMode(String m, {bool animate = true}) {
    if (m == _mode && !animate) return;
    setState(() => _mode = m);
    final i = _modes.indexOf(m);
    if (i >= 0 && _pager.hasClients && animate) {
      _pager.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    }
  }

  Future<_CalData> _load() async {
    final r = await Future.wait([fetchTimeline(_api), fetchSkills(_api)]);
    return _CalData(r[0] as List<TimelineItem>, r[1] as Map<String, SkillMeta>);
  }

  void _refresh() => bumpData(); // global bump → revision changes → re-fetch

  @override
  void initState() {
    super.initState();
    calendarHome.addListener(_goHome); // 今天 tab tapped → reset to 流
  }

  void _goHome() {
    if (mounted) _switchMode('timeline'); // the stream itself jumps to today
  }

  @override
  void dispose() {
    calendarHome.removeListener(_goHome);
    _pager.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
              child: SizedBox(
                height: 44,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: _Segmented(
                        value: _mode,
                        // Selecting 流 re-centers on today (bump calendarHome →
                        // _goHome switches mode + the stream jumps to today). 月/年
                        // just switch. Fixes 流 staying scrolled where it was left.
                        onChanged: (v) => v == 'timeline' ? calendarHome.value++ : _switchMode(v),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                          onPressed: _refresh,
                          tooltip: '刷新',
                          icon: Icon(Icons.refresh, color: eu.textMid)),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: dataRevision,
                builder: (context, rev, _) => FutureBuilder<_CalData>(
                future: _futureFor(rev),
                builder: (ctx, snap) {
                  if (snap.hasData) _lastData = snap.data;
                  final data = _lastData;
                  // First load only: spinner / error. On refetch we keep the
                  // PageView mounted with the last data — no spinner flash, and
                  // the PageController never detaches (so 流/月/年 never desyncs
                  // from the segmented control).
                  if (data == null) {
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('加载失败：${snap.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: eu.accentRed)),
                        ),
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Swipeable 流/月/年 (synced with the segmented control).
                  return PageView(
                    controller: _pager,
                    onPageChanged: (i) => setState(() => _mode = _modes[i]),
                    children: [
                      _TimelineView(data: data),
                      _MonthView(
                        focusMonth: _focusMonth,
                        byDay: data.byDay,
                        skills: data.skills,
                      ),
                      _YearView(
                        year: _focusMonth.year,
                        byDay: data.byDay,
                        onPickMonth: (m) {
                          setState(() => _focusMonth = m);
                          _switchMode('month');
                        },
                      ),
                    ],
                  );
                },
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ── 流 / 月 / 年 segmented control ──────────────────────────────────────── */

class _Segmented extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _Segmented({required this.value, required this.onChanged});

  static const _opts = [('timeline', '流'), ('month', '月'), ('year', '年')];

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in _opts)
            GestureDetector(
              onTap: () => onChanged(o.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: value == o.$1 ? eu.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(o.$2,
                    style: TextStyle(
                        color: value == o.$1 ? Colors.white : eu.textMid,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

/* ── 流 timeline ────────────────────────────────────────────────────────── */

/// One day in the 流 stream. Every day renders a row (Timepage-style continuous
/// flow — no collapsing): days with items get a tile, empty days a slim rail row.
class _DayR {
  final DateTime day;
  // First row of its month → the rail shows the vertical "YYYY 年 X 月" anchor.
  final bool monthBoundary;
  const _DayR(this.day, {this.monthBoundary = false});
}

/// 流 — a continuous, infinitely-scrollable day stream (Timepage style).
/// A CustomScrollView centered on today: scroll up for the past, down for the
/// future. The forward window grows as you near the bottom, so it never ends.
/// Empty stretches collapse into a thin separator so the stream stays scannable.
class _TimelineView extends StatefulWidget {
  final _CalData data;
  const _TimelineView({required this.data});

  @override
  State<_TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<_TimelineView> {
  final _scroll = ScrollController();
  // Per-day keys so the scroll handler can find which day sits at the viewport
  // center (the floating distance watermark) and whether today is on-screen.
  final Map<String, GlobalKey> _dayKeys = {};
  int _fwdDays = 90;
  // Small initial past window so the mount-time jump to today is accurate (few
  // rows to estimate); it grows on scroll-up (_growPast) for endless history.
  int _pastDays = 14;
  bool _growingPast = false;

  // §流:有内容的日 → 点(date / 空白)开全屏日视图(`_openDay`)。
  void _openDay(DateTime d) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DayDetailPage(day: d)));

  DateTime _today = _d(DateTime.now());
  // Overlay watermark + 回今天 button as notifiers: the per-scroll _updateOverlay
  // updates ONLY these layers (ValueListenableBuilder) instead of setState-
  // rebuilding (and repainting every band gradient) the whole timeline per frame.
  final _overlay = ValueNotifier<({String? text, bool visible})>((text: null, visible: false));
  final _todayInView = ValueNotifier<bool>(true);
  Timer? _fadeTimer;
  Timer? _overlayThrottle; // coalesce the O(rows) render-object scan to ~10fps

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);
  static String _dayStr(DateTime d) => '${d.year}-${d.month}-${d.day}';
  GlobalKey _keyFor(DateTime d) => _dayKeys.putIfAbsent(_dayStr(d), () => GlobalKey());

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    calendarHome.addListener(_onHome); // 今天 tab tapped → scroll to today
  }

  void _onHome() {
    // Don't gate on hasClients — switching to 流 from 月/年 mode (or another tab)
    // can fire this before the timeline lays out; _jumpToToday self-retries until
    // the scroll attaches. (Gating here meant the jump was silently dropped.)
    if (mounted) _jumpToToday();
  }

  @override
  void dispose() {
    calendarHome.removeListener(_onHome);
    _fadeTimer?.cancel();
    _overlayThrottle?.cancel();
    _overlay.dispose();
    _todayInView.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = _scroll.position;
    // Grow the forward window near the bottom → endless scroll.
    if (p.maxScrollExtent - p.pixels < 800 && _fwdDays < 3650) {
      setState(() => _fwdDays += 90);
    }
    // Grow the past window near the top → endless scroll up. Prepending rows
    // shifts content down, so compensate the offset to keep the view steady.
    if (_didScroll && !_growingPast && _pastDays < 3650 && p.pixels - p.minScrollExtent < 600) {
      _growPast();
    }
    // Throttle the overlay scan (O(rows) render-object queries) to ~10fps —
    // running it every scroll frame + setState was the main 流 jank.
    _overlayThrottle ??= Timer(const Duration(milliseconds: 100), () {
      _overlayThrottle = null;
      if (mounted) _updateOverlay();
    });
  }

  void _growPast() {
    _growingPast = true;
    const add = 90;
    final oldMin = _today.subtract(Duration(days: _pastDays));
    var addedH = 0.0;
    for (var i = 1; i <= add; i++) {
      final d = oldMin.subtract(Duration(days: i));
      final items = widget.data.byDay[DateTime(d.year, d.month, d.day)] ?? const [];
      addedH += (items.isEmpty ? 72 : 24 + items.length * 30 + (items.length - 1) * 8) + 8;
    }
    final px = _scroll.position.pixels;
    setState(() => _pastDays += add);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo((px + addedH).clamp(0.0, _scroll.position.maxScrollExtent));
      }
      _growingPast = false;
    });
  }

  // Floating distance watermark (A) + jump-to-today visibility (E): find the
  // day-row whose mid-point is nearest the viewport center.
  void _updateOverlay() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final viewH = box.size.height;
    final center = viewH / 2;

    String? bestStr;
    double best = double.infinity;
    _dayKeys.forEach((str, key) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final rb = ctx.findRenderObject() as RenderBox?;
      if (rb == null || !rb.attached) return;
      final dy = rb.localToGlobal(Offset.zero, ancestor: box).dy;
      final mid = dy + rb.size.height / 2;
      final dist = (mid - center).abs();
      if (dist < best) {
        best = dist;
        bestStr = str;
      }
    });

    var todayIn = false;
    final tctx = _dayKeys[_dayStr(_today)]?.currentContext;
    if (tctx != null) {
      final rb = tctx.findRenderObject() as RenderBox?;
      if (rb != null && rb.attached) {
        final dy = rb.localToGlobal(Offset.zero, ancestor: box).dy;
        todayIn = dy + rb.size.height > 0 && dy < viewH;
      }
    }

    final label = bestStr != null ? _distanceLabel(_parse(bestStr!)) : _overlay.value.text;
    // Notifier writes → only the watermark / button layers rebuild, not the list.
    _overlay.value = (text: label, visible: true);
    _todayInView.value = todayIn;
    _fadeTimer?.cancel();
    _fadeTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted) _overlay.value = (text: _overlay.value.text, visible: false);
    });
  }

  bool _didScroll = false;
  List<_DayR> _rows = const [];

  // Estimated pixel height per row — used to jump to today on mount without
  // relying on lazy-built GlobalKey contexts.
  double _estRowHeight(_DayR r) {
    final all = widget.data.byDay[r.day] ?? const <TimelineItem>[];
    // Flash lives in the rail pill, not the band tile — exclude it (matching
    // _BandView) or the estimate runs tall on flash-heavy days and overshoots.
    final items = all.where((i) => i.kind != 'input_turn').toList();
    if (items.isEmpty) return 50;
    // sticky 日头 (~48) + 时段 bands (each: 段头 + wash padding ~34) + rows ~30.
    // Counting bands keeps the seek-to-today estimate honest.
    final bands = <int>{for (final it in items) _bandIndexOf(it)};
    return 48.0 + bands.length * 34 + items.length * 30;
  }

  double _offsetToToday() {
    var off = 0.0;
    for (final r in _rows) {
      if (r.day == _today) break;
      off += _estRowHeight(r);
    }
    return (off - 12).clamp(0.0, double.infinity);
  }

  // Mount-time scroll so today sits near the top (past above, future below).
  // The estimate gets the viewport close; _seekToday then converges exactly.
  void _autoScroll([int tries = 0]) {
    if (_didScroll || !mounted) return;
    // Need an attached position that has reported content dimensions, else
    // maxScrollExtent/jumpTo throw and (since _didScroll would already be set)
    // every retry bails at the guard → silent blank 流. Retry via Future.delayed
    // (event-loop), not a post-frame, so an idle app still advances.
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      if (tries < 40) {
        Future.delayed(const Duration(milliseconds: 32), () => _autoScroll(tries + 1));
      }
      return;
    }
    _scroll.jumpTo(_offsetToToday().clamp(0.0, _scroll.position.maxScrollExtent));
    _didScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _seekToday());
  }

  // Corrective seek — the ESTIMATE-based jump can land ±weeks off: per-row
  // height guesses drift from the rendered truth and the error compounds over
  // hundreds of lazy rows; today's row then sits outside cacheExtent, so a
  // fixed frame-retry "snap" never sees its context and gives up at the bad
  // estimate (the「回到今天落在两周后」bug). Instead of trusting the estimate,
  // MEASURE where we actually landed (nearest laid-out day row — the same
  // logic that powers the「N 周后」watermark, which is always right), step by
  // the remaining day-distance × the measured average row height, and repeat.
  // Each hop shrinks the error; once today's row is really laid out we align
  // it exactly with ensureVisible.
  void _seekToday([int iter = 0]) {
    if (!mounted || !_scroll.hasClients) return;
    final tctx = _dayKeys[_dayStr(_today)]?.currentContext;
    if (tctx != null) {
      Scrollable.ensureVisible(tctx, alignment: 0.06, duration: Duration.zero);
      _todayInView.value = true;
      return;
    }
    if (iter >= 12) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _seekToday(iter + 1));
      return;
    }
    DateTime? nearest;
    var bestDist = double.infinity;
    var sumH = 0.0;
    var nH = 0;
    _dayKeys.forEach((str, key) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final rb = ctx.findRenderObject() as RenderBox?;
      if (rb == null || !rb.attached) return;
      final dy = rb.localToGlobal(Offset.zero, ancestor: box).dy;
      sumH += rb.size.height;
      nH++;
      if (dy.abs() < bestDist) {
        bestDist = dy.abs();
        nearest = _parse(str);
      }
    });
    if (nearest == null || nH == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _seekToday(iter + 1));
      return;
    }
    final deltaDays = _today.difference(nearest!).inDays;
    if (deltaDays != 0) {
      final avgH = sumH / nH + 8; // + inter-row gap
      _scroll.jumpTo((_scroll.position.pixels + deltaDays * avgH)
          .clamp(0.0, _scroll.position.maxScrollExtent));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _seekToday(iter + 1));
  }

  void _jumpToToday([int tries = 0]) {
    // The scroll may not be attached yet (switching to 流 from another mode/tab
    // before the page lays out) — retry a few frames.
    if (!_scroll.hasClients) {
      if (tries < 8) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday(tries + 1));
      return;
    }
    // Animate toward the estimate (feels intentional), then converge exactly
    // with the measuring seek — works no matter how far off the estimate is.
    _scroll
        .animateTo(
          _offsetToToday().clamp(0.0, _scroll.position.maxScrollExtent),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
      if (mounted) _seekToday();
    });
  }

  DateTime _parse(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  String _distanceLabel(DateTime day) {
    final days = day.difference(_today).inDays;
    if (days == 0) return '今天';
    if (days == 1) return '明天';
    if (days == -1) return '昨天';
    final abs = days.abs();
    final suffix = days > 0 ? '后' : '前';
    if (abs < 7) return '$abs 天$suffix';
    if (abs < 28) return '${(abs / 7).round()} 周$suffix';
    if (abs < 365) return '${(abs / 30).round()} 月$suffix';
    return '${(abs / 365).round()} 年$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    if (widget.data.items.isEmpty) {
      return Center(child: Text('还没有内容', style: TextStyle(color: eu.textMid)));
    }
    final byDay = widget.data.byDay;
    _today = _d(DateTime.now());
    final today = _today;

    // Window: _pastDays before today (grows on scroll-up, or back to the
    // earliest item) … today + _fwdDays forward (grows on scroll-down). Every
    // day in the window renders a row (continuous Timepage flow).
    var pastN = _pastDays;
    for (final dd in byDay.keys) {
      final diff = today.difference(dd).inDays;
      if (diff > pastN && diff <= 3650) pastN = diff;
    }
    final minD = today.subtract(Duration(days: pastN));
    final maxD = today.add(Duration(days: _fwdDays));
    final allDays = <DateTime>[
      for (var d = minD; !d.isAfter(maxD); d = d.add(const Duration(days: 1))) d,
    ];

    final rows = _buildRows(allDays);
    _rows = rows;
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScroll());

    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(top: 6, right: 16, bottom: 100),
          itemCount: rows.length,
          // RepaintBoundary isolates each day's repaint (band gradients) so a row
          // never drags its neighbours into a repaint during scroll.
          itemBuilder: (_, i) => RepaintBoundary(child: _rowWidget(rows[i])),
        ),
        // A — floating distance watermark; the notifier rebuilds ONLY this layer.
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<({String? text, bool visible})>(
              valueListenable: _overlay,
              builder: (_, ov, _) => ov.text == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: const Alignment(0.95, -0.12),
                      child: AnimatedOpacity(
                        opacity: ov.visible ? 0.16 : 0.0,
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          ov.text!,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 60,
                            height: 0.9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.5,
                            color: eu.textHi,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        // E — 跳回今天 button, only when today is off-screen (notifier-driven).
        Positioned(
          bottom: 104,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: _todayInView,
            builder: (_, inView, _) => inView
                ? const SizedBox.shrink()
                : Center(
                    child: GestureDetector(
                      onTap: _jumpToToday,
                      child: Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: eu.surfaceRaised,
                          border: Border.all(color: eu.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(Icons.today_outlined, size: 20, color: eu.textHi),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _rowWidget(_DayR r) {
    final items = widget.data.byDay[r.day] ?? const <TimelineItem>[];
    final key = _keyFor(r.day);
    if (items.isEmpty) {
      return _EmptyDayRow(key: key, day: r.day, monthBoundary: r.monthBoundary);
    }
    return _DayRow(
      key: key,
      day: r.day,
      items: items,
      skills: widget.data.skills,
      monthBoundary: r.monthBoundary,
      onOpen: () => _openDay(r.day),
      scroll: _scroll,
    );
  }

  /// One row per day (Timepage continuous flow — no collapsing). Marks the
  /// first row of each month so the rail can anchor the vertical month label.
  List<_DayR> _buildRows(List<DateTime> days) {
    final rows = <_DayR>[];
    String? lastMonthKey;
    for (final d in days) {
      final mk = '${d.year}-${d.month}';
      rows.add(_DayR(d, monthBoundary: mk != lastMonthKey));
      lastMonthKey = mk;
    }
    return rows;
  }
}

/// Vertical year/month anchor on the rail's LEFT edge at a month boundary,
/// reading bottom-to-top like Timepage's「JULY 2019」. Brand + glow for the
/// current month. Sits on the left so it never collides with the right-aligned
/// weekday/date.
Widget _railMonthLabel(EurekaColors eu, DateTime day) {
  final now = DateTime.now();
  final isCurrent = day.year == now.year && day.month == now.month;
  final fg = isCurrent ? eu.brand : eu.textLo.withValues(alpha: 0.7);
  return IgnorePointer(
    child: Center(
      child: RotatedBox(
        quarterTurns: 3,
        child: Text(
          '${day.year} 年 ${day.month} 月',
          style: euMono(fontSize: 8.5, letterSpacing: 1.4, color: fg).copyWith(
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            shadows: isCurrent
                ? [Shadow(color: eu.brand.withValues(alpha: 0.4), blurRadius: 8)]
                : null,
          ),
        ),
      ),
    ),
  );
}

class _EmptyDayRow extends StatefulWidget {
  final DateTime day;
  final bool monthBoundary;
  const _EmptyDayRow({
    super.key,
    required this.day,
    this.monthBoundary = false,
  });

  @override
  State<_EmptyDayRow> createState() => _EmptyDayRowState();
}

class _EmptyDayRowState extends State<_EmptyDayRow> {
  // 空日:第一次点 → 框内露出引导语;点引导语才弹创建 sheet(不一点就弹)。
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final isToday = widget.day == DateTime(now.year, now.month, now.day);
    const wd = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    final fg = isToday ? eu.brand : eu.textLo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 60,
              child: Padding(
                padding: const EdgeInsets.only(left: 4, top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(wd[widget.day.weekday % 7],
                        style: euMono(
                            fontSize: 9,
                            letterSpacing: 1.2,
                            color: fg.withValues(alpha: 0.8))),
                    Text('${widget.day.day}',
                        style: TextStyle(
                            fontSize: 23,
                            height: 1.05,
                            fontWeight: FontWeight.w600,
                            color: fg)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _revealed
                    ? () => showCreateMenu(context, presetDate: widget.day)
                    : () => setState(() => _revealed = true),
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: _revealed
                        ? eu.brand.withValues(alpha: 0.06)
                        : eu.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _revealed
                            ? eu.brand.withValues(alpha: 0.4)
                            : eu.border),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(
                              alpha: eu.brightness == Brightness.dark
                                  ? 0.18
                                  : 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _revealed
                      ? Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 15, color: eu.brand),
                              const SizedBox(width: 4),
                              Text('在这天记一笔',
                                  style: TextStyle(
                                      color: eu.brand,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      : CustomPaint(
                          painter: _HatchPainter(
                              eu.textLo.withValues(alpha: 0.10))),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _wdCaps = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

/// Shared rail header: weekday cap + prominent date, today brand-highlighted,
/// + the vertical month anchor at month boundaries + today's accent line. No
/// divider hairline — the day tiles carry the structure (reference design).
Widget railHeader(EurekaColors eu, DateTime day, bool isToday, bool monthBoundary) {
  return Stack(
    children: [
      // Two columns: a fixed 13px strip for the vertical month anchor + the
      // weekday/date column. Keeping them in separate strips means the month
      // label never overlaps the date.
      Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 13,
            child: monthBoundary ? _railMonthLabel(eu, day) : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_wdCaps[day.weekday % 7],
                      style: euMono(
                          fontSize: 10, letterSpacing: 1.5, color: isToday ? eu.brand : eu.textLo)),
                  const SizedBox(height: 2),
                  Text('${day.day}',
                      style: TextStyle(
                        fontSize: isToday ? 26 : 22,
                        height: 1.0,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                        color: isToday ? eu.brand : eu.textHi,
                        shadows: isToday
                            ? [Shadow(color: eu.brand.withValues(alpha: 0.5), blurRadius: 12)]
                            : null,
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
      if (isToday)
        Positioned(
          right: 0,
          top: 10,
          bottom: 10,
          child: Container(
            width: 2,
            decoration: BoxDecoration(
              color: eu.brand,
              boxShadow: [BoxShadow(color: eu.brand.withValues(alpha: 0.6), blurRadius: 8)],
            ),
          ),
        ),
    ],
  );
}

/// Faint rounded card used for every day tile (empty + content), so the stream
/// reads as a column of uniform cards (reference design).
BoxDecoration dayTileDecoration(EurekaColors eu) => BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(eu.brand.withValues(alpha: 0.08), eu.surfaceRaised),
          eu.surfaceRaised,
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: eu.border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: eu.brightness == Brightness.dark ? 0.22 : 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

/* ── 月 continuous month scroll + pinned selected-day footer ─────────────── */

/// Month surface: a continuous vertical scroll of 13 months (focus −6 … +6),
/// auto-scrolling to the focus month, with a pinned footer showing the
/// selected day's items. Mirrors the web MonthPane.
class _MonthView extends StatefulWidget {
  final DateTime focusMonth;
  final Map<DateTime, List<TimelineItem>> byDay;
  final Map<String, SkillMeta> skills;
  const _MonthView({required this.focusMonth, required this.byDay, required this.skills});

  @override
  State<_MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<_MonthView> {
  // Show ONE month (the date grid was eating the screen as a 13-month scroll);
  // prev/next switch it, and the 年视图 still drives it via focusMonth.
  late DateTime _displayMonth = DateTime(widget.focusMonth.year, widget.focusMonth.month);
  late DateTime _selected = _dayOnly(DateTime.now());

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void didUpdateWidget(_MonthView old) {
    super.didUpdateWidget(old);
    if (widget.focusMonth != old.focusMonth) {
      _displayMonth = DateTime(widget.focusMonth.year, widget.focusMonth.month);
    }
  }

  void _shiftMonth(int delta) => setState(
      () => _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + delta));

  void _openDay(DateTime d) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DayDetailPage(day: d),
    ));
  }

  // First tap selects the day (footer updates); tapping the already-selected
  // day opens the full day view — mirrors the web MonthPane (tap-again → DayDetail).
  void _onDayTap(DateTime d) {
    if (d.year == _selected.year && d.month == _selected.month && d.day == _selected.day) {
      _openDay(d);
    } else {
      setState(() => _selected = d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selItems = widget.byDay[_selected] ?? const <TimelineItem>[];
    return Column(
      children: [
        _monthSwitcher(context),
        _MonthBlock(
          month: _displayMonth,
          byDay: widget.byDay,
          selected: _selected,
          onSelect: _onDayTap,
        ),
        // Footer fills the rest → the content area is now the bigger half.
        Expanded(
          child: _SelectedDayFooter(
            day: _selected,
            items: selItems,
            skills: widget.skills,
            onOpenDay: () => _openDay(_selected),
          ),
        ),
      ],
    );
  }

  // ‹ 2026年6月 › — arrows switch the single displayed month; tap the label to
  // jump back to the current month. (年视图 selecting a month also drives this.)
  Widget _monthSwitcher(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final isCur = _displayMonth.year == now.year && _displayMonth.month == now.month;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      child: Row(
        children: [
          _arrow(eu, Icons.chevron_left, () => _shiftMonth(-1)),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isCur
                  ? null
                  : () => setState(() => _displayMonth = DateTime(now.year, now.month)),
              child: Center(
                child: Text('${_displayMonth.year}年${_displayMonth.month}月',
                    style: TextStyle(
                        color: isCur ? eu.brand : eu.textHi,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          _arrow(eu, Icons.chevron_right, () => _shiftMonth(1)),
        ],
      ),
    );
  }

  Widget _arrow(EurekaColors eu, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 22, color: eu.textMid),
        ),
      );
}

class _MonthBlock extends StatelessWidget {
  final DateTime month; // first of month
  final Map<DateTime, List<TimelineItem>> byDay;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _MonthBlock({
    required this.month,
    required this.byDay,
    required this.selected,
    required this.onSelect,
  });

  static const _wd = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    // 42 cells from the Sunday on/before the 1st.
    final first = DateTime(month.year, month.month, 1);
    final start = first.subtract(Duration(days: first.weekday % 7));
    final cells = [for (var i = 0; i < 42; i++) start.add(Duration(days: i))];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final w in _wd)
                Expanded(
                  child: Center(
                    child: Text(w,
                        style: euMono(fontSize: 9.5, letterSpacing: 1.4, color: eu.textLo)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            childAspectRatio: 1.2,
            children: [
              for (final d in cells)
                _MonthCell(
                  day: d,
                  inMonth: d.month == month.month,
                  kind: _kind(byDay[DateTime(d.year, d.month, d.day)]),
                  isToday: d.year == now.year && d.month == now.month && d.day == now.day,
                  isSelected: d.year == selected.year &&
                      d.month == selected.month &&
                      d.day == selected.day,
                  onTap: () => onSelect(DateTime(d.year, d.month, d.day)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dominant kind for the day's circle tint (event > todo/expense > mixed).
  /// Null = no fill (matches the web MonthPane).
  static String? _kind(List<TimelineItem>? items) {
    if (items == null || items.isEmpty) return null;
    final hasEvent = items.any((i) => i.kind == 'event' || i.skillName == 'event');
    final hasTodo =
        items.any((i) => i.kind == 'asset' && (i.skillName == 'todo' || i.skillName == 'expense'));
    if (hasEvent && hasTodo) return 'mixed';
    if (hasEvent) return 'event';
    if (hasTodo) return 'todo';
    return null;
  }
}

class _MonthCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final String? kind;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.kind,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    Color bg = Colors.transparent;
    Color fg = inMonth ? eu.textHi : eu.textLo.withValues(alpha: 0.4);
    Color border = Colors.transparent;
    List<BoxShadow>? glow;

    switch (kind) {
      case 'event':
        bg = eu.accentPurple.withValues(alpha: 0.26);
        border = eu.accentPurple.withValues(alpha: 0.40);
        fg = eu.accentPurple;
      case 'todo':
        bg = eu.accentBlue.withValues(alpha: 0.20);
        border = eu.accentBlue.withValues(alpha: 0.40);
        fg = eu.accentBlue;
      case 'mixed':
        bg = eu.accentPurple.withValues(alpha: 0.30);
        border = eu.accentPurple.withValues(alpha: 0.50);
        fg = eu.accentPurple;
    }
    if (isToday) {
      bg = eu.textHi;
      fg = eu.bg;
      border = Colors.transparent;
      glow = [BoxShadow(color: eu.textHi.withValues(alpha: 0.5), blurRadius: 12)];
    } else if (isSelected) {
      bg = Colors.transparent;
      border = eu.brand;
      fg = eu.brand;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 1.5),
            boxShadow: glow,
          ),
          child: Text('${day.day}',
              style: euMono(
                  fontSize: isToday ? 12.5 : 12,
                  color: fg)
              .copyWith(fontWeight: isToday ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }
}

/// Pinned footer under the month scroll — the selected day's items.
class _SelectedDayFooter extends StatefulWidget {
  final DateTime day;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final VoidCallback onOpenDay;
  const _SelectedDayFooter({
    required this.day,
    required this.items,
    required this.skills,
    required this.onOpenDay,
  });

  @override
  State<_SelectedDayFooter> createState() => _SelectedDayFooterState();
}

class _SelectedDayFooterState extends State<_SelectedDayFooter> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_SelectedDayFooter old) {
    super.didUpdateWidget(old);
    // Switching the selected day resets the footer scroll to the top.
    if (old.day != widget.day && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final flashes = FlashPill.flashesIn(widget.items);
    final hasContent =
        widget.items.where((i) => i.kind != 'input_turn').isNotEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: eu.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        border: Border(top: BorderSide(color: eu.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // §月 sticky 日头(固定 footer 顶):日期·周几(左) + ⚡N(最右)。点 → DayDetail。
          _header(eu, flashes),
          Expanded(
            child: hasContent
                ? SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
                    // 点空白内容 → day detail;条目仍开各自详情。(不挡纵向滚动)
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onOpenDay,
                      child: _BandView(
                        items: widget.items,
                        skills: widget.skills,
                        onTap: (it) =>
                            _openTimelineItem(context, it, widget.skills),
                      ),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onOpenDay,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Text('空闲',
                          style: TextStyle(
                              color: eu.textLo,
                              fontStyle: FontStyle.italic,
                              fontSize: 13)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(EurekaColors eu, List<TimelineItem> flashes) {
    final isToday = _isToday;
    return GestureDetector(
      onTap: widget.onOpenDay,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                  eu.brand.withValues(alpha: 0.05), eu.surfaceRaised),
              eu.surfaceRaised,
            ],
          ),
          border: Border(bottom: BorderSide(color: eu.border)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // Expanded(不是 Flexible+Spacer)——日期占满左侧、闪念真正贴到最右,无留白。
            Expanded(
              child: Text(_dateLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isToday ? eu.brand : eu.textHi)),
            ),
            // 闪念 → 最右侧(⚡N,无「闪念」字样),与左侧日期对称。点 → 当天闪念 session。
            if (flashes.isNotEmpty) ...[
              const SizedBox(width: 8),
              FlashPill(
                  day: widget.day,
                  flashes: flashes,
                  skills: widget.skills,
                  compact: true),
            ],
          ],
        ),
      ),
    );
  }

  bool get _isToday {
    final n = DateTime.now();
    return widget.day == DateTime(n.year, n.month, n.day);
  }

  String _dateLabel() {
    const wd = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    final d = widget.day;
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final diff = DateTime(d.year, d.month, d.day).difference(t0).inDays;
    final dist = diff == 0
        ? ' · 今天'
        : diff == 1
            ? ' · 明天'
            : '';
    return '${d.month}月${d.day}日 ${wd[d.weekday % 7]}$dist';
  }
}

/* ── 年 month grid ──────────────────────────────────────────────────────── */

class _YearView extends StatelessWidget {
  final int year;
  final Map<DateTime, List<TimelineItem>> byDay;
  final ValueChanged<DateTime> onPickMonth;
  const _YearView({required this.year, required this.byDay, required this.onPickMonth});

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final counts = List<int>.filled(12, 0);
    byDay.forEach((d, items) {
      if (d.year == year) counts[d.month - 1] += items.length;
    });
    return Column(
      children: [
        // Year header — mirrors the month view's header band so switching
        // 月 ↔ 年 keeps the same top anchor.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Center(
            child: Text('$year 年',
                style: TextStyle(color: eu.textHi, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            childAspectRatio: 1.15,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (var m = 1; m <= 12; m++)
                _YearMonthCell(
                  month: m,
                  count: counts[m - 1],
                  isCurrent: year == now.year && m == now.month,
                  onTap: () => onPickMonth(DateTime(year, m)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _YearMonthCell extends StatelessWidget {
  final int month;
  final int count;
  final bool isCurrent;
  final VoidCallback onTap;
  const _YearMonthCell({
    required this.month,
    required this.count,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent
              ? Color.alphaBlend(eu.brand.withValues(alpha: 0.12), eu.surfaceRaised)
              : eu.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isCurrent ? eu.brand.withValues(alpha: 0.45) : eu.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$month 月',
                style: TextStyle(
                    color: isCurrent ? eu.brand : eu.textHi,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(count > 0 ? '$count 件' : '—',
                style: euMono(fontSize: 11, color: count > 0 ? eu.brand : eu.textLo)),
          ],
        ),
      ),
    );
  }
}

/* ── shared day section + item row (流 + 月) ────────────────────────────── */

/// A day in the 流: a left date rail (weekday cap + big date, today brand line
/// + glow) beside a colored tile (brand-faint gradient) holding the day's rows.
/// Mirrors the web ScheduleView.
class _DayRow extends StatefulWidget {
  final DateTime day;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final bool monthBoundary;
  // §流:tap the date or the tile's empty area → open the day view (which has the
  // per-day add button). Items keep their own taps (open the item detail).
  final VoidCallback onOpen;
  final ScrollController scroll; // drives the sticky rail
  const _DayRow({
    super.key,
    required this.day,
    required this.items,
    required this.skills,
    required this.onOpen,
    required this.scroll,
    this.monthBoundary = false,
  });

  @override
  State<_DayRow> createState() => _DayRowState();
}

class _DayRowState extends State<_DayRow> {
  // Keyed tile so the sticky 左列 can read the day's height + viewport position.
  final _tileKey = GlobalKey();
  ScrollableState? _scrollable;
  // The scroll offset at which this day's 左列 starts pinning. Frozen once the day
  // crosses the viewport top so the float is driven by the live scroll offset
  // (smooth) instead of a one-frame-lagged localToGlobal (which jitters).
  double? _pin;

  // 左侧日期/闪念纵列宽(= 内容左缩进)。够宽以容下「⚡NN」pill,避免溢出。
  static const double _railW = 60;

  // 左列高度(日期 + 可选闪念 pill),用于钉到当天底部的 clamp。
  double get _railHeight =>
      42 + (FlashPill.flashesIn(widget.items).isNotEmpty ? 32 : 0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable = Scrollable.maybeOf(context);
  }

  // 左列(日期+闪念)随滚动钉顶/下滑,停在当天底部。钉住后用 live scroll offset 驱动
  // (不再每帧 localToGlobal 滞后 → 不抖);未钉住时持续刷新锚点、左列贴在当天顶部。
  double _railOffset(double tileH) {
    final maxOff = tileH - _railHeight;
    if (maxOff <= 0) return 0;
    final rb = _tileKey.currentContext?.findRenderObject() as RenderBox?;
    final vp = _scrollable?.context.findRenderObject() as RenderBox?;
    if (rb != null && rb.attached && vp != null && vp.attached) {
      final dy = rb.localToGlobal(Offset.zero, ancestor: vp).dy; // tile top vs viewport
      if (dy >= 0) {
        _pin = widget.scroll.offset + dy; // not pinned yet — keep anchor fresh
        return 0;
      }
      _pin ??= widget.scroll.offset + dy; // built already pinned (e.g. after seek)
    }
    if (_pin == null) return 0;
    return (widget.scroll.offset - _pin!).clamp(0.0, maxOff);
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final isToday = widget.day == DateTime(now.year, now.month, now.day);
    final flashes = FlashPill.flashesIn(widget.items);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: _tileKey,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        constraints: const BoxConstraints(minHeight: 52),
        child: Stack(
          children: [
            // 右内容:各时段 block 仍分块,但一起装进一个浅色「day 容器」表达"同一天",
            // 不再松散漂浮。左缩进让出日期纵列,无固定 header。点空白 → DayDetail。
            GestureDetector(
              onTap: widget.onOpen,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_railW, 2, 6, 2),
                child: Container(
                  decoration: BoxDecoration(
                    color: eu.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: eu.border),
                    // P2 表层深度:暖色软阴影(非纯黑)→ day 容器明确浮起 bg,修 beige-on-beige 扁平。
                    boxShadow: [
                      BoxShadow(
                          color: eu.brightness == Brightness.dark
                              ? Colors.black.withValues(alpha: 0.28)
                              : const Color(0xFF6B5A3A).withValues(alpha: 0.13),
                          blurRadius: 18,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  padding: const EdgeInsets.all(7),
                  child: _BandView(
                    items: widget.items,
                    skills: widget.skills,
                    onTap: (it) =>
                        _openTimelineItem(context, it, widget.skills),
                  ),
                ),
              ),
            ),
            // 左列:日期 + 闪念(回到日期下方),作为一个整体 sticky 一起跟随滚动。
            Positioned(
              top: 0,
              left: 0,
              child: ListenableBuilder(
                listenable: widget.scroll,
                builder: (_, _) {
                  final rb =
                      _tileKey.currentContext?.findRenderObject() as RenderBox?;
                  final off = _railOffset(rb?.size.height ?? 0);
                  return Transform.translate(
                    offset: Offset(0, off),
                    child: _rail(eu, isToday, flashes),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 左列:周缩写 + 日号(今天蓝 + 蓝点)+ 闪念 pill(回到日期下方)。
  Widget _rail(EurekaColors eu, bool isToday, List<TimelineItem> flashes) {
    const wd = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    final d = widget.day;
    return SizedBox(
      width: _railW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 日期 → DayDetail
          GestureDetector(
            onTap: widget.onOpen,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(wd[d.weekday % 7],
                      style: euMono(
                          fontSize: 9,
                          letterSpacing: 1.2,
                          color: isToday
                              ? eu.brand
                              : eu.textLo.withValues(alpha: 0.85))),
                  Text('${d.day}',
                      style: TextStyle(
                          fontSize: 23,
                          height: 1.05,
                          fontWeight: FontWeight.w600,
                          color: isToday ? eu.brand : eu.textHi)),
                ],
              ),
            ),
          ),
          // 闪念 pill(日期下方)。⚡ → 当天「X月X日 闪念」session。
          if (flashes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 1),
              child: FlashPill(
                  day: widget.day,
                  flashes: flashes,
                  skills: widget.skills,
                  compact: true),
            ),
        ],
      ),
    );
  }
}

/// §流 / 月 compact 段视图 — a day's items grouped into 时段水洗带 (段头 + rows),
/// built from stream-safe primitives (DayRender can't be measured inside the lazy
/// 流/月 lists). Flash (input_turn) is excluded — it lives in the day's ⚡N pill,
/// never as a band row. Reused by _DayRow (流) and the 月 day footer so the two
/// stay in lockstep.
class _BandView extends StatelessWidget {
  const _BandView({
    required this.items,
    required this.skills,
    this.onTap,
  });

  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final void Function(TimelineItem)? onTap;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final groups = _bandGroupsOf(items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var g = 0; g < groups.length; g++) ...[
          if (g > 0) const SizedBox(height: 11),
          _bandBlock(context, eu, groups[g]),
        ],
      ],
    );
  }

  // One 时段水洗带: a faint vertical wash of the band tint over the raised surface
  // (Direction B), holding 段头 (emoji + 时段) + its rows. width:∞ fills the parent;
  // the start-aligned Column (not a stretch Column) stays measurable in lazy lists.
  Widget _bandBlock(
    BuildContext context,
    EurekaColors eu,
    (String, String, Color, List<TimelineItem>) group,
  ) {
    final (_, label, tint, list) = group;
    // 有钟点的在上(按时刻);说了时段没说钟点的沉到段尾(虚线、不显时间)。
    final timed = [for (final it in list) if (!_noTime(it)) it];
    final noTime = [for (final it in list) if (_noTime(it)) it];
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        // 段色块:色温微洗在 base surface 上;卡片用 surfaceRaised 抬升、自然浮起。
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(tint.withValues(alpha: 0.16), eu.surface),
            Color.alphaBlend(tint.withValues(alpha: 0.07), eu.surface),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 段头:发光球 + 段名 + 向右渐隐细线。
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                _segOrb(tint, 12),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        color: eu.textMid,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 9),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        tint.withValues(alpha: 0.42),
                        tint.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < timed.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            _card(context, eu, timed[i], noTime: false),
          ],
          for (var i = 0; i < noTime.length; i++) ...[
            SizedBox(height: timed.isEmpty && i == 0 ? 0 : 7),
            _card(context, eu, noTime[i], noTime: true),
          ],
        ],
      ),
    );
  }

  // One record = 左侧时刻列 + 带边框小卡片(icon + 标题省略 + 领域 tag)。无时刻 = 虚线、空时刻列。
  Widget _card(BuildContext context, EurekaColors eu, TimelineItem it,
      {required bool noTime}) {
    final icon = it.kind == 'event'
        ? '📅'
        : it.kind == 'contact'
            ? '👤'
            : resolveMeta(it.skillName ?? 'misc', skills).icon;
    final time = '${it.effectiveAt.hour.toString().padLeft(2, '0')}:'
        '${it.effectiveAt.minute.toString().padLeft(2, '0')}';
    final inner = Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 7),
        // Expanded(而非 Flexible)→ 标题吃满中间,领域色点被推到卡片最右、各条对齐。
        Expanded(
          child: Text(it.title.isEmpty ? '记录' : it.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: eu.textHi, fontSize: 12.5, fontWeight: FontWeight.w500)),
        ),
        if (isDomain(it.domain)) ...[
          const SizedBox(width: 8),
          _domTag(eu, it.domain),
        ],
      ],
    );
    const pad = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final radius = BorderRadius.circular(10);
    // P1 悬浮态:去掉每条 item 的边框,用一道轻暖阴影让它浮在 day 容器上;
    // 没有时间的(noTime)用更淡填充 + 无阴影,读作"还没落定"。
    final Widget box = Container(
      decoration: BoxDecoration(
        color:
            noTime ? eu.surfaceRaised.withValues(alpha: 0.5) : eu.surfaceRaised,
        borderRadius: radius,
        boxShadow: noTime
            ? null
            : [
                BoxShadow(
                  color: eu.brightness == Brightness.dark
                      ? Colors.black.withValues(alpha: 0.22)
                      : const Color(0xFF6B5A3A).withValues(alpha: 0.10),
                  blurRadius: 7,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: pad,
      child: inner,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap!(it),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: noTime
                ? null
                : Text(time,
                    textAlign: TextAlign.right,
                    style: euMono(fontSize: 10, color: eu.textMid)),
          ),
          const SizedBox(width: 7),
          Expanded(child: box),
        ],
      ),
    );
  }

  // P3 降卡片色噪:领域 = 一个安静的小色点(不再色块 pill);领域名仍在详情可读。
  Widget _domTag(EurekaColors eu, String domain) {
    final c = domainColor(eu, domain);
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c),
    );
  }
}

// 发光小球 — radial highlight + soft glow of the band tint. Shared by 段头 + 日头。
Widget _segOrb(Color tint, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(tint, Colors.white, 0.55)!, tint],
          stops: const [0, 0.78],
        ),
        boxShadow: [
          BoxShadow(color: tint.withValues(alpha: 0.5), blurRadius: size * 0.5),
        ],
      ),
    );

// 斜纹占位 — diagonal hatch fill for empty days (空块斜纹).
class _HatchPainter extends CustomPainter {
  _HatchPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const gap = 9.0;
    for (var x = 0.0; x < size.width + size.height; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

// 是否「没有时间」(沉段尾、虚线、不显时刻):有 event/钟点 → 有时间;只说了时段没说
// 钟点 → 无时间;两者皆无的午夜兜底 → 无时间。
bool _noTime(TimelineItem it) {
  if (it.kind == 'event' || it.hasClockTime) return false;
  if (it.period.isNotEmpty) return true;
  return it.effectiveAt.hour == 0 && it.effectiveAt.minute == 0;
}

// Bucket a day's items into ordered time-of-day bands (凌晨/上午/中午/下午/晚上) +
// a「没说时间」tail. Flash (input_turn) is excluded (→ ⚡ pill). Placement matches
// DayRender: explicit 时段 (period) wins; else a clock time / event / non-midnight
// falls in its hour's band; a bare midnight capture drops to「没说时间」.
List<(String, String, Color, List<TimelineItem>)> _bandGroupsOf(
  List<TimelineItem> items,
) {
  // 时段 · 色温 tint (凌晨蓝灰 → 上午暖金 → 中午亮金 → 下午琥珀 → 晚上冷蓝;灰=没有时间)。
  // emoji 不再画(段头用发光球),保留占位以不动元组形状。
  const defs = [
    ('', '凌晨', Color(0xFF6B75C0)),
    ('', '上午', Color(0xFFF2B440)),
    ('', '中午', Color(0xFFF3A034)),
    ('', '下午', Color(0xFFE89149)),
    ('', '晚上', Color(0xFF5B69B2)),
    ('', '没有时间', Color(0xFF9AA0AD)),
  ];
  final buckets = List.generate(6, (_) => <TimelineItem>[]);
  for (final it in items) {
    if (it.kind == 'input_turn') continue; // flash → ⚡ pill, never a band row
    buckets[_bandIndexOf(it)].add(it);
  }
  final out = <(String, String, Color, List<TimelineItem>)>[];
  for (var i = 0; i < defs.length; i++) {
    if (buckets[i].isNotEmpty) {
      out.add((defs[i].$1, defs[i].$2, defs[i].$3, buckets[i]));
    }
  }
  return out;
}

// §流 compact 段视图 — which time-of-day band an item falls in (0凌晨…4晚上,
// 5没说时间). Explicit 时段 (period) wins; else a clock time / event / non-midnight
// lands in its hour's band; a bare midnight capture drops to「没说时间」. Top-level
// so the 流 tile and the seek's row-height estimate share one rule.
int _bandIndexOf(TimelineItem it) {
  switch (it.period) {
    case '凌晨':
      return 0;
    case '上午':
      return 1;
    case '中午':
      return 2;
    case '下午':
      return 3;
    case '晚上':
      return 4;
  }
  final timed = it.kind == 'event' ||
      it.hasClockTime ||
      !(it.effectiveAt.hour == 0 && it.effectiveAt.minute == 0);
  if (!timed) return 5;
  final h = it.effectiveAt.hour;
  if (h <= 5) return 0;
  if (h <= 11) return 1;
  if (h == 12) return 2;
  if (h <= 17) return 3;
  return 4;
}

/* ── 日 — full-screen day view (web DayDetailSheet parity) ──────────────────
   Opened from the 月 view (tap a day twice, or its footer header). Two modes:
   a default flat LIST of everything that day, and a 日程 hour-grid timeline
   with all-day chips + a 今日捕捉 section for time-less captures. Re-fetches on
   `dataRevision` so edits/deletes made from inside reflect immediately. */

const double _kHourHeight = 56;
const int _kGridStartHour = 0;
const int _kGridEndHour = 24;
// 「N 个待办」计数 chip 展开态(手风琴):折叠头高 + 每条展开行高。展开时在网格里
// 插入 N*_kClusterRowH 的真实高度、把下方内容整体下推(不悬浮覆盖)。
const double _kClusterHeaderH = 28;
const double _kClusterRowH = 30;

class DayDetailPage extends StatefulWidget {
  final DateTime day;
  const DayDetailPage({super.key, required this.day});

  @override
  State<DayDetailPage> createState() => _DayDetailPageState();
}

class _DayData {
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  _DayData(this.items, this.skills);
}

class _DayDetailPageState extends State<DayDetailPage> {
  final _api = ApiClient();
  final _gridScroll = ScrollController();
  int _loadedRev = -1;
  Future<_DayData>? _future;
  _DayData? _last; // stale-while-revalidate: keep showing this during reloads
  String _view = 'schedule'; // §B 默认「日程」网格(从流钻进某天 = 想看精确日程);'list' = 非日程段视图
  String? _capturedTab; // active type in 记录·按类型
  bool _unschedExpanded = false; // 待安排条是否展开全部
  final Set<String> _expandedClusters = {}; // 同点待办计数 chip 展开态(按代表 id)
  bool _didAnchor = false;
  // Items deleted via swipe — filtered out immediately so the row leaves the
  // list cleanly (avoids the "dismissed Dismissible still in tree" error) while
  // the bumpData re-fetch catches up.
  final Set<String> _deletedIds = {};

  Future<_DayData> _futureFor(int rev) {
    if (rev != _loadedRev || _future == null) {
      _loadedRev = rev;
      _future = _load();
    }
    return _future!;
  }

  bool _sameDay(DateTime a) =>
      a.year == widget.day.year && a.month == widget.day.month && a.day == widget.day.day;

  Future<_DayData> _load() async {
    final r = await Future.wait([fetchTimeline(_api), fetchSkills(_api)]);
    final items = (r[0] as List<TimelineItem>).where((it) => _sameDay(it.effectiveAt)).toList()
      ..sort((a, b) => a.effectiveAt.compareTo(b.effectiveAt));
    return _DayData(items, r[1] as Map<String, SkillMeta>);
  }

  @override
  void dispose() {
    _gridScroll.dispose();
    _api.close();
    super.dispose();
  }

  // ── bucket (§B 日程网格)──
  // 网格 = 事件 + **有时刻待办**;无时刻待办 → 顶部「待安排」条;结果记录(网球/记账/
  // 睡眠/带娃…)→ 顶部「记录·按类型」容器、不进网格;全天事件 → 顶部「全天」条。
  ({
    List<TimelineItem> allDay,
    List<TimelineItem> grid,
    List<TimelineItem> unscheduled,
    List<TimelineItem> records,
  }) _bucket(List<TimelineItem> items) {
    final allDay = <TimelineItem>[];
    final grid = <TimelineItem>[]; // 事件(有时刻) + 待办(有时刻)
    final unscheduled = <TimelineItem>[]; // 无时刻待办
    final records = <TimelineItem>[]; // 结果记录(非事件非待办)
    for (final it in items) {
      if (it.kind == 'input_turn') continue; // 闪念在 header ⚡N
      if (it.kind == 'event') {
        (it.allDay ? allDay : grid).add(it);
      } else if (it.skillName == 'todo') {
        (_todoTimed(it) ? grid : unscheduled).add(it);
      } else {
        records.add(it);
      }
    }
    return (allDay: allDay, grid: grid, unscheduled: unscheduled, records: records);
  }

  // 待办有没有"落格"的时刻:说了钟点(occurred_at)或 due 是非午夜时刻 → 进网格;
  // 否则(只有日期 / 没说时间)→「待安排」。
  static bool _todoTimed(TimelineItem it) =>
      it.hasClockTime ||
      !(it.effectiveAt.hour == 0 && it.effectiveAt.minute == 0);

  // 待办是否已完成(status=done / done / completed 任一)。
  static bool _isDone(TimelineItem it) {
    final p = it.payload;
    return p['status'] == 'done' ||
        p['done'] == true ||
        p['completed'] == true;
  }

  // ○ 点击 → 勾选/取消完成(PUT status,复用详情页路径);bumpData 即时重拉反映。
  Future<void> _toggleTodoDone(TimelineItem it) async {
    final next = !_isDone(it);
    try {
      await _api.putJson('/api/assets/${it.id}', {
        'payload_patch': {'status': next ? 'done' : 'pending'},
      });
    } catch (_) {}
    bumpData();
  }

  void _anchorGrid(List<TimelineItem> timed) {
    if (_didAnchor || !_gridScroll.hasClients) return;
    _didAnchor = true;
    final now = DateTime.now();
    final isToday = _sameDay(now);
    final firstHour = timed.isNotEmpty ? timed.first.effectiveAt.hour : null;
    final fallback = isToday ? (now.hour - 2).clamp(7, 23) : 7;
    final anchor = firstHour != null ? (firstHour - 1).clamp(0, fallback) : fallback;
    final target = (anchor - _kGridStartHour) * _kHourHeight;
    _gridScroll.jumpTo(target.clamp(0.0, _gridScroll.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Scaffold(
      backgroundColor: eu.bg,
      // Reliable per-day add — reachable no matter how full the day is (the 流
      // tile had no whitespace left to tap).
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateMenu(context, presetDate: widget.day),
        backgroundColor: eu.brand,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('在这天记一笔',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<int>(
          valueListenable: dataRevision,
          builder: (context, rev, _) => FutureBuilder<_DayData>(
            future: _futureFor(rev),
            builder: (ctx, snap) {
              // Stale-while-revalidate: a data change (e.g. closing a detail
              // sheet bumps dataRevision) re-fetches; keep showing the last
              // good data during the reload AND on a transient error, so items
              // never blank out mid-view (was: spinner/empty → looked like the
              // event "disappeared" after closing its card).
              if (snap.hasData) _last = snap.data;
              final data = snap.data ?? _last;
              final skills = data?.skills ?? const <String, SkillMeta>{};
              final items = (data?.items ?? const <TimelineItem>[])
                  .where((it) => !_deletedIds.contains(it.id))
                  .toList();
              final firstLoad = data == null && snap.connectionState != ConnectionState.done;
              return Column(
                children: [
                  _header(eu, items, skills),
                  Expanded(
                    child: firstLoad
                        ? const Center(child: CircularProgressIndicator())
                        : _view == 'list'
                            ? _listView(eu, items, skills)
                            : _scheduleView(eu, items, skills),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(EurekaColors eu, List<TimelineItem> items, Map<String, SkillMeta> skills) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back, color: eu.textHi),
            tooltip: '返回',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_weekday(widget.day),
                    style: TextStyle(
                        color: eu.textHi, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text('${_distance(widget.day)} · ${widget.day.month}月${widget.day.day}日',
                    style: euMono(fontSize: 10.5, letterSpacing: 1.6, color: eu.textLo)),
              ],
            ),
          ),
          // ⚡N闪念 pill — consistent across surfaces; N=0 self-hides.
          FlashPill(
            day: widget.day,
            flashes: FlashPill.flashesIn(items),
            skills: skills,
            compact: true,
          ),
          const SizedBox(width: 8),
          _modeToggle(eu),
        ],
      ),
    );
  }

  // 「非日程 / 日程」segmented control (固定命名). 非日程 = DayRender 段视图;
  // 日程 = 24h 网格.
  Widget _modeToggle(EurekaColors eu) {
    Widget seg(String label, String mode) {
      final active = _view == mode;
      return GestureDetector(
        onTap: () => setState(() {
          _view = mode;
          _didAnchor = false;
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: active ? eu.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: active ? Border.all(color: eu.border) : null,
          ),
          child: Text(label,
              style: TextStyle(
                  color: active ? eu.textHi : eu.textLo,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('非日程', 'list'), seg('日程', 'schedule')],
      ),
    );
  }

  // ── 非日程 view (default) — 段视图 DayRender (5 时段水洗带) ──
  Widget _listView(EurekaColors eu, List<TimelineItem> items, Map<String, SkillMeta> skills) {
    // Flash captures live in the ⚡ pill, not the bands — if a day has only those,
    // the segment view is empty → show the gentle empty state.
    if (items.where((i) => i.kind != 'input_turn').isEmpty) return _empty(eu);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 96),
      children: [
        DayRender(
          items: items,
          skills: skills,
          highlightNow: _sameDay(DateTime.now()),
          onTapItem: (it) => _openTimelineItem(context, it, skills),
        ),
      ],
    );
  }

  // ── SCHEDULE view (hour grid) ──
  Widget _scheduleView(EurekaColors eu, List<TimelineItem> items, Map<String, SkillMeta> skills) {
    final b = _bucket(items);
    WidgetsBinding.instance.addPostFrameCallback((_) => _anchorGrid(b.grid));
    final dayEmpty = items.where((i) => i.kind != 'input_turn').isEmpty;
    // 顺序(用户定 2026-06):记录(顶) → 日程;「全天 / 待安排」都收进日程 section、在网格之上。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b.records.isNotEmpty) _capturedSection(eu, b.records, skills),
        _sectionTitle(eu, '日程'),
        // 全天 + 待安排 = 网格顶部两个并列轻托盘(全天左 / 待安排右),同款样式。
        if (b.allDay.isNotEmpty || b.unscheduled.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: _topTrays(eu, b.allDay, b.unscheduled, skills),
          ),
        Expanded(child: _hourGrid(eu, b.grid, skills, dayEmpty)),
      ],
    );
  }

  // 网格顶部两个并列「轻托盘」(全天 / 待安排)= 同款容器 + 同款标题样式。
  Widget _topTray(EurekaColors eu,
      {required String label, String? count, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
      decoration: BoxDecoration(
        color: eu.surfaceRaised.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(label,
                  style: euMono(
                      fontSize: 10, letterSpacing: 1.5, color: eu.textMid)),
              if (count != null) ...[
                const Spacer(),
                Text(count, style: TextStyle(fontSize: 10, color: eu.textLo)),
              ],
            ],
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  // 全天(左)+ 待安排(右)左右并列;只有一个时占满整行。
  Widget _topTrays(EurekaColors eu, List<TimelineItem> allDay,
      List<TimelineItem> unscheduled, Map<String, SkillMeta> skills) {
    final left = allDay.isNotEmpty
        ? _topTray(eu,
            label: '全天', child: _allDayTrayContent(eu, allDay, skills))
        : null;
    final right = unscheduled.isNotEmpty
        ? _topTray(eu,
            label: '待安排',
            count: '共 ${unscheduled.length} 条',
            child: _unscheduledTrayContent(eu, unscheduled, skills))
        : null;
    if (left == null && right == null) return const SizedBox.shrink();
    if (left != null && right != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Expanded(child: right),
        ],
      );
    }
    return left ?? right!;
  }

  // 全天事件 = 正常的行(紫点 + 标题),不再是 pill。
  Widget _allDayTrayContent(EurekaColors eu, List<TimelineItem> allDay,
      Map<String, SkillMeta> skills) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final it in allDay)
          GestureDetector(
            onTap: () => _openTimelineItem(context, it, skills),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: eu.accentPurple)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(it.title.isEmpty ? '事件' : it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: eu.textHi, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // 待安排内容:○ 待办行(≤3)+ 展开其余 N 条(内部滚)。
  Widget _unscheduledTrayContent(EurekaColors eu, List<TimelineItem> todos,
      Map<String, SkillMeta> skills) {
    final shown = _unschedExpanded ? todos : todos.take(3).toList();
    final rest = todos.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _unschedExpanded ? 220 : 999),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: _unschedExpanded
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(height: 5),
            itemBuilder: (_, i) => _todoCheckRow(eu, shown[i], skills),
          ),
        ),
        if (rest > 0 || _unschedExpanded)
          GestureDetector(
            onTap: () => setState(() => _unschedExpanded = !_unschedExpanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_unschedExpanded ? '收起 ⌃' : '展开其余 $rest 条 ⌄',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: eu.brand,
                      fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  // 一条待办行(○ 勾选框 + 标题)。点行 → 详情;done 显勾 + 删除线。
  Widget _todoCheckRow(
      EurekaColors eu, TimelineItem it, Map<String, SkillMeta> skills) {
    final done = _isDone(it);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTimelineItem(context, it, skills),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _toggleTodoDone(it),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? eu.accentGreen : Colors.transparent,
                border: Border.all(
                    color: done
                        ? eu.accentGreen
                        : eu.textLo.withValues(alpha: 0.6),
                    width: 1.5),
              ),
              child: done
                  ? const Icon(Icons.check, size: 11, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(it.title.isEmpty ? '待办' : it.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: done ? eu.textLo : eu.textHi,
                    fontSize: 13,
                    decoration: done ? TextDecoration.lineThrough : null)),
          ),
        ],
      ),
    );
  }

  /// Unified small section heading (mono caps + optional trailing widget) —
  /// shared by 「今日捕捉」 and 「日程安排」 so they read as one system.
  // 两个对等 section 的标题(记录 / 日程):品牌竖条 + 实心标题。两个 section 同款,
  // 不分主次 —— 它们是并列的两段(记录段 / 日程段)。
  Widget _sectionTitle(EurekaColors eu, String text, {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
        child: Row(
          children: [
            Container(
                width: 3,
                height: 15,
                decoration: BoxDecoration(
                    color: eu.brand, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 9),
            Text(text,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: eu.textHi)),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Expanded(child: trailing),
            ],
          ],
        ),
      );


  static const _captureLabels = <String, String>{
    'todo': '待办', 'expense': '记账', 'contact': '名片',
    'notes': '随记', 'idea': '随记', 'misc': '随记',  // idea/misc merged into 随记
  };

  Widget _capturedSection(EurekaColors eu, List<TimelineItem> captured, Map<String, SkillMeta> skills) {
    // Group by type so a card-heavy day doesn't bury the hour grid; tabs switch
    // between types (待办 / 记账 / 想法 / 名片 / …), like the web CapturedSection.
    final types = <String>[];
    for (final it in captured) {
      final k = it.skillName ?? 'misc';
      if (!types.contains(k)) types.add(k);
    }
    final active = types.contains(_capturedTab) ? _capturedTab! : (types.isNotEmpty ? types.first : 'misc');
    final shown = captured.where((it) => (it.skillName ?? 'misc') == active).toList();
    String label(String t) => _captureLabels[t] ?? resolveMeta(t, skills).label;

    final tabRow = types.length > 1
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in types)
                  GestureDetector(
                    onTap: () => setState(() => _capturedTab = t),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: t == active ? eu.surfaceRaised : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: t == active ? eu.border : Colors.transparent),
                      ),
                      child: Text(
                        '${label(t)} ${captured.where((it) => (it.skillName ?? 'misc') == t).length}',
                        style: euMono(fontSize: 10.5, color: t == active ? eu.textHi : eu.textLo),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : null;

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: eu.rule))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sectionTitle(eu, '记录'),
          // 类型选择(随记 / 记账 …)移进容器内、标题下方一行,不再挤在标题行里。
          if (tabRow != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: tabRow,
            ),
          // Fixed 3-row window (60px row + 4px gap) — the section never changes
          // height when switching tabs, so the hour grid below stays put. Fewer
          // than 3 items → empty space; more → scrolls inside.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
            child: SizedBox(
              height: 60 * 3 + 4 * 2,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, i) => _itemRow(eu, shown[i], skills),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hourGrid(
      EurekaColors eu, List<TimelineItem> timed, Map<String, SkillMeta> skills, bool dayEmpty) {
    final now = DateTime.now();
    final isToday = _sameDay(now);
    final baseGridHeight = (_kGridEndHour - _kGridStartHour) * _kHourHeight;
    // §B 同一时刻 N 个待办收成一个「计数 chip」:按 startMin 把同点待办聚成 cluster,
    // 只把代表项放进列布局(渲染时换成计数 chip);事件 / 单条待办照旧。
    final clusters = <String, List<TimelineItem>>{}; // repId → 同点待办们
    final layout = <TimelineItem>[];
    final byMin = <int, List<TimelineItem>>{};
    for (final it in timed) {
      if (it.kind != 'event' && it.skillName == 'todo') {
        byMin.putIfAbsent(_startMin(it), () => []).add(it);
      } else {
        layout.add(it);
      }
    }
    byMin.forEach((_, todos) {
      if (todos.length > 1) clusters[todos.first.id] = todos;
      layout.add(todos.first);
    });
    // §B 手风琴:每个「展开」的计数 chip 在它的时刻插入 N*行高 的真实高度;pushAt(y) =
    // y 之上所有展开 chip 的插入量之和 → 加到每个元素的 top,把下方内容整体下推、不悬浮覆盖。
    final expansions = <(double, double)>[]; // (baseTop, extraHeight)
    clusters.forEach((repId, todos) {
      if (_expandedClusters.contains(repId)) {
        expansions.add((
          _startMin(todos.first) / 60.0 * _kHourHeight,
          todos.length * _kClusterRowH,
        ));
      }
    });
    double pushAt(double baseTop) {
      var s = 0.0;
      for (final e in expansions) {
        if (e.$1 < baseTop) s += e.$2;
      }
      return s;
    }
    final gridHeight =
        baseGridHeight + expansions.fold<double>(0.0, (a, e) => a + e.$2);
    // 重叠规则:同时段事件/待办等分成并列列(google-calendar 式)。grid 占满 body 宽。
    final cols = _eventColumns(layout);
    const leftPad = 62.0, gap = 3.0;
    final avail = (MediaQuery.sizeOf(context).width - leftPad - 12.0).clamp(40.0, double.infinity);
    return SingleChildScrollView(
      controller: _gridScroll,
      child: SizedBox(
        height: gridHeight,
        child: Stack(
          children: [
            // Hour rows + labels
            for (int h = _kGridStartHour; h < _kGridEndHour; h++)
              Positioned(
                top: (h - _kGridStartHour) * _kHourHeight +
                    pushAt((h - _kGridStartHour) * _kHourHeight),
                left: 0,
                right: 0,
                height: _kHourHeight,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: h > _kGridStartHour ? eu.rule : Colors.transparent)),
                  ),
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 56,
                      child: Text(_hourLabel(h),
                          textAlign: TextAlign.right,
                          style: euMono(fontSize: 10, letterSpacing: 0.4, color: eu.textLo)),
                    ),
                  ),
                ),
              ),
            // Timed event / 待办 blocks — overlap-aware columns;同点多待办 = 计数 chip。
            for (final it in layout)
              clusters.containsKey(it.id)
                  ? _todoClusterBlock(eu, clusters[it.id]!, skills,
                      col: cols[it.id]?.$1 ?? 0,
                      count: cols[it.id]?.$2 ?? 1,
                      leftPad: leftPad,
                      avail: avail,
                      gap: gap,
                      topOffset: pushAt(_startMin(it) / 60.0 * _kHourHeight))
                  : _eventBlock(eu, it, skills,
                      col: cols[it.id]?.$1 ?? 0,
                      count: cols[it.id]?.$2 ?? 1,
                      leftPad: leftPad,
                      avail: avail,
                      gap: gap,
                      topOffset: pushAt(_startMin(it) / 60.0 * _kHourHeight)),
            // "now" line — only on today
            if (isToday)
              Positioned(
                top: (now.hour * 60 + now.minute) / 60.0 * _kHourHeight +
                    pushAt((now.hour * 60 + now.minute) / 60.0 * _kHourHeight),
                left: 52,
                right: 12,
                child: Row(
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: eu.accentRed, shape: BoxShape.circle)),
                    Expanded(child: Container(height: 1.5, color: eu.accentRed)),
                  ],
                ),
              ),
            if (dayEmpty)
              Positioned(
                top: _kHourHeight * 8 + 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Text('这一天什么都没有',
                      style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic, fontSize: 14)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static int _startMin(TimelineItem it) => it.effectiveAt.hour * 60 + it.effectiveAt.minute;
  static int _endMin(TimelineItem it) {
    final s = _startMin(it);
    var e = it.endAt != null ? it.endAt!.hour * 60 + it.endAt!.minute : s + 30;
    if (e <= s) e = s + 30;
    return e;
  }

  // 重叠规则:把事件按重叠 cluster 分配并列列(每列内不重叠),返回每条的
  // (列序号, 该 cluster 的总列数)。一个 cluster 等分成 N 列。
  Map<String, (int, int)> _eventColumns(List<TimelineItem> events) {
    final sorted = [...events]
      ..sort((a, b) {
        final c = _startMin(a).compareTo(_startMin(b));
        return c != 0 ? c : _endMin(b).compareTo(_endMin(a));
      });
    final out = <String, (int, int)>{};
    final cluster = <TimelineItem>[];
    var clusterEnd = -1;

    void flush() {
      if (cluster.isEmpty) return;
      final colEnds = <int>[]; // end-min of the last event placed in each column
      final colOf = <String, int>{};
      for (final e in cluster) {
        final s = _startMin(e);
        var placed = -1;
        for (var i = 0; i < colEnds.length; i++) {
          if (colEnds[i] <= s) {
            placed = i;
            break;
          }
        }
        if (placed == -1) {
          placed = colEnds.length;
          colEnds.add(0);
        }
        colEnds[placed] = _endMin(e);
        colOf[e.id] = placed;
      }
      final count = colEnds.length;
      for (final e in cluster) {
        out[e.id] = (colOf[e.id] ?? 0, count);
      }
      cluster.clear();
      clusterEnd = -1;
    }

    for (final e in sorted) {
      if (cluster.isNotEmpty && _startMin(e) >= clusterEnd) flush();
      cluster.add(e);
      if (_endMin(e) > clusterEnd) clusterEnd = _endMin(e);
    }
    flush();
    return out;
  }

  Widget _eventBlock(EurekaColors eu, TimelineItem it, Map<String, SkillMeta> skills,
      {required int col,
      required int count,
      required double leftPad,
      required double avail,
      required double gap,
      double topOffset = 0}) {
    final start = it.effectiveAt;
    final startMin = start.hour * 60 + start.minute;
    var endMin = it.endAt != null ? it.endAt!.hour * 60 + it.endAt!.minute : startMin + 30;
    if (endMin <= startMin) endMin = startMin + 30;
    final top = startMin / 60.0 * _kHourHeight + topOffset;
    final rawH = (endMin - startMin) / 60.0 * _kHourHeight;
    final height = rawH < 24 ? 24.0 : rawH;
    final isEvent = it.kind == 'event';
    final isTodo = !isEvent && it.skillName == 'todo';
    final done = isTodo && _isDone(it);
    final accent = isEvent ? eu.accentPurple : eu.accentBlue;
    final colW = (avail - gap * (count - 1)) / count;
    final left = leftPad + col * (colW + gap);
    return Positioned(
      top: top,
      left: left,
      width: colW,
      height: height,
      child: GestureDetector(
        onTap: () => _openTimelineItem(context, it, skills),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 待办落格 = 带 ○ 勾选框(点 ○ 直接完成;done = 绿勾 + 删除线);事件无框。
                  if (isTodo) ...[
                    GestureDetector(
                      onTap: () => _toggleTodoDone(it),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? eu.accentGreen : Colors.transparent,
                          border: Border.all(
                              color: done ? eu.accentGreen : accent, width: 1.5),
                        ),
                        child: done
                            ? const Icon(Icons.check,
                                size: 9, color: Colors.white)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                        it.title.isEmpty ? (isEvent ? '事件' : '待办') : it.title,
                        maxLines: height > 40 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: done ? eu.textLo : eu.textHi,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            decoration:
                                done ? TextDecoration.lineThrough : null)),
                  ),
                ],
              ),
              if (it.location != null && it.location!.isNotEmpty && height > 44)
                Text(it.location!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: eu.textMid, fontSize: 10.5)),
            ],
          ),
        ),
      ),
    );
  }

  // §B 同一时刻 N 个待办 → 一个「N 个待办 ▾」计数 chip,点开就地展成可勾小列表。
  Widget _todoClusterBlock(
      EurekaColors eu, List<TimelineItem> todos, Map<String, SkillMeta> skills,
      {required int col,
      required int count,
      required double leftPad,
      required double avail,
      required double gap,
      double topOffset = 0}) {
    final repId = todos.first.id;
    final expanded = _expandedClusters.contains(repId);
    final top = _startMin(todos.first) / 60.0 * _kHourHeight + topOffset;
    final colW = (avail - gap * (count - 1)) / count;
    final left = leftPad + col * (colW + gap);
    final accent = eu.accentBlue;
    // 折叠 = 头一块;展开 = 头 + N 行(固定行高,精确等于 _hourGrid 在此处插入的
    // N*_kClusterRowH)→「撑大时间块、把下方内容整体下推」,不再悬浮覆盖其他 block。
    return Positioned(
      top: top,
      left: left,
      width: colW,
      height: _kClusterHeaderH + (expanded ? todos.length * _kClusterRowH : 0),
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: expanded ? 0.16 : 0.20),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _kClusterHeaderH,
              child: GestureDetector(
                onTap: () => setState(() => expanded
                    ? _expandedClusters.remove(repId)
                    : _expandedClusters.add(repId)),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text('${todos.length} 个待办',
                        style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16, color: accent),
                  ],
                ),
              ),
            ),
            if (expanded)
              for (final t in todos)
                SizedBox(
                    height: _kClusterRowH,
                    child: _todoCheckRow(eu, t, skills)),
          ],
        ),
      ),
    );
  }

  // ── shared item row (list + 今日捕捉) ──
  Widget _itemRow(EurekaColors eu, TimelineItem it, Map<String, SkillMeta> skills) {
    final isFlash = it.kind == 'input_turn';
    final timeStr = isFlash
        ? '${it.effectiveAt.hour.toString().padLeft(2, '0')}:${it.effectiveAt.minute.toString().padLeft(2, '0')}'
        : (it.allDay || (it.effectiveAt.hour == 0 && it.effectiveAt.minute == 0))
            ? '全天'
            : '${it.effectiveAt.hour.toString().padLeft(2, '0')}:${it.effectiveAt.minute.toString().padLeft(2, '0')}';
    final icon = isFlash
        ? '⚡'
        : it.kind == 'event'
            ? '📅'
            : it.kind == 'contact'
                ? '👤'
                : resolveMeta(it.skillName ?? 'misc', skills).icon;
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTimelineItem(context, it, skills),
      child: Container(
        // Fixed height → every card is the same size regardless of whether it
        // has a subtitle (the title is vertically centered when alone).
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: eu.border),
        ),
        child: Row(
          children: [
            SizedBox(width: 40, child: Text(timeStr, style: euMono(fontSize: 10.5, color: eu.textMid))),
            const SizedBox(width: 6),
            SizedBox(width: 20, child: Center(child: Text(icon, style: const TextStyle(fontSize: 14)))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.title.isEmpty ? (isFlash ? '闪念' : '记录') : it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: eu.textHi, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.3)),
                  if (it.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(it.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: eu.textMid, fontSize: 11.5)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // Left-swipe to delete (consistent with cards elsewhere). Flash captures
    // aren't deletable here. Grid event blocks delete via tap → detail sheet.
    final delPath = _deletePathFor(it);
    if (delPath == null) return row;
    return Dismissible(
      key: ValueKey('day_del_${it.kind}_${it.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: eu.accentRed.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(delPath),
      onDismissed: (_) {
        setState(() => _deletedIds.add(it.id));
        bumpData();
      },
      child: row,
    );
  }

  String? _deletePathFor(TimelineItem it) {
    switch (it.kind) {
      case 'input_turn':
        return null; // flash capture — not deletable from here
      case 'event':
        return '/api/events/${it.eventId ?? it.id}';
      case 'contact':
        return '/api/contacts/${it.contactId ?? it.id}';
      default:
        return '/api/assets/${it.id}';
    }
  }

  Future<bool> _confirmDelete(String path) async {
    final eu = context.eu;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: eu.surfaceRaised,
        title: Text('删除这条记录？', style: TextStyle(color: eu.textHi)),
        content: Text('删除后无法恢复。', style: TextStyle(color: eu.textMid)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: eu.textMid))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('删除',
                  style: TextStyle(color: eu.accentRed, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      await _api.deleteJson(path);
      return true; // proceed to dismiss; onDismissed filters + bumpData
    } catch (_) {
      return false; // delete failed → snap back, item stays
    }
  }

  Widget _empty(EurekaColors eu) => Center(
        child: Text('这一天什么都没有',
            style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic, fontSize: 14)),
      );

  String _hourLabel(int h) {
    final period = h < 12 ? '上午' : '下午';
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$period $hh时';
  }

  String _weekday(DateTime d) {
    const wd = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    return wd[d.weekday % 7];
  }

  String _distance(DateTime d) {
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day);
    final diff = DateTime(d.year, d.month, d.day).difference(t0).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == -1) return '昨天';
    return diff > 0 ? '$diff 天后' : '${-diff} 天前';
  }
}
