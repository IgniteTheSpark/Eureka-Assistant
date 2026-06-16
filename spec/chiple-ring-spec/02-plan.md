# ChipletRing 戒指录音接入 · 里程碑 2 实施计划(接入"闪念")

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development 或 superpowers:executing-plans 逐任务实施。步骤用 `- [ ]` 勾选框。
>
> **前置:里程碑 1 已跑通**(见 [00-spec.md](00-spec.md) §7):戒指连接稳定、双击实时录音、清晰 PCM 已能进 app。本计划在其之上把戒指录音接进现有"闪念"→ 生成卡片。

**Goal:** 戒指双击录音 → 实时 PCM → WAV → 腾讯 ASR 转写 → 文本 `sendFlash()` → 生成闪念卡片,体验与录音卡一致。

**Architecture:** 方案 A(已确认)——新增轻量 `RingCaptureController`,**复用现有后端两件套**(`TencentAsrS3Client.recognizeFile` 转写 + `flash/flash.dart` 的 `sendFlash` 建卡),**不碰**录音卡专用的 `FlashFileWorkflow`(那是 W1/W2 的 Opus 文件同步)。戒指音频走里程碑 1 已验证的实时流(`ChipletRing.startRecording()` + 双击手势)。

**Tech Stack:** Flutter/Dart;复用 `chiplet_ring` 插件(里程碑1)、`TencentAsrS3Client`、`sendFlash`、`FlashProcessingStatus`。

**关键复用点(已核实):**
- 录音:`ChipletRing`(`lib`:`packages/chiplet_ring`)——`startRecording()→Stream<RingAudioFrame>`、`stopRecording()`、`keyEvents`(双击=2)、`pcmToWav(pcm,sampleRate:8000,channels)`。
- 转写:`TencentAsrS3Client.recognizeFile(file)` → `TencentAsrSyncResult`(`mobile/lib/api/tencent_asr_s3_client.dart`;直传 `/api/platform/speech/asr`,multipart,baseUrl=`Config.tencentAsrBase`)。**不需要 S3 presign**(小文件直传即可)。
- 建卡:`sendFlash(api, text, source:'voice')` → `FlashResult`(`mobile/lib/flash/flash.dart`,打 `/api/flash`,走 `Config.apiBase`)。
- 启动点:`mobile/lib/main.dart:163` 登录后 `BleFlashManager.instance.start()`,在此并排启动戒指捕捉。
- 结果展示:`FlashProcessingStatus.instance`(`mobile/lib/flash/flash_processing_state.dart`)+ 现有 flash sheet。

> ⚠️ 与里程碑 1 一致:真机 + 真戒指联调为主;`/api/flash` 需要可用后端(`--dart-define=API_BASE=<prod>` 或本地后端),ASR 走 `tencentAsrBase` 独立服务。

---

## 文件结构

**新增:**
- `mobile/lib/ring/ring_capture_controller.dart` —— 戒指捕捉控制器(生命周期 + 双击触发 + PCM 累积 + ASR + 建卡)
- `mobile/lib/ring/ring_capture_controller_test.dart`(放 `mobile/test/ring/`)—— 状态机单测
- `mobile/lib/ring/ring_asr.dart` —— 薄封装:WAV→`recognizeFile`→文本(便于 mock 单测)

**改动:**
- `mobile/lib/main.dart` —— 登录后启动/停止 `RingCaptureController`(与 `BleFlashManager` 并排)
- `mobile/lib/pages/device_pairing_page.dart` 或新增戒指入口 —— 让用户能在正式 UI(非 debug)里连戒指(最小入口;完整配对 UX 见 §尾"后续")

---

## Task 1: ring_asr.dart —— WAV→文本 薄封装(TDD)

**Files:**
- Create: `mobile/lib/ring/ring_asr.dart`
- Test: `mobile/test/ring/ring_asr_test.dart`

- [ ] **Step 1: 写失败测试(注入假 ASR 客户端,验证 PCM→WAV→识别→返回文本)**

```dart
// mobile/test/ring/ring_asr_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/ring/ring_asr.dart';

void main() {
  test('transcribePcm writes wav and returns recognized text', () async {
    String? seenPath;
    final asr = RingAsr(
      recognize: (File f) async { seenPath = f.path; return '你好世界'; },
    );
    final pcm = Uint8List.fromList(List.filled(1600, 0));
    final text = await asr.transcribePcm(pcm, sampleRate: 8000, channels: 1);
    expect(text, '你好世界');
    expect(seenPath, isNotNull);
    expect(File(seenPath!).existsSync(), isTrue);
    expect(seenPath!.endsWith('.wav'), isTrue);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd mobile && flutter test test/ring/ring_asr_test.dart`
