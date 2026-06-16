# Spec · ChipletRing 智能戒指录音接入(Android 优先)

> **状态:里程碑 1 已跑通(2026-06-17,真机+真戒指验证)。** 目标 = 把 BraveChip 勇芯智能戒指作为**新的录音输入源**接入 UReka(Eureka-Assistant)Flutter app,替代/补充现有 W1/W2 录音卡。**本期只做录音链路,不接健康数据(心率/血氧/睡眠/ECG 全部不做)。** 实测结论见文末 §7。
>
> SDK 来源:`https://github.com/BravechipSpace/ChipletRing-APPSDK`(Android `ChipletRing-1.3.3-release.aar`,包名 `com.lm.sdk`)。
> **本卡描述 WHAT / 契约 + 真实 API 形态;实际代码写在新插件 `mobile/packages/chiplet_ring` + `mobile/lib`(里程碑 1 不碰现有 `lib/ble_flash`、`lib/device`)。**

---

## 0. 背景:UReka 现状(为什么这样接)

- UReka 主客户端是 **Flutter** app(`mobile/`,同时含 `android/`、`ios/`)。
- **已有一套 BLE 设备**:UReka 录音卡(W1/W2),走公司插件 `br_flutter_plugin_ble`(`BrBluetoothPlugin`),服务"闪念"语音捕捉。现有代码:
  - `lib/ble_flash/`(`ble_flash_manager.dart`、`flash_file_workflow.dart`)— 实时流 + 文件工作流
  - `lib/device/`(`device_controller.dart`、`device_silent_reconnect.dart`)、`lib/pages/device_pairing_page.dart`
- 戒指是**第二个、不同的 BLE 设备**,自带勇芯私有协议 + 厂商音频管线(ADPCM)。

## 1. SDK 真实能力(已核实)

### Android(本期目标)
- 主入口:`com.lm.sdk.LmAPILite` / `LmAPI`;底层 `com.lm.sdk.BLEService` 自带一套 GATT。
- 扫描:`BLEUtils.startLeScan` + `BluetoothAdapter.LeScanCallback`,广播解析 `LogicalApi.getBleDeviceInfoWhenBleScan(...)`。
- 录音(实时流):
  - `LmAPILite.CONTROL_AUDIO_ADPCM((byte)0x01, listener)` 开启 / `(byte)0x00` 停止
  - `LmAPILite.GET_CONTROL_AUDIO_ADPCM(listener)` 查询当前格式
  - 回调 `com.lm.sdk.lmApiInter.IAudioListenerLite`:
    - `controlAudioResult(byte[] bytes, int audioType)` — 实时音频帧,`audioType` 1=单声道 2=双声道
    - `controlAudioRawDataResult(byte[] bytes)`、`getControlAudioAdpcmResult(boolean)`、`pushAudioInformationResult(boolean)`、`recordingResult(boolean)`、`AudioFileContent(byte[])`(文件式)
  - 解码:`com.lm.sdk.AdPcmTool`(ADPCM→PCM);Demo 直接存 `.pcm`。
- 打包:`ChipletRing-1.3.3-release.aar`(1.5MB)+ `st25sdk-1.13.0.jar`(0.65MB,ST25 NFC)+ jni `.so`(arm64-v8a / armeabi-v7a / x86 / x86_64,合计 ~0.9MB)。aar `minSdkVersion=24`。

### iOS(本期不做,留待后续)
- 新版 framework `BCLRingSDK`(最新 1.2.1,xcframework),主类 `BCLRingManager.shared`。
- 录音 API 对照(供 iOS 阶段参考):`controlPCMFormatAudio(isOpen:)` / `controlADPCMFormatAudio(mode:isOpen:)`(`.adpcm/.adpcm1Mono/.adpcm1Stereo`)实时流;`ringStartRecording(isOpen:totalDuration:sliceDuration:)` 戒指端分片录音;`adpcm_to_pcm_for_swift` 解码。

## 2. 架构(方案 A:独立本地 Flutter 插件)

新建 `mobile/packages/chiplet_ring`,与现有 `br_flutter_plugin_ble` **平级共存,各管各的设备**。

