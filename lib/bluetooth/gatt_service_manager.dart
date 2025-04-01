import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

/// Lớp quản lý dịch vụ GATT cho thiết bị Bluetooth Low Energy
class GattServiceManager {
  final Logger _logger = Logger();

  // Lưu trữ cache các dịch vụ đã discover theo deviceId
  final Map<String, List<BluetoothService>> _discoveredServicesCache = {};

  /// Lấy danh sách các dịch vụ GATT được hỗ trợ bởi thiết bị
  ///
  /// [deviceId] - Địa chỉ MAC hoặc ID của thiết bị BLE
  ///
  /// Trả về danh sách các dịch vụ nếu thiết bị được kết nối và đã khám phá dịch vụ
  /// Trả về null nếu thiết bị không tồn tại hoặc chưa kết nối
  Future<List<BluetoothService>?> getSupportedGattServices(
      String deviceId) async {
    try {
      // Kiểm tra xem đã có cache chưa
      if (_discoveredServicesCache.containsKey(deviceId)) {
        _logger.i('Sử dụng cache dịch vụ cho thiết bị: $deviceId');
        return _discoveredServicesCache[deviceId];
      }

      // Tìm thiết bị trong danh sách các thiết bị đã kết nối
      final List<BluetoothDevice> connectedDevices =
          await FlutterBluePlus.connectedDevices;

      // Tìm kiếm thiết bị theo ID
      BluetoothDevice? device;
      try {
        device = connectedDevices.firstWhere(
          (d) => d.remoteId.str == deviceId,
        );
      } catch (e) {
        _logger.w('Thiết bị không tồn tại hoặc chưa được kết nối: $deviceId');
        return null;
      }

      // Kiểm tra trạng thái kết nối của thiết bị
      final connectionState = await device.connectionState.first;
      if (connectionState != BluetoothConnectionState.connected) {
        _logger.w('Thiết bị không ở trạng thái kết nối: $deviceId');
        return null;
      }

      // Lấy danh sách dịch vụ đã được khám phá từ thiết bị
      final services = await device.discoverServices();

      // Lưu vào cache
      _discoveredServicesCache[deviceId] = services;

      // Log các dịch vụ tìm thấy
      if (services.isNotEmpty) {
        _logger
            .i('Tìm thấy ${services.length} dịch vụ trên thiết bị: $deviceId');
        for (final service in services) {
          _logger.d(
              'Service: ${service.uuid}, ${service.characteristics.length} characteristics');
        }
      } else {
        _logger.w('Không tìm thấy dịch vụ nào trên thiết bị: $deviceId');
      }

      return services;
    } catch (e) {
      _logger.e('Lỗi khi lấy danh sách dịch vụ: $e');
      return null;
    }
  }

  /// Xóa cache dịch vụ cho một thiết bị cụ thể
  void clearServiceCache(String deviceId) {
    if (_discoveredServicesCache.containsKey(deviceId)) {
      _discoveredServicesCache.remove(deviceId);
      _logger.d('Đã xóa cache dịch vụ cho thiết bị: $deviceId');
    }
  }

  /// Xóa toàn bộ cache dịch vụ
  void clearAllServiceCache() {
    _discoveredServicesCache.clear();
    _logger.d('Đã xóa toàn bộ cache dịch vụ');
  }

  /// Lấy thông tin chi tiết về một dịch vụ cụ thể
  ///
  /// [deviceId] - ID của thiết bị BLE
  /// [serviceUuid] - UUID của dịch vụ cần lấy thông tin
  Future<BluetoothService?> getServiceDetails(
      String deviceId, String serviceUuid) async {
    try {
      final services = await getSupportedGattServices(deviceId);
      if (services == null) return null;

      try {
        return services.firstWhere((s) => s.uuid.toString() == serviceUuid);
      } catch (e) {
        _logger.w(
            'Không tìm thấy dịch vụ với UUID: $serviceUuid trên thiết bị: $deviceId');
        return null;
      }
    } catch (e) {
      _logger.e('Lỗi khi lấy thông tin chi tiết dịch vụ: $e');
      return null;
    }
  }
}
