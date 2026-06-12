import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../api/api_client.dart';
import '../flash/flash.dart';
import '../pet/floating_mascot.dart' show mascotSuppressed, releaseMascotSuppress;
import '../pet/pet_controller.dart';
import '../render/pet_view.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../widgets/toast.dart';
import 'pet_page.dart';

/// §9.2.2 孵化即 onboarding — 全新用户的第一屏。一条弧线在 ~30 秒交付产品 aha:
///
/// ```
/// 全屏蛋 →【点击越点越碎】→ 迸开 → REKA 现身(完整、戴帽+徽记,不摊组件)
///   →（起名/默认 Reka）→「随口说件今天的」→ 首次捕捉(打字)
///   →【魔法时刻】当场结构化成卡片 →「你记的都在这儿」→ 进 app
/// ```
///
/// 两条孵化硬要求(改自旧「轻点即瞬间破壳 + starter_drop 揭示弹窗」,§9.2.2):
/// ① **渐进破壳**:点击不是一下出 REKA,而是越点越碎(裂纹 + 抖动 + 触觉),
///    末击才迸开 —— 用户亲手把它孵出来,建立第一缕羁绊。
/// ② **出生不摊组件**:首孵不弹 `reka_drop_reveal`「稀有度 · 收下」揭示卡;
///    REKA 只呈现一只完整的、碰巧戴着帽子+徽记的伙伴(starter 件静默装好)。
///    收集/换装/稀有度留待用户自己逛到「我的岛」再发现(REKA 是角色不是 loadout)。
///
/// 由 [_PostAuthGate](../main.dart) 在 `!spawned` 时作为 home 挂载(`onDone` →
/// 切到 shell);也保留被 `pet_page` push 的旧路径(`onDone` 为空 → 进 PetPage)。
enum _Step { egg, born, name, invite, capturing, magic }

class PetSpawnPage extends StatefulWidget {
  /// Called when the onboarding arc finishes. When provided (root-gate mount),
  /// the gate swaps to the app shell. When null (legacy in-app push), we
  /// pushReplacement to the pet detail page instead.
  final VoidCallback? onDone;
  const PetSpawnPage({super.key, this.onDone});

  @override
  State<PetSpawnPage> createState() => _PetSpawnPageState();
}

class _PetSpawnPageState extends State<PetSpawnPage> with SingleTickerProviderStateMixin {
  final _pet = PetController.instance;
  final _nameCtrl = TextEditingController();
  final _captureCtrl = TextEditingController();
  late final AnimationController _shake;

  _Step _step = _Step.egg;
  int _cracks = 0; // 0.._maxTaps — 渐进破壳累积的裂纹数
  static const _maxTaps = 4;
  FlashResult? _result; // 魔法时刻的捕捉产物

