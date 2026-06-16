# ChipletRing 戒指录音接入 · 里程碑 1 实施计划(Android 垂直切片)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 UReka(Eureka-Assistant)Flutter app 内,新建本地插件 `chiplet_ring`,跑通 Android 端"扫描→连接戒指→录音→ADPCM 解码成 PCM→导出 WAV 试听"的完整闭环,证明 BraveChip SDK 可在本工程集成。

**Architecture:** 独立 Flutter 插件包 `mobile/packages/chiplet_ring`,与现有 `br_flutter_plugin_ble` 平级共存。Android 侧 Kotlin 封装闭源 `com.lm.sdk`(aar),对 Dart 暴露 `MethodChannel`(命令)+ `EventChannel`(PCM 帧流 / 连接状态流)。Dart 侧提供干净门面 `ChipletRing`,业务层不接触 `com.lm.sdk`。本里程碑**不碰** `lib/ble_flash`、`lib/device`,不接"闪念"。

**Tech Stack:** Flutter(plugin)、Dart、Kotlin、Android(BluetoothLE)、闭源 SDK `ChipletRing-1.3.3-release.aar`(包名 `com.lm.sdk`,minSdk 24)。

**SDK 真实 API(本计划所有 Kotlin 步骤的依据,源自官方 Demo `/tmp` 或仓库 `Android/example/ringDemo`):**
- 扫描:`BLEUtils.startLeScan(ctx, BluetoothAdapter.LeScanCallback)` / `BLEUtils.stopLeScan(ctx, cb)`;广播解析 `LogicalApi.getBleDeviceInfoWhenBleScan(device, rssi, bytes, false)` → `BleDeviceInfo`。
- 连接:`BLEUtils.connectLockByBLE(ctx, BluetoothDevice)`;断开 `BLEUtils.disconnectBLE(ctx)`;连接前 `BLEUtils.isHIDDevice=false`。
- 连接状态:动态注册 `BroadcastReceiver`,action `BLEService.BROADCAST_CONNECT_STATE_CHANGE`,extra int `BLEService.BROADCAST_CONNECT_STATE_VALUE`,成功值 `BLEService.CONNECT_STATE_SUCCESS`。
- 录音(javap 校准):`LmAPILite.CONTROL_AUDIO_ADPCM(int, IAudioListenerLite)` —— 参数是 **int**(开=1 关=0),Kotlin 直接传 `1`/`0`(demo 的 `(byte)0x01` 是 Java 自动加宽)。
- 音频回调接口 `com.lm.sdk.lmApiInter.IAudioListenerLite`(必须实现全部 6 个方法):`controlAudioResult(byte[] bytes, int audioType)`(audioType 1=单声道 2=双声道)、`controlAudioRawDataResult(byte[])`、`getControlAudioAdpcmResult(boolean)`、`pushAudioInformationResult(boolean)`、`TOUCH_AUDIO_FINISH_XUN_FEI()`、`recordingResult(boolean)`。
- 解码(javap 校准):`com.lm.sdk.AdPcmTool` 为**实例类**,分声道:`byte[] decodeADPCMMonoChannel(byte[], int)` / `byte[] decodeADPCMDualChannel(byte[], int)` / `void resetAllDecoders()` / `byte[] adpcmToPcmFromJNI(byte[])`。⚠️ 第二个 int 参(长度 or 标志)+ `controlAudioResult` 的 bytes 是否已是 PCM —— **需真机校准**。

> ⚠️ **硬件相关步骤无法纯单测**:Dart 侧(模型 / WAV 写入 / 门面)走 TDD;Android 侧 BLE/音频走**真机手动验收**(标注 `[真机]`)。SDK 必须配真戒指。

---

## 文件结构

**新建插件 `mobile/packages/chiplet_ring/`:**
- `pubspec.yaml` — 插件声明(仅 Android 平台)
- `lib/chiplet_ring.dart` — 导出 + 门面 `ChipletRing`
- `lib/src/models.dart` — `RingDevice` / `RingConnState` / `RingState` / `RingAudioFrame`
- `lib/src/ring_platform.dart` — MethodChannel/EventChannel 封装
- `lib/src/wav_writer.dart` — PCM→WAV(16-bit PCM)
- `android/build.gradle` — 模块构建 + 依赖 aar/jar
- `android/libs/ChipletRing-1.3.3-release.aar`、`android/libs/st25sdk-1.13.0.jar`
- `android/src/main/AndroidManifest.xml` — 权限 + 合并冲突处理
- `android/src/main/kotlin/com/eureka/chiplet_ring/ChipletRingPlugin.kt` — 插件主体
- `test/models_test.dart`、`test/wav_writer_test.dart`、`test/ring_platform_test.dart`

