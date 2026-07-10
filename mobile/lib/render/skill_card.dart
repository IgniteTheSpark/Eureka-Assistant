import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../data_revision.dart';
import '../theme/app_theme.dart';
import '../theme/domains.dart';
import '../theme/eureka_colors.dart';
import '../theme/ureka_tokens.dart';
import '../widgets/toast.dart';
import 'asset_detail_sheet.dart';
import 'render_spec.dart';

/// Bridges the global [dataRevision] ValueNotifier into Riverpod so providers
/// that watch it re-run after any mutation (`bumpData()`). Emits the current
/// revision immediately, then on every change.
final _revisionProvider = StreamProvider<int>((ref) {
  final controller = StreamController<int>();
  void listener() => controller.add(dataRevision.value);
  dataRevision.addListener(listener);
  ref.onDispose(() {
    dataRevision.removeListener(listener);
    controller.close();
  });
  controller.add(dataRevision.value);
  return controller.stream;
});

/// render_spec registry (skill name → spec), shared by every card. Re-fetched
/// whenever data changes (a new/edited skill is created via the wizard), so a
/// freshly-created skill's cards render with its real spec — not the generic
/// fallback — without an app restart. Riverpod keeps the prior value during the
/// refetch, so there's no loading flash.
final renderSpecsProvider = FutureProvider<Map<String, RenderSpec>>((
  ref,
) async {
  ref.watch(_revisionProvider);
  final api = ApiClient();
  try {
    return await fetchRenderSpecs(api);
  } finally {
    api.close();
  }
});

/// The universal render_spec-driven card (mirrors the web SkillCard). Resolves
/// its spec from the registry (asset cards) or synthesizes one (event/contact/
/// task), then renders the layout the spec asks for.
class SkillCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> card;

  /// Force a layout regardless of the spec — list contexts pass 'horizontal'
  /// so every card in a list reads the same size.
  final String? layoutOverride;
  const SkillCard(this.card, {super.key, this.layoutOverride});

  @override
  ConsumerState<SkillCard> createState() => _SkillCardState();
}

class _SkillCardState extends ConsumerState<SkillCard> {
  final _api = ApiClient();
  bool? _doneOverride;
  bool _deleted = false;
  // §1.8 B「一键升级成本子」: while the promote call runs, and the structured
  // card it returns (which replaces this 随记 card in place).
  bool _promoting = false;
  bool _promoted = false;
  Map<String, dynamic>? _replacedCard;

  Map<String, dynamic> get card => _replacedCard ?? widget.card;
  String? get _assetId {
    final type = card['card_type'] as String?;
    final id = switch (type) {
      'event' => card['event_id'] ?? card['id'] ?? card['asset_id'],
      'contact' => card['contact_id'] ?? card['asset_id'] ?? card['id'],
      _ => card['asset_id'] ?? card['id'],
    };
    return id as String?;
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  /// The right DELETE endpoint for this card, by type — null if it isn't
  /// user-deletable (task / a prebuilt card with no id).
  String? _deletePath(String cardType) {
    switch (cardType) {
      case 'event':
        final id = (card['event_id'] ?? card['id']) as String?;
        return id == null ? null : '/api/events/$id';
      case 'contact':
        final id = (card['contact_id'] ?? card['id']) as String?;
        return id == null ? null : '/api/contacts/$id';
      case 'task':
        return null;
      default: // asset-skill card
        final id = _assetId;
        return id == null ? null : '/api/assets/$id';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deleted) return const SizedBox.shrink();
    final eu = context.eu;
    final specs = ref.watch(renderSpecsProvider).valueOrNull ?? const {};
    var data = _resolve(specs);
    if (widget.layoutOverride != null) {
      data = data.copyWith(layout: widget.layoutOverride);
    }
    if (_doneOverride != null) data = data.copyWith(checkDone: _doneOverride);
    data = data.copyWith(domain: card['domain'] as String?); // §8 domain chip

    final type = card['card_type'] as String?;
    final isEntity = type == 'event' || type == 'contact' || type == 'task';
    final payload = isEntity
        ? card
        : ((card['payload'] as Map?)?.cast<String, dynamic>() ?? const {});
    final cardType = type ?? (card['user_skill_name'] as String?) ?? 'asset';
    // The skill's own spec drives the detail sheet's field labels + formats.
    final skill = card['user_skill_name'] as String?;
    final spec = skill != null ? specs[skill] : null;

    final canToggle = data.checkDone != null && _assetId != null;
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showAssetDetail(
        context,
        data: data,
        payload: payload,
        cardType: cardType,
        assetId: _assetId,
        sessionId: card['session_id'] as String?,
        spec: spec,
      ),
      child: _CardBody(data, onToggleCheck: canToggle ? _toggle : null),
    );

    // Left-swipe to delete — available on every deletable card, anywhere.
    final delPath = _deletePath(cardType);
    final cardWidget = delPath == null
        ? body
        : Dismissible(
            key: ValueKey('del_$delPath'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmAndDelete(delPath),
            onDismissed: (_) => setState(() => _deleted = true),
            background: Container(
              margin: const EdgeInsets.only(top: 6),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              decoration: BoxDecoration(
                color: eu.accentRed.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.delete_outline, color: eu.accentRed),
            ),
            child: body,
          );

    // §1.8 B — a 随记 the agent recognized as a structurable type carries a
    // `suggest_skill`. Offer a one-tap「长期记成『XX』本子?」under the card; tap
    // builds the skill + re-files this record into it (POST /api/skills/promote).
    final suggest = card['suggest_skill'] as String?;
    if (suggest == null || suggest.isEmpty || _promoted) return cardWidget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [cardWidget, _promoteChip(eu, suggest)],
    );
  }

