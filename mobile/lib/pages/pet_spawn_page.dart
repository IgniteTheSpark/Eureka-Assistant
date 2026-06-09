import 'package:flutter/material.dart';

import '../pet/floating_mascot.dart' show mascotSuppressed, releaseMascotSuppress;
import '../pet/pet_controller.dart';
import '../pet/pet_cosmetics.dart';
import '../pet/reka_drop_reveal.dart';
import '../render/pet_view.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../widgets/toast.dart';
import 'pet_page.dart';

/// §9 Reka — one-time spawn takeover: egg → hatch → name → intro. Gated on an
/// un-spawned pet (the header routes here only when `!spawned`). On finish it
/// replaces itself with the pet detail page.
enum _Step { egg, hatching, reveal, name, intro, firstCapture }

class PetSpawnPage extends StatefulWidget {
  const PetSpawnPage({super.key});

  @override
  State<PetSpawnPage> createState() => _PetSpawnPageState();
}

class _PetSpawnPageState extends State<PetSpawnPage> {
  final _pet = PetController.instance;
  final _nameCtrl = TextEditingController();
  _Step _step = _Step.egg;

  @override
  void initState() {
    super.initState();
    mascotSuppressed.value++; // this screen IS REKA — hide the floating one
    // Defensive: if it's somehow already spawned, jump straight to the intro.
    if (_pet.spawned) {
      _step = _Step.intro;
      _nameCtrl.text = _pet.pet?.name ?? 'Reka';
    }
  }

