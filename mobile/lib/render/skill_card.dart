import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import 'render_spec.dart';

/// Cached render_spec registry (skill name → spec), shared by every card.
final renderSpecsProvider = FutureProvider<Map<String, RenderSpec>>((ref) async {
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
class SkillCard extends ConsumerWidget {
  final Map<String, dynamic> card;
  const SkillCard(this.card, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specs = ref.watch(renderSpecsProvider).valueOrNull ?? const {};
    return _CardBody(_resolve(specs));
  }

  CardData _resolve(Map<String, RenderSpec> specs) {
    final type = card['card_type'] as String?;
    if (type == 'event' || type == 'contact' || type == 'task') {
      return buildCard(payload: card, spec: synthesizeSpec(type!), displayName: type);
    }
    final skill = card['user_skill_name'] as String?;
    final payload = (card['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final spec = skill != null ? specs[skill] : null;
    return buildCard(
      payload: payload,
      spec: spec ?? synthesizeSpec(skill ?? 'misc'),
      displayName: skill ?? '资产',
    );
  }
}

class _Accent {
  final Color fg;
  final Color bg;
  final Color edge;
  const _Accent(this.fg, this.bg, this.edge);
}

_Accent _accentOf(String name, EurekaColors eu) {
  final fg = switch (name) {
    'blue' => eu.accentBlue,
    'amber' => eu.accentAmber,
    'green' => eu.accentGreen,
    'red' => eu.accentRed,
    'purple' => eu.accentPurple,
    _ => eu.textMid,
  };
  return _Accent(fg, fg.withValues(alpha: 0.12), fg.withValues(alpha: 0.30));
}

class _CardBody extends StatelessWidget {
  final CardData data;
  const _CardBody(this.data);

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

  Widget _shell(EurekaColors eu, _Accent a, {required Widget child}) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: a.bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: a.edge),
        ),
        child: child,
      );

  Widget _iconTile(_Accent a, EurekaColors eu) {
    if (data.checkDone != null) {
      final done = data.checkDone == true;
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: done ? a.fg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: a.fg, width: 1.5),
        ),
        child: done ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
      );
    }
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [a.bg, Colors.transparent]),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: a.edge),
      ),
      child: Text(data.icon, style: const TextStyle(fontSize: 16)),
    );
  }

  Widget _title(EurekaColors eu) {
    final done = data.checkDone == true;
    return Text(
      data.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: done ? eu.textLo : eu.textHi,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        decoration: done ? TextDecoration.lineThrough : null,
      ),
    );
  }

  Widget _subAndMeta(EurekaColors eu, _Accent a) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (data.subtitle.isNotEmpty)
              Text(data.subtitle, style: TextStyle(color: eu.textMid, fontSize: 12)),
            for (final m in data.metaFields) _metaPill(m, a, eu),
          ],
        ),
      );

  Widget _metaPill(({String value, String? format}) m, _Accent a, EurekaColors eu) {
    if (m.format == 'badge') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: a.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: a.edge),
        ),
        child: Text(m.value,
            style: TextStyle(color: a.fg, fontSize: 11, fontWeight: FontWeight.w600)),
      );
    }
    return Text(m.value, style: TextStyle(color: eu.textLo, fontSize: 11));
  }

  Widget _horizontal(BuildContext context) {
    final eu = context.eu;
    final a = _accentOf(data.accentColor, eu);
    return _shell(
      eu,
      a,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconTile(a, eu),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title(eu),
                if (data.subtitle.isNotEmpty || data.metaFields.isNotEmpty)
                  _subAndMeta(eu, a),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stacked(BuildContext context) {
    final eu = context.eu;
    final a = _accentOf(data.accentColor, eu);
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
              Expanded(child: _title(eu)),
            ],
          ),
          if (data.subtitle.isNotEmpty || data.metaFields.isNotEmpty) _subAndMeta(eu, a),
        ],
      ),
    );
  }

  Widget _inline(BuildContext context) {
    final eu = context.eu;
    final a = _accentOf(data.accentColor, eu);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: a.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: a.edge),
      ),
      child: Row(
        children: [
          Text(data.icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: eu.textHi, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
