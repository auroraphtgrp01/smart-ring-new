package com.yucheng.smarthealthpro

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import com.yucheng.ycbtsdk.YCBTClient
import com.yucheng.ycbtsdk.Constants
import com.yucheng.smarthealthpro.home.bean.RealDataResponse
import com.yucheng.smarthealthpro.home.bean.ToAppDataResponse
import com.yucheng.smarthealthpro.home.bean.EventBusMessageEvent
import org.greenrobot.eventbus.EventBus
import org.greenrobot.eventbus.Subscribe
import org.greenrobot.eventbus.ThreadMode

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.yucheng.smarthealthpro/ycbt"
    private val EVENT_CHANNEL = "com.yucheng.smarthealthpro/ycbt_events"
    private val mainHandler = Handler(Looper.getMainLooper())
    
    private var eventSink: EventChannel.EventSink? = null
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Đăng ký với EventBus
        if (!EventBus.getDefault().isRegistered(this)) {
            EventBus.getDefault().register(this)
        }
        
        // Thiết lập method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectLastDevice" -> {
                    connectLastDevice(result)
                }
                "scanDevice" -> {
                    scanAndConnectDevice(result)
                }
                "disconnectDevice" -> {
                    disconnectDevice(result)
                }
                "getConnectionState" -> {
                    result.success(YCBTClient.connectState())
                }
                "startMeasurement" -> {
                    val type = call.argument<Int>("type") ?: 0
                    startMeasurement(type, result)
                }
                "stopMeasurement" -> {
                    val type = call.argument<Int>("type") ?: 0
                    stopMeasurement(type, result)
                }
                "getMeasurementHistory" -> {
                    val type = call.argument<Int>("type") ?: 0
                    getMeasurementHistory(type, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // Thiết lập event channel cho dữ liệu thời gian thực
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Hủy đăng ký EventBus
        if (EventBus.getDefault().isRegistered(this)) {
            EventBus.getDefault().unregister(this)
        }
    }
    
    // Xử lý dữ liệu thời gian thực
    @Subscribe(threadMode = ThreadMode.MAIN)
    fun onRealDataResponse(response: RealDataResponse) {
        if (response.i == 1538) { // Mã dữ liệu SPO2
            val data = HashMap<String, Any>()
            data["dataType"] = response.i
            
            val hashMap = response.hashMap
            val spo2Value = hashMap["bloodOxygenValue"] as? Int ?: 0
            
            data["bloodOxygenValue"] = spo2Value
            
            // Gửi dữ liệu thời gian thực đến Flutter
            mainHandler.post {
                eventSink?.success(mapOf(
                    "method" to "onRealTimeData",
                    "arguments" to data
                ))
            }
        }
    }
    
    // Xử lý hoàn thành phép đo
    @Subscribe(threadMode = ThreadMode.MAIN)
    fun onDataResponse(response: ToAppDataResponse) {
        if (response.cmd == 1038) {
            val data = response.data
            if (data.size >= 2) {
                val type = data[0].toInt() and 0xFF
                val status = data[1].toInt() and 0xFF
                
                mainHandler.post {
                    eventSink?.success(mapOf(
                        "method" to "onMeasurementComplete",
                        "arguments" to mapOf(
                            "type" to type,
                            "success" to (status == 1)
                        )
                    ))
                }
            }
        }
    }
    
    // Xử lý thay đổi trạng thái kết nối
    @Subscribe(threadMode = ThreadMode.MAIN)
    fun onEvent(event: EventBusMessageEvent) {
        if (event.belState == 0) {
            // Thiết bị đã ngắt kết nối
            mainHandler.post {
                eventSink?.success(mapOf(
                    "method" to "onConnectionStateChanged",
                    "arguments" to mapOf(
                        "connected" to false
                    )
                ))
            }
        }
    }
    
    private fun connectLastDevice(result: MethodChannel.Result) {
        YCBTClient.connectLastDevice { code, device ->
            mainHandler.post {
                if (code == Constants.CODE.Code_OK) {
                    result.success(mapOf(
                        "status" to "connected",
                        "deviceName" to (device?.deviceName ?: "Thiết bị không tên"),
                        "deviceAddress" to (device?.deviceMac ?: "")
                    ))
                } else {
                    result.error("CONNECTION_FAILED", "Kết nối thiết bị thất bại", null)
                }
            }
        }
    }
    
    private fun scanAndConnectDevice(result: MethodChannel.Result) {
        YCBTClient.startScanBle { code, device ->
            if (code == Constants.CODE.Code_OK && device != null) {
                // Dừng quét khi đã tìm thấy thiết bị
                YCBTClient.stopScanBle()
                
                // Kết nối với thiết bị tìm thấy
                YCBTClient.connectDevice(device.deviceMac, device.deviceName) { connectCode ->
                    mainHandler.post {
                        if (connectCode == Constants.CODE.Code_OK) {
                            result.success(mapOf(
                                "status" to "connected",
                                "deviceName" to (device.deviceName ?: "Thiết bị không tên"),
                                "deviceAddress" to (device.deviceMac ?: "")
                            ))
                        } else {
                            result.error("CONNECTION_FAILED", "Kết nối thiết bị thất bại: $connectCode", null)
                        }
                    }
                }
            }
        }
        
        // Đặt timeout để trả về lỗi nếu không tìm thấy thiết bị
        mainHandler.postDelayed({
            YCBTClient.stopScanBle()
            if (YCBTClient.connectState() != 10) { // 10 = đã kết nối
                mainHandler.post {
                    result.error("SCAN_TIMEOUT", "Không tìm thấy thiết bị", null)
                }
            }
        }, 20000) // 20 giây timeout
    }
    
    private fun disconnectDevice(result: MethodChannel.Result) {
        YCBTClient.disConnect()
        mainHandler.post {
            result.success(mapOf("status" to "disconnected"))
        }
    }
    
    private fun startMeasurement(type: Int, result: MethodChannel.Result) {
        YCBTClient.appStartMeasurement(1, type, object : YCBTClient.AppMeasureDataCallback {
            override fun onMeasureData(p0: Int, p1: MutableMap<String, Any>?) {
                // Dữ liệu được xử lý qua EventBus
            }
        })
        
        mainHandler.post {
            result.success(mapOf("status" to "started"))
        }
    }
    
    private fun stopMeasurement(type: Int, result: MethodChannel.Result) {
        YCBTClient.appStartMeasurement(0, type, null)
        mainHandler.post {
            result.success(mapOf("status" to "stopped"))
        }
    }
    
    private fun getMeasurementHistory(type: Int, result: MethodChannel.Result) {
        when (type) {
            2 -> { // SpO2
                YCBTClient.appGetBloodOxygenHistoryRecord { code, data ->
                    mainHandler.post {
                        if (code == Constants.CODE.Code_OK && data != null) {
                            val history = data.map { item ->
                                mapOf(
                                    "value" to (item["bloodOxygenValue"] as? Int ?: 0),
                                    "timestamp" to (item["measurementDate"] as? Long ?: 0)
                                )
                            }
                            result.success(mapOf("history" to history))
                        } else {
                            result.success(mapOf("history" to emptyList<Any>()))
                        }
                    }
                }
            }
            else -> {
                mainHandler.post {
                    result.error("INVALID_TYPE", "Loại đo không hợp lệ", null)
                }
            }
        }
    }
}