# 本地录音 → 后端 ASR 转写 → 闪念提交

手机麦克风本地录音,复用后端现有 ASR 能力转写为文字,并作为闪念提交到 Eureka 后端。
纯 mobile 端实现,不依赖录音卡 / 戒指等硬件。

## 功能链路

```
长按录音(麦克风)
  → WAV 音频文件(16kHz 单声道)
  → 腾讯 ASR(TencentAsrS3Client, POST /api/platform/speech/asr)
  → 转写文本
  → 提交闪念(sendFlash, POST /api/flash, asr_provider=client_text)
  → 后端 agent 整理(异步)
  → 轮询 GET /api/flash/recordings/{id} 直到终态(done / empty / failed)
```

## 文件结构

| 文件 | 职责 |
|---|---|
| `local_recording_service.dart` | 核心服务:录音 / 转写 / 提交 / 轮询 |
| `local_recording_result.dart` | 状态枚举 `LocalRecordingPhase` + 结果模型 `LocalRecordingResult` |
| `local_recording_entry.dart` | 全局入口,提供 `localRecording` 单例 |

## 依赖

- `record: ^7.1.1` — 麦克风录音(WAV 输出)
- 复用现有:`TencentAsrS3Client`(ASR)、`EurekaFlashFileApi`(轮询)、`sendFlash`(提交)

平台权限已具备(无需额外配置):

- Android:`RECORD_AUDIO`(AndroidManifest.xml)
- iOS:`NSMicrophoneUsageDescription`(Info.plist)

## API

### 全局入口

```dart
import 'package:eureka/local_recording/local_recording_entry.dart';

final service = localRecording; // 全局单例,惰性创建
```

### 录音

```dart
// 开始录音(自动请求麦克风权限;被拒时 emit failed)
await service.startRecording();

// 停止录音;返回音频文件路径(audioPath),供转写使用
final result = await service.stopRecording();
// result?.audioPath → WAV 文件路径

// 取消录音(丢弃音频文件)
await service.cancelRecording();
```

### 转写 + 提交(一步到位)

```dart
final outcome = await service.transcribeAndSubmit(
  File(audioPath),
  source: 'voice',        // 可选,默认 'voice'
  capturedAt: DateTime.now(), // 可选,录音时间
);
// outcome.phase:
//   done       → 整理完成,outcome.text 为识别文本,outcome.flash 为提交结果
//   failed     → 失败,outcome.error 为错误信息(权限拒绝 / ASR 空文本 / 后端失败)
//   submitting → 后端仍在处理(轮询 120s 超时),稍后可查 outcome.flash.recordingId
```

### 状态监听

```dart
service.status.addListener(() {
  final s = service.status.value;
  switch (s.phase) {
    case LocalRecordingPhase.recording:      // 录音中
    case LocalRecordingPhase.transcribing:   // 转写中
    case LocalRecordingPhase.submitting:     // 提交/整理中
    case LocalRecordingPhase.done:           // 完成
    case LocalRecordingPhase.failed:         // 失败
    case LocalRecordingPhase.cancelled:      // 取消
    default: // idle / requestingPermission
  }
});
```

或通过构造参数 `onResult` 回调接收每次状态变化。

### 生命周期

```dart
// 应用退出时释放(录音器 / HTTP client)
disposeLocalRecording();
```

## 状态机

| LocalRecordingPhase | 含义 |
|---|---|
| `idle` | 空闲(默认) |
| `requestingPermission` | 请求麦克风权限 |
| `recording` | 录音中 |
| `transcribing` | ASR 转写中 |
| `submitting` | 提交后端 + 等待 agent 整理 |
| `done` | 整理完成(含识别文本) |
| `failed` | 失败(error 含原因) |
| `cancelled` | 录音被取消 |

`isBusy` 覆盖 requestingPermission / recording / transcribing / submitting;
`isTerminal` 覆盖 done / failed / cancelled。

## 后端契约

- ASR:`POST {TENCENT_ASR_BASE}/api/platform/speech/asr`(multipart `audio` 字段),同步返回 `{text, segments}`
- 提交:`POST /api/flash`(client_text 路径,**无需卡片绑定**),`text` 为 ASR 结果
- 轮询:`GET /api/flash/recordings/{id}`,`process_status` 状态机 `accepted → asr_processing → asr_done → agent_processing → done`(或 `empty` / `failed`),每 2s 轮询,120s 超时

## 注意事项

- 录音格式固定 16kHz 单声道 WAV,与腾讯 ASR `16k_zh` 引擎匹配
- ASR 返回空文本时判定为失败(错误:`没有识别到内容`)
- 提交走 `POST /api/flash`(client_text),不要求绑定录音卡;`device_kind=phone`
- 轮询超时(120s)返回 `submitting`,不会误报成功;可通过 `flash.recordingId` 自行续查
- 音频文件写入临时目录(`getTemporaryDirectory`),应用清理临时目录时一并回收

## 集成示例(UI 用法)

```dart
// 长按开始,松开结束并提交
GestureDetector(
  onLongPressStart: (_) => localRecording.startRecording(),
  onLongPressEnd: (_) async {
    final result = await localRecording.stopRecording();
    if (result?.audioPath == null) return;
    await localRecording.transcribeAndSubmit(File(result!.audioPath!));
  },
  child: ...,
);
```