**改动现有工程:**
- `mobile/pubspec.yaml` — 加 `chiplet_ring: { path: packages/chiplet_ring }`
- `mobile/android/app/build.gradle.kts` — `ndk { abiFilters }` 收敛 ABI
- `mobile/lib/pages/ring_debug_page.dart`(新建)+ 一个临时入口按钮(改 `lib/app_shell.dart` 或 settings 页,**仅调试入口,不动现有逻辑**)

---

## Task 0: 新分支 + 插件骨架

**Files:**
- Create: `mobile/packages/chiplet_ring/pubspec.yaml`

- [ ] **Step 1: 建分支**

```bash
cd ~/workwork/eureka-staff/Eureka-Assistant
git checkout main && git pull
git checkout -b feat/chiplet-ring-audio
```

- [ ] **Step 2: 用 flutter 生成插件骨架(仅 Android)**

```bash
cd mobile
flutter create --template=plugin --platforms=android \
  --org com.eureka --project-name chiplet_ring packages/chiplet_ring
```

- [ ] **Step 3: 精简 pubspec.yaml**

将 `packages/chiplet_ring/pubspec.yaml` 的 `flutter.plugin.platforms` 改为只保留 android,pluginClass 指向我们将写的类:

```yaml
flutter:
  plugin:
    platforms:
      android:
        package: com.eureka.chiplet_ring
        pluginClass: ChipletRingPlugin
```

- [ ] **Step 4: Commit**

```bash
git add mobile/packages/chiplet_ring
git commit -m "chore: scaffold chiplet_ring flutter plugin (android-only)"
```

---

## Task 1: 集成 aar/jar + gradle/manifest/ABI,保证编译通过

**Files:**
- Create: `mobile/packages/chiplet_ring/android/libs/ChipletRing-1.3.3-release.aar`
- Create: `mobile/packages/chiplet_ring/android/libs/st25sdk-1.13.0.jar`
- Modify: `mobile/packages/chiplet_ring/android/build.gradle`
- Modify: `mobile/packages/chiplet_ring/android/src/main/AndroidManifest.xml`
- Modify: `mobile/android/app/build.gradle.kts`
- Modify: `mobile/pubspec.yaml`

