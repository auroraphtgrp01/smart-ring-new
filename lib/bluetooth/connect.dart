import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'service_discovery.dart';
import 'gatt_service_manager.dart';

class BluetoothConnector {
  final String targetDeviceName;
  final void Function(String) onLog;
  final Function(List<ScanResult>) onScanResults;
  final Function(bool) onScanningStateChanged;
  final Function(BluetoothConnectionState) onConnectionStateChanged;
  final Function(BluetoothDevice?) onDeviceConnectionChanged;
  final Function(List<BluetoothService>)? onServicesDiscovered;
  final Function(String, List<int>?)? onDataReceived;

  List<ScanResult> scanResults = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;
  ServiceDiscovery? serviceDiscovery;
  StreamSubscription? scanSubscription;
  StreamSubscription? connectionSubscription;
  final GattServiceManager gattServiceManager = GattServiceManager();

  BluetoothConnector({
    required this.targetDeviceName,
    required this.onLog,
    required this.onScanResults,
    required this.onScanningStateChanged,
    required this.onConnectionStateChanged,
    required this.onDeviceConnectionChanged,
    this.onServicesDiscovered,
    this.onDataReceived,
  });

  Future<void> initialize() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    FlutterBluePlus.isScanning.listen((scanning) {
      isScanning = scanning;
      onScanningStateChanged(scanning);
    });

    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results
          .where(
              (result) => result.device.platformName.contains(targetDeviceName))
          .toList();
      onScanResults(scanResults);
    });
  }

  Future<void> startScan() async {
    if (isScanning) {
      await FlutterBluePlus.stopScan();
      return;
    }
    scanResults.clear();
    onScanResults(scanResults);
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (connectedDevice != null) {
      await disconnectDevice();
    }

    try {
      onLog("Bắt đầu kết nối với thiết bị: ${device.platformName}");
      connectedDevice = device;
      onDeviceConnectionChanged(device);

      connectionSubscription?.cancel();
      connectionSubscription = device.connectionState.listen((state) {
        onLog("Trạng thái kết nối thay đổi: ${_getStateString(state)}");
        onConnectionStateChanged(state);

        if (state == BluetoothConnectionState.connected) {
          onLog("Đã kết nối thành công, thiết lập service discovery");
          _onConnectSuccess(device);
        }

        if (state == BluetoothConnectionState.disconnected) {
          onLog("Thiết bị đã ngắt kết nối");
          onDeviceConnectionChanged(null);
          serviceDiscovery = null;
        }
      });

      // Tăng timeout lên 30 giây để đảm bảo đủ thời gian kết nối
      await device.connect(timeout: const Duration(seconds: 30));
      onLog("Đã kết nối với ${device.platformName}");

      // Kiểm tra trạng thái kết nối sau khi gọi connect
      final currentState = await device.connectionState.first;
      onLog("Trạng thái kết nối hiện tại: ${_getStateString(currentState)}");
    } catch (e) {
      onLog("Lỗi kết nối: $e");
      onConnectionStateChanged(BluetoothConnectionState.disconnected);
    }
  }

  Future<void> _onConnectSuccess(BluetoothDevice device) async {
    connectedDevice = device;
    onDeviceConnectionChanged(device);
    onConnectionStateChanged(BluetoothConnectionState.connected);
    onLog("Đã kết nối với thiết bị: ${device.platformName}");

    final services =
        await gattServiceManager.getSupportedGattServices(device.remoteId.str);
    if (services != null) {
      serviceDiscovery = ServiceDiscovery(
        device: device,
        onLog: onLog,
        onServicesDiscovered: (services) {
          onServicesDiscovered?.call(services);
        },
        onDataReceived: (uuid, data) {
          onDataReceived?.call(uuid, data);
        },
      );
      onServicesDiscovered?.call(services);
    }
  }

  Future<void> readCharacteristic(String uuid) async {
    if (serviceDiscovery == null) {
      onLog("Chưa discover services");
      return;
    }
    await serviceDiscovery!.readCharacteristic(uuid);
  }

  Future<bool> writeCharacteristic(String uuid, List<int> data,
      {bool withResponse = true}) async {
    if (serviceDiscovery == null) {
      onLog("Chưa discover services");
      return false;
    }
    return await serviceDiscovery!
        .writeCharacteristic(uuid, data, withResponse: withResponse);
  }

  Future<void> disconnectDevice() async {
    await connectionSubscription?.cancel();
    await connectedDevice?.disconnect();
    connectedDevice = null;
    onDeviceConnectionChanged(null);
    onConnectionStateChanged(BluetoothConnectionState.disconnected);
    if (connectedDevice != null) {
      final deviceId = connectedDevice!.remoteId.str;
      gattServiceManager.clearServiceCache(deviceId);
    }
  }

  Future<void> dispose() async {
    await scanSubscription?.cancel();
    await connectionSubscription?.cancel();
    await connectedDevice?.disconnect();
    gattServiceManager.clearAllServiceCache();
  }

  static Color getConnectionStateColor(BluetoothConnectionState state) {
    switch (state) {
      case BluetoothConnectionState.connected:
        return Colors.green;
      case BluetoothConnectionState.connecting:
      case BluetoothConnectionState.disconnecting:
        return Colors.orange;
      case BluetoothConnectionState.disconnected:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String getConnectionStateText(BluetoothConnectionState state) {
    switch (state) {
      case BluetoothConnectionState.connected:
        return "ĐÃ KẾT NỐI";
      case BluetoothConnectionState.connecting:
        return "ĐANG KẾT NỐI...";
      case BluetoothConnectionState.disconnecting:
        return "ĐANG NGẮT KẾT NỐI...";
      case BluetoothConnectionState.disconnected:
        return "ĐÃ NGẮT KẾT NỐI";
      default:
        return "KHÔNG XÁC ĐỊNH";
    }
  }

  String _getStateString(BluetoothConnectionState state) {
    return getConnectionStateText(state);
  }

  Future<List<BluetoothService>?> getDeviceServices(BluetoothDevice device) {
    return gattServiceManager.getSupportedGattServices(device.remoteId.str);
  }
}
