import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'dart:async';

class ServiceDiscovery {
  final BluetoothDevice device;
  final void Function(String) onLog;
  final Function(List<BluetoothService>) onServicesDiscovered;
  final Function(String, List<int>?) onDataReceived;

  List<BluetoothService> discoveredServices = [];
  Map<String, BluetoothCharacteristic> characteristicsMap = {};

  ServiceDiscovery({
    required this.device,
    required this.onLog,
    required this.onServicesDiscovered,
    required this.onDataReceived,
  });

  Future<void> discoverServices() async {
    onLog("Bắt đầu quá trình discover services...");

    try {
      // Kiểm tra trạng thái kết nối qua giá trị hiện tại
      BluetoothConnectionState currentState =
          await device.connectionState.first;
      if (currentState != BluetoothConnectionState.connected) {
        onLog(
            "Không thể discover services: Thiết bị chưa kết nối (Trạng thái: $currentState)");
        return;
      }

      // Yêu cầu MTU cao hơn trước khi discover
      try {
        int mtu = await device.requestMtu(247);
        onLog("Đã thiết lập MTU: $mtu");
      } catch (e) {
        onLog("Không thể thiết lập MTU: $e");
      }

      onLog("Đang tìm kiếm services... (UUID thiết bị: ${device.remoteId})");
      discoveredServices = await device.discoverServices();
      onLog("Đã tìm thấy ${discoveredServices.length} services");

      // Lưu trữ các characteristics để dễ dàng truy cập sau này
      _mapCharacteristics();

      onServicesDiscovered(discoveredServices);
    } catch (e) {
      onLog("Lỗi khi discover services: $e");
      throw e;
    }
  }

  void _mapCharacteristics() {
    characteristicsMap.clear();
    for (var service in discoveredServices) {
      for (var characteristic in service.characteristics) {
        String charUuid = characteristic.uuid.toString();
        characteristicsMap[charUuid] = characteristic;

        onLog("Đã tìm thấy characteristic: $charUuid");

        _setupNotifications(characteristic);
      }
    }
  }

  Future<void> _setupNotifications(
      BluetoothCharacteristic characteristic) async {
    // Kiểm tra xem characteristic có hỗ trợ notify không
    if (characteristic.properties.notify) {
      try {
        // Đăng ký nhận thông báo
        await characteristic.setNotifyValue(true);
        characteristic.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            onDataReceived(characteristic.uuid.toString(), value);
          }
        });

        onLog("Đã đăng ký nhận thông báo từ ${characteristic.uuid}");
      } catch (e) {
        onLog("Lỗi khi đăng ký notify: $e");
      }
    }
  }

  Future<void> readCharacteristic(String characteristicUuid) async {
    if (!characteristicsMap.containsKey(characteristicUuid)) {
      onLog("Không tìm thấy characteristic: $characteristicUuid");
      return;
    }

    try {
      final characteristic = characteristicsMap[characteristicUuid]!;
      final value = await characteristic.read();
      onDataReceived(characteristicUuid, value);
      onLog("Đã đọc dữ liệu từ $characteristicUuid: $value");
    } catch (e) {
      onLog("Lỗi khi đọc characteristic: $e");
    }
  }

  Future<bool> writeCharacteristic(String characteristicUuid, List<int> data,
      {bool withResponse = true}) async {
    if (!characteristicsMap.containsKey(characteristicUuid)) {
      onLog("Không tìm thấy characteristic: $characteristicUuid");
      return false;
    }

    try {
      final characteristic = characteristicsMap[characteristicUuid]!;
      await characteristic.write(data, withoutResponse: !withResponse);
      onLog("Đã ghi dữ liệu vào $characteristicUuid: $data");
      return true;
    } catch (e) {
      onLog("Lỗi khi ghi characteristic: $e");
      return false;
    }
  }

  String getServiceInfo(BluetoothService service) {
    String uuid = service.uuid.toString();
    String knownService = _getKnownServiceName(uuid);
    return knownService.isNotEmpty ? "$knownService ($uuid)" : uuid;
  }

  String getCharacteristicInfo(BluetoothCharacteristic characteristic) {
    String uuid = characteristic.uuid.toString();
    String knownChar = _getKnownCharacteristicName(uuid);

    List<String> properties = [];
    if (characteristic.properties.read) properties.add("Read");
    if (characteristic.properties.write) properties.add("Write");
    if (characteristic.properties.writeWithoutResponse)
      properties.add("WriteNoResp");
    if (characteristic.properties.notify) properties.add("Notify");
    if (characteristic.properties.indicate) properties.add("Indicate");

    String propertiesStr = properties.join(", ");

    return knownChar.isNotEmpty
        ? "$knownChar ($uuid) [$propertiesStr]"
        : "$uuid [$propertiesStr]";
  }

  // Các hàm helper để ánh xạ UUID sang tên dễ đọc
  String _getKnownServiceName(String uuid) {
    // UUID tiêu chuẩn theo Bluetooth SIG
    switch (uuid.toUpperCase()) {
      case "1800":
        return "Generic Access";
      case "1801":
        return "Generic Attribute";
      case "180A":
        return "Device Information";
      case "180F":
        return "Battery Service";
      case "180D":
        return "Heart Rate";
      default:
        return "";
    }
  }

  String _getKnownCharacteristicName(String uuid) {
    // UUID tiêu chuẩn theo Bluetooth SIG
    switch (uuid.toUpperCase()) {
      case "2A00":
        return "Device Name";
      case "2A01":
        return "Appearance";
      case "2A19":
        return "Battery Level";
      case "2A29":
        return "Manufacturer Name";
      case "2A24":
        return "Model Number";
      case "2A25":
        return "Serial Number";
      case "2A27":
        return "Hardware Revision";
      case "2A26":
        return "Firmware Revision";
      case "2A28":
        return "Software Revision";
      default:
        return "";
    }
  }
}