  Widget _promoteChip(EurekaColors eu, String suggest) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2, bottom: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: _promoting ? null : () => _promote(suggest),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: eu.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: eu.brand.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_promoting)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: eu.brand,
                    ),
                  )
                else
                  Text('✨', style: TextStyle(fontSize: 12, color: eu.brand)),
                const SizedBox(width: 6),
                Text(
                  _promoting ? '正在建「$suggest」本子…' : '长期记成「$suggest」本子?',
                  style: TextStyle(
                    color: eu.brand,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _promote(String suggest) async {
    final id = _assetId;
    if (id == null) return;
    setState(() => _promoting = true);
    try {
      final res = await _api.postJson('/api/skills/promote', {
        'asset_id': id,
        'suggest_skill': suggest,
      });
      final m = (res as Map).cast<String, dynamic>();
      final newCard = (m['card'] as Map?)?.cast<String, dynamic>();
      final dn = (m['display_name'] as String?) ?? suggest;
      if (!mounted) return;
      setState(() {
        _promoted = true;
        _promoting = false;
        if (newCard != null) _replacedCard = newCard;
      });
      bumpData(); // new skill + re-filed asset → refresh any open lists
      if (mounted) showToast(context, '已建「$dn」本子，以后这类自动归类 ✓');
    } catch (_) {
      if (!mounted) return;
      setState(() => _promoting = false);
      showToast(context, '升级失败，先留作随记', error: true);
    }
  }

  Future<bool> _confirmAndDelete(String path) async {
    final eu = context.eu;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: eu.surfaceRaised,
            title: Text('删除这条记录？', style: TextStyle(color: eu.textHi)),
            content: Text('删除后无法恢复。', style: TextStyle(color: eu.textMid)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('取消', style: TextStyle(color: eu.textMid)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  '删除',
                  style: TextStyle(
                    color: eu.accentRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return false;
    try {
      await _api.deleteJson(path);
      bumpData();
      return true;
    } catch (_) {
      if (mounted) {
        showToast(context, '删除失败', error: true);
      }
      return false;
    }
  }

  Future<void> _toggle(bool next) async {
    final id = _assetId;
    if (id == null) return;
    setState(() => _doneOverride = next);
    try {
      await _api.putJson('/api/assets/$id', {
        'payload_patch': {'status': next ? 'done' : 'pending'},
      });
    } catch (_) {
      if (mounted) setState(() => _doneOverride = !next); // revert on failure
    }
  }

  CardData _resolve(Map<String, RenderSpec> specs) {
    // Pre-built card: agent/flash messages persist fully-rendered cards
    // (icon/title/subtitle/accent_color/meta_fields). Use them as-is instead
    // of re-resolving from a render_spec (we have no payload for these).
    if (card.containsKey('accent_color') || card.containsKey('meta_fields')) {
      return _prebuilt();
    }
    final type = card['card_type'] as String?;
    if (type == 'event' || type == 'contact' || type == 'task') {
      return buildCard(
        payload: card,
        spec: synthesizeSpec(type!),
        displayName: type,
      );
    }
    final skill = card['user_skill_name'] as String?;
    final payload =
        (card['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final spec = skill != null ? specs[skill] : null;
    return buildCard(
      payload: payload,
      spec: spec ?? synthesizeSpec(skill ?? 'misc'),
      displayName: skill ?? '资产',
    );
  }

  CardData _prebuilt() {
    final meta = <({String value, String? format})>[];
    for (final m
        in ((card['meta_fields'] as List?) ?? const []).whereType<Map>()) {
      final v = m['value']?.toString() ?? '';
      if (v.isNotEmpty) meta.add((value: v, format: m['format'] as String?));
    }
    // Checkable cards (todo) expose a "check" action → always carry a bool
    // checkDone so the corner checkbox renders and can be toggled. Non-check
    // cards keep checkDone null (emoji icon, no checkbox).
    final actions = ((card['actions'] as List?) ?? const [])
        .whereType<String>()
        .toSet();
    final done = card['status'] == 'done' || card['done'] == true;
    final checkable = actions.contains('check');
    return CardData(
      layout:
          (card['card_layout'] ?? card['layout']) as String? ?? 'horizontal',
      icon: card['icon'] as String? ?? '•',
      accentColor: card['accent_color'] as String? ?? 'gray',
      title: card['title'] as String? ?? '资产',
      subtitle: card['subtitle'] as String? ?? '',
      metaFields: meta,
      checkDone: checkable ? done : (done ? true : null),
    );
  }
}

/// Non-interactive render of a [CardData] — used by the AddSkillWizard live
/// preview (no tap/toggle/detail behaviour, just the visual).
class CardPreview extends StatelessWidget {
  final CardData data;
  const CardPreview(this.data, {super.key});

  @override
  Widget build(BuildContext context) => _CardBody(data);
}

class CardAccent {
  final Color fg;
  final Color bg;
  final Color edge;

  /// Solid强调 — progress bars, dots, the todo checkbox fill (§5.1 `-solid`).
  final Color solid;
  const CardAccent(this.fg, this.bg, this.edge, this.solid);
}

/// Map a render_spec accent_color to its quad. All 8 slots are covered
/// (blue/amber/green/red/purple/gray/neutral/cyan); unknown → neutral, which is
/// the same fallback the web buildCard ACCENT map lands on (§5.1).
CardAccent accentOf(String name, EurekaColors eu) {
  final fg = switch (name) {
    'blue' => eu.accentBlue,
    'amber' => eu.accentAmber,
    'green' => eu.accentGreen,
    'red' => eu.accentRed,
    'purple' => eu.accentPurple,
    'gray' => eu.accentGray,
    'cyan' => eu.accentCyan,
    'neutral' => eu.accentNeutral,
    _ => eu.accentNeutral,
  };
  return CardAccent(
    fg,
    fg.withValues(alpha: 0.12),
    fg.withValues(alpha: 0.30),
    fg,
  );
}

class _CardBody extends StatelessWidget {
  final CardData data;
  final ValueChanged<bool>? onToggleCheck;
  const _CardBody(this.data, {this.onToggleCheck});

  static const double _horizontalH = 88;

  @override
  Widget build(BuildContext context) {
    switch (data.layout) {
      case 'inline':
      case 'compact':
        return _inline(context);
      case 'stacked':
        return _stacked(context);
      default:
        return _horizontal(context);
    }
  }

  Widget _shell(EurekaColors eu, CardAccent a, {required Widget child}) {
    const radius = 11.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: UDurations.normal,
      curve: Curves.easeOutCubic,
      builder: (context, t, animatedChild) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 4),
          child: animatedChild,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(
          color: _sheetColor(eu),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: _sheetEdge(eu)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: child,
              ),
              Positioned(
                right: 0,
                top: 0,
                child: CustomPaint(
                  size: const Size(13, 13),
                  painter: _PaperCornerPainter(
                    edge: _sheetEdge(eu),
                    fill: _cornerFill(eu),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _sheetColor(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0xFFFFFEFB)
        : const Color(0xFF14181E);
  }

  static Color _sheetEdge(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0x14211F19)
        : const Color(0x1AFFFFFF);
  }

  static Color _cornerFill(EurekaColors eu) {
    return eu.brightness == Brightness.light
        ? const Color(0xFFFAF7F0)
        : const Color(0xFF1B2028);
  }

  /// Identity tile: always the skill's emoji glyph (so a todo still looks like a
  /// todo). When the skill has a "check" action, a small checkbox overlays the
  /// bottom-right corner — both visible at once, matching the web IconTile.
  Widget _iconTile(CardAccent a, EurekaColors eu) {
    final tile = Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: eu.surfaceRaised,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: eu.border),
      ),
      child: Opacity(
        opacity: data.checkDone == true ? 0.5 : 1.0,
        child: Text(data.icon, style: const TextStyle(fontSize: 16)),
      ),
    );
    if (data.checkDone == null) return tile;
    final done = data.checkDone == true;
    final overlay = GestureDetector(
      onTap: onToggleCheck == null ? null : () => onToggleCheck!(!done),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? a.fg : eu.bg,
          border: Border.all(color: a.fg, width: 1.5),
        ),
        child: done
            ? const Icon(Icons.check, size: 10, color: Colors.white)
            : null,
      ),
    );
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(right: -4, bottom: -4, child: overlay),
        ],
      ),
    );
  }

  Widget _title(EurekaColors eu) {
    final done = data.checkDone == true;
    // One line in the card (the detail/full view shows the whole title) — keeps
    // every card the same height regardless of title length.
    return Text(
      data.title.replaceAll(RegExp(r'\s*\n\s*'), ' '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: done ? eu.textLo : eu.textHi,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        decoration: done ? TextDecoration.lineThrough : null,
      ),
    );
  }

  // Fixed 2-row list card: title/domain row → one plain auxiliary text row.
  // Format hints can affect text elsewhere, but list cards do not render extra
  // chips/badges; the only chip-like signal kept here is the domain tag.
  Widget _subAndMeta(EurekaColors eu, {bool reserve = false}) {
    final sub = data.subtitle.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
    final meta = data.metaFields.take(2).toList(); // 最多展示 2 个信息
    final aux = [
      if (sub.isNotEmpty) sub,
      for (final m in meta)
        if (m.value.trim().isNotEmpty) m.value.trim(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: SizedBox(
        height: 18,
        child: aux.isEmpty && !reserve
            ? null
            : Text(
                aux,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: eu.textMid, fontSize: 12.5),
              ),
      ),
    );
  }

  // Title row — title fills the width, the 领域 tag sits at the top-right corner.
  Widget _titleRow(EurekaColors eu) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _title(eu)),
        if (data.domain != null) ...[
          const SizedBox(width: 8),
          DomainChip(data.domain), // §8: nothing rendered when null/unknown
        ],
      ],
    );
  }

  Widget _horizontal(BuildContext context) {
    final eu = context.eu;
    final a = accentOf(data.accentColor, eu);
    return SizedBox(
      height: _horizontalH,
      child: _shell(
        eu,
        a,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _iconTile(a, eu),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_titleRow(eu), _subAndMeta(eu, reserve: true)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stacked(BuildContext context) {
    final eu = context.eu;
    final a = accentOf(data.accentColor, eu);
    return _shell(
      eu,
      a,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconTile(a, eu),
              const SizedBox(width: 12),
              Expanded(child: _titleRow(eu)),
            ],
          ),
          if (data.subtitle.isNotEmpty || data.metaFields.isNotEmpty)
            _subAndMeta(eu),
        ],
      ),
    );
  }

  Widget _inline(BuildContext context) {
    final eu = context.eu;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: eu.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: eu.border),
      ),
      child: Row(
        children: [
          Text(data.icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: eu.textHi, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperCornerPainter extends CustomPainter {
  final Color edge;
  final Color fill;

  const _PaperCornerPainter({required this.edge, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawLine(
      Offset(0, 0),
      Offset(size.width, size.height),
      Paint()
        ..color = edge
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _PaperCornerPainter oldDelegate) {
    return oldDelegate.edge != edge || oldDelegate.fill != fill;
  }
}