```
Dart (UReka lib/)
  └── chiplet_ring (Flutter plugin)  —— 干净门面 ChipletRing
        ├── MethodChannel  chiplet_ring/methods
        │       scan() / stopScan() / connect(id) / disconnect()
        │       startRecording() / stopRecording()
        └── EventChannel
                chiplet_ring/audio   ← Stream<RingAudioFrame>{ pcm:Uint8List, seq:int, channels:int }
                chiplet_ring/state   ← Stream<RingState>{ scanning/connecting/connected/disconnected, devices[] }
  Android 侧 (Kotlin, in plugin)
        └── ChipletRingPlugin
              · 封装 LmAPILite / LmAPI / BLEService(懒加载,用到才 init)
              · CONTROL_AUDIO_ADPCM(0x01/0x00, IAudioListenerLite)
              · AdPcmTool 解码 ADPCM→PCM → EventChannel 上抛
```

**Dart 门面契约**:UReka 业务层只依赖 `ChipletRing`,**不碰 `com.lm.sdk`**。

```dart
class ChipletRing {
  Stream<RingState> get state;
  Future<void> startScan(); Future<void> stopScan();
  Future<void> connect(String deviceId); Future<void> disconnect();
  Stream<RingAudioFrame> startRecording(); Future<void> stopRecording();
}
```

## 3. 对现有版本的影响 ⭐(接入前重点)

**结论:对现有功能逻辑不影响;发版层面有三项被动变化,均可控。**

| 维度 | 影响 | 说明 / 处理 |
|---|---|---|
| **minSdk** | **不变** ✅ | app 现在 `minSdk = flutter.minSdkVersion`,当前 Flutter SDK 实际值 = **24**,正好等于戒指 aar 要求的 24。现有设备覆盖范围不变。 |
| **现有功能逻辑** | **零侵入** ✅ | 方案 A 独立插件 + 新分支,**不动** `lib/ble_flash`、`lib/device`。戒指 SDK **懒加载**(用到才 init),现有录音卡/闪念运行时行为不变。 |
| **AndroidManifest 合并** | 会变 ⚠️ | aar 注入前台 `BLEService`(`mediaPlayback`)、`android:persistent="true"`、蓝牙/前台服务权限。即使戒指功能没启用,**新版本权限清单会变**(用户/应用商店可见)。→ 用 `tools:replace`/`tools:node` 收敛,只保留必要权限,去掉 `persistent`。 |
| **包体积** | +约 2–3MB ⚠️ | aar 1.5M + st25 0.65M + 4 ABI 的 .so 0.9M。→ `abiFilters` 只留 `arm64-v8a`(+`armeabi-v7a`)可砍一半。 |
| **两套 BLE 栈共存** | 风险 ⚠️ | 戒指 `BLEService` 若 app 启动即自起,可能干扰现有卡片蓝牙。→ 必须懒加载,不主动初始化。 |

**隔离铁律**:在分支上做,**不合并则线上零影响**;合并后只要主流程不调用 `ChipletRing` 门面,运行时行为不变。

## 4. 里程碑

### 里程碑 1 —— Android 垂直切片(先做)
**目标:证明 SDK 在 UReka 工程里能跑通。不碰"闪念"。**
- 插件 `chiplet_ring` 骨架 + aar/jar/so 集成 + 编译通过(处理 manifest 合并、abiFilters)
- 一个临时调试页:扫描 → 连接戒指 → 开始/停止录音 → `AdPcmTool` 解码 PCM → 存 `.pcm`/`.wav` 文件,可导出试听
- **验收**:真机连真戒指,录一段,导出文件能正常播放、音质 OK。

### 里程碑 2 —— 接入"闪念"
- 把里程碑 1 的 PCM 流对齐现有 `BleFlashManager` 的数据形态,让戒指录音也能走"闪念"→ AI 归类成卡片。
- 复用现有上传/转写后端(**待确认**音频格式/采样率契合,可能需在端上转码或后端适配)。
- 设备选择 UX:卡片 / 戒指作为可切换的录音源。

## 5. 风险与未决

1. **两套 BLE 栈协调**(扫描、权限、前台服务)。里程碑 1 可暂不管,里程碑 2 必须解决。
2. **aar 闭源 + jni**:出问题只能黑盒调试 + 找厂商(联系 `xiaojian.cui@bravechip.com`)。
3. **音频格式契合**:戒指 PCM 的采样率/位深/声道是否与现有"闪念"转写后端期望一致 — **里程碑 2 前需实测确认**。
4. **后台长录音**:前台服务、续航、断连重传 — 里程碑 2 细化。
5. **iOS**:本期不做;插件预留 iOS 侧,后续补 `BCLRingSDK` 桥接。