Expected: FAIL — `ring_asr.dart` 不存在。

- [ ] **Step 3: 实现 ring_asr.dart**

```dart
// mobile/lib/ring/ring_asr.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:path_provider/path_provider.dart';

/// Recognize callback — injectable for tests. Real impl wraps TencentAsrS3Client.recognizeFile.
typedef RecognizeFn = Future<String> Function(File wav);

class RingAsr {
  RingAsr({required RecognizeFn recognize}) : _recognize = recognize;
  final RecognizeFn _recognize;

  /// PCM -> WAV (temp file) -> recognize -> text.
  Future<String> transcribePcm(Uint8List pcm,
      {required int sampleRate, required int channels}) async {
    final wav = pcmToWav(pcm, sampleRate: sampleRate, channels: channels);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ring_capture_${pcm.length}.wav';
    final file = await File(path).writeAsBytes(wav);
    return _recognize(file);
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd mobile && flutter test test/ring/ring_asr_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/admin/workwork/eureka-staff/Eureka-Assistant
git add mobile/lib/ring/ring_asr.dart mobile/test/ring/ring_asr_test.dart
git commit -m "feat(ring): ring_asr — pcm->wav->recognize wrapper (tdd)"
```

---

## Task 2: RingCaptureController —— 捕捉状态机(TDD)

**Files:**
- Create: `mobile/lib/ring/ring_capture_controller.dart`
- Test: `mobile/test/ring/ring_capture_controller_test.dart`

**职责:** 持有 `ChipletRing`;订阅 `keyEvents`,双击(2)切换 录/停;录时累积 `RingAudioFrame.pcm`;停时 → `RingAsr.transcribePcm` → `sendFlash` → 暴露结果。可注入依赖以便单测。

- [ ] **Step 1: 写失败测试(用 fake 流驱动双击+音频,断言 onCard 被调用、文本来自 ASR)**

```dart
// mobile/test/ring/ring_capture_controller_test.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/ring/ring_capture_controller.dart';

void main() {
  test('double-click starts capture; second stops -> transcribe -> card', () async {
    final keys = StreamController<int>.broadcast();
    final audio = StreamController<List<int>>.broadcast();
    final cards = <String>[];

    final c = RingCaptureController(
      keyEvents: keys.stream,
      startAudio: () { return audio.stream.map((b) =>
          RingFrame(pcm: Uint8List.fromList(b), channels: 1)); },
      stopAudio: () async {},
      transcribe: (pcm, sr, ch) async => 'hello ${pcm.length}',
      createCard: (text) async { cards.add(text); },
    );
    c.start();

    keys.add(2);                 // start
    audio.add(List.filled(800, 1));
    audio.add(List.filled(800, 2));
    await Future<void>.delayed(Duration.zero);
    keys.add(2);                 // stop -> transcribe -> card
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(cards.length, 1);
    expect(cards.first, 'hello 1600');
    await c.dispose();
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd mobile && flutter test test/ring/ring_capture_controller_test.dart`
Expected: FAIL — 类不存在。

- [ ] **Step 3: 实现 ring_capture_controller.dart**