- [ ] **Step 1: 拷贝 SDK 产物到插件 libs/**

```bash
cd ~/workwork/eureka-staff/Eureka-Assistant/mobile/packages/chiplet_ring
mkdir -p android/libs
# 路径来自克隆的 SDK 仓库 Android/example/ringDemo/app/libs/
cp <SDK_REPO>/Android/example/ringDemo/app/libs/ChipletRing-1.3.3-release.aar android/libs/
cp <SDK_REPO>/Android/example/ringDemo/app/libs/st25sdk-1.13.0.jar android/libs/
```

- [ ] **Step 2: 插件 android/build.gradle 加依赖**

在 `android` 块设 `minSdkVersion 24`;在 `dependencies` 加:

```gradle
android {
    defaultConfig {
        minSdkVersion 24
    }
}
dependencies {
    implementation fileTree(dir: "libs", include: ["*.aar", "*.jar"])
}
```

- [ ] **Step 3: 处理 Manifest 合并冲突(去掉 persistent,声明权限)**

写 `android/src/main/AndroidManifest.xml`(用 `tools:node="replace"` 覆盖 aar 注入的 `BLEService`,去掉 `persistent`;`tools:remove` 去掉用不到的 `persistent` 属性):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <application tools:remove="android:persistent">
        <service android:name="com.lm.sdk.BLEService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="false"
            tools:node="merge" />
    </application>
</manifest>
```

- [ ] **Step 4: app 侧 abiFilters 收敛 ABI**

在 `mobile/android/app/build.gradle.kts` 的 `defaultConfig` 内加(只保留主流真机 ABI,砍掉 x86/x86_64 减体积):

```kotlin
ndk {
    abiFilters += listOf("arm64-v8a", "armeabi-v7a")
}
```

- [ ] **Step 5: app 依赖插件**

`mobile/pubspec.yaml` 的 `dependencies:` 加:

```yaml
  chiplet_ring:
    path: packages/chiplet_ring
```

- [ ] **Step 6: 验证 app 能编译(集成成功的硬指标)**

Run: `cd mobile && flutter pub get && flutter build apk --debug`
Expected: BUILD SUCCESSFUL,无 manifest merger 报错,产物体积较接入前 +约 1.5–2.5MB。

- [ ] **Step 7: Commit**

```bash
git add mobile/packages/chiplet_ring/android mobile/android/app/build.gradle.kts mobile/pubspec.yaml mobile/packages/chiplet_ring/pubspec.yaml
git commit -m "build: vendor ChipletRing aar into chiplet_ring plugin, resolve manifest merge + abi"
```

---

## Task 2: Dart 数据模型(TDD)

**Files:**
- Create: `mobile/packages/chiplet_ring/lib/src/models.dart`
- Test: `mobile/packages/chiplet_ring/test/models_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chiplet_ring/src/models.dart';

void main() {
  test('RingDevice.fromMap parses fields', () {
    final d = RingDevice.fromMap({'id': 'AA:BB', 'name': 'Ring', 'rssi': -55});
    expect(d.id, 'AA:BB');
    expect(d.name, 'Ring');
    expect(d.rssi, -55);
  });

  test('RingAudioFrame.fromMap parses pcm bytes + seq + channels', () {
    final f = RingAudioFrame.fromMap({
      'pcm': [1, 2, 3, 4],
      'seq': 7,
      'channels': 1,
    });
    expect(f.pcm, [1, 2, 3, 4]);
    expect(f.seq, 7);
    expect(f.channels, 1);
  });

  test('RingState.disconnected has empty devices', () {
    const s = RingState(conn: RingConnState.disconnected, devices: []);
    expect(s.conn, RingConnState.disconnected);
    expect(s.devices, isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd mobile/packages/chiplet_ring && flutter test test/models_test.dart`
Expected: FAIL —— `Target of URI doesn't exist: 'package:chiplet_ring/src/models.dart'`

- [ ] **Step 3: 写最小实现**

```dart
// lib/src/models.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

enum RingConnState { disconnected, scanning, connecting, connected, error }

@immutable
class RingDevice {
  final String id;
  final String name;
  final int rssi;
  const RingDevice({required this.id, required this.name, required this.rssi});
  factory RingDevice.fromMap(Map m) => RingDevice(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        rssi: (m['rssi'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class RingState {
  final RingConnState conn;
  final List<RingDevice> devices;
  const RingState({required this.conn, required this.devices});
}

@immutable
class RingAudioFrame {
  final Uint8List pcm;
  final int seq;
  final int channels;
  const RingAudioFrame({required this.pcm, required this.seq, required this.channels});
  factory RingAudioFrame.fromMap(Map m) => RingAudioFrame(
        pcm: Uint8List.fromList(List<int>.from(m['pcm'] as List)),
        seq: (m['seq'] as num?)?.toInt() ?? 0,
        channels: (m['channels'] as num?)?.toInt() ?? 1,
      );
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/models_test.dart`
Expected: PASS(3 个测试)

- [ ] **Step 5: Commit**

```bash
git add mobile/packages/chiplet_ring/lib/src/models.dart mobile/packages/chiplet_ring/test/models_test.dart
git commit -m "feat(chiplet_ring): dart models for device/state/audio frame"
```

---

## Task 3: PCM→WAV 写入(TDD)

**Files:**
- Create: `mobile/packages/chiplet_ring/lib/src/wav_writer.dart`
- Test: `mobile/packages/chiplet_ring/test/wav_writer_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/wav_writer_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:chiplet_ring/src/wav_writer.dart';

void main() {
  test('wraps PCM into a valid 16-bit WAV header', () {
    final pcm = Uint8List.fromList(List.filled(8, 0));
    final wav = pcmToWav(pcm, sampleRate: 16000, channels: 1);
    // RIFF....WAVE
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    // 44-byte header + data
    expect(wav.length, 44 + pcm.length);
    // bitsPerSample = 16 at offset 34 (little-endian)
    expect(wav[34], 16);
    expect(wav[35], 0);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/wav_writer_test.dart`
Expected: FAIL —— URI doesn't exist

- [ ] **Step 3: 写最小实现**

```dart
// lib/src/wav_writer.dart
import 'dart:typed_data';

Uint8List pcmToWav(Uint8List pcm, {required int sampleRate, required int channels}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataLen = pcm.length;
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));
  str('RIFF'); u32(36 + dataLen); str('WAVE');
  str('fmt '); u32(16); u16(1); u16(channels);
  u32(sampleRate); u32(byteRate); u16(blockAlign); u16(bitsPerSample);
  str('data'); u32(dataLen); b.add(pcm);
  return b.toBytes();
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/wav_writer_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add mobile/packages/chiplet_ring/lib/src/wav_writer.dart mobile/packages/chiplet_ring/test/wav_writer_test.dart
git commit -m "feat(chiplet_ring): pcm-to-wav writer"
```

---

## Task 4: Dart 平台层 + 门面(TDD,mock channel)

**Files:**
- Create: `mobile/packages/chiplet_ring/lib/src/ring_platform.dart`
- Create: `mobile/packages/chiplet_ring/lib/chiplet_ring.dart`
- Test: `mobile/packages/chiplet_ring/test/ring_platform_test.dart`

- [ ] **Step 1: 写失败测试(用 mock MethodChannel 验证命令名)**

```dart
// test/ring_platform_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chiplet_ring/src/ring_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chiplet_ring/methods');
  final calls = <String>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });

  test('startScan/connect/startRecording invoke expected method names', () async {
    final p = RingPlatform();
    await p.startScan();
    await p.connect('AA:BB');
    await p.startRecording();
    await p.stopRecording();
    await p.disconnect();
    expect(calls, ['startScan', 'connect', 'startRecording', 'stopRecording', 'disconnect']);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/ring_platform_test.dart`
Expected: FAIL —— URI doesn't exist

- [ ] **Step 3: 写平台层**

```dart
// lib/src/ring_platform.dart
import 'package:flutter/services.dart';
import 'models.dart';

class RingPlatform {
  static const _methods = MethodChannel('chiplet_ring/methods');
  static const _audio = EventChannel('chiplet_ring/audio');
  static const _state = EventChannel('chiplet_ring/state');

  Future<void> startScan() => _methods.invokeMethod('startScan');
  Future<void> stopScan() => _methods.invokeMethod('stopScan');
  Future<void> connect(String id) => _methods.invokeMethod('connect', {'id': id});
  Future<void> disconnect() => _methods.invokeMethod('disconnect');
  Future<void> startRecording() => _methods.invokeMethod('startRecording');
  Future<void> stopRecording() => _methods.invokeMethod('stopRecording');

  Stream<RingAudioFrame> audioFrames() =>
      _audio.receiveBroadcastStream().map((e) => RingAudioFrame.fromMap(e as Map));

  Stream<RingState> states() => _state.receiveBroadcastStream().map((e) {
        final m = e as Map;
        return RingState(
          conn: RingConnState.values.byName(m['conn'] as String),
          devices: ((m['devices'] as List?) ?? [])
              .map((d) => RingDevice.fromMap(d as Map))
              .toList(),
        );
      });
}
```

- [ ] **Step 4: 写门面 + 导出**

```dart
// lib/chiplet_ring.dart
export 'src/models.dart';
export 'src/wav_writer.dart';

import 'src/models.dart';
import 'src/ring_platform.dart';

class ChipletRing {
  ChipletRing({RingPlatform? platform}) : _p = platform ?? RingPlatform();
  final RingPlatform _p;

  Stream<RingState> get state => _p.states();
  Future<void> startScan() => _p.startScan();
  Future<void> stopScan() => _p.stopScan();
  Future<void> connect(String deviceId) => _p.connect(deviceId);
  Future<void> disconnect() => _p.disconnect();

  Stream<RingAudioFrame> startRecording() {
    final s = _p.audioFrames();
    _p.startRecording();
    return s;
  }

  Future<void> stopRecording() => _p.stopRecording();
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test`
Expected: PASS(全部 Dart 测试)

- [ ] **Step 6: Commit**

```bash
git add mobile/packages/chiplet_ring/lib mobile/packages/chiplet_ring/test/ring_platform_test.dart
git commit -m "feat(chiplet_ring): dart platform layer + ChipletRing facade"
```

---

## Task 5: Android 插件骨架(MethodChannel/EventChannel + 懒加载)

**Files:**
- Modify: `mobile/packages/chiplet_ring/android/src/main/kotlin/com/eureka/chiplet_ring/ChipletRingPlugin.kt`

- [ ] **Step 1: 写插件骨架(注册三个 channel,SDK 懒加载)**

```kotlin
package com.eureka.chiplet_ring

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ChipletRingPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var appContext: Context
    private lateinit var methods: MethodChannel
    private lateinit var audio: EventChannel
    private lateinit var state: EventChannel

    private var audioSink: EventChannel.EventSink? = null
    private var stateSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        appContext = b.applicationContext
        methods = MethodChannel(b.binaryMessenger, "chiplet_ring/methods").also { it.setMethodCallHandler(this) }
        audio = EventChannel(b.binaryMessenger, "chiplet_ring/audio").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { audioSink = sink }
                override fun onCancel(args: Any?) { audioSink = null }
            })
        }
        state = EventChannel(b.binaryMessenger, "chiplet_ring/state").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { stateSink = sink }
                override fun onCancel(args: Any?) { stateSink = null }
            })
        }
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan" -> { /* Task 6 */ result.success(null) }
            "stopScan" -> { /* Task 6 */ result.success(null) }
            "connect" -> { /* Task 6 */ result.success(null) }
            "disconnect" -> { /* Task 6 */ result.success(null) }
            "startRecording" -> { /* Task 7 */ result.success(null) }
            "stopRecording" -> { /* Task 7 */ result.success(null) }
            else -> result.notImplemented()
        }
    }
}
```

- [ ] **Step 2: 编译确认骨架可用**

Run: `cd mobile && flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add mobile/packages/chiplet_ring/android/src/main/kotlin
git commit -m "feat(chiplet_ring): android plugin skeleton with method/event channels"
```

---

## Task 6: Android 扫描 + 连接 + 状态广播 → state 流

**Files:**
- Modify: `mobile/packages/chiplet_ring/android/src/main/kotlin/com/eureka/chiplet_ring/ChipletRingPlugin.kt`

> 依据官方 Demo `MainActivity.java`(扫描)+ `TestActivity3.java`(连接 / 广播)。

- [ ] **Step 1: 实现扫描 + 设备解析**

在 `onMethodCall` 的 `startScan`/`stopScan` 实现(`leScanCallback` 用 `LogicalApi.getBleDeviceInfoWhenBleScan` 解析,收集到一个 map 后用 `stateSink` 上抛 `conn=scanning, devices=[...]`):

```kotlin
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.os.Handler
import android.os.Looper
import com.lm.sdk.LogicalApi
import com.lm.sdk.utils.BLEUtils