  @override
  void dispose() {
    releaseMascotSuppress();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _hatch() async {
    setState(() => _step = _Step.hatching);
    try {
      await _pet.spawn();
      if (!mounted) return;
      setState(() => _step = _Step.reveal);
      // §9.3 hatchReveal — pop the rich reveal modal over the celebrate scene
      // once the egg has cracked. The starter is already equipped by the server,
      // so the CTA is a single 收下.
      final s = _starterDrop();
      if (s != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showRekaDropReveal(context, slot: s.slot, cosmeticKey: s.key, alreadyEquipped: true);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.egg);
      showToast(context, '孵化失败：$e', error: true);
    }
  }

  /// The guaranteed starter accessory the server equipped on hatch, mapped to the
  /// drop-pool slot keys (head | item). Null if none (defensive).
  ({String slot, String key})? _starterDrop() {
    final eq = _pet.pet?.equipped ?? const <String, String>{};
    final head = eq['head'] ?? 'none';
    if (head != 'none') return (slot: 'head', key: head);
    final left = eq['leftItem'] ?? 'none';
    if (left != 'none') return (slot: 'item', key: left);
    final right = eq['rightItem'] ?? 'none';
    if (right != 'none') return (slot: 'item', key: right);
    return null;
  }

  Future<void> _confirmName() async {
    final name = _nameCtrl.text.trim();
    try {
      if (name.isNotEmpty && name != _pet.pet?.name) await _pet.rename(name);
      if (!mounted) return;
      setState(() => _step = _Step.intro);
    } catch (e) {
      if (!mounted) return;
      showToast(context, '保存失败：$e', error: true);
    }
  }

  void _finish() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PetPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final p = _pet.pet;
    final skin = p?.skin ?? 'aurora';
    final isEgg = _step == _Step.egg || _step == _Step.hatching;
    final genome = p?.genome ?? {'skin': skin, 'emblem': 'star', 'emblemColor': 'gold'};
    final state = _step == _Step.reveal ? 'celebrate' : 'idle';

    return Scaffold(
      backgroundColor: eu.bg,
      body: Stack(
        children: [
          // ambient brand glow
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.9,
                    colors: [
                      eu.brand.withValues(alpha: eu.brightness == Brightness.dark ? 0.22 : 0.14),
                      eu.brand.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Vertically centered egg + copy (scrolls if the keyboard covers it on
          // the name step). Center + SingleChildScrollView = centered when it
          // fits, scrollable when it doesn't.
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: PetView(
                        key: ValueKey('spawn-${isEgg ? 'egg' : 'pet'}-$state'),
                        genome: genome,
                        egg: isEgg,
                        state: state,
                        scale: 7,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _copy(eu),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _copy(EurekaColors eu) {
    switch (_step) {
      case _Step.egg:
        return _block(eu,
            title: '一颗灵感蛋正在孵化',
            body: '它会成为陪着你的灵感伙伴 · Reka。\n你记录的每一条灵感，都会被它接住。',
            cta: '轻点唤醒  →',
            onCta: _hatch);
      case _Step.hatching:
        return Column(children: [
          Text('正在孵化…', style: TextStyle(color: eu.textMid, fontSize: 14)),
          const SizedBox(height: 16),
          SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: eu.brand),
          ),
        ]);
      case _Step.reveal:
        return _revealBlock(eu);
      case _Step.name:
        return _nameBlock(eu);
      case _Step.intro:
        final name = _pet.pet?.name ?? 'Reka';
        return _block(eu,
            title: '你好，我是$name',
            body: '你每记录或完成一件事，我都会接住它，\n偶尔还会带回一件小装饰。\n我们一起开始吧。',
            cta: '下一步  →',
            onCta: () => setState(() => _step = _Step.firstCapture));
      case _Step.firstCapture:
        return _block(eu,
            title: '记下你的第一条吧',
            body: '随手记一条灵感或待办，我就会接住它。\n你做得越多，我也会陪你长得越好。',
            cta: '完成 · 进入 →',
            onCta: _finish);
    }
  }

  // §9.3 reveal — Reka hatches already wearing its guaranteed starter accessory;
  // call it out with its rarity tier so the first drop feels like a gift.
  Widget _revealBlock(EurekaColors eu) {
    final s = _starterDrop();
    Widget? rewardChip;
    if (s != null) {
      final tier = tierOf(s.slot, s.key);
      final t = kTiers[tier] ?? kTiers['normal']!;
      final label = cosmeticLabel(s.slot, s.key);
      rewardChip = Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: t.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.color.withValues(alpha: 0.5)),
        ),
        child: RichText(
          text: TextSpan(style: TextStyle(color: eu.textMid, fontSize: 12.5), children: [
            const TextSpan(text: '🥚 孵化掉落 · '),
            TextSpan(text: t.label, style: TextStyle(color: t.color, fontWeight: FontWeight.w700)),
            const TextSpan(text: ' · '),
            TextSpan(text: label, style: TextStyle(color: eu.textHi, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Reka诞生了！',
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textHi, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('它带着属于你的颜色来到了世界，\n还从组件库带回了一件装饰。',
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textMid, fontSize: 14.5, height: 1.55)),
        const SizedBox(height: 18),
        ?rewardChip,
        _ctaButton(eu, '给它起名  →', () => setState(() => _step = _Step.name)),
      ],
    );
  }

  Widget _nameBlock(EurekaColors eu) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('给Reka起个名字', style: TextStyle(color: eu.textHi, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          maxLength: 8,
          textAlign: TextAlign.center,
          style: TextStyle(color: eu.textHi, fontSize: 18, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: 'Reka',
            counterText: '',
            hintStyle: TextStyle(color: eu.textLo),
            filled: true,
            fillColor: eu.surfaceRaised,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: eu.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: eu.brand, width: 1.6),
            ),
          ),
          onSubmitted: (_) => _confirmName(),
        ),
        const SizedBox(height: 18),
        _ctaButton(eu, '确认  →', _confirmName),
      ],
    );
  }

  Widget _block(EurekaColors eu,
      {required String title, required String body, required String cta, required VoidCallback onCta}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textHi, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(body,
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textMid, fontSize: 14.5, height: 1.55)),
        const SizedBox(height: 26),
        _ctaButton(eu, cta, onCta),
      ],
    );
  }

  Widget _ctaButton(EurekaColors eu, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
        decoration: BoxDecoration(
          color: eu.brand,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: eu.brand.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 8)),
          ],
        ),
        child: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
