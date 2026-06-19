import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../render/asset_detail_sheet.dart';
import '../render/day_render.dart';
import '../render/render_spec.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../timeline/timeline.dart';
import 'create_asset.dart';
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

  // 空日不常驻按钮:点选某个空日才露出「+ 在这天记一笔」(再点取消)。null = 无选中。
  DateTime? _selectedDay;

  DateTime _today = _d(DateTime.now());
  String? _overlayText; // 「今天 / N 天后 / N 月前 …」
  bool _overlayVisible = false;
  bool _todayInView = true;
  Timer? _fadeTimer;

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
    _updateOverlay();
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

    final label = bestStr != null ? _distanceLabel(_parse(bestStr!)) : _overlayText;
    if (label != _overlayText || !_overlayVisible || todayIn != _todayInView) {
      setState(() {
        _overlayText = label;
        _overlayVisible = true;
        _todayInView = todayIn;
      });
    }
    _fadeTimer?.cancel();
    _fadeTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => _overlayVisible = false);
    });
  }

  bool _didScroll = false;
  List<_DayR> _rows = const [];

  // Estimated pixel height per row — used to jump to today on mount without
  // relying on lazy-built GlobalKey contexts.
  double _estRowHeight(_DayR r) {
    final items = widget.data.byDay[r.day] ?? const <TimelineItem>[];
    if (items.isEmpty) return 50;
    return 24.0 + items.length * 30 + (items.length - 1) * 8 + 6;
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
  void _autoScroll() {
    if (_didScroll || !mounted || !_scroll.hasClients) return;
    _didScroll = true;
    _scroll.jumpTo(_offsetToToday().clamp(0.0, _scroll.position.maxScrollExtent));
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
      if (!_todayInView) setState(() => _todayInView = true);
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
          itemBuilder: (_, i) => _rowWidget(rows[i]),
        ),
        // A — floating distance watermark on the right, fades 280ms after scroll.
        if (_overlayText != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(0.95, -0.12),
                child: AnimatedOpacity(
                  opacity: _overlayVisible ? 0.16 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  child: Text(
                    _overlayText!,
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
        // E — 跳回今天 button, only when today is off-screen.
        if (!_todayInView)
          Positioned(
            bottom: 104,
            left: 0,
            right: 0,
            child: Center(
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
      ],
    );
  }

  Widget _rowWidget(_DayR r) {
    final items = widget.data.byDay[r.day] ?? const <TimelineItem>[];
    final key = _keyFor(r.day);
    if (items.isEmpty) {
      return _EmptyDayRow(
        key: key,
        day: r.day,
        monthBoundary: r.monthBoundary,
        selected: _selectedDay == r.day,
        onSelect: () => setState(() => _selectedDay = (_selectedDay == r.day) ? null : r.day),
      );
    }
    return _DayRow(
      key: key,
      day: r.day,
      items: items,
      skills: widget.data.skills,
      monthBoundary: r.monthBoundary,
      onOpen: () => _openDay(r.day),
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

class _EmptyDayRow extends StatelessWidget {
  final DateTime day;
  final bool monthBoundary;
  // §流:an empty day is a blank tile by default (NOT a permanent button). Tap to
  // select → it reveals「+ 在这天记一笔」(tap that → create directly; re-tap the
  // tile to deselect). Keeps long empty stretches clean.
  final bool selected;
  final VoidCallback onSelect;
  const _EmptyDayRow({
    super.key,
    required this.day,
    required this.selected,
    required this.onSelect,
    this.monthBoundary = false,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    final isTomorrow = day == tomorrow;
    final label = isToday ? 'TODAY' : isTomorrow ? 'TOMORROW' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: onSelect,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(width: 64, child: railHeader(eu, day, isToday, monthBoundary)),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onSelect, // tap to select/deselect this empty day
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.only(left: 6),
                  constraints: const BoxConstraints(minHeight: 72),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: selected
                      ? BoxDecoration(
                          color: eu.brand.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: eu.brand.withValues(alpha: 0.5)),
                        )
                      : dayTileDecoration(eu),
                  child: Stack(
                    children: [
                      if (selected)
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('空闲',
                                  style: TextStyle(
                                      color: eu.textLo, fontStyle: FontStyle.italic, fontSize: 13)),
                              const SizedBox(width: 16),
                              GestureDetector(
                                onTap: () => showCreateMenu(context, presetDate: day),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add, size: 15, color: eu.brand),
                                    const SizedBox(width: 3),
                                    Text('在这天记一笔',
                                        style: TextStyle(
                                            color: eu.brand, fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (label != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: Text(label,
                              style: euMono(fontSize: 9, letterSpacing: 2, color: eu.textMid)),
                        ),
                    ],
                  ),
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
  final _scroll = ScrollController();
  final _focusKey = GlobalKey();
  late DateTime _selected = _dayOnly(DateTime.now());
  late final List<DateTime> _months = [
    for (var i = -6; i <= 6; i++)
      DateTime(widget.focusMonth.year, widget.focusMonth.month + i),
  ];

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _focusKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
        Expanded(
          // Eager Column (not a lazy ListView) so the focus-month block is laid
          // out on first frame and ensureVisible can scroll to it on mount.
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Column(
              children: [
                for (final m in _months)
                  _MonthBlock(
                    key: m.year == widget.focusMonth.year && m.month == widget.focusMonth.month
                        ? _focusKey
                        : null,
                    month: m,
                    byDay: widget.byDay,
                    selected: _selected,
                    onSelect: _onDayTap,
                  ),
              ],
            ),
          ),
        ),
        _SelectedDayFooter(
          day: _selected,
          items: selItems,
          skills: widget.skills,
          onOpenDay: () => _openDay(_selected),
        ),
      ],
    );
  }
}

class _MonthBlock extends StatelessWidget {
  final DateTime month; // first of month
  final Map<DateTime, List<TimelineItem>> byDay;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  const _MonthBlock({
    super.key,
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
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    // 42 cells from the Sunday on/before the 1st.
    final first = DateTime(month.year, month.month, 1);
    final start = first.subtract(Duration(days: first.weekday % 7));
    final cells = [for (var i = 0; i < 42; i++) start.add(Duration(days: i))];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${month.month}月',
                  style: TextStyle(
                      color: isCurrentMonth ? eu.brand : eu.textHi,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      shadows: isCurrentMonth
                          ? [Shadow(color: eu.brand.withValues(alpha: 0.4), blurRadius: 14)]
                          : null)),
              const SizedBox(width: 8),
              Text('${month.year}',
                  style: euMono(fontSize: 10.5, letterSpacing: 1.4, color: eu.textLo)),
            ],
          ),
          const SizedBox(height: 8),
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
            childAspectRatio: 1.0,
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
class _SelectedDayFooter extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      width: double.infinity,
      // Fixed height (not maxHeight) so the month grid above never reflows when
      // you select a busy day vs. an empty one — the footer is a stable panel
      // that scrolls internally when its day has many items.
      height: MediaQuery.of(context).size.height * 0.30,
      decoration: BoxDecoration(
        color: eu.brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
        border: Border(top: BorderSide(color: eu.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tap the header → full day view (hour grid + list). The whole day
            // cell also re-opens on a second tap (see _MonthView._onDayTap).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenDay,
              child: Row(
                children: [
                  Expanded(
                    child: Text(_fullDateLabel(day),
                        style: euMono(fontSize: 10.5, letterSpacing: 1.8, color: eu.textMid)),
                  ),
                  Text('日程', style: euMono(fontSize: 10, letterSpacing: 1.2, color: eu.brand)),
                  Icon(Icons.chevron_right, size: 16, color: eu.brand),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              Text('空闲', style: TextStyle(color: eu.textLo, fontStyle: FontStyle.italic, fontSize: 13))
            else
              for (final it in items) _footerRow(context, eu, it),
          ],
        ),
      ),
    );
  }

  Widget _footerRow(BuildContext context, EurekaColors eu, TimelineItem it) {
    final isFlash = it.kind == 'input_turn';
    final time = isFlash || (it.effectiveAt.hour == 0 && it.effectiveAt.minute == 0)
        ? (isFlash
            ? '${it.effectiveAt.hour.toString().padLeft(2, '0')}:${it.effectiveAt.minute.toString().padLeft(2, '0')}'
            : '全天')
        : '${it.effectiveAt.hour.toString().padLeft(2, '0')}:${it.effectiveAt.minute.toString().padLeft(2, '0')}';
    final icon = isFlash
        ? '⚡'
        : it.kind == 'event'
            ? '📅'
            : it.kind == 'contact'
                ? '👤'
                : resolveMeta(it.skillName ?? 'misc', skills).icon;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 42, child: Text(time, style: euMono(fontSize: 10.5, color: eu.textMid))),
        const SizedBox(width: 8),
        SizedBox(width: 18, child: Center(child: Text(icon, style: const TextStyle(fontSize: 13)))),
        const SizedBox(width: 8),
        Expanded(
          child: Text(it.title.isEmpty ? '闪念' : it.title,
              style: TextStyle(color: eu.textHi, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w500)),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openTimelineItem(context, it, skills),
        child: row,
      ),
    );
  }

  String _fullDateLabel(DateTime d) {
    const wd = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    final weekday = wd[d.weekday % 7];
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final diff = DateTime(d.year, d.month, d.day).difference(t0).inDays;
    final dist = diff == 0
        ? '今天'
        : diff == 1
            ? '明天'
            : diff == -1
                ? '昨天'
                : diff > 0
                    ? '$diff 天后'
                    : '${-diff} 天前';
    return '$weekday · $dist · ${d.month}月${d.day}日';
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
class _DayRow extends StatelessWidget {
  final DateTime day;
  final List<TimelineItem> items;
  final Map<String, SkillMeta> skills;
  final bool monthBoundary;
  // §流:tap the date or the tile's empty area → open the day view (which has the
  // per-day add button). Items keep their own taps (open the item detail).
  final VoidCallback onOpen;
  const _DayRow({
    super.key,
    required this.day,
    required this.items,
    required this.skills,
    required this.onOpen,
    this.monthBoundary = false,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = day == today;
    final isTomorrow = day == today.add(const Duration(days: 1));
    final corner = isToday ? 'TODAY' : isTomorrow ? 'TOMORROW' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The date opens the day view — reliable even when the tile is packed
            // with items (little empty area left to tap).
            GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(width: 64, child: railHeader(eu, day, isToday, monthBoundary)),
            ),
            Expanded(child: _tile(context, eu, corner)),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, EurekaColors eu, String? corner) {
    return GestureDetector(
      // tapping an item (opaque, deeper) opens it; tapping the tile's empty area
      // opens the day view.
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: dayTileDecoration(eu),
        child: Stack(
          children: [
            // §流: the day reuses the same 时段水洗带 as DayDetail, compact.
            DayRender(
              items: items,
              skills: skills,
              compact: true,
              onTapItem: (it) => _openTimelineItem(context, it, skills),
            ),
            // TODAY / TOMORROW corner tag (web ScheduleView labels these tiles).
            if (corner != null)
              Positioned(
                top: 0,
                right: 0,
                child: Text(corner,
                    style: euMono(fontSize: 9, letterSpacing: 2, color: eu.textMid)),
              ),
          ],
        ),
      ),
    );
  }
}

/* ── 日 — full-screen day view (web DayDetailSheet parity) ──────────────────
   Opened from the 月 view (tap a day twice, or its footer header). Two modes:
   a default flat LIST of everything that day, and a 日程 hour-grid timeline
   with all-day chips + a 今日捕捉 section for time-less captures. Re-fetches on
   `dataRevision` so edits/deletes made from inside reflect immediately. */

const double _kHourHeight = 56;
const int _kGridStartHour = 0;
const int _kGridEndHour = 24;

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
  String _view = 'list'; // list | schedule
  String? _capturedTab; // active type in 今日捕捉
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

  // ── bucket ──
  // The hour grid (日历) shows **only 日程 = events** (per product). Everything
  // else — todos, expenses, ideas, contacts, notes — is a time-less "capture"
  // and goes to the categorized 今日捕捉 section, never on the grid.
  (List<TimelineItem>, List<TimelineItem>, List<TimelineItem>) _bucket(List<TimelineItem> items) {
    final allDay = <TimelineItem>[];
    final timed = <TimelineItem>[];
    final captured = <TimelineItem>[];
    for (final it in items) {
      if (it.kind == 'event') {
        (it.allDay ? allDay : timed).add(it);
      } else {
        captured.add(it);
      }
    }
    return (allDay, timed, captured);
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
                  _header(eu),
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

  Widget _header(EurekaColors eu) {
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
          GestureDetector(
            onTap: () => setState(() {
              _view = _view == 'list' ? 'schedule' : 'list';
              _didAnchor = false;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: _view == 'schedule' ? eu.accentPurple.withValues(alpha: 0.20) : eu.surfaceRaised,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: _view == 'schedule' ? eu.accentPurple.withValues(alpha: 0.45) : eu.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_view == 'schedule' ? Icons.list : Icons.schedule, size: 14, color: eu.textHi),
                  const SizedBox(width: 6),
                  Text(_view == 'schedule' ? '列表' : '日程',
                      style: TextStyle(color: eu.textHi, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
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
    final (allDay, timed, captured) = _bucket(items);
    WidgetsBinding.instance.addPostFrameCallback((_) => _anchorGrid(timed));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (allDay.isNotEmpty) _allDayRow(eu, allDay, skills),
        if (captured.isNotEmpty) _capturedSection(eu, captured, skills),
        _sectionTitle(eu, '日程安排'),
        Expanded(child: _hourGrid(eu, timed, skills, items.isEmpty)),
      ],
    );
  }

  /// Unified small section heading (mono caps + optional trailing widget) —
  /// shared by 「今日捕捉」 and 「日程安排」 so they read as one system.
  Widget _sectionTitle(EurekaColors eu, String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
        child: Row(
          children: [
            Text(text, style: euMono(fontSize: 10, letterSpacing: 2.2, color: eu.textLo)),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Expanded(child: trailing),
            ],
          ],
        ),
      );

  Widget _allDayRow(EurekaColors eu, List<TimelineItem> allDay, Map<String, SkillMeta> skills) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: eu.rule))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('全天', style: euMono(fontSize: 10, letterSpacing: 2.2, color: eu.textLo)),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final it in allDay)
                  GestureDetector(
                    onTap: () => _openTimelineItem(context, it, skills),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: eu.accentPurple.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: eu.accentPurple.withValues(alpha: 0.40)),
                      ),
                      child: Text(it.title.isEmpty ? '事件' : it.title,
                          style: TextStyle(color: eu.textHi, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
          _sectionTitle(eu, '今日捕捉', trailing: tabRow),
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
    final gridHeight = (_kGridEndHour - _kGridStartHour) * _kHourHeight;
    return SingleChildScrollView(
      controller: _gridScroll,
      child: SizedBox(
        height: gridHeight,
        child: Stack(
          children: [
            // Hour rows + labels
            for (int h = _kGridStartHour; h < _kGridEndHour; h++)
              Positioned(
                top: (h - _kGridStartHour) * _kHourHeight,
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
            // Timed event blocks
            for (final it in timed) _eventBlock(eu, it, skills),
            // "now" line — only on today
            if (isToday)
              Positioned(
                top: (now.hour * 60 + now.minute) / 60.0 * _kHourHeight,
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

  Widget _eventBlock(EurekaColors eu, TimelineItem it, Map<String, SkillMeta> skills) {
    final start = it.effectiveAt;
    final startMin = start.hour * 60 + start.minute;
    var endMin = it.endAt != null ? it.endAt!.hour * 60 + it.endAt!.minute : startMin + 30;
    if (endMin <= startMin) endMin = startMin + 30;
    final top = startMin / 60.0 * _kHourHeight;
    final rawH = (endMin - startMin) / 60.0 * _kHourHeight;
    final height = rawH < 24 ? 24.0 : rawH;
    final isEvent = it.kind == 'event';
    final accent = isEvent ? eu.accentPurple : eu.accentBlue;
    return Positioned(
      top: top,
      left: 62,
      right: 12,
      height: height,
      child: GestureDetector(
        onTap: () => _openTimelineItem(context, it, skills),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(it.title.isEmpty ? (isEvent ? '事件' : '待办') : it.title,
                  maxLines: height > 40 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: eu.textHi, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2)),
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
