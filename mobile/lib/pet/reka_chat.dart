import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/sse_client.dart';
import '../app_events.dart' show navigatorKey, openNotificationTarget;
import '../assets/assets.dart';
import '../data_revision.dart';
import '../pages/chat_page.dart';
import '../pages/create_asset.dart'
    show fetchSkillDefs, SkillDef, renderSpecForSkill, EventForm;
import '../pages/notifications_page.dart' show NotificationsPage;
import '../pages/pet_page.dart';
import '../pages/report_viewer_page.dart';
import '../render/asset_detail_sheet.dart' show AssetEditPage;
import '../render/pet_view.dart';
import '../widgets/asset_picker.dart';
import '../render/skill_card.dart' show accentOf;
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import 'floating_mascot.dart' show mascotSuppressed, releaseMascotSuppress;
import 'pet_controller.dart';
import 'pet_cosmetics.dart' show rekaGlow;
import 'reka_notifications.dart';

/// §9.2 REKA chat — a **bubble conversation popover** anchored to the floating
/// REKA (top layer, not a page). REKA's options + the user's choices happen in
/// the bubbles; heavy edits open as **centered modal popups** (设计稿 doctrine:
/// 居中弹窗、点 scrim 不关、X/取消 才退) that take over the screen.
///  - 快创 → bubble shows ALL types as a tile grid; tap one → centered edit popup.
///  - 洞察 → bubble = 一句话输入 + 快捷 pills + 「手动选择资产」;手动 → 居中弹窗
///    多选(资产卡片)→ 回气泡 → 生成(REKA 小动画)→ 结果气泡 + 查看报告。
class RekaChat extends StatefulWidget {
  final Rect anchor; // floating REKA's rect (global)
  final VoidCallback onClose;

  /// Seed the conversation straight into a function (from the radial menu):
  /// 'create' | 'summarize' | 'notifications'. null → show the root options.
  final String? intent;

  /// §14.5 Type B offer 一键即做: with intent='summarize', skip the wish entry
  /// and run generation immediately with this wish (傻瓜版:点了就开始).
  final String? prefillWish;

  const RekaChat({
    super.key,
    required this.anchor,
    required this.onClose,
    this.intent,
    this.prefillWish,
  });

  @override
  State<RekaChat> createState() => _RekaChatState();
}

enum _K {
  reka,
  user,
  chips,
  createGrid,
  synthEntry,
  status,
  receipt,
  notifPanel,
}

class _Opt {
  final String? icon;
  final String label;
  final VoidCallback onTap;
  _Opt(this.icon, this.label, this.onTap);
}

/// A 快创 type tile (mirrors reka-system.js CREATE_TYPES .ctile).
class _CreateType {
  final String icon;
  final String label;
  final String sub;
  final String accentKey;
  final Widget Function() form;
  _CreateType(this.icon, this.label, this.sub, this.accentKey, this.form);
}

class _Node {
  final _K kind;
  final String? text;
  final List<_Opt>? opts;
  final List<_CreateType>? types;
  _Node(this.kind, {this.text, this.opts, this.types});
}