```dart
// mobile/lib/ring/ring_capture_controller.dart
import 'dart:async';
import 'dart:typed_data';

/// Minimal frame shape so the controller is testable without the plugin types.
class RingFrame {
  RingFrame({required this.pcm, required this.channels});
  final Uint8List pcm;
  final int channels;
}

typedef StartAudioFn = Stream<RingFrame> Function();
typedef StopAudioFn = Future<void> Function();
typedef TranscribeFn = Future<String> Function(Uint8List pcm, int sampleRate, int channels);
typedef CreateCardFn = Future<void> Function(String text);

/// Double-click the ring to start a capture; double-click again to stop, which
/// transcribes the accumulated PCM and files it as a flash card.
class RingCaptureController {
  RingCaptureController({
    required Stream<int> keyEvents,
    required StartAudioFn startAudio,
    required StopAudioFn stopAudio,
    required TranscribeFn transcribe,
    required CreateCardFn createCard,
    this.sampleRate = 8000,
  })  : _keyEvents = keyEvents,
        _startAudio = startAudio,
        _stopAudio = stopAudio,
        _transcribe = transcribe,
        _createCard = createCard;

  final Stream<int> _keyEvents;
  final StartAudioFn _startAudio;
  final StopAudioFn _stopAudio;
  final TranscribeFn _transcribe;
  final CreateCardFn _createCard;
  final int sampleRate;

  StreamSubscription<int>? _keySub;
  StreamSubscription<RingFrame>? _audioSub;
  final BytesBuilder _buf = BytesBuilder();
  int _channels = 1;
  bool _recording = false;

  void start() {
    _keySub ??= _keyEvents.listen((k) {
      if (k == 2) _toggle();
    });
  }

  void _toggle() {
    if (_recording) {
      _stop();
    } else {
      _beginRecording();
    }
  }

  void _beginRecording() {
    _recording = true;
    _buf.clear();
    _audioSub = _startAudio().listen((f) {
      _channels = f.channels;
      _buf.add(f.pcm);
    });
  }

  Future<void> _stop() async {
    _recording = false;
    await _audioSub?.cancel();
    _audioSub = null;
    await _stopAudio();
    final pcm = _buf.toBytes();
    if (pcm.isEmpty) return;
    final text = await _transcribe(pcm, sampleRate, _channels);
    if (text.trim().isEmpty) return;
    await _createCard(text);
  }

  Future<void> dispose() async {
    await _keySub?.cancel();
    await _audioSub?.cancel();
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd mobile && flutter test test/ring/ring_capture_controller_test.dart`
Expected: PASS（1 测试）。

- [ ] **Step 5: Commit**

```bash
cd /Users/admin/workwork/eureka-staff/Eureka-Assistant
git add mobile/lib/ring/ring_capture_controller.dart mobile/test/ring/ring_capture_controller_test.dart
git commit -m "feat(ring): RingCaptureController state machine (tdd)"
```

---

## Task 3: 接线真实依赖(ChipletRing + 腾讯ASR + sendFlash)

**Files:**
- Create: `mobile/lib/ring/ring_capture_service.dart`(组装真实依赖的工厂)
- Modify: `mobile/lib/main.dart`

- [ ] **Step 1: 写组装工厂 ring_capture_service.dart**

```dart
// mobile/lib/ring/ring_capture_service.dart
import 'dart:io';
import 'package:chiplet_ring/chiplet_ring.dart';
import '../api/api_client.dart';
import '../api/tencent_asr_s3_client.dart';
import '../config.dart';
import '../flash/flash.dart';
import 'ring_asr.dart';
import 'ring_capture_controller.dart';

/// Builds a RingCaptureController wired to the real ring, Tencent ASR, and /api/flash.
RingCaptureController buildRingCapture(ApiClient api) {
  final ring = ChipletRing();
  final asrClient = TencentAsrS3Client(baseUrl: Config.tencentAsrBase);
  final asr = RingAsr(
    recognize: (File wav) async {
      final r = await asrClient.recognizeFile(file: wav);
      return r.text; // TencentAsrSyncResult.text
    },
  );
  return RingCaptureController(
    keyEvents: ring.keyEvents,
    startAudio: () => ring.startRecording().map(
      (f) => RingFrame(pcm: f.pcm, channels: f.channels),
    ),
    stopAudio: ring.stopRecording,
    transcribe: (pcm, sr, ch) => asr.transcribePcm(pcm, sampleRate: sr, channels: ch),
    createCard: (text) async { await sendFlash(api, text, source: 'voice'); },
  );
}
```

> 校准点:确认 `TencentAsrSyncResult` 的文本字段名(此处用 `.text`;若不同则改)。确认 `TencentAsrS3Client` 构造参数(baseUrl)。确认 `ApiClient` 获取方式(main.dart 里已有实例)。

- [ ] **Step 2: 在 main.dart 登录后启动(紧挨 BleFlashManager.start)**

在 `mobile/lib/main.dart` 约 163 行 `BleFlashManager.instance.start();` 之后添加(并保存引用以便登出时 dispose):

```dart
// 戒指实时录音 → 闪念(里程碑2)。仅在已有戒指连接时产生效果;无戒指则空转。
_ringCapture = buildRingCapture(api)..start();
```
并在登出/auth 失效处 `await _ringCapture?.dispose(); _ringCapture = null;`(参照 BleFlashManager 的停止位置)。顶部 import `ring/ring_capture_service.dart`、`ring/ring_capture_controller.dart`。

- [ ] **Step 3: 编译通过**

Run: `cd mobile && flutter build apk --debug`
Expected: BUILD SUCCESSFUL。（若 `r.text`/构造参数对不上,按编译错误校准后再过。）

- [ ] **Step 4: Commit**

