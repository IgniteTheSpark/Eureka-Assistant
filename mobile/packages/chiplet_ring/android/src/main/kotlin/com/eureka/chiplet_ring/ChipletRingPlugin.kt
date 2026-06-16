package com.eureka.chiplet_ring

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
import com.lm.sdk.lmApiInter.IAudioListenerLite
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
            // CALIBRATE (device-untested): assume `bytes` is ADPCM-encoded audio and the 2nd int arg
            // is the input byte length (bytes.size). Verify against real ring output:
            // - If audio is garbled/silent, the int param may be a frame-count flag rather than byte length.
            // - If audio is already PCM (not ADPCM), skip decode and use `bytes` directly.
            // audioType: 1 = mono, 2 = stereo
            val pcm = if (audioType == 2) adpcm.decodeADPCMDualChannel(bytes, bytes.size)
                      else adpcm.decodeADPCMMonoChannel(bytes, bytes.size)
            val s = seq++
            main.post { audioSink?.success(mapOf("pcm" to pcm.toList(), "seq" to s, "channels" to audioType)) }
        }
        override fun controlAudioRawDataResult(bytes: ByteArray) {}
        override fun getControlAudioAdpcmResult(adpcm: Boolean) {}
        override fun pushAudioInformationResult(success: Boolean) {}
        override fun TOUCH_AUDIO_FINISH_XUN_FEI() {}
        override fun recordingResult(result: Boolean) {}
    }
    private val lastRssi = HashMap<String, Int>()
    private var receiverRegistered = false

    // FIX 1: All access to found/lastRssi maps happens on main thread inside main.post{}
    private val leScanCallback = BluetoothAdapter.LeScanCallback { device, rssi, bytes ->
        val info = LogicalApi.getBleDeviceInfoWhenBleScan(device, rssi, bytes, false) ?: return@LeScanCallback
        main.post {
            found[device.address] = device
            lastRssi[device.address] = rssi
            val devices = found.values.map {
                mapOf("id" to it.address, "name" to (it.name ?: ""), "rssi" to (lastRssi[it.address] ?: 0))
            }
            stateSink?.success(mapOf("conn" to "scanning", "devices" to devices))
        }
    }

    private val connReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            if (intent?.action == BLEService.BROADCAST_CONNECT_STATE_CHANGE) {
                val s = intent.getIntExtra(BLEService.BROADCAST_CONNECT_STATE_VALUE, -1)
                val conn = if (s == BLEService.CONNECT_STATE_SUCCESS) "connected" else "disconnected"
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
        // FIX 3: Guard against double-registration
        if (!receiverRegistered) {
            val filter = IntentFilter(BLEService.BROADCAST_CONNECT_STATE_CHANGE)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                appContext.registerReceiver(connReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                appContext.registerReceiver(connReceiver, filter)
            }
            receiverRegistered = true
        }
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        if (receiverRegistered) { appContext.unregisterReceiver(connReceiver); receiverRegistered = false }
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan" -> {
                found.clear(); lastRssi.clear()
                // FIX 2: Guard BLEUtils call with try/catch
                try {
                    BLEUtils.startLeScan(appContext, leScanCallback)
                    main.post { stateSink?.success(mapOf("conn" to "scanning", "devices" to emptyList<Any>())) }
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "stopScan" -> {
                // FIX 2: Guard BLEUtils call with try/catch
                try {
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
                    LmAPILite.CONTROL_AUDIO_ADPCM(1, audioListener)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            "stopRecording" -> {
                // FIX 2: Guard LmAPILite call with try/catch
                try {
                    LmAPILite.CONTROL_AUDIO_ADPCM(0, audioListener)
                    result.success(null)
                } catch (e: Throwable) { result.error("ring_error", e.message, null) }
            }
            else -> result.notImplemented()
        }
    }
}
