# ChipletRing 戒指接入 · 交付状态(合并 main)

> 状态时间:2026-06-17 起,真机验证至 2026-06-19(Galaxy Z Fold5 / Android 16 + 真戒指 BCL603S,固件 6.0.1.8Z62,SDK aar `ChipletRing-1.3.3`)。
> 目标:把 BraveChip 勇芯智能戒指作为**录音输入**接入 UReka(Eureka-Assistant)Flutter app,**Android 优先,只做录音(不接健康数据)**。

## 一、已交付(真机验证通过)

1. **实时录音 → 闪念卡片(核心)**
   双击戒指开始录音 → 实时 PCM 流 → WAV → 腾讯 ASR(`recognizeFile`)转写 → `sendFlash` 建卡。和录音卡走**同一套** ASR + `/api/flash`,**任意页面**双击即可(全局 `RingCaptureController`)。实测一句中文准确转写并 AI 拆成 笔记 + 支出 两张卡。
2. **连接稳定 + 自动回连**
   连接成功后 `setGetToken(true)` token 保活(否则约 5 秒掉线)。冷启动/断线后**扫描式自动回连**(`RingReconnect`,扫到已存 `ring_mac` 就连,3→60s 退避;配对页期间暂停以免抢扫描)。**限制:戒指需在广播(醒着/佩戴),深睡需再广播或双击唤醒。**
3. **设备配对(卡片/戒指统一)**
   连接页先选「录音卡 / 戒指」(两个大图,非 tab)→ 占位图 → 搜到弹 modal → 连上进对应详情页。
4. **戒指详情页**(仿录音卡「我的设备」):占位金环图 + 连接状态 + **电量/固件/MAC**(实时 `GET_BATTERY`/`GET_VERSION` 拉取)+「解除绑定」(断开 + 清 `ring_mac` + 停自动回连)。
5. **头部设备图标**:戒指连上→环形图标「戒指已连接」(绿)、录音卡→卡片图标「录音卡已连接」(绿)、未连→空心图标。状态变化实时刷新(`RingConnection` 全局 Listenable)。
6. **硬件双击手势**:`IKeyDownListener`,双击(key=2)开/关录音。

## 二、未完成 / 阻塞

- **离线文件同步(脱机录音 → 连上后拉取建卡)——被 SDK bug 阻塞。**
  戒指可脱机本地录音(`*_8.bin` = ADPCM 8k),列表 `GET_FILE_LIST` 我们能取到;但**下载文件内容会让 SDK 崩溃**:`GET_FILE_CONTENT` 与 `DOWNLOAD_FILE` 的内容都经 `LmAPILite.onReceive → LmApiDataUtils.fileContentType/fileContentAudioType`,在 **aar 1.3.3** 解析尾包 OOM(分配 ~909MB)主线程 FATAL,**应用层 catch 不住**。数据其实在传(走 `saveData` hex 包)。官方 demo app 下载正常 = 用了**更新版 aar**。
  **行动:向勇芯(xiaojian.cui@bravechip.com)要修复版 Android aar + `DOWNLOAD_FILE` 用法示例。** 拿到后:`DOWNLOAD_FILE` → 累积 ADPCM → `AdPcmTool` 解码 → WAV → ASR → 建卡 → `DELETE_FILE`,下游全复用现有管线(代码已备:插件 DOWNLOAD_FILE 路径在,调试页下载按钮暂禁用)。
- **iOS**:未做。插件目前 Android-only;iOS SDK 是 `BCLRingSDK`(新框架),后续补插件 iOS 侧。
- **前台服务长录音保活**(息屏数分钟以上的实时录音)未专门处理。

## 三、代码地图

- 插件 `mobile/packages/chiplet_ring/`(Android-only):
  - `lib/`:`chiplet_ring.dart`(门面 `ChipletRing`)、`src/models.dart`、`src/ring_platform.dart`(MethodChannel + 4 个 EventChannel,广播流静态缓存避免多实例抢 sink)、`src/wav_writer.dart`。
  - `android/.../ChipletRingPlugin.kt`:封装 `com.lm.sdk`(LmAPILite/BLEUtils/AdPcmTool…),懒初始化、LocalBroadcastManager 连接状态、token 保活、扫描/连接/录音/按键/电量/文件。
  - `android/libs` + `local-maven`:vendored `ChipletRing-1.3.3-release.aar`(AGP 不允许 library 直接依赖本地 aar,用 local maven 坐标引入)、`st25sdk-1.13.0.jar`;补依赖 `localbroadcastmanager`/`greendao`/`gson`/`annotations`。
- App 侧 `mobile/lib/ring/`:`ring_capture_controller.dart`(双击状态机 + 掉帧检测 + 停录尾音 drain + 阶段回调)、`ring_capture_service.dart`(登录后幂等启动)、`ring_asr.dart`(PCM→WAV→识别)、`ring_reconnect.dart`(扫描式回连单例)、`ring_connection.dart`(全局连接态)、`ring_art.dart`(金环占位图)。
- 接线:`main.dart`(登录后 `startRingCapture` + `RingConnection.ensureStarted`)、`pages/device_pairing_page.dart`(卡片/戒指选择 + modal)、`pages/my_ring_page.dart`(戒指详情)、`widgets/global_header.dart`(设备图标)、`pages/login_page.dart` 与 `widgets/global_header.dart` 的 `kDebugMode` 调试入口、`pages/ring_debug_page.dart`(调试页)。
- 后端:**无改动**(复用现有 `/api/flash` + 腾讯 ASR)。

## 四、SDK 真实接口要点(踩坑总结见 00-spec §7)

`LmAPILite.init(Application)` 懒初始化;连接 `BLEUtils.connectLockByBLE`;连接态走 `LocalBroadcastManager` 的 `BLEService.BROADCAST_CONNECT_STATE_CHANGE`;成功(7)调 `BLEUtils.setGetToken(true)`;录音 `CONTROL_AUDIO_ADPCM(1/0, IAudioListenerLite)`,`controlAudioResult` 给的**已是解码 PCM(勿再解)**;采样率 **8kHz**;手势 `KEY_DOWN_LISTENER`;电量 `GET_BATTERY(0)`→`battery(0, 电量)`;回连 `BLEUtils.setMac`+`reconnectionLockByBLE`(冷启动不可靠,改用扫描式)。

## 五、运行 / 联调

- 真机 + 真戒指。本地后端联调:`docker compose up`(:8000)+ `adb reverse tcp:8000 tcp:8000`,默认 `API_BASE=localhost:8000` 即通(ASR 走 `tencentAsrBase`)。
- 调试入口:登录页「[Debug] Ring 调试（免登录）」(仅 debug 包可见);release 包默认隐藏。
- 测试:`cd mobile && flutter test test/ring/`(模型/WAV/ASR/控制器单测)。
