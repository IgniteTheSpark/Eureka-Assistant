import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../chat/markdown_text.dart';
import '../data_revision.dart';
import '../pages/chat_page.dart';
import '../pages/create_asset.dart'
    show EventForm, ContactForm, kSocialPlatforms;
import '../pages/report_viewer_page.dart';
import '../pages/session_detail_page.dart';
import '../theme/app_theme.dart';
import '../theme/domains.dart';
import '../theme/eureka_colors.dart';
import 'render_spec.dart';
import 'skill_card.dart' show accentOf, SkillCard;

/// Asset detail — opened by tapping any [SkillCard]. A general scheme for ANY
/// skill (an asset is a bag of fields; long content is just one possible field):
/// **one sheet, two states** (a `DraggableScrollableSheet` that peeks at ~半屏
/// and drags / 展开全文 to ~满屏 for reading). Hierarchy = hero(主→title · 副→
/// subtitle, shown once) → structured 信息 fields → long-text fields as folded
/// markdown bodies → a quiet one-line source. Actions live in a sticky bottom bar.
void showAssetDetail(
  BuildContext context, {
  required CardData data,
  required Map<String, dynamic> payload,
  required String cardType,
  String? assetId,
  String? sessionId,
  RenderSpec? spec,
}) {
  final eu = context.eu;
  final controller = DraggableScrollableController();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      controller: controller,
      initialChildSize: 0.62,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.62, 0.95],
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: eu.surfaceRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: _AssetView(
          data: data,
          payload: payload,
          cardType: cardType,
          assetId: assetId,
          sessionId: sessionId,
          spec: spec,
          scrollController: scrollController,
          onExpand: () => controller.animateTo(
            0.95,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        ),
      ),
    ),
  );
}

class _AssetView extends StatefulWidget {
  final CardData data;
  final Map<String, dynamic> payload;
  final String cardType;
  final String? assetId;
  final String? sessionId;
  final RenderSpec? spec;
  final ScrollController scrollController;
  final VoidCallback onExpand;
  const _AssetView({
    required this.data,
    required this.payload,
    required this.cardType,
    required this.assetId,
    required this.sessionId,
    required this.scrollController,
    required this.onExpand,
    this.spec,
  });

  @override
  State<_AssetView> createState() => _AssetViewState();
}

class _AssetViewState extends State<_AssetView> {
  final _api = ApiClient();
  bool _busy = false;
  bool? _doneOverride; // optimistic 完成 state for checkable (todo) cards
  late String? _domain = widget.data.domain;

  // Canonical asset data. Seeded from the (possibly partial / stale) card the
  // caller passed, then refreshed from the server in initState so EVERY surface
  // that opens this sheet — 资产库 / 会话内卡片 / 聊天 / 通知 — renders the SAME
  // full content, and 编辑 prefills from the complete payload. See _hydrate.
  late Map<String, dynamic> _payload = Map<String, dynamic>.from(
    widget.payload,
  );
  late CardData _data = widget.data;

  CardData get data => _data;
  Map<String, dynamic> get payload => _payload;
  String get cardType => widget.cardType;