## 6. 测试与交付

- Dart 门面单测(mock channel);Android 解码关键逻辑可单测。
- 真机联调为主(SDK 必须配真戒指)。
- 分支 `feat/chiplet-ring-audio`;里程碑 1 单独成 PR。

## 7. 里程碑 1 实测结论(2026-06-17,真机 Galaxy Z Fold5 / Android 16 + 真戒指 BCL6032CA2)

**结论:扫描→连接→双击手势录音→ADPCM(SDK 内部解码)→PCM→导出 WAV,音质清晰、速率正确,全链路跑通。** 以下是踩通的关键点(都是 bare aar 不会告诉你的,接手务必照做):

1. **SDK 必须初始化**:`LmAPILite.init(application)` + `AppConfig.setOverseas(false)`。不做则静态 Application 引用为 null,停录音/存文件 `sendBroadcast` NPE。我们在插件首次用到时懒初始化。
2. **bare aar 不带依赖,需手动补**:`androidx.localbroadcastmanager:localbroadcastmanager:1.1.0`(`BLEService.onCreate` 用到,缺了连接直接崩)、`org.greenrobot:greendao:3.3.0`、`com.google.code.gson:gson`、`org.jetbrains:annotations`。网络相关(okhttputils/retrofit)本地录音用不到,没加。
3. **连接状态走 LocalBroadcastManager**:SDK 用 `LocalBroadcastManager` 发 `BLEService.BROADCAST_CONNECT_STATE_CHANGE`(不是全局广播)。必须 `LocalBroadcastManager.getInstance(ctx).registerReceiver(...)`,否则永远收不到、卡在 connecting。
4. **连接成功必须做 token 握手保活**:注册 `IResponseListenerLite`(`LmAPILite.addWLSCmdListener`),在 `lmBleConnectionSucceeded(code==7)` 里调 `BLEUtils.setGetToken(true)`。不做的话连上约 **5 秒就掉线**、反复重连、音频起不来。
5. **连接前先停扫描**:`BLEUtils.stopLeScan(...)`。边扫边连会让 GATT 不稳;且扫描回调会把 UI 状态冲掉。
6. **音频回调 `controlAudioResult(bytes, audioType)` 给的已经是解码好的 PCM**(SDK 内部已 ADPCM→PCM;原始 ADPCM 另走 `controlAudioRawDataResult`)。**不要再用 `AdPcmTool` 解一遍**,否则纯杂音。直接透传 bytes。
7. **采样率 = 8000 Hz**(16-bit、`audioType` 1=单声道/2=双声道)。按 16000 写 WAV 会语速快一倍。
8. **录音触发**:`CONTROL_AUDIO_ADPCM(1)` 开 / `(0)` 关(参数是 **int**)。
9. **硬件手势**:注册 `IKeyDownListener`(`LmAPILite.KEY_DOWN_LISTENER`),`ringPushKeyDownResult(key)`,key:0=长按 1=单击 2=双击 3=三击 4-7=滑动。我们用**双击(2)**开/关录音。
10. **白灯 vs 绿灯**:我们截获双击→app 主动开**实时流(白灯)**,这是接闪念要的(实时 PCM)。Demo 的**绿灯**是戒指固件的**本地录音模式**(存戒指、事后拉文件),是另一套机制,后续可选。
11. **两套 BLE 栈并存**:公司 `br_flutter_plugin_ble`(`BrBluetoothManager`)也会感知同一戒指。目前实测加上 token 保活后连接已稳;里程碑 2 仍需关注扫描/前台服务协调。

**调试入口**:登录页 `kDebugMode` 下「[Debug] Ring 调试（免登录）」→ 扫描/连接/双击录音/导出 WAV。后端地址走 `--dart-define=API_BASE`(默认 `localhost:8000`),戒指链路不依赖后端。

**里程碑 2(接闪念)前仍需**:确认 8kHz/16-bit 单声道 PCM 与现有转写后端契合(可能要重采样到 16k);把戒指 PCM 流对齐 `BleFlashManager` 数据形态;前台服务保活长录音。