class _RekaChatState extends State<RekaChat>
    with SingleTickerProviderStateMixin {
  final _api = ApiClient();
  final _pet = PetController.instance;

  // §9.2 v4 — REKA's aura tint, shared by this card + the asset-picker modal.
  Color get _tint {
    final p = _pet.pet;
    return p != null
        ? rekaGlow(p.skin, p.equipped['aura'] ?? 'soft').first
        : const Color(0xFF6F9EFF);
  }

  final _scroll = ScrollController();
  final _input = TextEditingController();
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  final List<_Node> _nodes = [];
  bool _busy = false;
  bool _modal = false; // a centered modal (edit / picker) is taking over

  // 洞察 is a single-card STATE MACHINE (entry → generating → result/error),
  // NOT a growing chat: _synthBase marks where the 洞察 sub-flow begins in
  // _nodes, and each state REPLACES everything from there (see _replaceSynth).
  // This keeps the input/pills from scrolling out of reach and stops the user
  // stacking infinite generations in one bubble.
  int _synthBase = 0;
  String _lastWish = '';

  // 洞察 quick suggestions (reka-system.js SYN_PILLS).
  static const _synthPills = ['这周的运动', '本月的消费', '读书进展', '灵感升华一篇', '和谁聊了什么'];

  // report state
  List<AssetItem> _assets = const [];
  final Set<String> _selectedIds = {};
  List<SkillDef>? _skillDefs;

  @override
  void initState() {
    super.initState();
    switch (widget.intent) {
      case 'create':
        _chooseCreate();
      case 'summarize':
        final wish = widget.prefillWish;
        if (wish != null && wish.isNotEmpty) {
          // Type B offer 接受 → 一键即做:跳过输入,直接生成(显进度→出结果)
          _synthBase = _nodes.length;
          _generate(wish: wish);
        } else {
          _chooseSummarize();
        }
      case 'notifications':
        _notifications();
      default:
        _root();
    }
    _prefetch();
  }

  void _notifications() {
    _add(_Node(_K.notifPanel));
    RekaNotifications.instance.markAllRead();
    _loadNudgePrefs();
  }

  // §14.8 the one master switch (「球球提醒」, default ON) — lives right here in
  // REKA's own notification panel so the people who want it off can find it.
  bool? _nudgesEnabled;

  Future<void> _loadNudgePrefs() async {
    try {
      final r = await _api.getJson('/api/nudges/prefs');
      if (mounted && r is Map) {
        setState(() => _nudgesEnabled = r['nudges_enabled'] != false);
      }
    } catch (_) {
      /* switch row just stays hidden */
    }
  }

  Future<void> _toggleNudges(bool v) async {
    setState(() => _nudgesEnabled = v);
    try {
      await _api.patchJson('/api/nudges/prefs', {'nudges_enabled': v});
    } catch (_) {
      if (mounted) setState(() => _nudgesEnabled = !v); // revert on failure
    }
  }

  Future<void> _prefetch() async {
    try {
      final r = await Future.wait([fetchAssets(_api), fetchSkillDefs(_api)]);
      _assets = r[0] as List<AssetItem>;
      _skillDefs = r[1] as List<SkillDef>;
      // 快创 entered before skills loaded? swap the placeholder grid in now.
      if (mounted &&
          widget.intent == 'create' &&
          _nodes.every((n) => n.kind != _K.createGrid)) {
        setState(() {
          _nodes.removeWhere(
            (n) => n.kind == _K.reka && (n.text?.contains('加载中') ?? false),
          );
          _nodes.add(
            _Node(_K.createGrid, types: _createTypes(r[1] as List<SkillDef>)),
          );
        });
      }
    } catch (_) {
      /* features degrade gracefully */
    }
  }

  @override
  void dispose() {
    _in.dispose();
    _api.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _add(_Node n) {
    setState(() => _nodes.add(n));
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 洞察 state machine: replace the whole 洞察 sub-flow (everything from
  /// _synthBase onward) with `ns`. Preserves any preceding root nodes.
  void _replaceSynth(List<_Node> ns) {
    setState(() {
      if (_synthBase < _nodes.length) {
        _nodes.removeRange(_synthBase, _nodes.length);
      }
      _nodes.addAll(ns);
    });
    _scrollToEnd();
  }

  /// Back to the entry state (fresh scope). Optional [prefill] for the input
  /// (e.g. after「数据太少」the user tweaks the same range).
  void _showSynthEntry({String? prefill}) {
    _selectedIds.clear();
    if (prefill != null && prefill.isNotEmpty) {
      _input.text = prefill;
      _input.selection = TextSelection.collapsed(offset: prefill.length);
    } else {
      _input.clear();
    }
    _replaceSynth([_Node(_K.synthEntry)]);
  }

  void _close() => widget.onClose();

  void _push(Widget page) {
    _close();
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => page));
  }

  // ── steps ─────────────────────────────────────────────────────────────────
  void _root() {
    _add(_Node(_K.reka, text: '我在,想做点什么?'));
    _add(
      _Node(
        _K.chips,
        opts: [
          _Opt('✨', '新建对话', () => _push(const ChatPage(startBlank: true))),
          _Opt('➕', '快创', _chooseCreate),
          _Opt('✦', '洞察 · 升华', _chooseSummarize),
          _Opt('🏝', '我的岛', () => _push(const PetPage())),
        ],
      ),
    );
  }

  void _chooseCreate() {
    if (_busy) return;
    final defs = _skillDefs;
    if (defs == null) {
      _add(_Node(_K.reka, text: '想快速记点什么?(加载中…)'));
      return; // _prefetch swaps in the grid when skills arrive
    }
    _add(_Node(_K.createGrid, types: _createTypes(defs)));
  }

  // 全部类型(事件 + 每个技能),带域色 → 点开**居中弹窗**编辑表单。
  List<_CreateType> _createTypes(List<SkillDef> defs) => [
    _CreateType('📅', '事件', '约定时间', 'purple', () => const EventForm()),
    for (final s in defs)
      _CreateType(
        s.icon,
        s.displayName,
        _createSub(s.name),
        s.accentColor,
        // same AssetEditPage as 编辑 — create = edit with empty data.
        () => AssetEditPage(
          payload: const {},
          cardType: s.name,
          title: '',
          spec: renderSpecForSkill(s),
          displayName: s.displayName,
        ),
      ),
  ];

  String _createSub(String name) =>
      const {
        'event': '约定时间',
        'todo': '要做的事',
        'note': '随手记一笔',
        '随记': '随手记一笔',
        'contact': '一张名片',
        'expense': '一笔花销',
        'book_note': '读书笔记',
        'idea': '一个念头',
      }[name] ??
      '快速记录';

  // §9.2 居中编辑弹窗(替代底部 sheet):form 自带 Scaffold + 标题 + 保存;存后
  // maybePop(result) → 回执气泡 + REKA celebrate。点 scrim 不关(barrierDismissible:false)。
  Future<void> _openCreatePop(Widget form) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final eu = ctx.eu;
    _enterModal(); // hide the bubble + floating ball — the popup takes over
    try {
      final res = await showDialog<Map<String, dynamic>>(
        context: ctx,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (dctx) {
          final mq = MediaQuery.of(dctx);
          return Padding(
            padding: EdgeInsets.fromLTRB(14, 24, 14, mq.viewInsets.bottom + 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: mq.size.height * 0.86,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Material(color: eu.surface, child: form),
                ),
              ),
            ),
          );
        },
      );
      if (res != null && mounted) _onCreated(res);
    } finally {
      _exitModal();
    }
  }

  void _enterModal() {
    mascotSuppressed.value++;
    if (mounted) setState(() => _modal = true);
  }

  void _exitModal() {
    releaseMascotSuppress();
    if (mounted) setState(() => _modal = false);
  }

  void _onCreated(Map<String, dynamic> res) {
    final name = (res['display_name'] as String?) ?? '记录';
    final icon = (res['icon'] as String?) ?? '✅';
    final payload =
        (res['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final detail = _receiptDetail(payload);
    final receipt = detail.isEmpty
        ? '$name · 已闭环 ✓'
        : '$name · $detail · 已闭环 ✓';
    _add(_Node(_K.receipt, text: receipt));
    RekaNotifications.instance.add(
      icon: icon,
      title: '已记下 · $name',
      meta: detail.isEmpty ? null : detail,
    );
  }

  String _receiptDetail(Map<String, dynamic> p) {
    if (p['amount'] != null) return '¥${p['amount']}';
    for (final k in ['content', 'title', 'name', 'quote', 'note']) {
      final v = p[k];
      if (v != null && '$v'.trim().isNotEmpty) {
        final s = '$v'.trim();
        return s.length > 12 ? '${s.substring(0, 12)}…' : s;
      }
    }
    return '';
  }

  void _chooseSummarize() {
    if (_busy) return;
    _synthBase =
        _nodes.length; // 洞察 sub-flow starts here (replace-in-place anchor)
    _add(_Node(_K.synthEntry));
  }

  void _submitWish() {
    if (_busy) return;
    final t = _input.text.trim();
    // Need a description OR a manual selection (or both). A manual pick AUGMENTS
    // the wish — they're sent to _generate together, not one-or-the-other.
    if (t.isEmpty && _selectedIds.isEmpty) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    _generate(wish: t.isEmpty ? null : t);
  }

  // §9.2 资产选择 —— 与 session「关联 context」共用同一个 `AssetPickerPanel`,
  // 只是这里挂在居中弹窗里(session 是底部 sheet)。返回选中的 AssetItem。
  Future<void> _pickAssets() async {
    final ctx = navigatorKey.currentContext;
    if (_busy || ctx == null) return;
    FocusScope.of(context).unfocus();
    final eu = ctx.eu;
    _enterModal();
    List<AssetItem>? picked;
    try {
      picked = await showDialog<List<AssetItem>>(
        context: ctx,
        barrierDismissible: true, // 点 scrim 即关(panel 顶部也有 ✕);返回 null
        barrierColor: Colors.black.withValues(alpha: 0.62),
        builder: (dctx) {
          final mq = MediaQuery.of(dctx);
          return Padding(
            padding: EdgeInsets.fromLTRB(14, 24, 14, mq.viewInsets.bottom + 24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: mq.size.height * 0.86,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Material(
                    color: eu.surfaceRaised,
                    child: AssetPickerPanel(
                      initialSelected: _selectedIds,
                      title: '挑要洞察的资产',
                      confirmVerb: '用这',
                      unit: '条',
                      tint: _tint,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _exitModal();
    }
    if (picked == null || !mounted) return;
    final ids = picked.map((a) => a.id).toSet();
    // Keep the entry card; just record the picks. They render BELOW the input so
    // the user can still add a description and decide whether to generate —
    // manual selection is a HINT to the LLM, not the whole query.
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(ids);
    });
  }

  List<Map<String, dynamic>> _selectedSummary() {
    final byType = <String, List<AssetItem>>{};
    for (final a in _assets.where((a) => _selectedIds.contains(a.id))) {
      byType.putIfAbsent(a.skillName, () => []).add(a);
    }
    return [
      for (final e in byType.entries)
        {
          'type': e.key,
          'count': e.value.length,
          'sample_titles': e.value.take(3).map((a) => a.title).toList(),
        },
    ];
  }

  Future<void> _generate({String? wish}) async {
    if (_busy) return;
    _lastWish = wish?.trim() ?? '';
    setState(() => _busy = true);
    // Switch the card to the generating state (the entry/pills are replaced, so
    // there's nothing to scroll away and no way to fire a second generation).
    final label = _lastWish.isNotEmpty
        ? _lastWish
        : (_selectedIds.isNotEmpty ? '选中的 ${_selectedIds.length} 条' : '最近的记录');
    _replaceSynth([_Node(_K.status, text: '正在撰写《$label》…')]);
    // Buttons that return to a fresh entry so the user can try again (no stacking).
    _Opt againChip(String label) =>
        _Opt('↺', label, () => _showSynthEntry(prefill: _lastWish));
    try {
      final stream = postSse('/api/reports/generate', {
        'user_wish': (wish == null || wish.isEmpty) ? '用选中的资产生成一份报告' : wish,
        if (_selectedIds.isNotEmpty) 'source_asset_ids': _selectedIds.toList(),
        if (_selectedIds.isNotEmpty) 'selected_summary': _selectedSummary(),
      });
      await for (final ev in stream) {
        if (!mounted) return;
        switch (ev.type) {
          case 'status':
            final msg = (ev.json['message'] as String?) ?? '生成中…';
            setState(() {
              final i = _nodes.lastIndexWhere((n) => n.kind == _K.status);
              if (i >= 0) _nodes[i] = _Node(_K.status, text: msg);
            });
          case 'report':
            bumpData();
            final r = ev.json;
            final title = (r['title'] as String?) ?? '报告';
            final html = (r['html'] as String?) ?? '';
            final rid = r['id'] as String?;
            setState(() => _busy = false);
            _replaceSynth([
              _Node(_K.reka, text: '洞察好啦 ✦ 《$title》'),
              _Node(
                _K.chips,
                opts: [
                  _Opt(
                    '📄',
                    '查看报告',
                    () => _push(
                      ReportViewerPage(title: title, html: html, reportId: rid),
                    ),
                  ),
                  _Opt('✦', '再洞察一篇', _showSynthEntry),
                ],
              ),
            ]);
            RekaNotifications.instance.add(
              icon: '📄',
              title: '报告生成',
              meta: title,
              type: 'report_done',
              link: rid ?? '',
            );
            return;
          case 'insufficient':
            setState(() => _busy = false);
            _replaceSynth([
              _Node(
                _K.reka,
                text: (ev.json['message'] as String?) ?? '数据有点少,先多记几条再来洞察吧。',
              ),
              _Node(_K.chips, opts: [againChip('换个范围')]),
            ]);
            return;
          case 'error':
            setState(() => _busy = false);
            _replaceSynth([
              _Node(_K.reka, text: '生成失败：${ev.json['message']}'),
              _Node(_K.chips, opts: [againChip('再试一次')]),
            ]);
            return;
        }
      }
      if (mounted && _busy) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _replaceSynth([
        _Node(_K.reka, text: '生成失败：$e'),
        _Node(_K.chips, opts: [againChip('再试一次')]),
      ]);
    }
  }

  // ── layout ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // While a centered modal (edit / picker) is open it takes over — hide the
    // bubble card + its scrim entirely (no REKA content behind it).
    if (_modal) return const SizedBox.shrink();
    final eu = context.eu;
    final mq = MediaQuery.of(context);
    final sw = mq.size.width, sh = mq.size.height;
    final kb = mq.viewInsets.bottom;
    final a = widget.anchor;
    final alignRight = a.center.dx > sw * 0.5;
    final cardW = (sw * 0.86).clamp(260.0, 360.0);
    // Open ABOVE REKA when it sits in the lower half (or keyboard up), else open
    // BELOW it — so a top-positioned ball doesn't squash the card (设计稿
    // positionBubbles)。
    final kbUp = kb > 0;
    final openAbove = kbUp || a.top > sh * 0.46;
    double? top, bottom;
    double maxH;
    if (kbUp) {
      bottom = kb + 12;
      maxH = sh - bottom - mq.padding.top - 16;
    } else if (openAbove) {
      bottom = (sh - a.top + 10).clamp(12.0, sh - 120);
      maxH = a.top - mq.padding.top - 24;
    } else {
      top = (a.bottom + 10).clamp(mq.padding.top + 8, sh - 140);
      maxH = sh - top - mq.viewPadding.bottom - 16;
    }
    maxH = maxH.clamp(150.0, sh);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: FadeTransition(
              opacity: _in,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.10)),
            ),
          ),
        ),
        Positioned(
          left: alignRight ? null : a.left.clamp(10.0, sw - cardW - 10),
          right: alignRight
              ? (sw - a.right).clamp(10.0, sw - cardW - 10)
              : null,
          top: top,
          bottom: bottom,
          width: cardW,
          child: ScaleTransition(
            scale: Tween(
              begin: 0.85,
              end: 1.0,
            ).animate(CurvedAnimation(parent: _in, curve: Curves.easeOutBack)),
            alignment: openAbove
                ? (alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
                : (alignRight ? Alignment.topRight : Alignment.topLeft),
            child: FadeTransition(
              opacity: _in,
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      constraints: BoxConstraints(
                        maxHeight: maxH.clamp(160.0, sh),
                      ),
                      // §9.2 v4 统一色源 — the whole REKA surface tints to its aura glow.
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          _tint.withValues(alpha: 0.12),
                          eu.surface,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Color.alphaBlend(
                            _tint.withValues(alpha: 0.42),
                            eu.border,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.30),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: _tint.withValues(alpha: 0.30),
                            blurRadius: 26,
                            spreadRadius: -8,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ListView(
                          controller: _scroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(13, 14, 13, 13),
                          children: [for (final n in _nodes) _node(eu, n)],
                        ),
                      ),
                    ),
                    // close X (reka-system.js .bub-close)
                    Positioned(
                      top: -8,
                      right: -8,
                      child: GestureDetector(
                        onTap: _close,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: eu.surfaceRaised,
                            shape: BoxShape.circle,
                            border: Border.all(color: eu.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(Icons.close, size: 14, color: eu.textMid),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _node(EurekaColors eu, _Node n) {
    switch (n.kind) {
      case _K.reka:
        return _textBubble(eu, false, n.text ?? '');
      case _K.user:
        return _textBubble(eu, true, n.text ?? '');
      case _K.chips:
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final o in n.opts!) _chip(eu, o)],
          ),
        );
      case _K.createGrid:
        return _createGridBubble(eu, n.types ?? const []);
      case _K.synthEntry:
        return _synthEntryBubble(eu);
      case _K.status:
        return _statusBubble(eu, n.text ?? '生成中…', working: true);
      case _K.receipt:
        return _statusBubble(eu, n.text ?? '已闭环 ✓');
      case _K.notifPanel:
        return _notifPanel(eu);
    }
  }

  // kicker line (mono, brand-hi) — reka-system.js .bub-title
  Widget _kicker(EurekaColors eu, String text) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: eu.brandHi,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    ),
  );

  // ── 快创 tile grid (reka-system.js .ctgrid) ─────────────────────────────────
  Widget _createGridBubble(EurekaColors eu, List<_CreateType> types) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: eu.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kicker(eu, '快创 · 选个类型'),
          Text(
            '想快速记点什么?选一个,我给你开张卡。',
            style: TextStyle(color: eu.textHi, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            childAspectRatio: 2.55,
            children: [for (final t in types) _createTile(eu, t)],
          ),
        ],
      ),
    );
  }

  Widget _createTile(EurekaColors eu, _CreateType t) {
    final accent = accentOf(t.accentKey, eu).solid;
    return GestureDetector(
      onTap: () => _openCreatePop(t.form()),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: eu.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: eu.border),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(t.icon, style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: eu.textHi,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    t.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: eu.textLo,
                      fontSize: 10,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 洞察 entry (reka-system.js renderSynthBubble) ───────────────────────────
  Widget _synthEntryBubble(EurekaColors eu) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: eu.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kicker(eu, '洞察 · 升华一段'),
          RichText(
            text: TextSpan(
              style: TextStyle(color: eu.textHi, fontSize: 13.5, height: 1.4),
              children: [
                const TextSpan(text: '想洞察什么?'),
                TextSpan(
                  text: '说一句',
                  style: TextStyle(
                    color: eu.brandHi,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const TextSpan(text: '告诉我范围。'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // input row — submit moved to the bottom 「生成洞察」 button
          Container(
            decoration: BoxDecoration(
              color: eu.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: eu.brand.withValues(alpha: 0.45)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _input,
              enabled: !_busy,
              minLines: 1,
              maxLines: 3,
              style: TextStyle(color: eu.textHi, fontSize: 14),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitWish(),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '例如「这周的运动」…',
                hintStyle: TextStyle(color: eu.textLo, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 关联资产 context row —— 像 session 的「关联 context」:输入框下方放
          // 「+ 手动选择资产」+ 已选 chips(可点 × 取消),作为对描述的定向补充。
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GestureDetector(
                onTap: _pickAssets,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: eu.textLo),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 13, color: eu.textMid),
                      const SizedBox(width: 3),
                      Text(
                        '手动选择资产',
                        style: TextStyle(color: eu.textMid, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              for (final a in _assets.where((a) => _selectedIds.contains(a.id)))
                GestureDetector(
                  onTap: () => setState(() => _selectedIds.remove(a.id)),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 170),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _tint.withValues(alpha: 0.34)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            a.title.isEmpty ? '记录' : a.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: eu.textHi, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.close, size: 12, color: eu.textMid),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (_selectedIds.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '已选 ${_selectedIds.length} 条 · 会结合你上面的描述一起洞察',
              style: TextStyle(color: eu.textLo, fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in _synthPills)
                GestureDetector(
                  onTap: () {
                    _input.text = p;
                    _input.selection = TextSelection.collapsed(
                      offset: p.length,
                    );
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: eu.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: eu.border),
                    ),
                    child: Text(
                      p,
                      style: TextStyle(color: eu.textHi, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // bottom full-width submit (was the inline ↑) — generates with the
          // description AND any manual picks together.
          GestureDetector(
            onTap: _busy ? null : _submitWish,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: eu.brand,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '生成洞察',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// §14.8「Reka提醒」总开关行 — shown once prefs load; toggles server-side.
  Widget _nudgeSwitchRow(EurekaColors eu) {
    final v = _nudgesEnabled;
    if (v == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 2),
      padding: const EdgeInsets.fromLTRB(12, 2, 6, 2),
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        children: [
          const Text('🐾', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reka提醒',
              style: TextStyle(
                color: eu.textHi,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.78,
            child: Switch(
              value: v,
              activeThumbColor: eu.brand,
              onChanged: _toggleNudges,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notifPanel(EurekaColors eu) {
    return AnimatedBuilder(
      animation: RekaNotifications.instance,
      builder: (context, _) {
        final items = RekaNotifications.instance.items;
        const max = 6; // 面板最多展示 max 条；更多走「查看全部」→ 独立通知页
        if (items.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _textBubble(eu, false, '还没有通知 🛎️\n记录、完成、生成报告都会出现在这里。'),
              _nudgeSwitchRow(eu),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _nudgeSwitchRow(eu),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: eu.surfaceRaised,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: eu.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                    child: Text(
                      '通知 · ${items.length}',
                      style: TextStyle(
                        color: eu.textMid,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (final n in items.take(max))
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Tap → open the target (report / 闪念 session / calendar) + mark
                      // read + close the REKA menu. Non-tappable notes do nothing.
                      onTap: n.tappable
                          ? () {
                              RekaNotifications.instance.markReadNote(n);
                              _close();
                              openNotificationTarget(n.type, n.link);
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.icon, style: const TextStyle(fontSize: 15)),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.title,
                                    style: TextStyle(
                                      color: eu.textHi,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (n.meta != null && n.meta!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Text(
                                        n.meta!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: eu.textMid,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (n.tappable)
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: eu.textLo,
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (items.length > max)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _close();
                        navigatorKey.currentState?.push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsPage(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 8,
                          left: 4,
                          right: 4,
                          bottom: 2,
                        ),
                        child: Row(
                          children: [
                            Text(
                              '查看全部 ${items.length} 条',
                              style: TextStyle(
                                color: eu.brand,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: eu.brand,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _textBubble(EurekaColors eu, bool user, String text) {
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: user ? eu.brand.withValues(alpha: 0.16) : eu.surfaceRaised,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(15),
            topRight: const Radius.circular(15),
            bottomLeft: Radius.circular(user ? 15 : 5),
            bottomRight: Radius.circular(user ? 5 : 15),
          ),
          border: Border.all(
            color: user ? eu.brand.withValues(alpha: 0.34) : eu.border,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(color: eu.textHi, fontSize: 14, height: 1.4),
        ),
      ),
    );
  }

  Widget _chip(EurekaColors eu, _Opt o) {
    return GestureDetector(
      onTap: _busy ? null : o.onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: eu.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (o.icon != null) ...[
              Text(o.icon!, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
            ],
            Text(
              o.label,
              style: TextStyle(
                color: eu.textHi,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // [working] = mid-generation (calm pet + animated typing dots);
  // false = a one-shot receipt (已闭环 ✓ → a quick celebrate, no dots).
  Widget _statusBubble(EurekaColors eu, String text, {bool working = false}) {
    final p = _pet.pet;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(10, 9, 14, 9),
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: eu.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p != null)
              SizedBox(
                width: 34,
                height: 34,
                // 'idle' (not 'celebrate') while working — celebrate's particles
                // spill out of a small bubble; the typing dots carry the motion.
                child: PetView(
                  genome: p.genome,
                  scale: 1.3,
                  state: working ? 'idle' : 'celebrate',
                ),
              )
            else
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: eu.brand,
                ),
              ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: eu.textHi, fontSize: 13.5, height: 1.3),
              ),
            ),
            if (working) ...[
              const SizedBox(width: 8),
              _TypingDots(color: eu.textLo),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small three-dot "working" indicator (staggered pulse). Self-contained so it
/// owns its repeating controller; used in the 洞察 generating status bubble.
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Opacity(
              opacity:
                  (0.3 +
                          0.7 *
                              ((math.sin(_c.value * 2 * math.pi - i * 0.9) +
                                      1) /
                                  2))
                      .clamp(0.0, 1.0),
              child: Container(
                width: 4.5,
                height: 4.5,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
