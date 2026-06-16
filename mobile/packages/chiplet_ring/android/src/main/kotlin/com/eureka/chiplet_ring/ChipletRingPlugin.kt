package com.eureka.chiplet_ring

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import com.lm.sdk.BLEService
import com.lm.sdk.LogicalApi
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

    private var audioSink: EventChannel.EventSink? = null
    private var stateSink: EventChannel.EventSink? = null

    private val main = Handler(Looper.getMainLooper())
    private val found = LinkedHashMap<String, BluetoothDevice>()
    private val lastRssi = HashMap<String, Int>()
    private var receiverRegistered = false

    private val leScanCallback = BluetoothAdapter.LeScanCallback { device, rssi, bytes ->
        val info = LogicalApi.getBleDeviceInfoWhenBleScan(device, rssi, bytes, false) ?: return@LeScanCallback
        found[device.address] = device
        lastRssi[device.address] = rssi
        emitScanning()
    }

    private fun emitScanning() {
        val devices = found.values.map {
            mapOf("id" to it.address, "name" to (it.name ?: ""), "rssi" to (lastRssi[it.address] ?: 0))
        }
        main.post { stateSink?.success(mapOf("conn" to "scanning", "devices" to devices)) }
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
        val filter = IntentFilter(BLEService.BROADCAST_CONNECT_STATE_CHANGE)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(connReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            appContext.registerReceiver(connReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        if (receiverRegistered) { appContext.unregisterReceiver(connReceiver); receiverRegistered = false }
        methods.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startScan" -> {
                found.clear(); lastRssi.clear()
                BLEUtils.startLeScan(appContext, leScanCallback)
                main.post { stateSink?.success(mapOf("conn" to "scanning", "devices" to emptyList<Any>())) }
                result.success(null)
            }
            "stopScan" -> { BLEUtils.stopLeScan(appContext, leScanCallback); result.success(null) }
            "connect" -> {
                val id = call.argument<String>("id")
                if (id == null) { result.error("no_id", "connect requires id", null); return }
                val dev = found[id] ?: BluetoothAdapter.getDefaultAdapter()?.getRemoteDevice(id)
                if (dev == null) { result.error("no_device", "device not found: $id", null); return }
                BLEUtils.isHIDDevice = false
                main.post { stateSink?.success(mapOf("conn" to "connecting", "devices" to emptyList<Any>())) }
                BLEUtils.connectLockByBLE(appContext, dev)
                result.success(null)
            }
            "disconnect" -> { BLEUtils.disconnectBLE(appContext); result.success(null) }
            "startRecording" -> { /* Task 7 */ result.success(null) }
            "stopRecording" -> { /* Task 7 */ result.success(null) }
            else -> result.notImplemented()
        }
    }
}