```bash
cd /Users/admin/workwork/eureka-staff/Eureka-Assistant
git add mobile/lib/ring/ring_capture_service.dart mobile/lib/main.dart
git commit -m "feat(ring): wire RingCaptureController to ring + tencent ASR + sendFlash"
```

---

## Task 4: 正式 UI 里能连戒指(最小入口)

**Files:**
- Modify: `mobile/lib/pages/device_pairing_page.dart`(或新增 `mobile/lib/ring/ring_pairing_section.dart`)

里程碑 1 的连接入口在 debug 页。里程碑 2 要让普通用户能连戒指。最小做法:在现有设备配对页加一个"戒指"区块,复用 `ChipletRing.startScan/state/connect`(逻辑同 debug 页,但去掉 `kDebugMode` 门控)。

- [ ] **Step 1: 加戒指扫描/连接区块**

在设备配对页加一个 `ChipletRing` 实例 + 一段「扫描戒指 / 选择连接」UI(列表项点连接),状态用 `ChipletRing.state`。代码可直接搬 `ring_debug_page.dart` 的扫描/连接部分(不含录音/文件按钮)。

- [ ] **Step 2: 编译 + 真机确认能在正式页连上戒指**

Run: `cd mobile && flutter run --debug`(真机)
Expected: 在设备配对页能扫描到戒指、点连接后状态变 connected。

- [ ] **Step 3: Commit**

```bash
cd /Users/admin/workwork/eureka-staff/Eureka-Assistant
git add mobile/lib/pages/device_pairing_page.dart
git commit -m "feat(ring): ring scan/connect entry in device pairing page"
```

---

## Task 5: 端到端真机联调(里程碑2 验收)

> 需要:真机 + 真戒指 + 可用后端(`flutter run --debug --dart-define=API_BASE=<可用后端>`;ASR 走 tencentAsrBase)。

- [ ] **Step 1: 跑通 双击→说话→双击→出卡片**

操作:登录 → 设备页连戒指 → 双击戒指说一句「明天下午三点开会」→ 再双击 → 等待。
预期:ASR 转写出文本 → `sendFlash` 生成对应卡片(待办/日程),在时间线/卡片列表可见。

- [ ] **Step 2: 看日志校准**

`adb logcat | grep -iE 'ChipletRing|recognize|sync_asr|/api/flash'`
- 若 ASR 返回空/报错:见下方校准点(采样率/格式)。
- 若卡片没生成:确认 `/api/flash` 状态码(API_BASE 是否指向可用后端)。

- [ ] **Step 3: 回归——录音卡不受影响**

确认现有 W1/W2 录音卡的闪念流程仍正常(连接、录音、生成卡片),戒指捕捉与之并存不冲突。

---

## 校准点(真机/后端实测确认)

1. **ASR 采样率/格式**:戒指是 **8kHz/16bit 单声道**;`recognizeFile` 上传 `audio/wav`。腾讯 ASR 引擎可能默认 16k 中文模型 → 若 8k WAV 识别为空或乱:① 改用 8k 引擎(看 `/api/platform/speech/asr` 是否有引擎参数),或 ② 端上把 8k PCM 线性重采样到 16k 再封 WAV。先按 8k 试,据日志定。
2. **`TencentAsrSyncResult` 文本字段名**:Task 3 用 `.text`,以真实定义为准。
3. **后端地址**:`/api/flash` 走 `Config.apiBase`,debug 默认 localhost → 联调必须 `--dart-define=API_BASE=<可用后端>`。
4. **两套 BLE 栈**:戒指 + 录音卡同时连时的扫描/前台服务协调(里程碑1已加 token 保活,连接稳;此处复测并存)。

## 后续(不在本计划)

- **长录音前台服务保活**(超过几分钟的录音 / 息屏)。
- **完整戒指配对 UX**(绑定持久化、重连、电量显示)。
- **本地文件路线**(绿灯脱机录 → 事后同步,debug 已具雏形)。
- **录音源选择 UX**(卡片/戒指切换、默认源)。
- **iOS 端**。

## 自查(spec 覆盖)

- 方案 A(实时流→ASR→卡片)→ Task 1–3。
- 复用 ASR(`recognizeFile`)+ 建卡(`sendFlash`)→ Task 1/3。
- 双击触发(里程碑1已验证)→ Task 2。
- 正式 UI 连戒指 → Task 4。
- 端到端验收 + 回归 → Task 5。
- 8k/格式契合(00-spec §5.3 未决)→ 校准点 1。