  @override
  void initState() {
    super.initState();
    mascotSuppressed.value++; // this screen IS REKA — hide the floating one
    _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 340));
    // Defensive: already spawned somehow → skip the egg, go straight to the
    // invite (skipping the reveal/born celebration of an already-met pet).
    if (_pet.spawned) {
      _step = _Step.invite;
      _nameCtrl.text = _pet.pet?.name ?? 'Reka';
    }
  }

  @override
  void dispose() {
    releaseMascotSuppress();
    _shake.dispose();
    _nameCtrl.dispose();
    _captureCtrl.dispose();
    super.dispose();
  }

  // ── ① 渐进破壳 ──────────────────────────────────────────────────────────
  void _tapEgg() {
    if (_step != _Step.egg) return;
    _shake.forward(from: 0);
    final next = _cracks + 1;
    if (next < _maxTaps) {
      HapticFeedback.lightImpact();
      setState(() => _cracks = next);
    } else {
      // 末击:迸裂 → 孵化
      HapticFeedback.heavyImpact();
      setState(() => _cracks = _maxTaps);
      _hatch();
    }
  }

  Future<void> _hatch() async {
    try {
      await _pet.spawn();
      if (!mounted) return;
      // ② 不摊组件:starter_drop 已由服务端静默装好(就是它的样子);首孵
      // 不弹 reka_drop_reveal 揭示卡。直接进「现身」。
      setState(() => _step = _Step.born);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cracks = 0);
      showToast(context, '孵化失败：$e', error: true);
    }
  }

  Future<void> _confirmName() async {
    final name = _nameCtrl.text.trim();
    try {
      if (name.isNotEmpty && name != _pet.pet?.name) await _pet.rename(name);
      if (!mounted) return;
      setState(() => _step = _Step.invite);
    } catch (e) {
      if (!mounted) return;
      showToast(context, '保存失败：$e', error: true);
    }
  }

  // ── 魔法时刻:随口一句 → 当场结构化成卡片 ───────────────────────────────
  Future<void> _capture() async {
    final text = _captureCtrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = _Step.capturing);
    final api = ApiClient();
    try {
      final r = await sendFlash(api, text);
      if (!mounted) return;
      setState(() {
        _result = r;
        _step = _Step.magic;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.invite);
      showToast(context, '整理失败：$e', error: true);
    } finally {
      api.close();
    }
  }

  void _finish() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const PetPage()),
      );
    }
  }

  String get _petName => _pet.pet?.name ?? 'Reka';

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final p = _pet.pet;
    final skin = p?.skin ?? 'aurora';
    final isEgg = _step == _Step.egg;
    final genome = p?.genome ?? {'skin': skin, 'emblem': 'star', 'emblemColor': 'gold'};
    // celebrate on the born moment; idle otherwise.
    final state = _step == _Step.born ? 'celebrate' : 'idle';
    // Shrink the creature once we move into the conversational capture steps so
    // the text field + magic card have room (the column scrolls regardless).
    final petBox = (_step == _Step.invite || _step == _Step.capturing || _step == _Step.magic)
        ? 132.0
        : 220.0;

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
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // egg / creature — tappable only during 渐进破壳
                    GestureDetector(
                      onTap: isEgg ? _tapEgg : null,
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedBuilder(
                        animation: _shake,
                        builder: (context, child) {
                          final t = _shake.value;
                          // damped sideways wobble, amplitude grows with cracks
                          final amp = (3 + _cracks * 2.5) * (1 - t);
                          final dx = math.sin(t * math.pi * 3) * amp;
                          return Transform.translate(offset: Offset(dx, 0), child: child);
                        },
                        child: SizedBox(
                          width: petBox,
                          height: petBox,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // IgnorePointer: PetView is a WKWebView platform
                              // view — it swallows touches, so without this the
                              // egg's GestureDetector never sees the tap (the
                              // floating mascot wraps its ball the same way).
                              IgnorePointer(
                                child: PetView(
                                  key: ValueKey('spawn-${isEgg ? 'egg' : 'pet'}-$state'),
                                  genome: genome,
                                  egg: isEgg,
                                  state: state,
                                  scale: petBox >= 220 ? 7 : 4.2,
                                ),
                              ),
                              // 裂纹覆盖层(仅蛋阶段)
                              if (isEgg && _cracks > 0)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: _CrackPainter(_cracks, eu.textHi),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('一颗灵感蛋正在孵化',
                textAlign: TextAlign.center,
                style: TextStyle(color: eu.textHi, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text('它会成为陪着你的灵感伙伴 · Reka。\n轻点蛋，亲手把它唤醒。',
                textAlign: TextAlign.center,
                style: TextStyle(color: eu.textMid, fontSize: 14.5, height: 1.55)),
            const SizedBox(height: 18),
            // 进度点:越点越亮,提示「再点几下」
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_maxTaps, (i) {
                final on = i < _cracks;
                return Container(
                  width: 8, height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? eu.brand : eu.border,
                  ),
                );
              }),
            ),
          ],
        );
      case _Step.born:
        return _block(eu,
            title: '这是 $_petName',
            body: '你专属的灵感伙伴诞生了。\n往后你随口说的每件小事，都交给它打理。',
            cta: '给它起名  →',
            onCta: () => setState(() => _step = _Step.name));
      case _Step.name:
        return _nameBlock(eu);
      case _Step.invite:
        return _captureBlock(eu);
      case _Step.capturing:
        return Column(children: [
          Text('$_petName 正在帮你整理…', style: TextStyle(color: eu.textMid, fontSize: 14)),
          const SizedBox(height: 16),
          SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: eu.brand),
          ),
        ]);
      case _Step.magic:
        return _magicBlock(eu);
    }
  }

  Widget _nameBlock(EurekaColors eu) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('给 $_petName 起个名字',
            style: TextStyle(color: eu.textHi, fontSize: 20, fontWeight: FontWeight.w700)),
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

  // 引导首捕:REKA 邀请 + 输入框(打字;正式上线无软件语音,语音=硬件录音卡)
  Widget _captureBlock(EurekaColors eu) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('来，随口说件今天的',
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textHi, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text('想到什么记什么——一笔花销、一个念头、一件要做的事。\n$_petName 会当场替你整理成卡片。',
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textMid, fontSize: 13.5, height: 1.5)),
        const SizedBox(height: 18),
        TextField(
          controller: _captureCtrl,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.send,
          style: TextStyle(color: eu.textHi, fontSize: 15),
          decoration: InputDecoration(
            hintText: '例如：早上买咖啡花了 28 块',
            hintStyle: TextStyle(color: eu.textLo, fontSize: 14),
            filled: true,
            fillColor: eu.surfaceRaised,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: eu.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: eu.brand, width: 1.6),
            ),
          ),
          onSubmitted: (_) => _capture(),
        ),
        const SizedBox(height: 16),
        _ctaButton(eu, '交给 $_petName  →', _capture),
      ],
    );
  }

  // 魔法时刻:展示捕捉产物的卡片 + 「你记的都在这儿」→ 进 app
  Widget _magicBlock(EurekaColors eu) {
    final cards = _result?.cards ?? const [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('✨ $_petName 替你记下了',
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textHi, fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (cards.isNotEmpty)
          for (final c in cards) SkillCard(c, layoutOverride: 'horizontal')
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: eu.surfaceRaised,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: eu.border),
            ),
            child: Text(
              _result?.summary.isNotEmpty == true
                  ? _result!.summary
                  : '记下了。往后你说的每件事，都会落在资产库里。',
              style: TextStyle(color: eu.textMid, fontSize: 14, height: 1.5),
            ),
          ),
        const SizedBox(height: 18),
        Text('你记的都在「资产库」里，随时找得到。',
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textMid, fontSize: 13.5, height: 1.5)),
        const SizedBox(height: 20),
        Center(child: _ctaButton(eu, '开始使用  →', _finish)),
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
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// 渐进破壳的裂纹覆盖层 —— 从蛋中心向外画 `n` 条锯齿裂纹(确定性,不随重绘抖动)。
/// 设计可后续替换为真实裂纹贴图;此为编码侧的 v1 近似。
class _CrackPainter extends CustomPainter {
  final int n;
  final Color color;
  const _CrackPainter(this.n, this.color);

  // 4 条裂纹的基准方向(弧度)+ 锯齿横向偏移因子,固定以保证累积稳定。
  static const _angles = [-0.5, 0.85, 2.15, 3.7];
  static const _jitter = [0.18, -0.22, 0.2, -0.16];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.46); // 蛋视觉中心略偏上
    final r = size.shortestSide * 0.30;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < n && i < _angles.length; i++) {
      final a = _angles[i];
      final j = _jitter[i];
      final dir = Offset(math.cos(a), math.sin(a));
      final perp = Offset(-dir.dy, dir.dx);
      final path = Path()..moveTo(c.dx, c.dy);
      // 3 段锯齿,逐段向外 + 交替横移
      for (var s = 1; s <= 3; s++) {
        final along = c + dir * (r * s / 3);
        final side = (s.isOdd ? 1.0 : -1.0) * j * r * (s / 3);
        final pt = along + perp * side;
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_CrackPainter old) => old.n != n || old.color != color;
}
