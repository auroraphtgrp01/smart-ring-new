import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'bluetooth/connect.dart';
import 'bluetooth/service_discovery.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'R12M 1DE1 Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyHomePage(title: 'R12M 1DE1 Scanner'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final String targetDeviceName = "R12M 1DE1";
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  BluetoothDevice? connectedDevice;
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;
  List<String> logs = [];
  List<BluetoothService> discoveredServices = [];
  ServiceDiscovery? serviceDiscovery;
  late BluetoothConnector bluetoothConnector;

  @override
  void initState() {
    super.initState();
    _initializeBluetoothConnector();
  }

  void _initializeBluetoothConnector() {
    bluetoothConnector = BluetoothConnector(
      targetDeviceName: targetDeviceName,
      onLog: (message) {
        Logger().d("DEBUG LOG: $message");
      },
      onScanResults: (results) => setState(() => scanResults = results),
      onScanningStateChanged: (scanning) =>
          setState(() => isScanning = scanning),
      onConnectionStateChanged: (state) =>
          setState(() => connectionState = state),
      onDeviceConnectionChanged: (device) =>
          setState(() => connectedDevice = device),
      onServicesDiscovered: (services) => setState(() {
        discoveredServices = services;
        if (bluetoothConnector.serviceDiscovery != null) {
          serviceDiscovery = bluetoothConnector.serviceDiscovery;
        }
      }),
      onDataReceived: (uuid, data) {
        setState(() => logs.add("Nhận dữ liệu từ $uuid: $data"));
      },
    )..initialize();
  }

  void _handleCharacteristicTap(String uuid) {
    bluetoothConnector.readCharacteristic(uuid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          ConnectionStatusBar(connectionState: connectionState),
          DeviceInfoBar(targetDeviceName: targetDeviceName),
          ScanButton(
            isScanning: isScanning,
            onPressed: bluetoothConnector.startScan,
          ),
          Expanded(
            child: connectedDevice != null
                ? _buildConnectedView()
                : DeviceList(
                    scanResults: scanResults,
                    connectedDevice: connectedDevice,
                    onConnect: bluetoothConnector.connectToDevice,
                    onDisconnect: bluetoothConnector.disconnectDevice,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedView() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: "DỊCH VỤ", icon: Icon(Icons.settings)),
              Tab(text: "LOGS", icon: Icon(Icons.list)),
            ],
            labelColor: Colors.blue,
          ),
          // Nút ngắt kết nối
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: bluetoothConnector.disconnectDevice,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text(
                'NGẮT KẾT NỐI',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
          // Thêm TabBarView để hiển thị nội dung các tab
          Expanded(
            child: TabBarView(
              children: [
                // Tab DỊCH VỤ - hiển thị danh sách services đã discover
                discoveredServices.isEmpty
                    ? const Center(
                        child: Text('Chưa tìm thấy dịch vụ nào',
                            style: TextStyle(fontSize: 16, color: Colors.grey)))
                    : ListView.builder(
                        itemCount: discoveredServices.length,
                        itemBuilder: (context, index) {
                          final service = discoveredServices[index];
                          return ServiceView(
                            service: service,
                            serviceDiscovery: serviceDiscovery,
                            onTap: _handleCharacteristicTap,
                          );
                        },
                      ),

                // Tab LOGS - hiển thị log
                LogView(logs: logs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    bluetoothConnector.dispose();
    super.dispose();
  }
}

class ConnectionStatusBar extends StatelessWidget {
  final BluetoothConnectionState connectionState;

  const ConnectionStatusBar({Key? key, required this.connectionState})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BluetoothConnector.getConnectionStateColor(connectionState),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          BluetoothConnector.getConnectionStateText(connectionState),
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class DeviceInfoBar extends StatelessWidget {
  final String targetDeviceName;

  const DeviceInfoBar({Key? key, required this.targetDeviceName})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Đang tìm thiết bị: $targetDeviceName',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class ScanButton extends StatelessWidget {
  final bool isScanning;
  final VoidCallback onPressed;

  const ScanButton(
      {Key? key, required this.isScanning, required this.onPressed})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          minimumSize: const Size(double.infinity, 50),
        ),
        child: Text(
          isScanning ? 'Dừng quét' : 'Quét thiết bị',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class DeviceList extends StatelessWidget {
  final List<ScanResult> scanResults;
  final BluetoothDevice? connectedDevice;
  final Function(BluetoothDevice) onConnect;
  final VoidCallback onDisconnect;

  const DeviceList({
    Key? key,
    required this.scanResults,
    required this.connectedDevice,
    required this.onConnect,
    required this.onDisconnect,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (scanResults.isEmpty) {
      return const Center(
        child: Text(
          'Chưa tìm thấy thiết bị R12M 1DE1',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: scanResults.length,
      itemBuilder: (context, index) {
        final result = scanResults[index];
        final isConnected =
            connectedDevice?.remoteId.str == result.device.remoteId.str;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: Colors.green.shade50,
          child: ListTile(
            title: Text(
              result.device.platformName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('ID: ${result.device.remoteId.str}'),
            trailing: ElevatedButton(
              onPressed:
                  isConnected ? onDisconnect : () => onConnect(result.device),
              style: ElevatedButton.styleFrom(
                backgroundColor: isConnected ? Colors.red : Colors.blue,
              ),
              child: Text(isConnected ? 'Ngắt kết nối' : 'Kết nối'),
            ),
            tileColor: isConnected ? Colors.blue.withOpacity(0.1) : null,
          ),
        );
      },
    );
  }
}

class LogView extends StatelessWidget {
  final List<String> logs;

  const LogView({Key? key, required this.logs}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có log nào',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: logs.length,
      reverse: true,
      itemBuilder: (context, index) {
        final logIndex = logs.length - 1 - index;
        return ListTile(
          dense: true,
          title: Text(
            logs[logIndex],
            style: const TextStyle(fontSize: 12),
          ),
        );
      },
    );
  }
}

class ServiceView extends StatelessWidget {
  final BluetoothService service;
  final ServiceDiscovery? serviceDiscovery;
  final Function(String) onTap;

  const ServiceView({
    Key? key,
    required this.service,
    required this.serviceDiscovery,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String serviceInfo =
        serviceDiscovery?.getServiceInfo(service) ?? service.uuid.toString();

    return ExpansionTile(
      title: Text(serviceInfo,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      children: service.characteristics.map((characteristic) {
        String charInfo =
            serviceDiscovery?.getCharacteristicInfo(characteristic) ??
                characteristic.uuid.toString();

        return ListTile(
          title: Text(charInfo),
          dense: true,
          onTap: () => onTap(characteristic.uuid.toString()),
        );
      }).toList(),
    );
  }
}
