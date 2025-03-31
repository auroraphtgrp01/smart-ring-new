import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:intl/intl.dart';

// Method channel để giao tiếp với mã native
const platform = MethodChannel('com.yucheng.smarthealthpro/ycbt');
const eventChannel = EventChannel('com.yucheng.smarthealthpro/ycbt_events');

// Enum cho các loại đo
enum MeasurementType {
  heartRate(1),
  bloodOxygen(2),
  bloodPressure(3),
  temperature(4);

  final int value;
  const MeasurementType(this.value);
}

// Model quản lý kết nối Bluetooth
class BluetoothDeviceModel with ChangeNotifier {
  bool _isConnected = false;
  String _deviceName = "";
  String _deviceAddress = "";
  String _connectionError = "";
  bool _isConnecting = false;

  bool get isConnected => _isConnected;
  String get deviceName => _deviceName;
  String get deviceAddress => _deviceAddress;
  String get connectionError => _connectionError;
  bool get isConnecting => _isConnecting;

  // Quét và kết nối thiết bị
  Future<void> scanAndConnect() async {
    try {
      _connectionError = "";
      _isConnecting = true;
      notifyListeners();

      final result = await platform.invokeMethod('scanDevice');

      if (result['status'] == 'connected') {
        _isConnected = true;
        _deviceName = result['deviceName'];
        _deviceAddress = result['deviceAddress'];
      }
    } on PlatformException catch (e) {
      _connectionError = "Lỗi kết nối: ${e.message}";
      print("Lỗi kết nối: ${e.message}");
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  // Kết nối thiết bị cuối cùng đã lưu
  Future<void> connectLastDevice() async {
    try {
      _connectionError = "";
      _isConnecting = true;
      notifyListeners();

      final result = await platform.invokeMethod('connectLastDevice');

      if (result['status'] == 'connected') {
        _isConnected = true;
        _deviceName = result['deviceName'];
        _deviceAddress = result['deviceAddress'];
      }
    } on PlatformException catch (e) {
      _connectionError = "Lỗi kết nối: ${e.message}";
      print("Lỗi kết nối: ${e.message}");
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  // Ngắt kết nối thiết bị
  Future<void> disconnect() async {
    try {
      await platform.invokeMethod('disconnectDevice');
      _isConnected = false;
      _deviceName = "";
      _deviceAddress = "";
    } on PlatformException catch (e) {
      print("Lỗi ngắt kết nối: ${e.message}");
    }
    notifyListeners();
  }

  // Kiểm tra trạng thái kết nối
  void startConnectionMonitoring() {
    Timer.periodic(Duration(seconds: 5), (timer) async {
      try {
        final connectionState =
            await platform.invokeMethod('getConnectionState');
        final bool wasConnected = _isConnected;
        _isConnected =
            connectionState == 10; // 10 = đã kết nối trong YCBTClient

        if (wasConnected != _isConnected) {
          notifyListeners();
        }
      } on PlatformException catch (e) {
        print("Lỗi kiểm tra kết nối: ${e.message}");
      }
    });
  }

  // Xử lý sự kiện thay đổi trạng thái kết nối
  void handleConnectionStateChange(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      if (!connected) {
        _deviceName = "";
        _deviceAddress = "";
      }
      notifyListeners();
    }
  }
}

// Model quản lý dữ liệu đo
class MeasurementModel with ChangeNotifier {
  int _spo2Value = 0;
  bool _isMeasuring = false;
  List<Map<String, dynamic>> _measurementHistory = [];
  String _measuringError = "";

  int get spo2Value => _spo2Value;
  bool get isMeasuring => _isMeasuring;
  List<Map<String, dynamic>> get measurementHistory => _measurementHistory;
  String get measuringError => _measuringError;

  // Bắt đầu đo
  Future<void> startMeasurement(MeasurementType type) async {
    if (_isMeasuring) return;

    try {
      _measuringError = "";
      final result = await platform.invokeMethod('startMeasurement', {
        'type': type.value,
      });

      if (result['status'] == 'started') {
        _isMeasuring = true;
        // Reset giá trị đọc được
        _spo2Value = 0;
        notifyListeners();
      }
    } on PlatformException catch (e) {
      _measuringError = "Lỗi bắt đầu đo: ${e.message}";
      print("Lỗi bắt đầu đo: $e");
      notifyListeners();
    }
  }

  // Dừng đo
  Future<void> stopMeasurement(MeasurementType type) async {
    if (!_isMeasuring) return;

    try {
      await platform.invokeMethod('stopMeasurement', {
        'type': type.value,
      });
      _isMeasuring = false;
      notifyListeners();
    } on PlatformException catch (e) {
      _measuringError = "Lỗi dừng đo: ${e.message}";
      print("Lỗi dừng đo: $e");
      _isMeasuring = false;
      notifyListeners();
    }
  }

  // Cập nhật giá trị SpO2
  void updateSpo2Value(int value) {
    if (value >= 70 && value <= 100) {
      // Khoảng SpO2 hợp lệ
      _spo2Value = value;
      notifyListeners();
    }
  }

  // Lấy lịch sử đo
  Future<void> fetchMeasurementHistory() async {
    try {
      final result = await platform.invokeMethod('getMeasurementHistory', {
        'type': MeasurementType.bloodOxygen.value,
      });

      _measurementHistory = List<Map<String, dynamic>>.from(result['history']);
      notifyListeners();
    } on PlatformException catch (e) {
      print("Lỗi lấy lịch sử: $e");
    }
  }

  // Xử lý sự kiện hoàn thành đo
  void handleMeasurementComplete(int type, bool success) {
    if (type == MeasurementType.bloodOxygen.value) {
      _isMeasuring = false;

      if (success) {
        // Thêm kết quả hiện tại vào lịch sử nếu có giá trị hợp lệ
        if (_spo2Value > 0) {
          _measurementHistory.add({
            'value': _spo2Value,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
        fetchMeasurementHistory();
      } else {
        _measuringError = "Đo không thành công, vui lòng thử lại";
      }

      notifyListeners();
    }
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final bluetoothModel = BluetoothDeviceModel();
  final measurementModel = MeasurementModel();

  // Thiết lập lắng nghe event channel
  eventChannel.receiveBroadcastStream().listen((event) {
    final Map<String, dynamic> eventData = Map<String, dynamic>.from(event);
    final String method = eventData['method'];
    final Map<String, dynamic> arguments =
        Map<String, dynamic>.from(eventData['arguments']);

    switch (method) {
      case 'onRealTimeData':
        if (arguments['dataType'] == 1538) {
          // Mã dữ liệu SPO2
          final int spo2Value = arguments['bloodOxygenValue'];
          measurementModel.updateSpo2Value(spo2Value);
        }
        break;

      case 'onMeasurementComplete':
        final int type = arguments['type'];
        final bool success = arguments['success'];
        measurementModel.handleMeasurementComplete(type, success);
        break;

      case 'onConnectionStateChanged':
        final bool connected = arguments['connected'];
        bluetoothModel.handleConnectionStateChange(connected);
        break;
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bluetoothModel),
        ChangeNotifierProvider.value(value: measurementModel),
      ],
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Bắt đầu giám sát kết nối
    Provider.of<BluetoothDeviceModel>(context, listen: false)
        .startConnectionMonitoring();

    return MaterialApp(
      title: 'Smart Health Pro',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Smart Health Pro'),
      ),
      body: Consumer<BluetoothDeviceModel>(
        builder: (context, deviceModel, child) {
          if (deviceModel.isConnecting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text('Đang kết nối thiết bị...'),
                ],
              ),
            );
          }

          return deviceModel.isConnected ? ConnectedView() : NotConnectedView();
        },
      ),
    );
  }
}

class NotConnectedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final deviceModel = Provider.of<BluetoothDeviceModel>(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bluetooth_disabled,
            size: 80,
            color: Colors.grey,
          ),
          SizedBox(height: 20),
          Text(
            'Chưa kết nối với thiết bị',
            style: TextStyle(fontSize: 18),
          ),
          SizedBox(height: 10),
          if (deviceModel.connectionError.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                deviceModel.connectionError,
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => deviceModel.scanAndConnect(),
            child: Text('Quét và kết nối thiết bị'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => deviceModel.connectLastDevice(),
            child: Text('Kết nối thiết bị đã lưu'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final deviceModel = Provider.of<BluetoothDeviceModel>(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bluetooth_connected,
            size: 80,
            color: Colors.blue,
          ),
          SizedBox(height: 20),
          Text(
            'Đã kết nối với: ${deviceModel.deviceName}',
            style: TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          Text(
            'ID: ${deviceModel.deviceAddress}',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => deviceModel.disconnect(),
            child: Text('Ngắt kết nối'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MeasurementScreen(),
                ),
              );
            },
            child: Text('Bắt đầu đo SpO2'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              backgroundColor: Colors.green,
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => HistoryScreen(),
                ),
              );
            },
            child: Text('Xem lịch sử'),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              backgroundColor: Colors.purple,
            ),
          ),
        ],
      ),
    );
  }
}