  bool get _deletable => widget.assetId != null;
  bool get _editable => widget.assetId != null;
  // Checkable (todo) cards carry a non-null checkDone (set by buildCard) and a
  // real asset id → the 完成 affordances render + toggle.
  bool get _checkable => data.checkDone != null && widget.assetId != null;
  bool get _done => _doneOverride ?? (data.checkDone == true);
  bool get _domainEditable =>
      widget.assetId != null &&
      cardType != 'event' &&
      cardType != 'contact' &&
      cardType != 'task';

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  // Single source of truth: re-fetch the asset by id so the detail never renders
  // the stale snapshot a session message happened to carry — that's why a card
  // looked different in a 会话 vs the 资产库. On any failure (offline / 404) we
  // silently keep the passed payload, so this is never worse than before.
  Future<void> _hydrate() async {
    final id = widget.assetId;
    if (id == null) return;
    try {
      if (cardType == 'event') {
        final res = await _api.getJson('/api/events/$id');
        final event = (res is Map ? (res['event'] ?? res) : null) as Map?;
        final full = event?.cast<String, dynamic>();
        if (full == null || !mounted) return;
        setState(() {
          _payload = {'card_type': 'event', ...full};
          _data = buildCard(
            payload: _payload,
            spec: synthesizeSpec('event'),
            displayName: 'event',
          );
        });
        return;
      }
      if (cardType == 'contact') {
        final res = await _api.getJson('/api/contacts/$id');
        final contact = (res is Map ? (res['contact'] ?? res) : null) as Map?;
        final full = contact?.cast<String, dynamic>();
        if (full == null || !mounted) return;
        setState(() {
          _payload = {'card_type': 'contact', ...full};
          _data = buildCard(
            payload: _payload,
            spec: synthesizeSpec('contact'),
            displayName: 'contact',
          );
        });
        return;
      }
      // Asset-backed cards may be partial session snapshots. Re-fetch so detail
      // and edit always use the complete canonical payload.
      if (cardType == 'task') return;
      final res = await _api.getJson('/api/assets/$id');
      final asset = (res is Map ? res['asset'] : null) as Map?;
      final full = (asset?['payload'] as Map?)?.cast<String, dynamic>();
      if (full == null || !mounted) return;
      setState(() {
        _payload = full;
        final dm = asset?['domain'] as String?;
        if (dm != null) _domain = dm;
        final spec = widget.spec ?? synthesizeSpec(cardType);
        _data = buildCard(
          payload: full,
          spec: spec,
          displayName: widget.data.title,
        ).copyWith(domain: _domain);
      });
    } catch (_) {
      // keep widget.payload — no-op
    }
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  /* ── actions ─────────────────────────────────────────────────────────────── */

  String _deletePath() {
    final id = widget.assetId;
    switch (cardType) {
      case 'event':
        return '/api/events/$id';
      case 'contact':
        return '/api/contacts/$id';
      default:
        return '/api/assets/$id';
    }
  }

  Future<void> _confirmDelete() async {
    final eu = context.eu;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: eu.surfaceRaised,
        title: Text('删除', style: TextStyle(color: eu.textHi, fontSize: 17)),
        content: Text(
          '删除后不可恢复，确定删除这条记录吗？',
          style: TextStyle(color: eu.textMid, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: eu.accentRed)),
          ),
        ],
      ),
    );
    if (ok == true) _delete();
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.deleteJson(_deletePath());
      bumpData();
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openSource() {
    final sid = widget.sessionId;
    if (sid == null || sid.isEmpty) return;
    final nav = Navigator.of(context);
    nav.maybePop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => SessionDetailPage(sessionId: sid, title: '来源会话'),
      ),
    );
  }

  /// §6.13 溯源 — a todo created from a report's「✦ 接下来」opens its origin report.
  Future<void> _openSourceReport() async {
    final id = payload['source_report_id'] as String?;
    if (id == null || id.isEmpty) return;
    try {
      final res = await _api.getJson('/api/reports/$id');
      final r = (res is Map ? res['report'] : null) as Map?;
      final html = r?['html'] as String?;
      if (html == null || html.isEmpty || !mounted) return;
      final nav = Navigator.of(context);
      nav.maybePop();
      nav.push(
        MaterialPageRoute(
          builder: (_) => ReportViewerPage(
            title: (r?['title'] as String?) ?? '报告',
            html: html,
            reportId: id,
          ),
        ),
      );
    } catch (_) {
      // report may have been deleted — the quiet line just does nothing
    }
  }

  String _subjectType() => switch (cardType) {
    'event' => 'event',
    'contact' => 'contact',
    _ => 'asset',
  };

  void _discuss() {
    final id = widget.assetId;
    if (id == null) return;
    final nav = Navigator.of(context);
    nav.maybePop();
    nav.push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          subjectType: _subjectType(),
          subjectId: id,
          subjectLabel: data.title,
        ),
      ),
    );
  }

  // 完成 / 撤销完成 — same PUT status path the 资产库 card uses; optimistic.
  Future<void> _toggleDone() async {
    final id = widget.assetId;
    if (id == null) return;
    final next = !_done;
    setState(() => _doneOverride = next);
    try {
      await _api.putJson('/api/assets/$id', {
        'payload_patch': {'status': next ? 'done' : 'pending'},
      });
      bumpData();
    } catch (_) {
      if (mounted) setState(() => _doneOverride = !next); // revert on failure
    }
  }

  // §4 长内容编辑：全屏编辑页(支持 md 文档),而非二次弹出的底部 sheet。
  Future<void> _edit() async {
    final nav = Navigator.of(context);
    // event/contact are 真身 entities (not assets) — edit them with their
    // dedicated forms (proper date/time pickers, end>start validation, flat
    // PUT to /api/events|contacts). Everything else uses the type-aware
    // asset editor (controls driven by the skill's payload_schema).
    final Widget editor = switch (cardType) {
      'event' => EventForm(eventId: widget.assetId, existing: payload),
      'contact' => ContactForm(contactId: widget.assetId, existing: payload),
      _ => AssetEditPage(
        assetId: widget.assetId!,
        payload: payload,
        cardType: cardType,
        spec: widget.spec,
        title: data.title,
        initialDomain: data.domain,
      ),
    };
    final changed = await nav.push<bool>(
      MaterialPageRoute(builder: (_) => editor),
    );
    if (changed == true && mounted) {
      bumpData();
      nav.maybePop(); // close the sheet → back to the refreshed list
    }
  }

  Future<void> _pickDomain() async {
    final eu = context.eu;
    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: eu.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择领域',
                style: TextStyle(
                  color: eu.textHi,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in kDomains)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: domainColor(
                            eu,
                            d,
                          ).withValues(alpha: _domain == d ? 0.24 : 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: domainColor(
                              eu,
                              d,
                            ).withValues(alpha: _domain == d ? 0.6 : 0.26),
                          ),
                        ),
                        child: Text(
                          '${domainIcon(d)} $d',
                          style: TextStyle(
                            color: domainColor(eu, d),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (_domain != null)
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, '__clear__'),
                  child: Text(
                    '清除领域',
                    style: TextStyle(color: eu.accentRed, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final newDomain = picked == '__clear__' ? null : picked;
    if (newDomain == _domain) return;
    setState(() => _domain = newDomain);
    try {
      await _api.putJson('/api/assets/${widget.assetId}', {
        'domain': newDomain,
      });
      bumpData();
    } catch (_) {
      /* keep optimistic value; revision refresh will reconcile */
    }
  }

  /* ── build ───────────────────────────────────────────────────────────────── */

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final hasActions = widget.assetId != null;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            padding: EdgeInsets.only(
              bottom: hasActions ? 96 + bottomInset : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: eu.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        cardType.toUpperCase(),
                        style: euMono(
                          fontSize: 10.5,
                          letterSpacing: 1.6,
                          color: eu.textLo,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        behavior: HitTestBehavior.opaque,
                        child: Icon(Icons.close, size: 19, color: eu.textMid),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _hero(eu),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(height: 1, color: eu.rule),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _bodyParts(eu),
                  ),
                ),
                _sourceLine(eu),
              ],
            ),
          ),
        ),
        if (hasActions)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _stickyActions(eu, bottomInset),
          ),
      ],
    );
  }

  // icon + title (size scales for short numeric heroes) + subtitle + domain.
  // P3 联系人头像:首字母 monogram + 名字 hash 派生色环,替掉灰色 👤 蛋。
  Widget _monogramAvatar(EurekaColors eu, String name) {
    final t = name.trim();
    final initial = t.runes.isEmpty
        ? '?'
        : String.fromCharCode(t.runes.first).toUpperCase();
    final palette = [
      eu.accentBlue,
      eu.accentPurple,
      eu.accentGreen,
      eu.accentAmber,
      eu.accentCyan,
      eu.brand,
    ];
    final c = palette[t.hashCode.abs() % palette.length];
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.withValues(alpha: 0.16),
        border: Border.all(color: c.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Text(
        initial,
        style: TextStyle(color: c, fontSize: 20, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _hero(EurekaColors eu) {
    final a = accentOf(data.accentColor, eu);
    final bigTitle =
        widget.spec?.primaryFormat == 'currency' ||
        data.title.runes.length <= 4;
    final iconTile = widget.cardType == 'contact'
        ? _monogramAvatar(eu, data.title)
        : Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [a.bg, Colors.transparent]),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: a.edge),
            ),
            child: Opacity(
              opacity: _done ? 0.4 : 1.0,
              child: Text(data.icon, style: const TextStyle(fontSize: 23)),
            ),
          );
    // checkable (todo) → the icon doubles as a tappable 完成 checkbox.
    final iconWidget = !_checkable
        ? iconTile
        : SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                iconTile,
                Positioned(
                  right: -5,
                  bottom: -5,
                  child: GestureDetector(
                    onTap: _busy ? null : _toggleDone,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _done ? eu.accentGreen : eu.surfaceRaised,
                        border: Border.all(color: eu.accentGreen, width: 2),
                      ),
                      child: _done
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data.title,
                    style: TextStyle(
                      color: _done ? eu.textMid : eu.textHi,
                      fontSize: bigTitle ? 30 : 22,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      decoration: _done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (data.subtitle.isNotEmpty && !_secondaryIsBody) ...[
                    const SizedBox(height: 3),
                    Text(
                      data.subtitle,
                      style: TextStyle(color: eu.textMid, fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (_domainEditable || isDomain(_domain)) ...[
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // §8 领域
              if (_domainEditable)
                GestureDetector(
                  onTap: _busy ? null : _pickDomain,
                  behavior: HitTestBehavior.opaque,
                  child: isDomain(_domain)
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DomainChip(_domain),
                            const SizedBox(width: 6),
                            Icon(Icons.edit, size: 12, color: eu.textLo),
                          ],
                        )
                      : _addChip(eu, '＋ 领域'),
                )
              else if (isDomain(_domain))
                DomainChip(_domain),
            ],
          ),
        ],
      ],
    );
  }

  Widget _addChip(EurekaColors eu, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: eu.border),
    ),
    child: Text(label, style: TextStyle(color: eu.textLo, fontSize: 11.5)),
  );

  // Sticky bottom action bar (讨论 / 编辑 / 删除). A short fade strip lets the
  // scrolling content dissolve INTO the bar, then a SOLID bar sits behind the
  // buttons so nothing bleeds through them (the 讨论 ghost button used to be
  // see-through over a transparent gradient).
  Widget _stickyActions(EurekaColors eu, double bottomInset) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [eu.surfaceRaised.withValues(alpha: 0), eu.surfaceRaised],
            ),
          ),
        ),
        Container(
          color: eu.surfaceRaised,
          padding: EdgeInsets.fromLTRB(18, 0, 18, 16 + bottomInset),
          child: Row(
            children: [
              // 完成 is the primary action for todos; 编辑 drops to a ghost button.
              if (_checkable) ...[
                Expanded(
                  flex: 13,
                  child: _barBtn(
                    eu,
                    _done ? Icons.undo : Icons.check,
                    _done ? '撤销完成' : '完成',
                    _done ? eu.textMid : Colors.white,
                    !_done,
                    _busy ? null : _toggleDone,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                flex: 10,
                child: _barBtn(
                  eu,
                  Icons.auto_awesome,
                  '讨论',
                  eu.brand,
                  false,
                  _busy ? null : _discuss,
                ),
              ),
              if (_editable) ...[
                const SizedBox(width: 9),
                Expanded(
                  flex: 11,
                  child: _barBtn(
                    eu,
                    Icons.edit_outlined,
                    '编辑',
                    _checkable ? eu.textHi : Colors.white,
                    !_checkable,
                    _busy ? null : _edit,
                  ),
                ),
              ],
              if (_deletable) ...[
                const SizedBox(width: 9),
                _barIcon(
                  eu,
                  Icons.delete_outline,
                  eu.accentRed,
                  _busy ? null : _confirmDelete,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _barBtn(
    EurekaColors eu,
    IconData icon,
    String label,
    Color fg,
    bool filled,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // ghost (non-filled) buttons get a real surface fill so content can't
          // bleed through them.
          color: filled ? eu.brand : eu.surface,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: eu.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barIcon(
    EurekaColors eu,
    IconData icon,
    Color color,
    VoidCallback? onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: eu.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: eu.border),
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }

  /* ── body: structured 信息 fields + markdown doc blocks ──────────────────── */

  // A field is "正文/body" text → render it as a full 内容 block (regardless of
  // length, never truncated) instead of a one-line hero subtitle. Uses the SAME
  // body-key set the editor uses (_isDocKey: content/note/description/…), plus
  // schema-declared `long` fields and `truncate_*` formats (notes.content is
  // secondary_format: truncate_40). Keeps 展示 and 编辑 on identical field logic.
  bool _isBodyField(String key) {
    if (_isDocKey(key)) return true;
    final s = widget.spec;
    if (s == null) return false;
    if (s.longFields.contains(key)) return true;
    final fmt = s.formatForField(key);
    return fmt != null && fmt.startsWith('truncate_');
  }

  // The secondary (hero subtitle) is actually body text → don't also show it as
  // a truncated subtitle; it renders below as the full 内容 block.
  bool get _secondaryIsBody {
    final sk = widget.spec?.secondaryField;
    return sk != null && _isBodyField(sk);
  }

  // 主→title shown ONCE in the hero (never repeated). 副 shows in the hero only
  // when it's a short attribute; body副 (e.g. notes.content) renders below.
  // Short fields → 信息 rows; long-text / body fields → md 内容 blocks.
  List<Widget> _bodyParts(EurekaColors eu) {
    final primaryKey = widget.spec?.primaryField;
    final secondaryKey = widget.spec?.secondaryField;
    final stats = <({String label, Widget value})>[];
    final docs = <Widget>[];

    payload.forEach((key, value) {
      if (_skip(key, value)) return;
      if (cardType == 'contact' &&
          (key == 'name' || key == 'company' || key == 'title')) {
        return;
      }
      final label = widget.spec?.fieldLabels[key] ?? _label(key, cardType);

      // 名片 socials → emoji + 平台 + handle rows (fixed supported set).
      if (key == 'socials' && value is Map && value.isNotEmpty) {
        final block = _socialsBlock(eu, value);
        if (block != null) stats.add((label: '社交媒体', value: block));
        return;
      }
      // 名片 notes → markdown doc (在哪相遇 / 怎么认识…), not chips.
      if (cardType == 'contact' &&
          key == 'notes' &&
          value is List &&
          value.isNotEmpty) {
        final md = value.map((l) => '- $l').join('\n');
        docs.add(_DocBlock(label: label, text: md, onExpand: widget.onExpand));
        return;
      }

      if (value is List) {
        stats.add((label: label, value: _chips(eu, value)));
        return;
      }
      // body text (or just-long text) → full 内容 block — but never the primary,
      // which is already the big hero title.
      if (value is String &&
          value.trim().isNotEmpty &&
          key != primaryKey &&
          (_isLongText(value) || _isBodyField(key))) {
        docs.add(
          _DocBlock(label: label, text: value, onExpand: widget.onExpand),
        );
        return;
      }
      // 主 / 副 already live in the hero — don't duplicate them in the 信息 list.
      if (key == primaryKey || key == secondaryKey) return;

      final fmt = widget.spec?.formatForField(key) ?? _inferFormat(key, value);
      final shown = applyFormat(value, fmt);
      final text = shown.isEmpty ? '$value' : shown;
      stats.add((
        label: label,
        value: Text(
          text,
          style: TextStyle(color: eu.textHi, fontSize: 15, height: 1.4),
        ),
      ));
    });

    return [
      if (stats.isNotEmpty) _infoList(eu, stats),
      for (var i = 0; i < docs.length; i++) ...[
        SizedBox(height: (i == 0 && stats.isEmpty) ? 0 : 18),
        docs[i],
      ],
    ];
  }

  // 信息 fields as a quiet label-over-value list (not a heavy boxed panel).
  Widget _infoList(EurekaColors eu, List<({String label, Widget value})> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.label,
                  style: TextStyle(
                    color: eu.textLo,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                r.value,
              ],
            ),
          ),
      ],
    );
  }

  Widget _chips(EurekaColors eu, List value) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final it in value)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: eu.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: eu.border),
            ),
            child: Text(
              _listEntry(it),
              style: TextStyle(color: eu.text, fontSize: 14),
            ),
          ),
      ],
    );
  }

  // 名片 socials block: one row per platform (emoji + 平台名 + 可选中的 handle),
  // in the fixed kSocialPlatforms order. Returns null if nothing displayable.
  Widget? _socialsBlock(EurekaColors eu, Map socials) {
    final rows = <Widget>[];
    for (final p in kSocialPlatforms) {
      final h = socials[p.key];
      if (h == null || '$h'.trim().isEmpty) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: Text(
                  p.label,
                  style: TextStyle(color: eu.textLo, fontSize: 13, height: 1.4),
                ),
              ),
              Expanded(
                child: SelectableText(
                  '$h'.trim(),
                  style: TextStyle(color: eu.textHi, fontSize: 15, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) return null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  // Quiet one-line source. §四: manual (no session) shows nothing.
  Widget _sourceLine(EurekaColors eu) {
    // §6.13: a todo born from a report's action bar shows its origin first.
    final reportTitle = payload['source_report_title'] as String?;
    final reportId = payload['source_report_id'] as String?;
    if (reportId != null && reportId.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 1, color: eu.rule),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _openSourceReport,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text('✦', style: TextStyle(color: eu.brand, fontSize: 13)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '来自报告《${(reportTitle ?? '').isEmpty ? '报告' : reportTitle}》·',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: eu.textLo, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '查看报告',
                    style: TextStyle(
                      color: eu.brand,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 15, color: eu.brand),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final hasSession = widget.sessionId != null && widget.sessionId!.isNotEmpty;
    if (!hasSession) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: eu.rule),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _openSource,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  '⚡',
                  style: TextStyle(color: eu.accentAmber, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  '由「闪念 / 对话」整理 ·',
                  style: TextStyle(color: eu.textLo, fontSize: 12),
                ),
                const SizedBox(width: 6),
                Text(
                  '查看原始记录',
                  style: TextStyle(
                    color: eu.brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.chevron_right, size: 15, color: eu.brand),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _listEntry(dynamic it) {
    if (it == null) return '—';
    if (it is String || it is num) return '$it';
    if (it is Map) {
      final name = it['name'] ?? it['title'] ?? it['display_name'];
      final role = it['role'];
      if (name != null && role != null) return '$name ($role)';
      if (name != null) return '$name';
    }
    return '$it';
  }
}

/* ── long-content markdown block (peek → 展开全文) ─────────────────────────── */

/// A long-text field rendered as **markdown**, folded to ~132px with a bottom
/// fade + a centered 展开全文 pill. Expanding also asks the sheet to pull to full
/// ([onExpand]) so the reader gets the whole screen.
class _DocBlock extends StatefulWidget {
  final String label;
  final String text;
  final VoidCallback? onExpand;
  const _DocBlock({required this.label, required this.text, this.onExpand});

  @override
  State<_DocBlock> createState() => _DocBlockState();
}

class _DocBlockState extends State<_DocBlock> {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) widget.onExpand?.call();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final md = MarkdownText(
      widget.text,
      baseStyle: TextStyle(color: eu.text, fontSize: 15, height: 1.62),
    );
    // Short body text (e.g. a one-line 随记) shows in full — the clip + fade +
    // 展开全文 toggle only makes sense for genuinely long documents.
    if (!_isLongText(widget.text)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              color: eu.textLo,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          md,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: eu.textLo,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_expanded)
          md
        else
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0.0, 0.66, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ClipRect(
              child: SizedBox(
                height: 132,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: md,
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: eu.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: eu.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? '收起' : '展开全文',
                    style: TextStyle(
                      color: eu.textMid,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: eu.textMid,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ── full-screen editor (md 文档 · 短字段 + 长文共存) ──────────────────────── */

/// Full-screen asset editor. A real title field becomes a big document-title
/// input; long/doc fields get a markdown editor with 编辑/预览; short fields get
/// compact inputs. No formatting toolbar — users type markdown syntax directly.
/// Shared CREATE + EDIT form for asset-backed skills. `assetId == null` → CREATE
/// (empty/preset payload → POST /api/assets, pops a receipt map); otherwise EDIT
/// (prefilled → PUT payload_patch). **Same UI both ways** — create is just edit
/// with empty data, so 快创 and 编辑 never drift apart (one component).
/// event/contact are NOT assets → they keep their own EventForm/ContactForm.
class AssetEditPage extends StatefulWidget {
  final String? assetId; // null = CREATE
  final Map<String, dynamic> payload;
  final String cardType; // skill machine_name (= user_skill_name for assets)
  final RenderSpec? spec;
  final String title;
  final String? initialDomain; // edit: the asset's domain; create: null
  final String? displayName; // skill 中文名 (appBar + create receipt)
  final DateTime? presetDate; // create: preset date/datetime fields (empty-day)
  const AssetEditPage({
    super.key,
    this.assetId,
    required this.payload,
    required this.cardType,
    required this.title,
    this.spec,
    this.initialDomain,
    this.displayName,
    this.presetDate,
  });

  bool get isCreate => assetId == null;

  @override
  State<AssetEditPage> createState() => _AssetEditPageState();
}

class _AssetEditPageState extends State<AssetEditPage> {
  final _api = ApiClient();
  // Type-aware field model: each editable field is stored by its kind so the
  // editor can render the right control (date picker / toggle / chips / md /
  // text) and serialize back correctly. Order = schema order ∪ orphan payload.
  late final List<String> _fields = _orderedKeys();
  final Map<String, String> _types = {}; // field → resolved edit kind
  final Map<String, TextEditingController> _ctrls = {}; // string / number
  final Map<String, DateTime?> _dates = {}; // datetime / date
  final Map<String, bool> _bools = {}; // boolean
  final Map<String, List<String>> _lists = {}; // array (e.g. tags)
  late String? _domain = widget.initialDomain;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final k in _fields) {
      final v = widget.payload[k];
      final t = _typeOf(k, v);
      _types[k] = t;
      switch (t) {
        case 'datetime':
        case 'date':
          var d = (v is String && v.isNotEmpty)
              ? DateTime.tryParse(v.replaceAll('Z', '+00:00'))?.toLocal()
              : null;
          // empty-day create presets the date/time fields to that day.
          if (d == null && widget.isCreate && widget.presetDate != null) {
            d = widget.presetDate;
          }
          _dates[k] = d;
        case 'boolean':
          _bools[k] = v == true || v == 1 || v == '1' || v == 'true';
        case 'array':
          _lists[k] = v is List ? v.map((e) => '$e').toList() : <String>[];
        default:
          _ctrls[k] = TextEditingController(text: v == null ? '' : '$v')
            ..addListener(_rebuild);
      }
    }
  }

  // Edit fields = the skill's FULL schema (so every asset edits the same
  // structure, empty included, fillable) ∪ orphan payload fields (left over
  // from a skill regenerate). Plumbing keys + nested maps dropped.
  List<String> _orderedKeys() {
    final out = <String>[];
    void add(String k, {required bool fromSchema}) {
      if (out.contains(k) || _skipKeys.contains(k)) return;
      final v = widget.payload[k];
      if (v is Map) return;
      if (!fromSchema && _skip(k, v)) return; // orphans: skip empty/plumbing
      out.add(k);
    }

    for (final k in widget.spec?.schemaFields ?? const <String>[]) {
      add(k, fromSchema: true);
    }
    widget.payload.forEach((k, v) => add(k, fromSchema: false));
    return out;
  }

  // A field's edit kind: schema `type` wins; else infer from key / value so
  // entity fields (start_at / all_day / due_date) get the right control even
  // without a payload_schema.
  String _typeOf(String key, dynamic v) {
    final t = widget.spec?.fieldTypes[key];
    if (t != null && t != 'uuid') return t;
    if (v is bool) return 'boolean';
    if (v is List) return 'array';
    if (key == 'all_day' || key == 'done' || key == 'completed') {
      return 'boolean';
    }
    if (key.endsWith('_at') ||
        key.endsWith('_date') ||
        key == 'date' ||
        key == 'due') {
      return 'datetime';
    }
    if (v is String && _isoDt.hasMatch(v)) return 'datetime';
    return 'string';
  }

  bool _isDateOnly(String k) => _types[k] == 'date';

  void _rebuild() {
    if (mounted) setState(() {});
  }

  // Live payload from the current field values (overlaid on the original), for
  // the card preview that updates as you type.
  Map<String, dynamic> _currentPayload() {
    final p = Map<String, dynamic>.from(widget.payload);
    _ctrls.forEach((k, c) => p[k] = c.text);
    _dates.forEach(
      (k, d) =>
          p[k] = d == null ? '' : _isoBeijing(d, dateOnly: _isDateOnly(k)),
    );
    _bools.forEach((k, b) => p[k] = b);
    _lists.forEach((k, l) => p[k] = l);
    return p;
  }

  // Serialize a picked wall-clock time as Beijing (+08:00), matching the backend
  // convention; date-only fields emit a bare YYYY-MM-DD.
  static String _isoBeijing(DateTime d, {bool dateOnly = false}) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${d.year}-${two(d.month)}-${two(d.day)}';
    return dateOnly ? date : '${date}T${two(d.hour)}:${two(d.minute)}:00+08:00';
  }

  Map<String, dynamic> _previewCard() {
    final p = _currentPayload();
    if (widget.cardType == 'event' ||
        widget.cardType == 'contact' ||
        widget.cardType == 'task') {
      return {'card_type': widget.cardType, ...p};
    }
    return {'user_skill_name': widget.cardType, 'payload': p};
  }

  // The field to elevate to a big document-title input: the skill's textual
  // primary field (book_title, title…), else a real title/name. Never a numeric
  // / currency primary (e.g. expense's ¥amount).
  String? get _titleKey {
    final p = widget.spec?.primaryField;
    if (p != null &&
        _ctrls.containsKey(p) &&
        !_isDocKey(p) &&
        widget.spec?.primaryFormat != 'currency') {
      final v = _ctrls[p]!.text;
      if (!_isLongText(v) && double.tryParse(v.trim()) == null) return p;
    }
    for (final k in const ['title', 'name']) {
      final c = _ctrls[k];
      if (c != null && !_isDocKey(k) && !_isLongText(c.text)) return k;
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _api.close();
    super.dispose();
  }

  bool _fieldEmpty(String k) {
    if (_ctrls.containsKey(k)) return _ctrls[k]!.text.trim().isEmpty;
    if (_dates.containsKey(k)) return _dates[k] == null;
    if (_lists.containsKey(k)) return _lists[k]!.isEmpty;
    return false; // booleans are never "empty"
  }

  // CREATE: validate required → build full payload → POST → pop a receipt map
  // (REKA quick-create turns it into a 已闭环 ✓ bubble; the library menu ignores it).
  Future<void> _create() async {
    for (final k in (widget.spec?.requiredFields ?? const <String>{})) {
      if (_fieldEmpty(k)) {
        setState(
          () => _error =
              '请填写「${widget.spec?.fieldLabels[k] ?? _label(k, widget.cardType)}」',
        );
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = <String, dynamic>{};
    _ctrls.forEach((k, c) {
      final t = c.text.trim();
      if (t.isEmpty) return;
      payload[k] = _types[k] == 'number' ? (num.tryParse(t) ?? t) : t;
    });
    _dates.forEach((k, d) {
      if (d != null) payload[k] = _isoBeijing(d, dateOnly: _isDateOnly(k));
    });
    _bools.forEach((k, b) => payload[k] = b);
    _lists.forEach((k, l) {
      if (l.isNotEmpty) payload[k] = l;
    });
    try {
      final body = <String, dynamic>{
        'user_skill_name': widget.cardType,
        'payload': payload,
        'domain': _domain ?? '', // '' → backend uses the skill's prior
      };
      // 「在这天记一笔」: 在某天创建 → created_at 锚到那天(那天 + 此刻时分),否则
      // 随记等无日期字段的记录类资产会按 created_at 落到今天。todo/expense 仍由各自
      // due_date/date 决定 effective_at,这里只是兜底锚点。
      final pd = widget.presetDate;
      if (pd != null) {
        final now = DateTime.now();
        body['created_at'] = _isoBeijing(
          DateTime(pd.year, pd.month, pd.day, now.hour, now.minute, now.second),
        );
      }
      await _api.postJson('/api/assets', body);
      bumpData();
      if (mounted) {
        Navigator.of(context).pop(<String, dynamic>{
          'user_skill_name': widget.cardType,
          'display_name': widget.displayName ?? widget.cardType,
          'icon': widget.spec?.icon ?? '📋',
          'payload': payload,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (widget.isCreate) return _create();
    setState(() => _busy = true);
    final patch = <String, dynamic>{};
    _ctrls.forEach((k, c) {
      final inPayload = widget.payload.containsKey(k);
      final orig = inPayload ? '${widget.payload[k]}' : '';
      if (c.text == orig) return;
      if (!inPayload && c.text.trim().isEmpty) {
        return; // don't add a blank new field
      }
      patch[k] = c.text;
    });
    _dates.forEach((k, d) {
      final newVal = d == null
          ? null
          : _isoBeijing(d, dateOnly: _isDateOnly(k));
      if ('${widget.payload[k] ?? ''}' == (newVal ?? '')) return;
      if (newVal != null) patch[k] = newVal;
    });
    _bools.forEach((k, b) {
      final orig = widget.payload[k];
      final origB = orig == true || orig == 1 || orig == '1' || orig == 'true';
      if (widget.payload.containsKey(k) && origB == b) return;
      patch[k] = b;
    });
    _lists.forEach((k, l) {
      final orig = widget.payload[k];
      final same =
          orig is List && orig.map((e) => '$e').join('') == l.join('');
      if (same) return;
      if (l.isEmpty && !widget.payload.containsKey(k)) return;
      patch[k] = l;
    });
    final domainChanged = _domain != widget.initialDomain;
    try {
      if (patch.isNotEmpty || domainChanged) {
        // event/contact are routed to dedicated forms (not this editor); these
        // branches are a safety net (flat PUT, all_day as 0/1).
        switch (widget.cardType) {
          case 'event':
            if (patch['all_day'] is bool) {
              patch['all_day'] = patch['all_day'] == true ? 1 : 0;
            }
            await _api.putJson('/api/events/${widget.assetId}', patch);
          case 'contact':
            await _api.putJson('/api/contacts/${widget.assetId}', patch);
          default:
            final body = <String, dynamic>{};
            if (patch.isNotEmpty) body['payload_patch'] = patch;
            if (domainChanged) body['domain'] = _domain ?? '';
            await _api.putJson('/api/assets/${widget.assetId}', body);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final titleKey = _titleKey;
    return Scaffold(
      backgroundColor: eu.bg,
      appBar: AppBar(
        backgroundColor: eu.bg,
        foregroundColor: eu.textHi,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text('取消', style: TextStyle(color: eu.textMid, fontSize: 15)),
        ),
        leadingWidth: 64,
        centerTitle: true,
        title: Text(
          widget.cardType.toUpperCase(),
          style: euMono(fontSize: 11, letterSpacing: 1.6, color: eu.textLo),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '保存',
                      style: TextStyle(
                        color: eu.brand,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // §2 live card preview — re-renders as you edit the fields below.
              Text(
                '预览',
                style: euMono(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: eu.textLo,
                ),
              ),
              const SizedBox(height: 8),
              IgnorePointer(
                child: SkillCard(_previewCard(), layoutOverride: 'horizontal'),
              ),
              const SizedBox(height: 18),
              Container(height: 1, color: eu.rule),
              const SizedBox(height: 18),
              if (titleKey != null) ...[
                Text(
                  '${widget.spec?.fieldLabels[titleKey] ?? _label(titleKey, widget.cardType)} · $titleKey',
                  style: TextStyle(
                    color: eu.textLo,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                TextField(
                  controller: _ctrls[titleKey],
                  style: TextStyle(
                    color: eu.textHi,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText:
                        widget.spec?.fieldLabels[titleKey] ??
                        _label(titleKey, widget.cardType),
                  ),
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: eu.rule),
                const SizedBox(height: 18),
              ],
              for (final k in _fields)
                if (k != titleKey) ...[
                  _fieldWidget(eu, k),
                  const SizedBox(height: 18),
                ],
              // 领域 selector — same control in create & edit (event/contact define
              // their own domain, so this only shows for asset skills).
              if (widget.cardType != 'event' && widget.cardType != 'contact')
                _domainField(eu),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: TextStyle(color: eu.accentRed, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // §8 manual domain selector (默认 + 8 选 1). 默认 = null → backend uses the prior.
  Widget _domainField(EurekaColors eu) {
    Widget chip(String? d) {
      final selected = _domain == d;
      final c = d == null ? eu.textMid : domainColor(eu, d);
      return GestureDetector(
        onTap: () => setState(() => _domain = d),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: c.withValues(alpha: selected ? 0.22 : 0.08),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: c.withValues(alpha: selected ? 0.6 : 0.22),
            ),
          ),
          child: Text(
            d == null ? '默认' : '${domainIcon(d)} $d',
            style: TextStyle(
              color: c,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '领域',
          style: TextStyle(
            color: eu.textLo,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [chip(null), for (final d in kDomains) chip(d)],
        ),
      ],
    );
  }

  // Pick the right control for a field by its resolved kind.
  Widget _fieldWidget(EurekaColors eu, String k) {
    final base = widget.spec?.fieldLabels[k] ?? _label(k, widget.cardType);
    final label = (widget.spec?.requiredFields.contains(k) ?? false)
        ? '$base *'
        : base;
    switch (_types[k]) {
      case 'datetime':
      case 'date':
        return _DateField(
          label: label,
          value: _dates[k],
          dateOnly: _types[k] == 'date',
          onChanged: (d) => setState(() => _dates[k] = d),
        );
      case 'boolean':
        return _BoolField(
          label: label,
          value: _bools[k] ?? false,
          onChanged: (b) => setState(() => _bools[k] = b),
        );
      case 'array':
        return _ChipsField(
          label: label,
          values: _lists[k] ?? <String>[],
          onChanged: (l) => setState(() => _lists[k] = l),
        );
      default:
        final c = _ctrls[k]!;
        if ((widget.spec?.longFields.contains(k) ?? false) ||
            _isDocKey(k) ||
            _isLongText(c.text)) {
          return MdEditor(label: label, controller: c);
        }
        return _shortField(eu, label, c, numeric: _types[k] == 'number');
    }
  }

  Widget _shortField(
    EurekaColors eu,
    String label,
    TextEditingController c, {
    bool numeric = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: eu.textLo,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          style: TextStyle(color: eu.textHi, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: eu.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: eu.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: eu.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(11),
              borderSide: BorderSide(color: eu.brand),
            ),
          ),
        ),
      ],
    );
  }
}

/// Date(+time) picker field — a labeled tappable box showing the value (or a
/// placeholder), with a clear button. `dateOnly` skips the time step.
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool dateOnly;
  final ValueChanged<DateTime?> onChanged;
  const _DateField({
    required this.label,
    required this.value,
    required this.dateOnly,
    required this.onChanged,
  });

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${d.year}年${d.month}月${d.day}日';
    return dateOnly ? date : '$date ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _pick(BuildContext context) async {
    final base = value ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 5),
      lastDate: DateTime(base.year + 5),
    );
    if (d == null || !context.mounted) return;
    if (dateOnly) {
      onChanged(DateTime(d.year, d.month, d.day));
      return;
    }
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    onChanged(
      DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? base.hour,
        t?.minute ?? base.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: eu.textLo,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => _pick(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: eu.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: eu.border),
            ),
            child: Row(
              children: [
                Icon(
                  dateOnly
                      ? Icons.calendar_today_outlined
                      : Icons.event_outlined,
                  size: 16,
                  color: eu.textMid,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    value == null
                        ? '选择${dateOnly ? '日期' : '时间'}'
                        : _fmt(value!),
                    style: TextStyle(
                      color: value == null ? eu.textLo : eu.textHi,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (value != null)
                  GestureDetector(
                    onTap: () => onChanged(null),
                    behavior: HitTestBehavior.opaque,
                    child: Icon(Icons.close, size: 16, color: eu.textLo),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Boolean field — label + a switch.
class _BoolField extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _BoolField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: eu.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: eu.textHi, fontSize: 15),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: eu.brand,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Array field (e.g. tags) — removable chips + an inline add input.
class _ChipsField extends StatefulWidget {
  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  const _ChipsField({
    required this.label,
    required this.values,
    required this.onChanged,
  });

  @override
  State<_ChipsField> createState() => _ChipsFieldState();
}

class _ChipsFieldState extends State<_ChipsField> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  void _commit() {
    final v = _add.text.trim();
    if (v.isEmpty || widget.values.contains(v)) {
      _add.clear();
      return;
    }
    widget.onChanged([...widget.values, v]);
    _add.clear();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: eu.textLo,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final v in widget.values)
              Container(
                padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
                decoration: BoxDecoration(
                  color: eu.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: eu.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(v, style: TextStyle(color: eu.text, fontSize: 13)),
                    const SizedBox(width: 3),
                    GestureDetector(
                      onTap: () =>
                          widget.onChanged([...widget.values]..remove(v)),
                      behavior: HitTestBehavior.opaque,
                      child: Icon(Icons.close, size: 14, color: eu.textLo),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _add,
                style: TextStyle(color: eu.textHi, fontSize: 13),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _commit(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '+ 添加',
                  hintStyle: TextStyle(color: eu.textLo, fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: eu.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: eu.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: eu.brand),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Large markdown editor field with an 编辑/预览 toggle (no formatting toolbar —
/// markdown is typed directly).
/// Label + edit/preview markdown editor (min-height 220, live MarkdownText
/// preview). Public so the dedicated forms (EventForm…) reuse the exact same
/// long-text control as the asset editor.
class MdEditor extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  const MdEditor({super.key, required this.label, required this.controller});

  @override
  State<MdEditor> createState() => _MdEditorState();
}

class _MdEditorState extends State<MdEditor> {
  bool _preview = false;

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${widget.label} · Markdown',
                style: TextStyle(
                  color: eu.textLo,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _toggle(
              eu,
              '编辑',
              !_preview,
              () => setState(() => _preview = false),
            ),
            const SizedBox(width: 4),
            _toggle(eu, '预览', _preview, () => setState(() => _preview = true)),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 220),
          width: double.infinity,
          decoration: BoxDecoration(
            color: eu.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: eu.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: _preview
              ? (widget.controller.text.trim().isEmpty
                    ? Text(
                        '（无内容）',
                        style: TextStyle(color: eu.textLo, fontSize: 14),
                      )
                    : MarkdownText(
                        widget.controller.text,
                        baseStyle: TextStyle(
                          color: eu.text,
                          fontSize: 15,
                          height: 1.62,
                        ),
                      ))
              : TextField(
                  controller: widget.controller,
                  minLines: 9,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(
                    color: eu.textHi,
                    fontSize: 15,
                    height: 1.55,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: '支持 Markdown：# 标题、**加粗**、*斜体*、- 列表、> 引用…',
                  ),
                ),
        ),
      ],
    );
  }

  Widget _toggle(EurekaColors eu, String label, bool sel, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? eu.brand.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: sel ? eu.brand.withValues(alpha: 0.4) : eu.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: sel ? eu.brand : eu.textMid,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/* ── field labels / skip / format / long detection ─────────────────────────── */

const _fieldLabels = <String, String>{
  'title': '标题', 'subtitle': '摘要', 'content': '内容', 'note': '备注', 'notes': '备注',
  'description': '描述', 'summary': '摘要', 'body': '正文', 'markdown': '正文',
  'due_date': '截止时间',
  'date': '日期',
  'time': '时间',
  'start_at': '开始',
  'end_at': '结束',
  'amount': '金额', 'price': '价格', 'currency': '币种', 'category': '分类',
  'location': '地点',
  'distance': '距离',
  'duration': '时长',
  'pace': '配速',
  'mood': '心情',
  'name': '名称', 'company': '公司', 'phone': '电话', 'email': '邮箱',
  'reps': '次数', 'weight': '重量', 'pages_read': '阅读页数',
  // common custom-skill fields (agent sometimes omits a label → fall back here)
  'book_title': '书名', 'author': '作者', 'key_insights': '要点', 'time_spent': '用时',
  'rating': '评分',
  'progress': '进度',
  'merchant': '商家',
  'place': '地点',
  'teacher': '老师',
};

String _label(String key, String cardType) {
  if (key == 'amount') return cardType == 'expense' ? '金额' : '数量';
  if (key == 'price') return cardType == 'expense' ? '价格' : '数量';
  return _fieldLabels[key] ?? key;
}

/// Keys whose value should ALWAYS get the big markdown editor when editing, even
/// if currently short/empty (so the user can write a long document there).
const _docKeys = <String>{
  'content',
  'note',
  'notes',
  'description',
  'body',
  'markdown',
  'summary',
  'detail',
  'remark',
  // fallback for skills created before the schema's `long` flag (e.g. reading_notes)
  'key_insights',
  'insights',
  'takeaways',
  'review',
  'reflection',
  'comment',
  'thoughts',
};
bool _isDocKey(String key) => _docKeys.contains(key.toLowerCase());

const _skipKeys = <String>{
  'ok', 'contact_action', 'when', 'card_type', 'kind', 'skill_name',
  'user_skill_name', 'user_id', 'all_day', 'status', 'task_id', 'external_id',
  'external_url', 'external_system', 'external_type', 'event_id', 'asset_id',
  'id', 'contact_id', 'file_id', 'source_input_turn_id', 'session_id',
  'sync_source', 'sync_external_id', 'recurrence_rule', 'updated_at',
  'user_skill_id', 'logId', 'trace_id',
  'source_report_id',
  'source_report_title', // §6.13 溯源 — shown via _sourceLine, not as fields
  'icon', 'accent_color', 'accentColor', 'actions', 'card_layout', 'layout',
  'cardType', 'checkDone', 'primary_field', 'primary_format', 'secondary_field',
  'secondary_format', 'meta_fields', 'metaFields', 'timeline_position',
  'calendar_render', 'created_at',
};

bool _skip(String key, dynamic value) {
  if (_skipKeys.contains(key)) return true;
  if (value == null) return true;
  if (value is String && value.isEmpty) return true;
  if (value is List && value.isEmpty) return true;
  if (value is Map && value.isEmpty) return true;
  return false;
}

/// A field is "long" by a universal rule (not a hardcoded field name): many
/// characters or several line breaks. Custom-skill long bodies qualify too.
bool _isLongText(String s) => s.length > 120 || '\n'.allMatches(s).length >= 3;

final _isoDt = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}');

String? _inferFormat(String key, dynamic value) {
  if (value is! String) return null;
  if (key == 'due_date') return 'relative_date';
  if (key.endsWith('_date') || key.endsWith('_at')) return 'absolute_date';
  if (key == 'date' || key == 'time') return 'absolute_date';
  if (_isoDt.hasMatch(value)) return 'absolute_date';
  return null;
}
