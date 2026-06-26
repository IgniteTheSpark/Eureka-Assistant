# =============================================================================
# proguard-rules.pro — app 模块 R8 规则
#
# 为什么需要它:Flutter Gradle 插件对 release 默认开启 R8
# (FlutterPlugin.kt 里 shouldShrinkResources() 默认 true → isMinifyEnabled = true),
# 并自动把本文件、proguard-android-optimize.txt、flutter_proguard_rules.pro
# 一起挂进 release 的 proguardFiles。所以 *不需要* 在 build.gradle.kts 里再显式
# 设 isMinifyEnabled / proguardFiles —— 只要本文件存在,Flutter 就会带上它。
#
# 为什么 release 之前一直挂:chiplet_ring 里 vendored 的勇芯戒指 SDK
# (com.lm.sdk:ChipletRing,纯 aar + libblelibrary.so)内部带了一整套"云端"网络层
# (GoMore 睡眠/HRV 分析、ServerApi),依赖 RxJava1 + Retrofit + fastjson +
# okhttputils + okhttp3 + 旧版 Apache HTTP。这些库被有意排除(见
# chiplet_ring/android/build.gradle.kts 注释):本地 BLE / 录音 / DFU 链路根本不走
# 这些类,profile 包同样没带这些库也能正常用戒指。R8 只是在链接期发现这些引用
# 缺失而报 "Missing class" 中断构建 —— 告诉它忽略即可,不要把这些重依赖加回来。
# 死代码引用确认仅来自这 8 个云端类:LogicalApi、library/http/{ServerApi,
# ServerAPIClient,BaseSubscriber}、model/{MainModel,GomoreSleepModel}、
# utils/GoMoreUtils;BLE/audio/DFU 核心一概不引用。
# =============================================================================

# ---- 戒指 SDK 死代码网络层所引用、且被有意排除的依赖:忽略缺失告警 ----
-dontwarn rx.**
-dontwarn retrofit2.**
-dontwarn com.alibaba.fastjson.**
-dontwarn com.zhy.http.okhttp.**
-dontwarn okhttp3.**
-dontwarn org.apache.http.**

# ---- 戒指 SDK 本体:含 JNI(libblelibrary.so 反向回调 Java)、greenDAO 实体、
#      Nordic DFU、gson 模型,全部对混淆/裁剪敏感。整包 keep,杜绝 R8 改名/删除
#      导致 .so 回调或 greenDAO/gson 反射找不到类。SDK 仅 ~680KB,不混淆可接受。 ----
-keep class com.lm.sdk.** { *; }
-dontwarn com.lm.sdk.**

# ---- greenDAO 3.x:DAO 通过反射读取 Property[] 静态字段 ----
-keepclassmembers class * extends org.greenrobot.greendao.AbstractDao {
    public static final org.greenrobot.greendao.Property[] *;
}
-dontwarn org.greenrobot.greendao.**

# ---- gson 泛型 TypeToken 需要保留泛型签名(默认已 keep *Annotation*) ----
-keepattributes Signature

# ---- 百融原生 BLE / 音频库(blelib、opus2mp3,含 JNI 回调):防混淆破坏连接/录音 ----
-keep class com.bairong.lib.** { *; }
-dontwarn com.bairong.lib.**
