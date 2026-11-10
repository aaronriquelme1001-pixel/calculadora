import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/aooog_ble.dart';
import 'services/tank_geometry.dart';
import 'services/aooog_manager.dart';

void main() {
  runApp(const FuelMasterApp());
}

class FuelMasterApp extends StatelessWidget {
  const FuelMasterApp({super.key});

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(_scanSubscription?.cancel());
    unawaited(_sensorConnectionSubscription?.cancel());
    unawaited(FlutterBluePlus.stopScan());
    unawaited(_bleManager.disconnect());
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuel Master Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0B1329),
          secondary: Color(0xFFD97706),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B1329),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          toolbarHeight: 64,
          titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFFF8FAFC),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFFD97706), width: 1.6),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(48, 44)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
            elevation: WidgetStatePropertyAll(0),
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // BLE State
  final AoooGManager _bleManager = AoooGManager();
  bool _isScanning = false;
  final List<AoooGSensor> _discoveredSensors = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _scanTimer;
  StreamSubscription<BluetoothConnectionState>? _sensorConnectionSubscription;
  AoooGSensor? _selectedSensor;
  bool _isConnected = false;

  // Medidas del estanque
  String _tankType = 'rectangular';
  double _length = 850;
  double _width = 600;
  double _height = 650;
  double _thickness = 2.5;
  bool _isExternal = true;
  String _cylHead = 'flat';
  double _tank2Length = 850;
  double _tank2Width = 600;
  double _tank2Height = 650;
  double _stepWidth = 200;
  double _stepHeight = 250;
  String _stepSide = 'bottom_right';
  double _dRBottomFront = 200;
  double _dRTopFront = 100;
  double _dRBackCorners = 40;

  // Radios esquinas
  double _rInfLi = 150;
  double _rInfLd = 150;
  double _rSupLi = 50;
  double _rSupLd = 50;
  double _rInfAf = 150;
  double _rInfAp = 150;
  double _rSupAf = 50;
  double _rSupAp = 50;
  double _rVert = 50;

  // Calibración Sensor AoooG
  double _emptyFreq = 15000;
  double _fullFreq = 10000;
  double _curFreq = 13250;
  String _authPin = '';

  // Progreso de subida
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  Future<void> _startBleScan() async {
    await _scanSubscription?.cancel();
    _scanTimer?.cancel();

    final permissionResults = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    final denied = permissionResults.entries.any((entry) => !entry.value.isGranted);
    if (denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes conceder los permisos Bluetooth para buscar sensores.')),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _discoveredSensors.clear();
    });

    try {
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {

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
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));
      _scanTimer = Timer(const Duration(seconds: 7), () async {
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
        await _scanSubscription?.cancel();
        _scanSubscription = null;
        if (mounted) setState(() => _isScanning = false);
      });
    } catch (error) {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar el escaneo BLE: $error')),
        );
      }
    }
  }

  Future<void> _connectToSensor(AoooGSensor sensor) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Color(0xFF0B1329))),
    );

    final ok = await _bleManager.connect(sensor);
    if (!mounted) {
      await _bleManager.disconnect();
      return;
    }
    Navigator.pop(context);

    if (ok) {
      await _sensorConnectionSubscription?.cancel();
      _sensorConnectionSubscription = sensor.device.connectionState.listen((connectionState) {
        if (connectionState == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _isConnected = false;
            _selectedSensor = null;
          });
        }
      });
      setState(() {
        _selectedSensor = sensor;
        _isConnected = true;
        _curFreq = sensor.frequency > 0 ? sensor.frequency : _curFreq;
        _emptyFreq = sensor.emptyFreq > 0 ? sensor.emptyFreq : _emptyFreq;
      });

      // Leer parámetros del sensor (Comando 0x0D)
      final params = await _bleManager.readParameters();
      if (!mounted) return;
      if (params != null) {
        setState(() {
          if (params['emptyFreq']! > 0) _emptyFreq = params['emptyFreq']!;
          if (params['fullFreq']! > 0) _fullFreq = params['fullFreq']!;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conectado con éxito a Sensor #${sensor.id}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar al sensor BLE')),
      );
    }
  }

  List<CalibrationRow> _generateCalibrationTable() {
    List<CalibrationRow> list = [];
    int totalRows = 30; // Fila 1 a 30

    double t = _isExternal ? _thickness : 0.0;
    final primaryEffH = _height - 2 * t;
    final secondaryEffH = _tank2Height > 0 ? _tank2Height - 2 * t : primaryEffH;
    final double effH = (_tankType == 'double_tank'
        ? math.max(primaryEffH, secondaryEffH)
        : primaryEffH).toDouble();

    for (int i = 0; i < totalRows; i++) {
      double frac = i / (totalRows - 1);
      double level = frac * effH;
      double vol = TankGeometryEngine.calculateVolumeAtHeight(
        tankType: _tankType,
        length: _length,
        width: _width,
        height: _height,
        thickness: _thickness,
        isExternal: _isExternal,
        hMm: level,
        rInfLi: _rInfLi,
        rInfLd: _rInfLd,
        rSupLi: _rSupLi,
        rSupLd: _rSupLd,
        rInfAf: _rInfAf,
        rInfAp: _rInfAp,
        rSupAf: _rSupAf,
        rSupAp: _rSupAp,
        rVert: _rVert,
        tank2Length: _tank2Length,
        tank2Width: _tank2Width,
        tank2Height: _tank2Height,
        cylHead: _cylHead,
        stepWidth: _stepWidth,
        stepHeight: _stepHeight,
        stepSide: _stepSide,
        dRBottomFront: _dRBottomFront,
        dRTopFront: _dRTopFront,
        dRBackCorners: _dRBackCorners,
      );

      // Coordenada fix_value de 0 a 5000
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

    if (_authPin.length != 8 || !_authPin.codeUnits.every((b) => b >= 0x30 && b <= 0x39)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el PIN real del sensor: exactamente 8 caracteres ASCII.')),
      );
      return;
    }
    if (!_emptyFreq.isFinite || !_fullFreq.isFinite || _emptyFreq <= 0 || _fullFreq <= 0 || _emptyFreq == _fullFreq) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las frecuencias de vacío y lleno deben ser positivas y diferentes.')),
      );
      return;
    }

    final t = _isExternal ? _thickness : 0.0;
    final validPrimaryDimensions = [_length, _width, _height].every((v) => v.isFinite && v > 0) &&
        _thickness.isFinite && _thickness >= 0 &&
        (!_isExternal || (2 * t < _length && 2 * t < _width && 2 * t < _height));
    final validSecondaryDimensions = _tankType != 'double_tank' ||
        ([_tank2Length, _tank2Width, _tank2Height].every((v) => v.isFinite && v > 0) &&
            (!_isExternal || (2 * t < _tank2Length && 2 * t < _tank2Width && 2 * t < _tank2Height)));
    final validStep = _tankType != 'step_notch' ||
        (_stepWidth.isFinite && _stepHeight.isFinite && _stepWidth > 0 && _stepHeight > 0 &&
            _stepWidth < _width && _stepHeight < _height);
    if (!validPrimaryDimensions || !validSecondaryDimensions || !validStep) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dimensiones inválidas: revisa medidas, espesor y geometría seleccionada.')),
      );
      return;
    }

    final rows = _generateCalibrationTable();
    final validRows = rows.length == 30 &&
        rows.first.levelMm == 0 &&
        rows.first.volumeL == 0 &&
        rows.last.fixValue == 5000 &&
        rows.last.volumeL > 0 &&
        rows.every((row) => row.volumeL.isFinite && row.volumeL >= 0) &&
        rows.asMap().entries.skip(1).every((entry) =>
            entry.value.levelMm > rows[entry.key - 1].levelMm &&
            entry.value.fixValue > rows[entry.key - 1].fixValue &&
            entry.value.volumeL >= rows[entry.key - 1].volumeL);
    if (!validRows) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La geometría no genera una tabla válida de 30 puntos. Revisa dimensiones y espesor.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    // 1. Autenticar PIN
    final List<int> pinBytes = _authPin.codeUnits;
    bool authOk = await _bleManager.authenticate(pinBytes);
    if (!authOk) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de Autenticación. Verifica el PIN del sensor.')),
      );
      return;
    }

    // 2. Subir tabla
    bool uploadOk = await _bleManager.uploadCalibrationTable(
      rows,
      onProgress: (cur, tot) {
        if (!mounted) return;
        setState(() {
          _uploadProgress = cur / tot;
        });
      },
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (uploadOk) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('¡Calibración Exitosa!'),
          content: Text('Se grabaron ${rows.length} puntos en el sensor #${_selectedSensor?.id}.\nSalida fijada en Litros directos.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Aceptar')),
          ],
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al transferir la tabla de calibración al sensor.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuel Master Pro • AoooG BLE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD97706),
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'Sensores'),
            Tab(icon: Icon(Icons.straighten), text: 'Estanque'),
            Tab(icon: Icon(Icons.table_chart), text: 'Calibración'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSensorsTab(),
          _buildTankTab(),
          _buildCalibrationTab(),
        ],
      ),
    );
  }

  Widget _buildSensorsTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isConnected ? 'Conectado: Sensor #${_selectedSensor?.id}' : 'Sin sensor conectado',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isConnected ? const Color(0xFF059669) : Colors.black87,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isScanning ? null : _startBleScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B1329),
                  foregroundColor: Colors.white,
                ),
                icon: _isScanning
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search, size: 18),
                label: Text(_isScanning ? 'Buscando...' : 'Escanear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _discoveredSensors.isEmpty
              ? Center(
                  child: Text(
                    _isScanning ? 'Buscando sensores AoooG cercanos...' : 'Presiona Escanear para buscar sensores AoooG AG-BFLS',
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: _discoveredSensors.length,
                  itemBuilder: (context, idx) {
                    final s = _discoveredSensors[idx];
                    final isSel = _selectedSensor?.id == s.id && _isConnected;
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSel ? const Color(0xFF059669) : const Color(0xFF0B1329),
                          child: const Icon(Icons.sensors, color: Colors.white),
                        ),
                        title: Text('Sensor AoooG #${s.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${s.frequency.toStringAsFixed(0)} Hz • ${s.temperature}°C • Bat: ${s.battery}% • RSSI: ${s.rssi} dBm'),
                        trailing: ElevatedButton(
                          onPressed: isSel ? null : () => _connectToSensor(s),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSel ? Colors.grey : const Color(0xFF0B1329),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(isSel ? 'Activo' : 'Conectar'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTankTab() {
    double totalVol = TankGeometryEngine.calculateVolumeAtHeight(
      tankType: _tankType,
      length: _length,
      width: _width,
      height: _height,
      thickness: _thickness,
      isExternal: _isExternal,
      hMm: _tankType == 'double_tank'
          ? math.max(
              _height - (_isExternal ? _thickness * 2 : 0),
              _tank2Height - (_isExternal ? _thickness * 2 : 0),
            ).toDouble()
          : _height - (_isExternal ? _thickness * 2 : 0),
      rInfLi: _rInfLi,
      rInfLd: _rInfLd,
      rSupLi: _rSupLi,
      rSupLd: _rSupLd,
      rInfAf: _rInfAf,
      rInfAp: _rInfAp,
      rSupAf: _rSupAf,
      rSupAp: _rSupAp,
      rVert: _rVert,
      tank2Length: _tank2Length,
      tank2Width: _tank2Width,
      tank2Height: _tank2Height,
      cylHead: _cylHead,
      stepWidth: _stepWidth,
      stepHeight: _stepHeight,
      stepSide: _stepSide,
      dRBottomFront: _dRBottomFront,
      dRTopFront: _dRTopFront,
      dRBackCorners: _dRBackCorners,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Capacidad
          Card(
            color: const Color(0xFF0B1329),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Capacidad Calculada', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('${totalVol.toStringAsFixed(1)} L', style: const TextStyle(color: Color(0xFFD97706), fontSize: 26, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text('${_length.toInt()} × ${_width.toInt()} × ${_height.toInt()} mm', style: const TextStyle(color: Colors.white60)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Geometría
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Geometría del Estanque', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _tankType,
                    decoration: const InputDecoration(labelText: 'Tipo de Estanque', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'rectangular', child: Text('Prisma Rectangular (Radios Libres)')),
                      DropdownMenuItem(value: 'cylinder_horizontal', child: Text('Cilíndrico Horizontal')),
                      DropdownMenuItem(value: 'elliptical_horizontal', child: Text('Elíptico / Ovalado')),
                      DropdownMenuItem(value: 'd_shape', child: Text('Forma D (Volvo / Scania)')),
                      DropdownMenuItem(value: 'step_notch', child: Text('Tipo Escalera (Retroexcavadora)')),
                      DropdownMenuItem(value: 'double_tank', child: Text('Doble Estanque Conectado')),
                    ],
                    onChanged: (v) => setState(() => _tankType = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('Largo (L) mm', _length, (v) => setState(() => _length = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('Ancho (W) mm', _width, (v) => setState(() => _width = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('Alto (H) mm', _height, (v) => setState(() => _height = v))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('Espesor Chapa mm', _thickness, (v) => setState(() => _thickness = v))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<bool>(
                          value: _isExternal,
                          decoration: const InputDecoration(labelText: 'Medida', border: OutlineInputBorder()),
                          items: const [
                            DropdownMenuItem(value: true, child: Text('Externa')),
                            DropdownMenuItem(value: false, child: Text('Interna')),
                          ],
                          onChanged: (v) => setState(() => _isExternal = v!),
                        ),
                      ),
                    ],
                  ),
                  if (_tankType == 'rectangular')
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Radios y redondeos'),
                      children: [
                        Row(children: [
                          Expanded(child: _buildNumField('Piso izq. (mm)', _rInfLi, (v) => setState(() => _rInfLi = v))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildNumField('Piso der. (mm)', _rInfLd, (v) => setState(() => _rInfLd = v))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _buildNumField('Techo izq. (mm)', _rSupLi, (v) => setState(() => _rSupLi = v))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildNumField('Techo der. (mm)', _rSupLd, (v) => setState(() => _rSupLd = v))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _buildNumField('Frente piso (mm)', _rInfAf, (v) => setState(() => _rInfAf = v))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildNumField('Posterior piso (mm)', _rInfAp, (v) => setState(() => _rInfAp = v))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: _buildNumField('Frente techo (mm)', _rSupAf, (v) => setState(() => _rSupAf = v))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildNumField('Posterior techo (mm)', _rSupAp, (v) => setState(() => _rSupAp = v))),
                        ]),
                        const SizedBox(height: 8),
                        _buildNumField('Radio esquinas verticales (mm)', _rVert, (v) => setState(() => _rVert = v)),
                      ],
                    ),
                  if (_tankType == 'step_notch') ...[
                    const SizedBox(height: 14),
                    const Text('Escalón / muesca', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _buildNumField('Ancho escalón (mm)', _stepWidth, (v) => setState(() => _stepWidth = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('Alto escalón (mm)', _stepHeight, (v) => setState(() => _stepHeight = v))),
                    ]),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _stepSide,
                      decoration: const InputDecoration(labelText: 'Ubicación del escalón', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'bottom_right', child: Text('Inferior derecho')),
                        DropdownMenuItem(value: 'bottom_left', child: Text('Inferior izquierdo')),
                        DropdownMenuItem(value: 'top_right', child: Text('Superior derecho')),
                      ],
                      onChanged: (value) => setState(() => _stepSide = value ?? 'bottom_right'),
                    ),
                  ],
                  if (_tankType == 'd_shape') ...[
                    const SizedBox(height: 14),
                    const Text('Radios de perfil Forma D', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _buildNumField('Frente inferior (mm)', _dRBottomFront, (v) => setState(() => _dRBottomFront = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('Frente superior (mm)', _dRTopFront, (v) => setState(() => _dRTopFront = v))),
                    ]),
                    const SizedBox(height: 8),
                    _buildNumField('Esquinas posteriores (mm)', _dRBackCorners, (v) => setState(() => _dRBackCorners = v)),
                  ],
                  if (_tankType == 'cylinder_horizontal') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _cylHead,
                      decoration: const InputDecoration(labelText: 'Tipo de tapas', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'flat', child: Text('Planas')),
                        DropdownMenuItem(value: 'hemispherical', child: Text('Hemisféricas')),
                      ],
                      onChanged: (value) => setState(() => _cylHead = value ?? 'flat'),
                    ),
                  ],
                  if (_tankType == 'double_tank') ...[
                    const SizedBox(height: 14),
                    const Text('Segundo estanque conectado', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildNumField('Largo 2 (mm)', _tank2Length, (v) => setState(() => _tank2Length = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumField('Ancho 2 (mm)', _tank2Width, (v) => setState(() => _tank2Width = v))),
                        const SizedBox(width: 8),
                        Expanded(child: _buildNumField('Alto 2 (mm)', _tank2Height, (v) => setState(() => _tank2Height = v))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Parámetros de Sensor Frecuencia
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Parámetros de Frecuencia AoooG (Hz)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildNumField('Frecuencia Vacío Hz', _emptyFreq, (v) => setState(() => _emptyFreq = v))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildNumField('Frecuencia Lleno Hz', _fullFreq, (v) => setState(() => _fullFreq = v))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Frecuencia Actual Sensor: ${_curFreq.toStringAsFixed(0)} Hz', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0B1329))),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: _authPin,
                    decoration: const InputDecoration(labelText: 'PIN de Acceso Sensor (8 dígitos)', border: OutlineInputBorder()),
                    obscureText: true,
                    maxLength: 8,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _authPin = v,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrationTab() {
    final rows = _generateCalibrationTable();

    return Column(
      children: [
        if (_isUploading)
          LinearProgressIndicator(value: _uploadProgress, color: const Color(0xFFD97706), backgroundColor: Colors.grey.shade200),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tabla Generada (${rows.length} Puntos)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _uploadCalibrationToSensor,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B1329),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.upload, size: 18),
                label: Text(_isUploading ? 'Subiendo...' : 'Cargar al Sensor BLE'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final r = rows[idx];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 12,
                  backgroundColor: const Color(0xFF0B1329),
                  child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                ),
                title: Text('${r.volumeL.toStringAsFixed(1)} Litros  (${r.levelMm} mm)', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Coord Fix: ${r.fixValue}  •  Frecuencia Esperada: ${r.expectedFreqHz.toStringAsFixed(0)} Hz'),
                trailing: Text('${((r.fixValue / 5000) * 100).toStringAsFixed(0)} %', style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNumField(String label, double val, Function(double) onChanged) {
    return TextFormField(
      initialValue: val.toInt().toString(),
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