private val main = Handler(Looper.getMainLooper())
private val found = LinkedHashMap<String, BluetoothDevice>()

private val leScanCallback = BluetoothAdapter.LeScanCallback { device, rssi, bytes ->
    val info = LogicalApi.getBleDeviceInfoWhenBleScan(device, rssi, bytes, false) ?: return@LeScanCallback
    found[device.address] = device
    val devices = found.values.map { mapOf("id" to it.address, "name" to (it.name ?: ""), "rssi" to rssi) }
    main.post { stateSink?.success(mapOf("conn" to "scanning", "devices" to devices)) }
}
```

`startScan`:
```kotlin
"startScan" -> { found.clear(); BLEUtils.startLeScan(appContext, leScanCallback); result.success(null) }
"stopScan" -> { BLEUtils.stopLeScan(appContext, leScanCallback); result.success(null) }
```

- [ ] **Step 2: 实现连接 + 状态广播接收**

```kotlin
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import com.lm.sdk.BLEService

private val connReceiver = object : BroadcastReceiver() {
    override fun onReceive(c: Context?, intent: Intent?) {
        if (intent?.action == BLEService.BROADCAST_CONNECT_STATE_CHANGE) {
            val s = intent.getIntExtra(BLEService.BROADCAST_CONNECT_STATE_VALUE, -1)
            val conn = if (s == BLEService.CONNECT_STATE_SUCCESS) "connected" else "disconnected"
            main.post { stateSink?.success(mapOf("conn" to conn, "devices" to emptyList<Any>())) }
        }
    }
}
private var receiverRegistered = false
```

在 `onAttachedToEngine` 末尾注册:
```kotlin
appContext.registerReceiver(connReceiver, IntentFilter(BLEService.BROADCAST_CONNECT_STATE_CHANGE), Context.RECEIVER_NOT_EXPORTED)
receiverRegistered = true
```
在 `onDetachedFromEngine` 注销:
```kotlin
if (receiverRegistered) { appContext.unregisterReceiver(connReceiver); receiverRegistered = false }
```

`connect`/`disconnect`:
```kotlin
"connect" -> {
    val id = call.argument<String>("id")!!
    val dev = found[id] ?: BluetoothAdapter.getDefaultAdapter().getRemoteDevice(id)
    BLEUtils.isHIDDevice = false
    main.post { stateSink?.success(mapOf("conn" to "connecting", "devices" to emptyList<Any>())) }
    BLEUtils.connectLockByBLE(appContext, dev)
    result.success(null)
}
"disconnect" -> { BLEUtils.disconnectBLE(appContext); result.success(null) }
```

- [ ] **Step 3: 编译通过**

Run: `cd mobile && flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: `[真机]` 验收扫描+连接**

