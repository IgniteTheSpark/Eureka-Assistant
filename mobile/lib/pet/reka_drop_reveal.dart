import 'package:flutter/material.dart';

import '../app_events.dart' show navigatorKey;
import '../render/pet_view.dart';
import '../theme/app_theme.dart';
import 'pet_controller.dart';
import 'pet_cosmetics.dart';

/// §9.3 孵化 / 掉落揭示弹窗 — mirrors reka-system.js `hatchReveal`. A centered modal
/// that reveals a freshly-dropped cosmetic component with its rarity tint + big
/// sprite, then 收下并装备 (equip) / 稍后. Used for the hatch starter grant and for
/// routine drops, so every drop is a little reveal moment (not just a toast).
///
/// [slot] = the drop-pool slot: skin | emblem | head | item | carrier | aura.
/// [alreadyEquipped] = true for the hatch starter (backend already equipped it) →
/// the CTA becomes a single 收下.
Future<void> showRekaDropReveal(
  BuildContext context, {
  required String slot,
  required String cosmeticKey,
  String? emblemColor,
  bool alreadyEquipped = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (_) => _DropReveal(
      slot: slot,
      cosmeticKey: cosmeticKey,
      emblemColor: emblemColor,
      alreadyEquipped: alreadyEquipped,
    ),
  );
}

/// Convenience: show the reveal for a [PetDrop] via the root navigator (used by
/// PetController when it diffs a new drop).
void showDropRevealGlobal(PetDrop drop) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  showRekaDropReveal(ctx, slot: drop.slot, cosmeticKey: drop.key);
}

class _DropReveal extends StatelessWidget {
  final String slot;
  final String cosmeticKey;
  final String? emblemColor;
  final bool alreadyEquipped;
  const _DropReveal({
    required this.slot,
    required this.cosmeticKey,
    required this.emblemColor,
    required this.alreadyEquipped,
  });

  // engine slot/key → preview genome (full Reka wearing the dropped piece).
  Map<String, dynamic> _previewOpts(String skin) {
    const bare = {
      'head': 'none', 'leftItem': 'none', 'rightItem': 'none',
      'emblem': 'none', 'carrier': 'none', 'aura': 'none', 'scale': 6,
    };
    switch (slot) {
      case 'skin':
        return {...bare, 'skin': cosmeticKey, 'aura': 'soft'};
      case 'emblem':
        return {...bare, 'skin': 'sky', 'emblem': cosmeticKey, 'emblemColor': emblemColor ?? 'gold'};
      case 'head':
        return {...bare, 'skin': skin, 'head': cosmeticKey};
      case 'item':
        return {...bare, 'skin': skin, 'leftItem': cosmeticKey};
      case 'carrier':
        return {...bare, 'skin': skin, 'carrier': cosmeticKey};
      case 'aura':
        return {...bare, 'skin': skin, 'emblem': 'star', 'aura': cosmeticKey};
      default:
        return {...bare, 'skin': skin};
    }
  }

  String get _name {
    if (slot == 'emblem') return emblemComponentOf(cosmeticKey, emblemColor ?? 'gold').name;
    if (slot == 'item') return itemLabel[cosmeticKey] ?? cosmeticKey;
    return cosmeticLabel(slot, cosmeticKey);
  }

  String get _tier {
    if (slot == 'emblem') return emblemComponentOf(cosmeticKey, emblemColor ?? 'gold').tier;
    return tierOf(slot, cosmeticKey);
  }

  String get _slotLabel => const {
        'skin': '身色', 'emblem': '徽记', 'head': '头部',
        'item': '手持', 'carrier': '承载', 'aura': '光环',
      }[slot] ?? '装饰';

  Future<void> _equip(BuildContext context) async {
    final pet = PetController.instance;
    try {
      switch (slot) {
        case 'skin':
          await pet.equip('skin', cosmeticKey);
        case 'emblem':
          await pet.equipAll({'emblem': cosmeticKey, 'emblem_color': emblemColor ?? 'gold'});
        case 'item':
          await pet.equip('leftItem', cosmeticKey);
        case 'head':
        case 'carrier':
        case 'aura':
          await pet.equip(slot, cosmeticKey);
      }
    } catch (_) {/* best-effort */}
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final t = kTiers[_tier] ?? kTiers['normal']!;
    final skin = PetController.instance.pet?.skin ?? 'aurora';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 40),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(t.color.withValues(alpha: 0.16), eu.surfaceRaised),
                    eu.surface,
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Color.alphaBlend(t.color.withValues(alpha: 0.5), eu.border)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40, offset: const Offset(0, 16)),
                  BoxShadow(color: t.color.withValues(alpha: 0.30), blurRadius: 36, spreadRadius: -8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: t.color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: t.color.withValues(alpha: 0.4)),
                          ),
                          child: const Text('🥚', style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  style: TextStyle(color: eu.textLo, fontSize: 10, letterSpacing: 0.8),
                                  children: [
                                    const TextSpan(text: '孵化掉落 · '),
                                    TextSpan(text: t.label, style: TextStyle(color: t.color, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(_name, style: TextStyle(color: eu.textHi, fontSize: 19, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: eu.surface, shape: BoxShape.circle, border: Border.all(color: eu.border)),
                            child: Icon(Icons.close, size: 16, color: eu.textMid),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // rarity-tinted stage + big sprite
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    height: 168,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.1),
                        radius: 0.8,
                        colors: [t.color.withValues(alpha: 0.22), eu.surface.withValues(alpha: 0.0)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Color.alphaBlend(t.color.withValues(alpha: 0.3), eu.border)),
                    ),
                    child: SizedBox(
                      width: 150,
                      height: 150,
                      child: PetView(
                        genome: _previewOpts(skin),
                        scale: 6,
                        celebrateSignal: 1, // little pop on reveal
                      ),
                    ),
                  ),
                  // meta
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(color: eu.textMid, fontSize: 12.5, height: 1.6),
                        children: [
                          const TextSpan(text: 'Reka 的 '),
                          TextSpan(text: _slotLabel, style: TextStyle(color: eu.textHi, fontWeight: FontWeight.w700)),
                          const TextSpan(text: ' 多了一件组件 · 从组件库'),
                          const TextSpan(text: '随机', style: TextStyle(fontWeight: FontWeight.w700)),
                          const TextSpan(text: '掉落 · 稀有度 '),
                          TextSpan(text: t.label, style: TextStyle(color: t.color, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                  // actions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                            decoration: BoxDecoration(
                              color: eu.surface,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: eu.border),
                            ),
                            child: Text('稍后', style: TextStyle(color: eu.textMid, fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => alreadyEquipped ? Navigator.of(context).pop() : _equip(context),
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: eu.brand, borderRadius: BorderRadius.circular(13)),
                              child: Text(alreadyEquipped ? '收下' : '收下并装备',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
