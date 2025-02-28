import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Light Control',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _isLightOn = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  String _connectionMethod = "None";
  String _connectionStatus = "Disconnected";
  String _ipAddress = "";
  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;

  // BLE UUIDs - must match the ESP32 ones
  final String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  final TextEditingController _ipController = TextEditingController();
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBluetoothState();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _disconnectBLE();
    WidgetsBinding.instance.removeObserver(this);
    _ipController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came to foreground
      _initBluetoothState();
    } else if (state == AppLifecycleState.paused) {
      // App went to background
      _statusTimer?.cancel();
    }
  }

  Future<void> _initBluetoothState() async {
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        // Bluetooth is on, ready to scan
      }
    });
  }

  // WiFi connection methods
  Future<void> _connectWiFi(String ip) async {
    if (ip.isEmpty) {
      _showSnackBar('Please enter a valid IP address');
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionStatus = "Connecting to WiFi...";
    });

    try {
      final response = await http
          .get(Uri.parse('http://$ip/status'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          _isConnected = true;
          _connectionMethod = "WiFi";
          _connectionStatus = "Connected via WiFi";
          _ipAddress = ip;
          _isLightOn = response.body.trim() == "ON";
        });

        // Start periodic status checks
        _startStatusTimer();

        _showSnackBar('Connected to ESP32 via WiFi');
      } else {
        setState(() {
          _isConnected = false;
          _connectionStatus = "Failed to connect (HTTP ${response.statusCode})";
        });
        _showSnackBar('Failed to connect to ESP32');
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _connectionStatus = "Connection error: $e";
      });
      _showSnackBar('Connection error: $e');
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_connectionMethod == "WiFi" && _isConnected) {
        _checkLightStatus();
      }
    });
  }

  Future<void> _checkLightStatus() async {
    if (_ipAddress.isEmpty) return;

    try {
      final response = await http
          .get(Uri.parse('http://$_ipAddress/status'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        setState(() {
          _isLightOn = response.body.trim() == "ON";
        });
      } else {
        // Status check failed
        setState(() {
          _isConnected = false;
          _connectionStatus = "Connection lost";
        });
        _statusTimer?.cancel();
      }
    } catch (e) {
      // Network error
      setState(() {
        _isConnected = false;
        _connectionStatus = "Connection lost";
      });
      _statusTimer?.cancel();
    }
  }

  Future<void> _toggleLight() async {
    if (!_isConnected) {
      _showSnackBar('Not connected to ESP32');
      return;
    }

    if (_connectionMethod == "WiFi") {
      try {
        final response = await http
            .get(
              Uri.parse('http://$_ipAddress/toggle'),
            )
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 || response.statusCode == 302) {
          await _checkLightStatus();
        }
      } catch (e) {
        _showSnackBar('Failed to toggle light: $e');
      }
    } else if (_connectionMethod == "BLE" && _characteristic != null) {
      try {
        final newState = !_isLightOn ? "ON" : "OFF";
        await _characteristic!.write(utf8.encode(newState));
        setState(() {
          _isLightOn = !_isLightOn;
        });
      } catch (e) {
        _showSnackBar('Failed to toggle light via BLE: $e');
      }
    }
  }

  // BLE connection methods
  Future<void> _scanAndConnectBLE() async {
    setState(() {
      _isConnecting = true;
      _connectionStatus = "Scanning for BLE devices...";
    });

    try {
      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      // Listen for scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          if (result.device.name == "ESP32_LIGHT_CONTROL") {
            FlutterBluePlus.stopScan();
            _connectToBLEDevice(result.device);
            break;
          }
        }
      });

      // Set a timeout to stop scanning
      Future.delayed(const Duration(seconds: 6), () {
        if (_connectionMethod != "BLE") {
          FlutterBluePlus.stopScan();
          setState(() {
            _isConnecting = false;
            _connectionStatus = "ESP32 device not found";
          });
          _showSnackBar('ESP32 device not found');
        }
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionStatus = "BLE scan error: $e";
      });
      _showSnackBar('BLE scan error: $e');
    }
  }

  Future<void> _connectToBLEDevice(BluetoothDevice device) async {
    setState(() {
      _connectionStatus = "Connecting to ${device.name}...";
    });

    try {
      // Connect to the device
      await device.connect();

      setState(() {
        _device = device;
        _connectionStatus =
            "Connected to ${device.name}, discovering services...";
      });

      // Discover services
      List<BluetoothService> services = await device.discoverServices();

      for (BluetoothService service in services) {
        if (service.uuid.toString().toUpperCase() ==
            SERVICE_UUID.toUpperCase()) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid.toString().toUpperCase() ==
                CHARACTERISTIC_UUID.toUpperCase()) {
              setState(() {
                _characteristic = characteristic;
                _isConnected = true;
                _connectionMethod = "BLE";
                _connectionStatus = "Connected via BLE";
              });

              // Read initial value
              List<int> value = await characteristic.read();
              String strValue = String.fromCharCodes(value);
              setState(() {
                _isLightOn = strValue == "ON";
              });

              // Subscribe to notifications
              await characteristic.setNotifyValue(true);
              characteristic.onValueReceived.listen((value) {
                String strValue = String.fromCharCodes(value);
                setState(() {
                  _isLightOn = strValue == "ON";
                });
              });

              _showSnackBar('Connected to ESP32 via BLE');
              break;
            }
          }
        }
      }

      if (_characteristic == null) {
        await device.disconnect();
        setState(() {
          _isConnecting = false;
          _connectionStatus = "Required service/characteristic not found";
        });
        _showSnackBar('Required BLE service not found on device');
      }
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionStatus = "BLE connection error: $e";
      });
      _showSnackBar('BLE connection error: $e');
    } finally {
      setState(() {
        _isConnecting = false;
      });
    }
  }

  Future<void> _disconnectBLE() async {
    if (_device != null && _connectionMethod == "BLE") {
      try {
        await _device!.disconnect();
      } catch (e) {
        // Ignore error
      } finally {
        setState(() {
          _device = null;
          _characteristic = null;
          _isConnected = false;
          _connectionMethod = "None";
          _connectionStatus = "Disconnected";
        });
      }
    }
  }

  void _disconnect() {
    if (_connectionMethod == "WiFi") {
      _statusTimer?.cancel();
      setState(() {
        _isConnected = false;
        _connectionMethod = "None";
        _connectionStatus = "Disconnected";
        _ipAddress = "";
      });
    } else if (_connectionMethod == "BLE") {
      _disconnectBLE();
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Light Control'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Status: $_connectionStatus',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    if (!_isConnected) ...[
                      // WiFi connection
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: TextField(
                          controller: _ipController,
                          decoration: const InputDecoration(
                            labelText: 'ESP32 IP Address',
                            border: OutlineInputBorder(),
                            hintText: '192.168.1.x',
                          ),
                          enabled: !_isConnecting,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isConnecting
                            ? null
                            : () => _connectWiFi(_ipController.text),
                        child: Text(_isConnecting
                            ? 'Connecting...'
                            : 'Connect via WiFi'),
                      ),
                      const SizedBox(height: 16),
                      // BLE connection
                      ElevatedButton(
                        onPressed: _isConnecting ? null : _scanAndConnectBLE,
                        child: Text(_isConnecting
                            ? 'Scanning...'
                            : 'Connect via Bluetooth'),
                      ),
                    ] else ...[
                      ElevatedButton(
                        onPressed: _disconnect,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Disconnect'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Light control section
            if (_isConnected) ...[
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: _toggleLight,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isLightOn ? Colors.yellow : Colors.grey,
                        boxShadow: [
                          if (_isLightOn)
                            const BoxShadow(
                              color: Colors.yellow,
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.lightbulb,
                          size: 100,
                          color: _isLightOn ? Colors.black54 : Colors.black26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Tap the bulb to toggle the light',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ] else ...[
              const Expanded(
                child: Center(
                  child: Text(
                    'Connect to an ESP32 device to control the light',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
