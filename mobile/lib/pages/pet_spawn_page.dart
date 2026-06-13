import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../api/api_client.dart';
import '../flash/flash.dart';
import '../pet/floating_mascot.dart'
    show mascotSuppressed, releaseMascotSuppress;
import '../pet/pet_controller.dart';
import '../render/pet_view.dart';
import '../render/skill_card.dart';
import '../theme/app_theme.dart';
import '../theme/eureka_colors.dart';
import '../ble_flash/ble_flash_manager.dart';
import '../ble_flash/flash_file_task.dart';
import '../ble_flash/flash_file_workflow.dart';
import '../device/device_controller.dart';
import '../widgets/toast.dart';
import 'device_pairing_page.dart';
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
// 孵化弧线:蛋→破壳→现身→起名→【连卡提示】→(有卡:硬件录一句 / 没卡:打字)→ 进 app
enum _Step {
  egg,
  born,
  name,
  pairPrompt,
  invite,
  capturing,
  magic,
  hardwareWait,
}

class PetSpawnPage extends StatefulWidget {
  /// Called when the onboarding arc finishes. When provided (root-gate mount),
  /// the gate swaps to the app shell. When null (legacy in-app push), we
  /// pushReplacement to the pet detail page instead.
  final VoidCallback? onDone;
  const PetSpawnPage({super.key, this.onDone});

  @override
  State<PetSpawnPage> createState() => _PetSpawnPageState();
}

