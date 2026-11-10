import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/aooog_ble.dart';
import 'services/aooog_manager.dart';
import 'services/tank_geometry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FuelMasterApp());
}

class FuelMasterApp extends StatelessWidget {
  const FuelMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuel Master Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        primaryColor: const Color(0xFF0B1329),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0B1329),
          secondary: Color(0xFFD97706),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1329),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const FuelMasterHomePage(),
    );
  }
}

class FuelMasterHomePage extends StatefulWidget {
  const FuelMasterHomePage({super.key});

  @override
  State<FuelMasterHomePage> createState() => _FuelMasterHomePageState();
}

class _FuelMasterHomePageState extends State<FuelMasterHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // BLE State
  final AoooGManager _bleManager = AoooGManager();
  bool _isScanning = false;
  final List<AoooGSensor> _discoveredSensors = [];
  AoooGSensor? _selectedSensor;
  bool _isConnected = false;

  // Telemetría en vivo
  double _liveFuelLiters = 0.0;
  double _liveFrequency = 13250.0;
  double _liveTemperature = 20.0;
  double _liveBattery = 100.0;
  int _outputMode = 0; // 0=%, 1=mm, 2=litros
  int _broadcastInterval = 5; // segundos
  Timer? _telemetryTimer;

  // Medidas Generales del Estanque Base (Rectangular Vikar)
  double _length = 850;
  double _width = 600;
  double _height = 650;
  double _thickness = 2.5;
  bool _isExternal = true;

  // Radios en Bordes Inferiores / Piso (mm)
  double _rInfLi = 150; // L. Izq
  double _rInfLd = 150; // L. Der
  double _rInfAf = 150; // A. Front
  double _rInfAp = 150; // A. Post

  // Radios en Bordes Superiores / Techo (mm)
  double _rSupLi = 50;  // L. Izq
  double _rSupLd = 50;  // L. Der
  double _rSupAf = 50;  // A. Front
  double _rSupAp = 50;  // A. Post

  // Radio aristas verticales
  double _rVert = 50;

  // Nivel de líquido actual simulado / calibrado
  double _currentLiquidMm = 260;

  // Calibración Sensor AoooG
  double _emptyFreq = 15000;
  double _fullFreq = 10000;
  String _authPin = '12345678';

  // Progreso de subida
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _bleManager.disconnect();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _startBleScan() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    setState(() {
      _isScanning = true;
      _discoveredSensors.clear();
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final sensor = AoooGProtocol.parseAdvertisement(r);
        if (sensor != null) {
          int existing = _discoveredSensors.indexWhere((s) => s.id == sensor.id);
          if (existing >= 0) {
            _discoveredSensors[existing] = sensor;
          } else {
            _discoveredSensors.add(sensor);
          }
          if (mounted) setState(() {});
        }
      }
    });

    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  Future<void> _connectToSensor(AoooGSensor sensor) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF0B1329))),
    );

    bool ok = await _bleManager.connect(sensor);
    if (!mounted) return;
    Navigator.pop(context);

    if (ok) {
      setState(() {
        _selectedSensor = sensor;
        _isConnected = true;
        _liveFrequency = sensor.frequency > 0 ? sensor.frequency : _liveFrequency;
        _liveTemperature = sensor.temperature.toDouble();
        _liveBattery = sensor.battery.toDouble();
        _liveFuelLiters = sensor.output;
      });

      // Leer parámetros (comando 0x0D), intervalo (0x05) y modo salida (0x1A)
      final params = await _bleManager.readParameters();
      if (params != null) {
        setState(() {
          if (params['emptyFreq']! > 0) _emptyFreq = params['emptyFreq']!;
          if (params['fullFreq']! > 0) _fullFreq = params['fullFreq']!;
        });
      }

      final outMode = await _bleManager.readOutputMode();
      if (outMode != null) setState(() => _outputMode = outMode);

      final interval = await _bleManager.readBroadcastInterval();
      if (interval != null) setState(() => _broadcastInterval = interval);

      // Iniciar sondeo de telemetría en vivo cada 3 segundos
      _telemetryTimer?.cancel();
      _telemetryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (!_isConnected || _isUploading) return;
        final data = await _bleManager.readRealtimeData();
        if (data != null && mounted) {
          setState(() {
            _liveFrequency = data.frequencyHz;
            _liveTemperature = data.temperatureC;
            _liveBattery = data.batteryPct;
            _liveFuelLiters = data.fuelOutput;
          });
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conectado con éxito a Sensor #${sensor.id}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar al sensor BLE')),
      );
    }
  }

  Future<void> _disconnectSensor() async {
    _telemetryTimer?.cancel();
    await _bleManager.disconnect();
    setState(() {
      _isConnected = false;
      _selectedSensor = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sensor desconectado')),
    );
  }

  double _calculateTotalVolume() {
    double t = _isExternal ? _thickness : 0.0;
    double effH = _height - 2 * t;
    if (effH <= 0) return 0.0;
    return TankGeometryEngine.calculateVolumeAtHeight(
      tankType: 'rectangular',
      length: _length,
      width: _width,
      height: _height,
      thickness: _thickness,
      isExternal: _isExternal,
      hMm: effH,
      rInfLi: _rInfLi,
      rInfLd: _rInfLd,
      rSupLi: _rSupLi,
      rSupLd: _rSupLd,
      rInfAf: _rInfAf,
      rInfAp: _rInfAp,
      rSupAf: _rSupAf,
      rSupAp: _rSupAp,
      rVert: _rVert,
    );
  }

  double _calculateVolumeAt(double h) {
    return TankGeometryEngine.calculateVolumeAtHeight(
      tankType: 'rectangular',
      length: _length,
      width: _width,
      height: _height,
      thickness: _thickness,
      isExternal: _isExternal,
      hMm: h,
      rInfLi: _rInfLi,
      rInfLd: _rInfLd,
      rSupLi: _rSupLi,
      rSupLd: _rSupLd,
      rInfAf: _rInfAf,
      rInfAp: _rInfAp,
      rSupAf: _rSupAf,
      rSupAp: _rSupAp,
      rVert: _rVert,
    );
  }

  List<CalibrationRow> _generateCalibrationTable() {
    List<CalibrationRow> list = [];
    int totalRows = 30;

    double t = _isExternal ? _thickness : 0.0;
    double effH = _height - 2 * t;

    for (int i = 0; i < totalRows; i++) {
      double frac = i / (totalRows - 1);
      double level = frac * effH;
      double vol = _calculateVolumeAt(level);

      int fixVal = (frac * 5000).round();
      double expectedF = TankGeometryEngine.fixValueToFrequency(
        fixValue: fixVal.toDouble(),
        emptyFreqHz: _emptyFreq,
        fullFreqHz: _fullFreq,
      );

      list.add(CalibrationRow(
        index: i,
        volumeL: vol,
        levelMm: level.round(),
        fixValue: fixVal,
        expectedFreqHz: expectedF,
      ));
    }
    return list;
  }

  Future<void> _uploadCalibrationToSensor() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero conecta un sensor BLE en la pestaña Sensores')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    // Pausar telemetría mientras se programa el sensor
    _telemetryTimer?.cancel();

    // 1. Autenticar PIN (prueba el PIN ingresado, PIN de fábrica 12345678, y alternativas)
    bool authOk = await _bleManager.authenticate(_authPin);
    if (!authOk) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sensor no aceptó PIN "$_authPin". Verifica la contraseña o usa 12345678.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // 2. Subir tabla de 30 puntos por bloques (0x16)
    final rows = _generateCalibrationTable();
    bool uploadOk = await _bleManager.uploadCalibrationTable(
      rows,
      onProgress: (cur, tot) {
        if (!mounted) return;
        setState(() => _uploadProgress = cur / tot);
      },
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (uploadOk) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('¡Calibración Grabada!'),
          content: Text('Se grabó la tabla de 30 puntos en el Sensor #${_selectedSensor?.id}.\nSalida configurada en Litros directos.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar')),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Error al transferir la tabla de calibración.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fuel Master Pro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Text(
              _isConnected ? 'Conectado: #${_selectedSensor?.id}' : 'AoooG BLE Suite',
              style: TextStyle(fontSize: 11, color: _isConnected ? const Color(0xFF34D399) : Colors.white60),
            ),
          ],
        ),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.link_off, color: Colors.redAccent),
              tooltip: 'Desconectar Sensor',
              onPressed: _disconnectSensor,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD97706),
          indicatorWeight: 3,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'Sensores'),
            Tab(icon: Icon(Icons.speed), text: 'Monitor'),
            Tab(icon: Icon(Icons.straighten), text: 'Estanque'),
            Tab(icon: Icon(Icons.settings), text: 'Configuración'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSensorsTab(),
          _buildMonitorTab(),
          _buildTankTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  // ==========================================================================
  // PESTAÑA 1: SENSORES BLE (ESCÁNER & CONEXIÓN)
  // ==========================================================================
  Widget _buildSensorsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isConnected ? 'Sensor activo: #${_selectedSensor?.id}' : 'Busca dispositivos AoooG cercanos',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _isConnected ? const Color(0xFF059669) : Colors.black87,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startBleScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B1329),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                icon: _isScanning
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.refresh, size: 18),
                label: Text(_isScanning ? 'Buscando...' : 'Escanear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _discoveredSensors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        _isScanning ? 'Detectando sensores AoooG AG-BFLS...' : 'Presiona Escanear para listar sensores',
                        style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _discoveredSensors.length,
                  itemBuilder: (context, idx) {
                    final s = _discoveredSensors[idx];
                    final isSel = _selectedSensor?.id == s.id && _isConnected;
                    return Card(
                      elevation: isSel ? 3 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: isSel ? const Color(0xFF059669) : Colors.transparent, width: 1.5),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSel ? const Color(0xFF059669) : const Color(0xFF0B1329),
                          child: const Icon(Icons.sensors, color: Colors.white, size: 20),
                        ),
                        title: Text('Sensor AoooG #${s.id}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        subtitle: Text(
                          '${s.frequency.toStringAsFixed(0)} Hz • ${s.temperature}°C • Bat: ${s.battery}% • RSSI: ${s.rssi} dBm',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        trailing: ElevatedButton(
                          onPressed: isSel ? _disconnectSensor : () => _connectToSensor(s),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSel ? Colors.red.shade700 : const Color(0xFF0B1329),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(isSel ? 'Desconectar' : 'Conectar'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================================================
  // PESTAÑA 2: MONITOR DE DISPOSITIVO (IDÉNTICO A APP OFICIAL + ESTANQUE)
  // ==========================================================================
  Widget _buildMonitorTab() {
    double totalCapacity = _calculateTotalVolume();
    double fillFraction = totalCapacity > 0 ? (_liveFuelLiters / totalCapacity).clamp(0.0, 1.0) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Tarjeta de Combustible en Vivo con Medidor Visual
          Card(
            color: const Color(0xFF0B1329),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('VOLUMEN EN ESTANQUE', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                          const SizedBox(height: 4),
                          Text('${_liveFuelLiters.toStringAsFixed(1)} L', style: const TextStyle(color: Color(0xFFD97706), fontSize: 32, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)),
                        child: Text('${(fillFraction * 100).toStringAsFixed(1)} %', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Barra de Nivel Gráfica con Silueta
                  Stack(
                    children: [
                      Container(
                        height: 22,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(11)),
                      ),
                      FractionallySizedBox(
                        widthFactor: fillFraction > 0 ? fillFraction : 0.02,
                        child: Container(
                          height: 22,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFB45309), Color(0xFFF59E0B)]),
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Vacío: 0 L', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                      Text('Capacidad Total: ${totalCapacity.toStringAsFixed(1)} L', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Métricas de Telemetría AoooG en Vivo (Grid)
          Row(
            children: [
              Expanded(child: _buildMetricTile('Frecuencia Hz', '${_liveFrequency.toStringAsFixed(0)} Hz', Icons.waves, const Color(0xFF2563EB))),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Temperatura', '${_liveTemperature.toStringAsFixed(0)} °C', Icons.thermostat, const Color(0xFF059669))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildMetricTile('Batería', '${_liveBattery.toStringAsFixed(0)} %', Icons.battery_charging_full, const Color(0xFF7C3AED))),
              const SizedBox(width: 8),
              Expanded(child: _buildMetricTile('Salida Reportada', _outputMode == 2 ? '${_liveFuelLiters.toStringAsFixed(1)} L' : (_outputMode == 1 ? '${_liveFuelLiters.toInt()} mm' : '${_liveFuelLiters.toStringAsFixed(0)} pts'), Icons.tune, const Color(0xFFD97706))),
            ],
          ),
          const SizedBox(height: 12),

          // Controles Rápidos de Calibración de Campo (Vacío / Lleno)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Calibración Rápida de Campo (Botones Físicos AoooG)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                           onPressed: !_isConnected ? null : () async {
                            bool ok = await _bleManager.setEmptyPoint();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? 'Punto VACÍO grabado en sensor' : 'Error al grabar vacío')),
                            );
                          },
                          icon: const Icon(Icons.arrow_downward, color: Color(0xFF2563EB)),
                          label: const Text('Fijar Vacío (10)'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: !_isConnected ? null : () async {
                            bool ok = await _bleManager.setFullPoint();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? 'Punto LLENO grabado en sensor' : 'Error al grabar lleno')),
                            );
                          },
                          icon: const Icon(Icons.arrow_upward, color: Color(0xFFD97706)),
                          label: const Text('Fijar Lleno (11)'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String title, String val, IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(radius: 18, backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                  Text(val, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0B1329))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // PESTAÑA 3: ESTANQUE (SIMPLIFICADO Y LIMPIO: DIMENSIONES + RADIOS + CÁLCULO)
  // ==========================================================================
  Widget _buildTankTab() {
    double totalVol = _calculateTotalVolume();
    double currentVol = _calculateVolumeAt(_currentLiquidMm);
    double emptyVol = (totalVol - currentVol).clamp(0.0, totalVol);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tarjeta: Dimensiones Generales (mm)
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.blue.shade100, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Dimensiones Generales (mm)', style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('Largo (mm)', _length, (v) => setState(() => _length = v))),
                      const SizedBox(width: 10),
                      Expanded(child: _buildNumField('Ancho (mm)', _width, (v) => setState(() => _width = v))),
                      const SizedBox(width: 10),
                      Expanded(child: _buildNumField('Alto (mm)', _height, (v) => setState(() => _height = v))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('Espesor Chapa (mm)', _thickness, (v) => setState(() => _thickness = v))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<bool>(
                          value: _isExternal,
                          decoration: const InputDecoration(labelText: 'Medición', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                          items: const [
                            DropdownMenuItem(value: true, child: Text('Externa')),
                            DropdownMenuItem(value: false, child: Text('Interna')),
                          ],
                          onChanged: (v) => setState(() => _isExternal = v!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tarjeta: Radios en Bordes Inferiores / Piso (mm)
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.blue.shade100, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RADIOS EN BORDES INFERIORES / PISO (MM)', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('L. Izq.', _rInfLi, (v) => setState(() => _rInfLi = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('L. Der.', _rInfLd, (v) => setState(() => _rInfLd = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('A. Front.', _rInfAf, (v) => setState(() => _rInfAf = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('A. Post.', _rInfAp, (v) => setState(() => _rInfAp = v))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tarjeta: Radios en Bordes Superiores / Techo (mm)
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.blue.shade100, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RADIOS EN BORDES SUPERIORES / TECHO (MM)', style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('L. Izq.', _rSupLi, (v) => setState(() => _rSupLi = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('L. Der.', _rSupLd, (v) => setState(() => _rSupLd = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('A. Front.', _rSupAf, (v) => setState(() => _rSupAf = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('A. Post.', _rSupAp, (v) => setState(() => _rSupAp = v))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('Aristas Verticales (L×W)', _rVert, (v) => setState(() => _rVert = v))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tarjeta: Nivel de Líquido y Resumen Volumétrico
          Card(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.blue.shade100, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nivel de Líquido', style: TextStyle(color: Color(0xFF1E3A8A), fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumField(
                          'Altura del Combustible Actual (mm)',
                          _currentLiquidMm,
                          (v) => setState(() => _currentLiquidMm = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Volumen Total
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Column(
                            children: [
                              Text('Volumen Total', style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('${totalVol.toStringAsFixed(1)} L', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Líquido Actual
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Column(
                            children: [
                              Text('Líquido Actual', style: TextStyle(fontSize: 11, color: Colors.green.shade900, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('${currentVol.toStringAsFixed(1)} L', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Espacio Vacío
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Column(
                            children: [
                              Text('Espacio Vacío', style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text('${emptyVol.toStringAsFixed(1)} L', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // PESTAÑA 4: CONFIGURACIÓN AVANZADA & CARGA DE TABLA AL SENSOR
  // ==========================================================================
  Widget _buildSettingsTab() {
    final rows = _generateCalibrationTable();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Autenticación PIN AoooG
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Seguridad y PIN del Sensor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: _authPin,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña de Acceso (PIN de fábrica: 12345678)',
                      border: OutlineInputBorder(),
                      helperText: 'Requerido por protocolo AoooG para grabar calibración',
                    ),
                    onChanged: (v) => _authPin = v,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Puntos Frecuencia Extremos
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Puntos Extremos de Frecuencia AoooG (Hz)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('Frecuencia Vacío Hz', _emptyFreq, (v) => setState(() => _emptyFreq = v))),
                      const SizedBox(width: 10),
                      Expanded(child: _buildNumField('Frecuencia Lleno Hz', _fullFreq, (v) => setState(() => _fullFreq = v))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Parámetros de Transmisión BLE
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Parámetros de Transmisión y Salida', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _outputMode,
                          decoration: const InputDecoration(labelText: 'Tipo de Salida', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Normalizado (0-100%)')),
                            DropdownMenuItem(value: 1, child: Text('Milímetros (mm)')),
                            DropdownMenuItem(value: 2, child: Text('Litros (L)')),
                          ],
                          onChanged: !_isConnected ? null : (v) async {
                            if (v != null) {
                              setState(() => _outputMode = v);
                              await _bleManager.setOutputMode(v);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _broadcastInterval,
                          decoration: const InputDecoration(labelText: 'Intervalo BLE', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 segundo')),
                            DropdownMenuItem(value: 5, child: Text('5 segundos')),
                            DropdownMenuItem(value: 10, child: Text('10 segundos')),
                            DropdownMenuItem(value: 20, child: Text('20 segundos')),
                          ],
                          onChanged: !_isConnected ? null : (v) async {
                            if (v != null) {
                              setState(() => _broadcastInterval = v);
                              await _bleManager.setBroadcastInterval(v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: !_isConnected ? null : () async {
                      bool ok = await _bleManager.restartSensor();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(ok ? 'Sensor reiniciado' : 'Error al reiniciar sensor')),
                      );
                    },
                    icon: const Icon(Icons.restart_alt, color: Colors.red),
                    label: const Text('Reiniciar Sensor AoooG (Comando 01)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Botón Carga de Calibración
          if (_isUploading)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _uploadProgress, color: const Color(0xFFD97706)),
                  const SizedBox(height: 6),
                  Text('Grabando bloques de calibración... (${(_uploadProgress * 100).toInt()}%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadCalibrationToSensor,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B1329),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: const Icon(Icons.cloud_upload),
            label: Text(_isUploading ? 'Grabando...' : 'Cargar Tabla al Sensor AoooG (${rows.length} Puntos)'),
          ),
        ],
      ),
    );
  }

  Widget _buildNumField(String label, double val, Function(double) onChanged) {
    return TextFormField(
      initialValue: val % 1 == 0 ? val.toInt().toString() : val.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onChanged: (v) {
        double? d = double.tryParse(v);
        if (d != null) onChanged(d);
      },
    );
  }
}