在 Task 8 的调试页接好后回到此步;或先用临时日志验证。
预期:真机点扫描能看到戒指(name/rssi),点连接后 state 流依次出现 `connecting`→`connected`。

- [ ] **Step 5: Commit**

```bash
git add mobile/packages/chiplet_ring/android/src/main/kotlin
git commit -m "feat(chiplet_ring): android scan + connect + connection-state broadcast"
```

---

## Task 7: Android 录音 + ADPCM 解码 → audio 流

**Files:**
- Modify: `mobile/packages/chiplet_ring/android/src/main/kotlin/com/eureka/chiplet_ring/ChipletRingPlugin.kt`

> 依据官方 Demo `TestActivity2.java`(音频)。`IAudioListenerLite` 必须实现全部 6 个方法。

- [ ] **Step 1: 实现音频监听 + 开始/停止录音**

```kotlin
import com.lm.sdk.AdPcmTool
import com.lm.sdk.LmAPILite
import com.lm.sdk.lmApiInter.IAudioListenerLite

private var seq = 0

private val audioListener = object : IAudioListenerLite {
    override fun controlAudioResult(bytes: ByteArray, audioType: Int) {
        // bytes 为 ADPCM,解码成 PCM 后上抛(解码 API 以真实签名为准,见 Step 2 校准)
        val pcm = AdPcmTool.decode(bytes)   // ⚠️ 见 Step 2:确认 AdPcmTool 实际方法名/签名
        val s = seq++
        main.post { audioSink?.success(mapOf("pcm" to pcm.toList(), "seq" to s, "channels" to audioType)) }
    }
    override fun controlAudioRawDataResult(bytes: ByteArray) {}
    override fun getControlAudioAdpcmResult(adpcm: Boolean) {}
    override fun pushAudioInformationResult(success: Boolean) {}
    override fun TOUCH_AUDIO_FINISH_XUN_FEI() {}
    override fun recordingResult(result: Boolean) {}
}
```