class _PetSpawnPageState extends State<PetSpawnPage>
    with SingleTickerProviderStateMixin {
  final _pet = PetController.instance;
  final _nameCtrl = TextEditingController();
  final _captureCtrl = TextEditingController();
  late final AnimationController _shake;

  _Step _step = _Step.egg;
  int _cracks = 0; // 0.._maxTaps — 渐进破壳累积的裂纹数
  static const _maxTaps = 4;
  FlashResult? _result; // 魔法时刻的捕捉产物
  String _captureError = '';
  // 硬件路径:录音结束只是中间态。onboarding 必须等服务端 ASR + Flash
  // pipeline 完成并返回至少一张成功卡片,才允许完成。
  bool _wasFlashing = false;
  int _hardwareRun = 0;
  String _hardwareFileName = '';
  String _hardwareStatus = '';
  String _hardwareError = '';

  @override
  void initState() {
    super.initState();
    mascotSuppressed.value++; // this screen IS REKA — hide the floating one
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    BleFlashManager.instance.isFlashing.addListener(_onFlashingChanged);
    // Defensive: already spawned somehow → skip the egg, go straight to the
    // pair prompt (skipping the reveal/born celebration of an already-met pet).
    if (_pet.spawned) {
      _step = _Step.pairPrompt;
      _nameCtrl.text = _pet.pet?.name ?? 'Reka';
    }
  }

  @override
  void dispose() {
    releaseMascotSuppress();
    BleFlashManager.instance.isFlashing.removeListener(_onFlashingChanged);
    _shake.dispose();
    _nameCtrl.dispose();
    _captureCtrl.dispose();
    super.dispose();
  }

  // 录音卡录完一条(isFlashing true→false)且正停在硬件等待步 → 等待后端结果。
  void _onFlashingChanged() {
    final now = BleFlashManager.instance.isFlashing.value;
    if (_wasFlashing && !now && _step == _Step.hardwareWait && mounted) {
      final fileName = _lastFlashFileName();
      if (fileName.isNotEmpty) {
        final run = ++_hardwareRun;
        setState(() {
          _hardwareFileName = fileName;
          _hardwareStatus = '$_petName 已接住,正在同步录音…';
          _hardwareError = '';
        });
        unawaited(_waitForHardwareResult(fileName, run));
      }
    }
    _wasFlashing = now;
  }

  String _lastFlashFileName() {
    final event = BleFlashManager.instance.lastEndEvent;
    final info = (event?['info'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (info['file'] ?? info['fileName'] ?? event?['file'] ?? '')
        .toString();
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
      setState(() => _step = _Step.pairPrompt);
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
      // onboarding 首捕统一进入 flash session；source 保留 typed 作为真实输入来源。
      final r = await sendFlash(
        api,
        text,
        source: 'typed',
        captureSessionType: 'flash',
      );
      if (!_hasSuccessCards(r.cards)) {
        if (!mounted) return;
        setState(() {
          _step = _Step.invite;
          _captureError = '这句话还没有整理成卡片,换一句要记录的事试试';
        });
        showToast(context, _captureError, error: true);
        return;
      }
      await _pet.completeOnboarding(sessionId: r.sessionId);
      if (!mounted) return;
      setState(() {
        _result = r;
        _step = _Step.magic;
        _captureError = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.invite;
        _captureError = '$e';
      });
      showToast(context, '整理失败：$e', error: true);
    } finally {
      api.close();
    }
  }

  bool _hasSuccessCards(List<Map<String, dynamic>> cards) {
    return cards.any((c) {
      if (c['card_type'] == 'error') return false;
      return (c['asset_id']?.toString().isNotEmpty == true) ||
          (c['event_id']?.toString().isNotEmpty == true) ||
          (c['contact_id']?.toString().isNotEmpty == true);
    });
  }

  Future<void> _waitForHardwareResult(String fileName, int run) async {
    final started = DateTime.now();
    String recordingId = '';
    final api = ApiClient();
    try {
      while (_isCurrentHardwareRun(run, fileName)) {
        final task = FlashFileWorkflow.instance.realtimeTaskForFile(fileName);
        if (task != null) {
          if (task.stage == FlashFileStage.failed) {
            _setHardwareError(run, fileName, task.lastError ?? '同步失败,请再录一次');
            return;
          }
          recordingId = task.eurekaRecordingId ?? '';
          if (recordingId.isNotEmpty) break;
          _setHardwareStatus(run, fileName, _statusForTask(task));
        }
        if (DateTime.now().difference(started) > const Duration(minutes: 3)) {
          _setHardwareError(run, fileName, '整理时间过长,可以再录一次或改用打字');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }

      while (_isCurrentHardwareRun(run, fileName)) {
        final res = await api.getJson('/api/flash/recordings/$recordingId');
        final recording =
            ((res as Map)['recording'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final process = recording['process_status']?.toString() ?? '';
        final cards = ((recording['result_cards'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        if (process == 'done') {
          if (!_hasSuccessCards(cards)) {
            _setHardwareError(run, fileName, '这条录音没有整理出卡片,请再录一次或改用打字');
            return;
          }
          final sessionId = recording['session_id']?.toString() ?? '';
          await _pet.completeOnboarding(
            sessionId: sessionId,
            recordingId: recordingId,
          );
          if (!mounted || !_isCurrentHardwareRun(run, fileName)) return;
          setState(() {
            _result = FlashResult(
              ok: true,
              sessionId: sessionId,
              inputTurnId: recording['input_turn_id']?.toString() ?? '',
              reply: '',
              summary: recording['result_summary']?.toString() ?? '',
              cards: cards,
              error: '',
            );
            _hardwareStatus = '';
            _hardwareError = '';
            _step = _Step.magic;
          });
          return;
        }
        if (process == 'failed') {
          _setHardwareError(
            run,
            fileName,
            recording['error_message']?.toString() ?? '整理失败,请再录一次',
          );
          return;
        }
        _setHardwareStatus(run, fileName, _statusForRecording(recording));
        if (DateTime.now().difference(started) > const Duration(minutes: 3)) {
          _setHardwareError(run, fileName, '整理时间过长,可以再录一次或改用打字');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    } catch (e) {
      _setHardwareError(run, fileName, '处理失败：$e');
    } finally {
      api.close();
    }
  }

  bool _isCurrentHardwareRun(int run, String fileName) {
    return mounted &&
        _step == _Step.hardwareWait &&
        _hardwareRun == run &&
        _hardwareFileName == fileName;
  }

  String _statusForTask(FlashFileTask task) {
    return switch (task.stage) {
      FlashFileStage.queued => '$_petName 已接住,正在排队…',
      FlashFileStage.syncingFromCard => '正在从录音卡同步…',
      FlashFileStage.convertingToMp3 => '正在转换音频…',
      FlashFileStage.uploadingToS3 ||
      FlashFileStage.requestingS3Presign ||
      FlashFileStage.s3Uploaded => '正在上传音频…',
      FlashFileStage.notifyingEureka => '正在提交给 $_petName…',
      FlashFileStage.deletingDeviceFile => '正在收尾…',
      _ => '$_petName 已接住,正在处理…',
    };
  }

  String _statusForRecording(Map<String, dynamic> recording) {
    final process = recording['process_status']?.toString() ?? '';
    return switch (process) {
      'pending' || 'asr_processing' => '正在听写录音…',
      'asr_done' || 'processing_flash' => '听写好了,正在整理成卡片…',
      _ => '$_petName 已接住,正在处理…',
    };
  }

  void _setHardwareStatus(int run, String fileName, String status) {
    if (!_isCurrentHardwareRun(run, fileName)) return;
    setState(() => _hardwareStatus = status);
  }

  void _setHardwareError(int run, String fileName, String message) {
    if (!_isCurrentHardwareRun(run, fileName)) return;
    setState(() {
      _hardwareStatus = '';
      _hardwareError = message;
    });
  }

  void _resetHardwareCapture() {
    setState(_resetHardwareFields);
  }

  void _resetHardwareFields() {
    _hardwareRun++;
    _hardwareFileName = '';
    _hardwareStatus = '';
    _hardwareError = '';
  }

  void _finish() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const PetPage()));
    }
  }

  String get _petName => _pet.pet?.name ?? 'Reka';

  @override
  Widget build(BuildContext context) {
    final eu = context.eu;
    final p = _pet.pet;
    final skin = p?.skin ?? 'aurora';
    final isEgg = _step == _Step.egg;
    final genome =
        p?.genome ?? {'skin': skin, 'emblem': 'star', 'emblemColor': 'gold'};
    // celebrate on the born moment; idle otherwise.
    final state = _step == _Step.born ? 'celebrate' : 'idle';
    // Shrink the creature once we move into the conversational capture steps so
    // the text field + magic card have room (the column scrolls regardless).
    final petBox =
        (_step == _Step.invite ||
            _step == _Step.capturing ||
            _step == _Step.magic ||
            _step == _Step.pairPrompt ||
            _step == _Step.hardwareWait)
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
                      eu.brand.withValues(
                        alpha: eu.brightness == Brightness.dark ? 0.22 : 0.14,
                      ),
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
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
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
                                  key: ValueKey(
                                    'spawn-${isEgg ? 'egg' : 'pet'}-$state',
                                  ),
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
                                      painter: _CrackPainter(
                                        _cracks,
                                        eu.textHi,
                                      ),
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
            Text(
              '一颗灵感蛋正在孵化',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: eu.textHi,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '它会成为陪着你的灵感伙伴 · Reka。\n轻点蛋，亲手把它唤醒。',
              textAlign: TextAlign.center,
              style: TextStyle(color: eu.textMid, fontSize: 14.5, height: 1.55),
            ),
            const SizedBox(height: 18),
            // 进度点:越点越亮,提示「再点几下」
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_maxTaps, (i) {
                final on = i < _cracks;
                return Container(
                  width: 8,
                  height: 8,
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
        return _block(
          eu,
          title: '这是 $_petName',
          body: '你专属的灵感伙伴诞生了。\n往后你随口说的每件小事，都交给它打理。',
          cta: '给它起名  →',
          onCta: () => setState(() => _step = _Step.name),
        );
      case _Step.name:
        return _nameBlock(eu);
      case _Step.invite:
        return _captureBlock(eu);
      case _Step.capturing:
        return Column(
          children: [
            Text(
              '$_petName 正在帮你整理…',
              style: TextStyle(color: eu.textMid, fontSize: 14),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: eu.brand,
              ),
            ),
          ],
        );
      case _Step.magic:
        return _magicBlock(eu);
      case _Step.pairPrompt:
        return _pairPromptBlock(eu);
      case _Step.hardwareWait:
        return _hardwareWaitBlock(eu);
    }
  }

  Widget _nameBlock(EurekaColors eu) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '给 $_petName 起个名字',
          style: TextStyle(
            color: eu.textHi,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          maxLength: 8,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: eu.textHi,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
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
        Text(
          '来，随口说件今天的',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: eu.textHi,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '想到什么记什么——一笔花销、一个念头、一件要做的事。\n$_petName 会当场替你整理成卡片。',
          textAlign: TextAlign.center,
          style: TextStyle(color: eu.textMid, fontSize: 13.5, height: 1.5),
        ),
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
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
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
        if (_captureError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            _captureError,
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.accentRed, fontSize: 12.5, height: 1.4),
          ),
        ],
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
        Text(
          '✨ $_petName 替你整理好了',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: eu.textHi,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
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
        Text(
          '你记的都在「资产库」里，随时找得到。',
          textAlign: TextAlign.center,
          style: TextStyle(color: eu.textMid, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 20),
        Center(child: _ctaButton(eu, '开始使用  →', _finish)),
      ],
    );
  }

  // ① 连卡提示(孵化后第一件事)—— 决定首捕用哪种方式:有卡用硬件、没卡用打字。
  // 录音卡是「随口说」的零摩擦入口;没卡/想稍后的人可走打字,绝不卡住 onboarding。
  Widget _pairPromptBlock(EurekaColors eu) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '🎙️ 有录音卡吗?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: eu.textHi,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '连上它,按一下就能随口记,$_petName 当场帮你整理 ——\n不用打字、不用掏手机。还没有卡也行,先用打字试试。',
          textAlign: TextAlign.center,
          style: TextStyle(color: eu.textMid, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 22),
        _ctaButton(eu, '连接录音卡  →', _connectDevice),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _step = _Step.invite),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              '我还没有卡,用打字',
              style: TextStyle(
                color: eu.brand,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _connectDevice() async {
    // 复用 jigong 的配对页;返回后按是否绑成分叉:绑成 → 硬件首捕(按卡说);
    // 没绑成(取消/失败/没扫到)→ 退回打字首捕,绝不卡住。
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const DevicePairingPage()));
    if (!mounted) return;
    setState(() {
      _resetHardwareFields();
      _step = DeviceController.instance.isBound
          ? _Step.hardwareWait
          : _Step.invite;
    });
  }

  // ② 硬件首捕 —— 已连卡:让用户按一下录音卡说件今天的。录完只算接住,
  // 必须等后端返回成功卡片后才完成 onboarding。
  Widget _hardwareWaitBlock(EurekaColors eu) {
    final hasRecording = _hardwareFileName.isNotEmpty;
    if (hasRecording) {
      final isError = _hardwareError.isNotEmpty;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isError ? '这条还没整理成卡片' : '$_petName 已接住',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isError ? eu.accentRed : eu.textHi,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            isError
                ? _hardwareError
                : (_hardwareStatus.isNotEmpty ? _hardwareStatus : '正在帮你整理成卡片…'),
            textAlign: TextAlign.center,
            style: TextStyle(color: eu.textMid, fontSize: 13.5, height: 1.5),
          ),
          const SizedBox(height: 18),
          if (!isError)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: eu.brand,
              ),
            ),
          if (isError) ...[
            _ctaButton(eu, '再录一次', _resetHardwareCapture),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() {
                _resetHardwareFields();
                _step = _Step.invite;
              }),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 16,
                ),
                child: Text(
                  '改用打字',
                  style: TextStyle(
                    color: eu.brand,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '按一下录音卡,说件今天的',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: eu.textHi,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '随口说一笔花销、一个念头、一件要做的事 ——\n$_petName 会接住它,帮你整理成卡片。',
          textAlign: TextAlign.center,
          style: TextStyle(color: eu.textMid, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 18),
        // 「正在听」实时指示(录音卡按下时 BleFlashManager.isFlashing=true)
        ValueListenableBuilder<bool>(
          valueListenable: BleFlashManager.instance.isFlashing,
          builder: (_, flashing, _) => AnimatedOpacity(
            opacity: flashing ? 1 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: eu.brand,
                  ),
                ),
                const SizedBox(width: 8),
                Text('正在听…', style: TextStyle(color: eu.brand, fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => setState(() => _step = _Step.invite),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              '改用打字',
              style: TextStyle(color: eu.textMid, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _block(
    EurekaColors eu, {
    required String title,
    required String body,
    required String cta,
    required VoidCallback onCta,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: eu.textHi,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: eu.textMid, fontSize: 14.5, height: 1.55),
        ),
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
            BoxShadow(
              color: eu.brand.withValues(alpha: 0.4),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
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
