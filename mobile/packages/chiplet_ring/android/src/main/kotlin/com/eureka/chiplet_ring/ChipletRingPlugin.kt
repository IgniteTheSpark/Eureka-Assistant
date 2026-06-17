package com.eureka.chiplet_ring

import android.app.Application
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import com.lm.sdk.AdPcmTool
import com.lm.sdk.BLEService
import com.lm.sdk.LmAPILite
import com.lm.sdk.LogicalApi
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.lm.sdk.inter.IKeyDownListener
import com.lm.sdk.inter.IFileListListener
import com.lm.sdk.inter.FileResponseCallback
import com.lm.sdk.library.AppConfig
import com.lm.sdk.lmApiInter.IAudioListenerLite
import com.lm.sdk.lmApiInter.IBatteryListenerLite
import com.lm.sdk.lmApiInter.ICommonalityListenerLite
import com.lm.sdk.lmApiInter.IResponseListenerLite
import com.lm.sdk.lmApiInter.IVersionListenerLite
import com.lm.sdk.utils.BLEUtils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class ChipletRingPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var appContext: Context
    private lateinit var methods: MethodChannel
    private lateinit var audio: EventChannel
    private lateinit var state: EventChannel
    private lateinit var key: EventChannel
    private lateinit var file: EventChannel

    @Volatile private var audioSink: EventChannel.EventSink? = null
    @Volatile private var stateSink: EventChannel.EventSink? = null
    @Volatile private var keySink: EventChannel.EventSink? = null
    @Volatile private var fileSink: EventChannel.EventSink? = null

    // On-device file ops (local recordings live here). One IFileListListener serves both
    // GET_FILE_LIST (-> file()/getFileContentFinish) and GET_FILE_CONTENT (-> fileContent/
    // AudioFileContent/getFileContentFinish). Events are streamed to Dart on chiplet_ring/file.
    private val fileListListener = object : IFileListListener {
        // SDK may pass null for raw/name — declare nullable to avoid Kotlin's
        // non-null parameter NPE (which was silently dropping every file entry).
        override fun file(count: Int, index: Int, size: Int, name: String?, raw: ByteArray?) {
            android.util.Log.i("ChipletRing", "file list item #$index/$count name=$name size=$size rawLen=${raw?.size ?: -1}")
            val nm = name ?: ""
            // Use raw bytes as the file id if provided, else fall back to the name bytes
            // (GET_FILE_CONTENT/DELETE_FILE need an identifier).
            val id = raw?.toList() ?: nm.toByteArray().toList()
            main.post { fileSink?.success(mapOf(
                "kind" to "item", "count" to count, "index" to index,
                "size" to size, "name" to nm, "id" to id)) }
        }
        override fun fileContent(content: String?) {
            main.post { fileSink?.success(mapOf("kind" to "text", "content" to (content ?: ""))) }
        }
        override fun AudioFileContent(content: ByteArray?) {
            android.util.Log.i("ChipletRing", "AudioFileContent len=${content?.size ?: 0}")
            main.post { fileSink?.success(mapOf("kind" to "audio", "pcm" to (content?.toList() ?: emptyList<Int>()))) }
        }
        override fun getFileContentFinish() {
            main.post { fileSink?.success(mapOf("kind" to "done")) }
        }
    }

    // PERFORM_FORMAT_FILESYSTEM / GET_FILE_MEMORY use the lower-level FileResponseCallback.
    // We only log here; the format handler also emits a "formatted" event optimistically.
    private val fileRespCb = object : FileResponseCallback {
        override fun onFileListReceived(b: ByteArray) {}
        override fun onFileInfoReceived(b: ByteArray) {}
        override fun onFileDownloadEndReceived(b: ByteArray) {}
        override fun onDownloadAllFileProgress(b: ByteArray) {}
        override fun oneFileDownloadSuccess() {}
        override fun onDownloadStatusReceived(b: ByteArray) {}
        override fun onFileDataReceived(b: ByteArray) {}
        override fun onFileState(state: Int) {
            android.util.Log.i("ChipletRing", "onFileState=$state")
            main.post { fileSink?.success(mapOf("kind" to "memory", "state" to state)) }
        }
        override fun onFilePushFileName(b: ByteArray) {}
        override fun onFilePushFileData(b: ByteArray) {}
        override fun onFileResumeBreakpoint(a: Int, b: Long, c: Long) {}
        override fun onFileResumeBreakpointProgress(a: Int) {}
        override fun localMemoryFull(a: Int, b: Int, c: Int) {
            main.post { fileSink?.success(mapOf("kind" to "memoryFull", "a" to a, "b" to b, "c" to c)) }
        }
    }

    // Ring gesture/key codes: 0=long-press 1=single 2=double 3=triple 4=up 5=down 6=left 7=right
    private val keyListener = IKeyDownListener { keyCode ->
        android.util.Log.i("ChipletRing", "ringPushKeyDownResult key=$keyCode")
        main.post { keySink?.success(keyCode) }
    }

    private val main = Handler(Looper.getMainLooper())
    private val found = LinkedHashMap<String, BluetoothDevice>()

    private var seq = 0
    private val adpcm = AdPcmTool()

    private val audioListener = object : IAudioListenerLite {
        override fun controlAudioResult(bytes: ByteArray, audioType: Int) {
            // CALIBRATED on-device: `bytes` here is ALREADY-DECODED 16-bit PCM. The SDK decodes
            // the raw ADPCM internally (raw arrives separately via controlAudioRawDataResult) and
            // hands us PCM. Decoding it again produced noise — so pass it straight through.
            // audioType: 1 = mono, 2 = stereo.
            val s = seq++
            main.post { audioSink?.success(mapOf("pcm" to bytes.toList(), "seq" to s, "channels" to audioType)) }
        }
        override fun controlAudioRawDataResult(bytes: ByteArray) {
            android.util.Log.i("ChipletRing", "controlAudioRawDataResult len=${bytes.size}")
        }
        override fun getControlAudioAdpcmResult(adpcm: Boolean) {
            android.util.Log.i("ChipletRing", "getControlAudioAdpcmResult adpcm=$adpcm")
        }
        override fun pushAudioInformationResult(success: Boolean) {
            android.util.Log.i("ChipletRing", "pushAudioInformationResult success=$success")
        }
        override fun TOUCH_AUDIO_FINISH_XUN_FEI() {
            android.util.Log.i("ChipletRing", "TOUCH_AUDIO_FINISH_XUN_FEI")
        }
        override fun recordingResult(result: Boolean) {
            android.util.Log.i("ChipletRing", "recordingResult result=$result")
        }
    }
    private val lastRssi = HashMap<String, Int>()
    private var receiverRegistered = false
    @Volatile private var scanning = false

    // FIX 1: All access to found/lastRssi maps happens on main thread inside main.post{}
    private val leScanCallback = BluetoothAdapter.LeScanCallback { device, rssi, bytes ->
        if (!scanning) return@LeScanCallback // ignore stray callbacks once we stop/connect
        val info = LogicalApi.getBleDeviceInfoWhenBleScan(device, rssi, bytes, false) ?: return@LeScanCallback
        main.post {
            if (!scanning) return@post
            found[device.address] = device
            lastRssi[device.address] = rssi
            val devices = found.values.map {
                mapOf("id" to it.address, "name" to (it.name ?: ""), "rssi" to (lastRssi[it.address] ?: 0))
            }
            stateSink?.success(mapOf("conn" to "scanning", "devices" to devices))
        }
    }

    private var wlsRegistered = false

    // The SDK delivers high-level connection lifecycle here. On success (code 7) we MUST
    // kick off the token handshake via setGetToken(true) — without it the ring drops the
    // connection after ~5s and audio never streams (mirrors the official demo).
    private val responseListener = object : IResponseListenerLite {
        override fun lmBleConnecting(code: Int) {
            android.util.Log.i("ChipletRing", "lmBleConnecting code=$code")
            BLEUtils.setConnecting(true)
            main.post { stateSink?.success(mapOf("conn" to "connecting", "devices" to emptyList<Any>())) }
        }
        override fun lmBleConnectionSucceeded(code: Int) {
            android.util.Log.i("ChipletRing", "lmBleConnectionSucceeded code=$code")
            BLEUtils.setConnecting(false)
            if (code == 7) {
                BLEUtils.setGetToken(true) // token handshake keeps the link alive
                main.post { stateSink?.success(mapOf("conn" to "connected", "devices" to emptyList<Any>())) }
            }
        }
        override fun lmBleConnectionFailed(code: Int) {
            android.util.Log.i("ChipletRing", "lmBleConnectionFailed code=$code")
            BLEUtils.setGetToken(false)
            BLEUtils.setConnecting(false)
            main.post { stateSink?.success(mapOf("conn" to "disconnected", "devices" to emptyList<Any>())) }
        }
        override fun timeOut(msg: String?) { android.util.Log.i("ChipletRing", "timeOut $msg") }
        override fun saveData(data: String?) { android.util.Log.i("ChipletRing", "saveData $data") }
    }

    private val connReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            if (intent?.action == BLEService.BROADCAST_CONNECT_STATE_CHANGE) {
                val s = intent.getIntExtra(BLEService.BROADCAST_CONNECT_STATE_VALUE, -1)
                android.util.Log.i("ChipletRing", "connState=$s (success=${BLEService.CONNECT_STATE_SUCCESS})")
                val conn = when (s) {
                    BLEService.CONNECT_STATE_SUCCESS -> "connected"
                    BLEService.CONNECT_STATE_SERVICE_DISCONNECTED -> "disconnected"
                    else -> "connecting" // intermediate handshake states 1..6
                }
                main.post { stateSink?.success(mapOf("conn" to conn, "devices" to emptyList<Any>())) }
            }
        }
    }

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
        key = EventChannel(b.binaryMessenger, "chiplet_ring/key").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { keySink = sink }
                override fun onCancel(args: Any?) { keySink = null }
            })
        }
        file = EventChannel(b.binaryMessenger, "chiplet_ring/file").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) { fileSink = sink }
                override fun onCancel(args: Any?) { fileSink = null }
            })
        }
        // FIX 3: Guard against double-registration.
        // The SDK's BLEService dispatches connect-state via androidx LocalBroadcastManager
        // (app-local), NOT global broadcasts — so we must register on LBM, matching the demo.
        if (!receiverRegistered) {
            val filter = IntentFilter(BLEService.BROADCAST_CONNECT_STATE_CHANGE)
            LocalBroadcastManager.getInstance(appContext).registerReceiver(connReceiver, filter)
            receiverRegistered = true
        }
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        if (receiverRegistered) {
            LocalBroadcastManager.getInstance(appContext).unregisterReceiver(connReceiver); receiverRegistered = false
        }
        if (wlsRegistered) { LmAPILite.removeWLSCmdListener(appContext); wlsRegistered = false }
        methods.setMethodCallHandler(null)
    }

    /// Lazily initialize the BraveChip SDK on first use (not at app launch).
    /// Without init() the SDK's static Application ref is null and audio/file calls NPE.
    private fun ensureSdkInit() {
        if (!LmAPILite.isInit()) {
            LmAPILite.init(appContext as Application)
            AppConfig.setOverseas(false) // domestic
        }
        if (!wlsRegistered) {
            LmAPILite.addWLSCmdListener(appContext, responseListener)
            LmAPILite.KEY_DOWN_LISTENER(keyListener) // ring gesture/button events
            wlsRegistered = true
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try { ensureSdkInit() } catch (e: Throwable) {
            result.error("ring_error", "sdk init failed: ${e.message}", null); return
        }
        when (call.method) {
            "startScan" -> {
                found.clear(); lastRssi.clear()
                // FIX 2: Guard BLEUtils call with try/catch
                try {
                    scanning = true
                    BLEUtils.startLeScan(appContext, leScanCallback)
                    main.post { stateSink?.success(mapOf("conn" to "scanning", "devices" to emptyList<Any>())) }
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "stopScan" -> {
                // FIX 2: Guard BLEUtils call with try/catch
                try {
                    scanning = false
                    BLEUtils.stopLeScan(appContext, leScanCallback)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "connect" -> {
                val id = call.argument<String>("id")
                if (id == null) { result.error("no_id", "connect requires id", null); return }
                val dev = found[id] ?: BluetoothAdapter.getDefaultAdapter()?.getRemoteDevice(id)
                if (dev == null) { result.error("no_device", "device not found: $id", null); return }
                // FIX 2: Guard BLEUtils call with try/catch
                try {
                    // Stop scanning before connecting — concurrent LE scan destabilizes GATT
                    // and stray scan callbacks would clobber the connection state in the UI.
                    scanning = false
                    BLEUtils.stopLeScan(appContext, leScanCallback)
                    BLEUtils.isHIDDevice = false
                    main.post { stateSink?.success(mapOf("conn" to "connecting", "devices" to emptyList<Any>())) }
                    BLEUtils.connectLockByBLE(appContext, dev)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "disconnect" -> {
                // FIX 2: Guard BLEUtils call with try/catch
                try {
                    BLEUtils.disconnectBLE(appContext)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "startRecording" -> {
                seq = 0
                // FIX 2: Guard adpcm + LmAPILite calls with try/catch
                try {
                    adpcm.resetAllDecoders()
                    android.util.Log.i("ChipletRing", "startRecording -> CONTROL_AUDIO_ADPCM(1)")
                    LmAPILite.CONTROL_AUDIO_ADPCM(1, audioListener)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "stopRecording" -> {
                // FIX 2: Guard LmAPILite call with try/catch
                try {
                    android.util.Log.i("ChipletRing", "stopRecording -> CONTROL_AUDIO_ADPCM(0)")
                    LmAPILite.CONTROL_AUDIO_ADPCM(0, audioListener)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            // ---- On-device (local) recording + file management ----
            "startLocalRecording" -> {
                val total = call.argument<Int>("total") ?: 1200
                val slice = call.argument<Int>("slice") ?: 600
                try {
                    android.util.Log.i("ChipletRing", "CMD_START_STOP_RECORDING(true,$total,$slice)")
                    LmAPILite.CMD_START_STOP_RECORDING(true, total, slice, audioListener)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "stopLocalRecording" -> {
                try {
                    android.util.Log.i("ChipletRing", "CMD_START_STOP_RECORDING(false)")
                    LmAPILite.CMD_START_STOP_RECORDING(false, 0, 0, audioListener)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "getFileList" -> {
                try { LmAPILite.GET_FILE_LIST(fileListListener); result.success(null) }
                catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "downloadFile" -> {
                val type = call.argument<Int>("type") ?: 0
                val id = (call.argument<List<Int>>("id"))?.map { it.toByte() }?.toByteArray() ?: ByteArray(0)
                try { LmAPILite.GET_FILE_CONTENT(type, id, fileListListener); result.success(null) }
                catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "deleteFile" -> {
                val id = (call.argument<List<Int>>("id"))?.map { it.toByte() }?.toByteArray() ?: ByteArray(0)
                try {
                    LmAPILite.DELETE_FILE(id, object : ICommonalityListenerLite {
                        override fun success() { main.post { fileSink?.success(mapOf("kind" to "deleted", "ok" to true)) } }
                        override fun fail() { main.post { fileSink?.success(mapOf("kind" to "deleted", "ok" to false)) } }
                    })
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "formatFiles" -> {
                try {
                    LmAPILite.PERFORM_FORMAT_FILESYSTEM(fileRespCb)
                    main.post { fileSink?.success(mapOf("kind" to "formatted")) }
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            // ---- Keep-alive / auto-reconnect ----
            "setSavedMac" -> {
                val mac = call.argument<String>("mac")
                try {
                    if (mac != null) BLEUtils.setMac(mac)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "reconnect" -> {
                try {
                    android.util.Log.i("ChipletRing", "reconnectionLockByBLE")
                    BLEUtils.reconnectionLockByBLE(appContext)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "isConnected" -> {
                try { result.success(BLEUtils.isConnected()) }
                catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            // ---- Device info (battery / firmware) — one-shot async queries ----
            "getBattery" -> {
                var replied = false
                try {
                    LmAPILite.GET_BATTERY(0, object : IBatteryListenerLite {
                        override fun battery(type: Int, electricity: Int) {
                            if (type == 0 && !replied) { replied = true; main.post { result.success(electricity) } }
                        }
                        override fun battery_push(type: Int, electricity: Int) {}
                    })
                } catch (e: Throwable) { if (!replied) { replied = true; result.error("ring_error", e.message, null) } }
            }
            "getVersion" -> {
                var replied = false
                try {
                    LmAPILite.GET_VERSION(true, object : IVersionListenerLite {
                        override fun versionResult(fw: String, hw: String) {
                            if (!replied) { replied = true; main.post { result.success(mapOf("fw" to fw, "hw" to hw)) } }
                        }
                    })
                } catch (e: Throwable) { if (!replied) { replied = true; result.error("ring_error", e.message, null) } }
            }
            else -> result.notImplemented()
        }
    }
}