class MeasurementScreen extends StatefulWidget {
  @override
  _MeasurementScreenState createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat();

    // Bắt đầu đo SpO2
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MeasurementModel>(context, listen: false)
          .startMeasurement(MeasurementType.bloodOxygen);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    // Dừng đo SpO2 khi rời khỏi màn hình
    Provider.of<MeasurementModel>(context, listen: false)
        .stopMeasurement(MeasurementType.bloodOxygen);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Đo SpO2'),
      ),
      body: Consumer<MeasurementModel>(
        builder: (context, measurementModel, child) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'SpO2',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 20),
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.withOpacity(0.1),
                  ),
                  child: Center(
                    child: measurementModel.isMeasuring
                        ? RotationTransition(
                            turns: _animationController,
                            child: CircleAvatar(
                              radius: 80,
                              backgroundColor: Colors.transparent,
                              child: Icon(
                                Icons.favorite,
                                size: 80,
                                color: Colors.red,
                              ),
                            ),
                          )
                        : Text(
                            measurementModel.spo2Value > 0
                                ? '${measurementModel.spo2Value}%'
                                : '-- %',
                            style: TextStyle(
                              fontSize: 60,
                              fontWeight: FontWeight.bold,
                              color: _getSpo2Color(measurementModel.spo2Value),
                            ),
                          ),
                  ),
                ),
                SizedBox(height: 20),

                // Hiển thị lỗi đo nếu có
                if (measurementModel.measuringError.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      measurementModel.measuringError,
                      style: TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),

                SizedBox(height: 20),
                Text(
                  measurementModel.isMeasuring
                      ? 'Đang đo... Vui lòng giữ ngón tay cố định'
                      : _getSpo2Message(measurementModel.spo2Value),
                  style: TextStyle(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () {
                    if (measurementModel.isMeasuring) {
                      measurementModel
                          .stopMeasurement(MeasurementType.bloodOxygen);
                      _animationController.stop();
                    } else {
                      measurementModel
                          .startMeasurement(MeasurementType.bloodOxygen);
                      _animationController.repeat();
                    }
                  },
                  child: Text(
                      measurementModel.isMeasuring ? 'Dừng đo' : 'Bắt đầu lại'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    backgroundColor: measurementModel.isMeasuring
                        ? Colors.red
                        : Colors.green,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _getSpo2Color(int value) {
    if (value == 0) return Colors.grey;
    if (value >= 95) return Colors.green;
    if (value >= 90) return Colors.orange;
    return Colors.red;
  }

  String _getSpo2Message(int value) {
    if (value == 0) return "Nhấn Bắt đầu để đo";
    if (value >= 95) return "Mức SpO2 bình thường";
    if (value >= 90) return "Mức SpO2 hơi thấp";
    if (value >= 70) return "Mức SpO2 thấp - Hãy tham khảo ý kiến bác sĩ";
    return "Nhấn Bắt đầu để đo";
  }
}

class HistoryScreen extends StatefulWidget {
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Lấy lịch sử đo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MeasurementModel>(context, listen: false)
          .fetchMeasurementHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Lịch sử đo'),
      ),
      body: Consumer<MeasurementModel>(
        builder: (context, measurementModel, child) {
          if (measurementModel.measurementHistory.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text(
                    'Không có lịch sử đo nào',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: measurementModel.measurementHistory.length,
            itemBuilder: (context, index) {
              final item = measurementModel.measurementHistory[index];
              final DateTime timestamp =
                  DateTime.fromMillisecondsSinceEpoch(item['timestamp']);
              final String dateStr =
                  DateFormat('yyyy-MM-dd HH:mm').format(timestamp);

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getSpo2Color(item['value']),
                    child: Text(
                      '${item['value']}%',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text('Kết quả đo SpO2'),
                  subtitle: Text(dateStr),
                  trailing: Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    // Hiển thị chi tiết
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Chi tiết kết quả'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ngày: $dateStr'),
                            SizedBox(height: 8),
                            Text('Chỉ số SpO2: ${item['value']}%'),
                            SizedBox(height: 8),
                            Text(
                                'Trạng thái: ${_getSpo2StatusText(item['value'])}'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('Đóng'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getSpo2Color(int value) {
    if (value >= 95) return Colors.green;
    if (value >= 90) return Colors.orange;
    return Colors.red;
  }

  String _getSpo2StatusText(int value) {
    if (value >= 95) return "Bình thường";
    if (value >= 90) return "Hơi thấp";
    return "Thấp - Cần tham khảo ý kiến bác sĩ";
  }
}