`startRecording`/`stopRecording`:
```kotlin
"startRecording" -> { seq = 0; LmAPILite.CONTROL_AUDIO_ADPCM(0x01.toByte(), audioListener); result.success(null) }
"stopRecording" -> { LmAPILite.CONTROL_AUDIO_ADPCM(0x00.toByte(), audioListener); result.success(null) }
```

- [ ] **Step 2: 校准 `AdPcmTool` 真实解码签名**

`AdPcmTool` 的具体方法名/签名以 aar 为准(本计划编写时仅确认类存在)。校准命令:

Run:
```bash
cd /tmp && unzip -o <SDK_REPO>/Android/example/ringDemo/app/libs/ChipletRing-1.3.3-release.aar classes.jar -d _aar2 >/dev/null
javap -classpath _aar2/classes.jar com.lm.sdk.AdPcmTool
```
将 Step 1 中 `AdPcmTool.decode(bytes)` 替换为 `javap` 输出里真实的解码方法(若为实例方法则先 `AdPcmTool()` 实例化;若 Demo 内有用例,以 Demo 为准)。

- [ ] **Step 3: 编译通过**

Run: `cd mobile && flutter build apk --debug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
git add mobile/packages/chiplet_ring/android/src/main/kotlin
git commit -m "feat(chiplet_ring): android audio start/stop + adpcm decode to pcm stream"
```

---

## Task 8: 调试页 + 真机验收闭环

**Files:**
- Create: `mobile/lib/pages/ring_debug_page.dart`
- Modify: `mobile/lib/app_shell.dart`(仅加一个临时调试入口按钮)

- [ ] **Step 1: 写调试页(扫描列表 / 连接 / 录音 / 停止并存 WAV / 分享)**

