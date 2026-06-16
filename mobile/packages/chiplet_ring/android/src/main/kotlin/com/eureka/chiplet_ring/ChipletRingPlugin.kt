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
import com.lm.sdk.library.AppConfig
import com.lm.sdk.lmApiInter.IAudioListenerLite
import com.lm.sdk.lmApiInter.IResponseListenerLite
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

    @Volatile private var audioSink: EventChannel.EventSink? = null
    @Volatile private var stateSink: EventChannel.EventSink? = null

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
            else -> result.notImplemented()
        }
    }
}