```dart
// lib/pages/ring_debug_page.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:chiplet_ring/chiplet_ring.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class RingDebugPage extends StatefulWidget {
  const RingDebugPage({super.key});
  @override
  State<RingDebugPage> createState() => _RingDebugPageState();
}

class _RingDebugPageState extends State<RingDebugPage> {
  final _ring = ChipletRing();
  RingState _state = const RingState(conn: RingConnState.disconnected, devices: []);
  final _pcm = BytesBuilder();
  int _channels = 1;

  @override
  void initState() {
    super.initState();
    _ring.state.listen((s) => setState(() => _state = s));
  }

  void _record() {
    _pcm.clear();
    _ring.startRecording().listen((f) {
      _channels = f.channels;
      _pcm.add(f.pcm);
    });
  }

  Future<void> _stopAndExport() async {
    await _ring.stopRecording();
    final wav = pcmToWav(_pcm.toBytes(), sampleRate: 16000, channels: _channels);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ring_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(path).writeAsBytes(wav);
    await Share.shareXFiles([XFile(path)], text: 'ring recording');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ring Debug · ${_state.conn.name}')),
      body: Column(children: [
        Wrap(spacing: 8, children: [
          ElevatedButton(onPressed: _ring.startScan, child: const Text('扫描')),
          ElevatedButton(onPressed: _record, child: const Text('录音')),
          ElevatedButton(onPressed: _stopAndExport, child: const Text('停止并导出')),
        ]),
        Expanded(
          child: ListView(children: [
            for (final d in _state.devices)
              ListTile(
                title: Text(d.name.isEmpty ? d.id : d.name),
                subtitle: Text('${d.id}  rssi=${d.rssi}'),
                onTap: () => _ring.connect(d.id),
              ),
          ]),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 2: 加临时调试入口**

在 `lib/app_shell.dart` 加一个仅 debug 可见的入口(`if (kDebugMode)`)跳转 `RingDebugPage`,不改任何现有逻辑。确保 `import 'package:flutter/foundation.dart';` 与页面 import 存在。

- [ ] **Step 3: 确认 path_provider 依赖存在**

Run: `cd mobile && grep -E 'path_provider|share_plus' pubspec.yaml`
Expected: `share_plus` 已存在(现有依赖);若 `path_provider` 缺失则 `flutter pub add path_provider`。

- [ ] **Step 4: `[真机]` 完整验收(里程碑 1 的 Definition of Done)**

Run: `cd mobile && flutter run --release`(真机 + 真戒指)
手动流程:打开调试页 → 扫描看到戒指 → 点连接(状态变 connected)→ 录音 → 说几句 → 停止并导出 → 用系统播放器播放导出的 WAV。
**通过标准:WAV 能正常播放、能听清人声、音质 OK(与你已试听的 Demo 一致)。**

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/pages/ring_debug_page.dart mobile/lib/app_shell.dart mobile/pubspec.yaml
git commit -m "feat(chiplet_ring): ring debug page for android record-and-export acceptance"
```

---

## Task 9: 收尾 + PR

- [ ] **Step 1: 跑全部 Dart 测试**

Run: `cd mobile/packages/chiplet_ring && flutter test`
Expected: 全部 PASS

- [ ] **Step 2: 确认现有功能未受影响(回归)**

`[真机]` 冒烟:现有"闪念"录音卡流程仍正常(连接卡片、录音、生成卡片),戒指 SDK 未在 app 启动时自起(查看日志无 `BLEService` 早启)。

- [ ] **Step 3: 开 PR**

```bash
git push -u origin feat/chiplet-ring-audio
gh pr create --title "feat: ChipletRing 戒指录音接入(里程碑1·Android垂直切片)" \
  --body "见 spec/chiple-ring-spec/00-spec.md。本 PR 仅 Android 切片:连接→录音→ADPCM 解码→导出 WAV;不接闪念,不动现有 ble_flash/device。"
```

---

## 自查(spec 覆盖)

- §2 架构(插件 + 三 channel + 门面)→ Task 4/5。
- §1 Android API(扫描/连接/录音/解码)→ Task 6/7。
- §3 对现有版本影响(minSdk/manifest/abi/懒加载)→ Task 1(manifest+abi)、Task 5(懒加载)、Task 9 Step 2(回归)。
- §4 里程碑 1 验收(导出 WAV 试听)→ Task 8 Step 4。
- **里程碑 2(接入闪念)= 另出一份 plan**,本计划不含。
