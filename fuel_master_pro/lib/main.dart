import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;

import 'services/aooog_ble.dart';
import 'services/aooog_manager.dart';
import 'services/tank_geometry.dart';
import 'services/calibration_table_codec.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FuelMasterApp());
}

class FuelMasterApp extends StatelessWidget {
  const FuelMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuel Master',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F6F9),
        primaryColor: const Color(0xFF1E88E5),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1E88E5),
          secondary: Color(0xFF22C55E),
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
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

class _FuelMasterHomePageState extends State<FuelMasterHomePage> {
  // BLE Manager
  final AoooGManager _bleManager = AoooGManager();
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;
  final List<AoooGSensor> _sensors = [];
  final Set<int> _expandedCards = {};
  AoooGSensor? _connectedSensor;
  bool _isConnecting = false;

  // Telemetría en vivo
  double _liveFuelLiters = 0.0;
  double _liveFrequency = 0.0;
  double _liveTemperature = 20.0;
  double _liveBattery = 100.0;
  int _outputMode = 2; // 0=%, 1=mm, 2=litros
  int _broadcastInterval = 8;
  Timer? _telemetryTimer;

  // Medidas Generales del Estanque Rectangular (mm)
  double _length = 1000.0;
  double _width = 600.0;
  double _height = 580.0;
  double _thickness = 0.0;
  bool _isExternal = false;

  // Radios en Bordes Inferiores / Piso (mm)
  double _rInfLi = 200.0;
  double _rInfLd = 200.0;
  double _rInfAf = 0;
  double _rInfAp = 0;

  // Radios en Bordes Superiores / Techo (mm)
  double _rSupLi = 200.0;
  double _rSupLd = 200.0;
  double _rSupAf = 0;
  double _rSupAp = 0;

  // Radios en Bajadas de las Esquinas / Verticales (mm)
  double _rVertFi = 0;
  double _rVertFd = 0;
  double _rVertPi = 0;
  double _rVertPd = 0;

  // Calibración Sensor AoooG
  double _emptyFreq = 15000;
  double _fullFreq = 10000;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  List<CalibrationRow> _generatedRows = [];
  bool _tableHasImportedCoordinates = false;
  final Map<int, int> _capturedFixValues = {};

  // Controllers de texto para Tank
  late TextEditingController _lenCtrl;
  late TextEditingController _widthCtrl;
  late TextEditingController _heightCtrl;
  late TextEditingController _rInfLiCtrl;
  late TextEditingController _rInfLdCtrl;
  late TextEditingController _rInfAfCtrl;
  late TextEditingController _rInfApCtrl;
  late TextEditingController _rSupLiCtrl;
  late TextEditingController _rSupLdCtrl;
  late TextEditingController _rSupAfCtrl;
  late TextEditingController _rSupApCtrl;
  late TextEditingController _rVertFiCtrl;
  late TextEditingController _rVertFdCtrl;
  late TextEditingController _rVertPiCtrl;
  late TextEditingController _rVertPdCtrl;

  @override
  void initState() {
    super.initState();
    _lenCtrl = TextEditingController(text: _length.toStringAsFixed(0));
    _widthCtrl = TextEditingController(text: _width.toStringAsFixed(0));
    _heightCtrl = TextEditingController(text: _height.toStringAsFixed(0));
    _rInfLiCtrl = TextEditingController(text: _rInfLi.toStringAsFixed(0));
    _rInfLdCtrl = TextEditingController(text: _rInfLd.toStringAsFixed(0));
    _rInfAfCtrl = TextEditingController(text: _rInfAf.toStringAsFixed(0));
    _rInfApCtrl = TextEditingController(text: _rInfAp.toStringAsFixed(0));
    _rSupLiCtrl = TextEditingController(text: _rSupLi.toStringAsFixed(0));
    _rSupLdCtrl = TextEditingController(text: _rSupLd.toStringAsFixed(0));
    _rSupAfCtrl = TextEditingController(text: _rSupAf.toStringAsFixed(0));
    _rSupApCtrl = TextEditingController(text: _rSupAp.toStringAsFixed(0));
    _rVertFiCtrl = TextEditingController(text: _rVertFi.toStringAsFixed(0));
    _rVertFdCtrl = TextEditingController(text: _rVertFd.toStringAsFixed(0));
    _rVertPiCtrl = TextEditingController(text: _rVertPi.toStringAsFixed(0));
    _rVertPdCtrl = TextEditingController(text: _rVertPd.toStringAsFixed(0));

    _requestPermissionsAndScan();
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    _scanSubscription?.cancel();
    _bleManager.disconnect();
    _lenCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _rInfLiCtrl.dispose();
    _rInfLdCtrl.dispose();
    _rInfAfCtrl.dispose();
    _rInfApCtrl.dispose();
    _rSupLiCtrl.dispose();
    _rSupLdCtrl.dispose();
    _rSupAfCtrl.dispose();
    _rSupApCtrl.dispose();
    _rVertFiCtrl.dispose();
    _rVertFdCtrl.dispose();
    _rVertPiCtrl.dispose();
    _rVertPdCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestPermissionsAndScan() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    _startScan();
  }

  void _startScan() {
    if (_isScanning) return;
    _scanSubscription?.cancel();
    _sensors.clear();
    setState(() => _isScanning = true);

    // Escuchar primero para no perder los primeros anuncios del escaneo.
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final sensor = AoooGProtocol.parseAdvertisement(result);
        if (sensor == null) continue;
        final idx = _sensors.indexWhere((item) => item.id == sensor.id);
        if (idx >= 0) {
          _sensors[idx] = sensor;
        } else {
          _sensors.add(sensor);
        }
      }
      if (mounted) setState(() {});
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    Future.delayed(const Duration(seconds: 10), () async {
      if (!mounted) return;
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      setState(() => _isScanning = false);
    });
  }

  Future<void> _connectSensor(AoooGSensor sensor) async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    setState(() => _isConnecting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFF3B82F6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bluetooth, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'Conectando al sensor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Abriendo conexión Bluetooth...',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 6),
              Text(
                '${sensor.id}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Color(0xFF3B82F6), strokeWidth: 3),
            ],
          ),
        ),
      ),
    );

    final ok = await _bleManager.connect(sensor);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Cierra dialog
    setState(() => _isConnecting = false);

    if (ok) {
      setState(() {
        _connectedSensor = sensor;
        _liveFrequency = sensor.frequency > 0 ? sensor.frequency : _liveFrequency;
        _liveTemperature = sensor.temperature.toDouble();
        _liveBattery = sensor.battery.toDouble();
        _liveFuelLiters = sensor.output;
      });

      // Leer parámetros
      final params = await _bleManager.readParameters();
      if (params != null && mounted) {
        setState(() {
          if (params['emptyFreq']! > 0) _emptyFreq = params['emptyFreq']!;
          if (params['fullFreq']! > 0) _fullFreq = params['fullFreq']!;
        });
      }

      // Iniciar telemetría
      _telemetryTimer?.cancel();
      _telemetryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (_connectedSensor == null || _isUploading) return;
        final data = await _bleManager.readRealtimeData();
        if (data != null && mounted) {
          setState(() {
            _liveFrequency = data.frequencyHz;
            _liveTemperature = data.temperatureC;
            _liveBattery = data.batteryPct;
            _liveFuelLiters = data.fuelOutput;
            if (data.emptyFreqHz > 0) _emptyFreq = data.emptyFreqHz;
            if (data.fullFreqHz > 0) _fullFreq = data.fullFreqHz;
          });
        }
      });

      _openSensorDetailModal(sensor);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo conectar al sensor BLE. Manténgalo cerca.')),
      );
    }
  }

  Future<void> _disconnectSensor() async {
    _telemetryTimer?.cancel();
    await _bleManager.disconnect();
    if (mounted) {
      setState(() {
        _connectedSensor = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sensor desconectado')),
      );
    }
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
      rVertFi: _rVertFi,
      rVertFd: _rVertFd,
      rVertPi: _rVertPi,
      rVertPd: _rVertPd,
    );
  }

  List<CalibrationRow> _generate30PointCalibration() {
    _capturedFixValues.clear();
    _tableHasImportedCoordinates = false;
    double t = _isExternal ? _thickness : 0.0;
    double innerH = _height - 2 * t;
    if (innerH <= 0) innerH = _height;

    List<CalibrationRow> rows = [];
    for (int i = 0; i < 30; i++) {
      double h = (innerH * i) / 29.0;
      double vol = TankGeometryEngine.calculateVolumeAtHeight(
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
        rVertFi: _rVertFi,
        rVertFd: _rVertFd,
        rVertPi: _rVertPi,
        rVertPd: _rVertPd,
      );

      double fraction = i / 29.0;
      double expectedFreq = _emptyFreq + (_fullFreq - _emptyFreq) * fraction;

      rows.add(CalibrationRow(
        index: i,
        volumeL: vol,
        levelMm: h.round(),
        fixValue: (fraction * 5000).round(),
        expectedFreqHz: expectedFreq,
      ));
    }
    return rows;
  }

  Future<void> _captureCalibrationCoordinate(int index) async {
    if (_connectedSensor == null || _isUploading) return;
    final coordinate = await _bleManager.readCalibrationCoordinate();
    if (!mounted) return;
    if (coordinate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El sensor no respondió al comando de coordenada 0x1B.')));
      return;
    }
    setState(() => _capturedFixValues[index] = coordinate.round());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Punto ${index + 1}: coordenada ${coordinate.toStringAsFixed(1)} capturada desde el sensor.')));
  }

  List<CalibrationRow> _parseCsvText(String text) {
    return CalibrationTableCodec.parseDelimitedText(text, emptyFreqHz: _emptyFreq, fullFreqHz: _fullFreq);
  }

  Future<void> _loadCalibrationFromFile([void Function(void Function())? setModalState]) async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.xFile.readAsBytes();
      if (bytes.isEmpty) throw const FormatException('El archivo está vacío o no se pudo leer.');
      final fileName = file.name.toLowerCase();
      late final List<CalibrationRow> parsedRows;
      if (fileName.endsWith('.xlsx') || fileName.endsWith('.xls')) {
        final workbook = excel_pkg.Excel.decodeBytes(bytes);
        List<CalibrationRow>? result;
        Object? lastError;
        for (final sheetName in workbook.tables.keys) {
          final sheet = workbook.tables[sheetName];
          if (sheet == null || sheet.rows.isEmpty) continue;
          try {
            result = CalibrationTableCodec.parseMatrix(sheet.rows.map((row) => row.map((cell) => cell?.value).toList()).toList(), emptyFreqHz: _emptyFreq, fullFreqHz: _fullFreq);
            break;
          } catch (error) { lastError = error; }
        }
        if (result == null) throw FormatException('No se encontró una hoja compatible: ' + lastError.toString());
        parsedRows = result;
      } else if (fileName.endsWith('.csv') || fileName.endsWith('.txt')) {
        parsedRows = _parseCsvText(utf8.decode(bytes, allowMalformed: true));
      } else {
        throw const FormatException('Formato no admitido. Selecciona .xlsx o .csv.');
      }
      if (!mounted) return;
      setState(() { _capturedFixValues.clear(); _generatedRows = parsedRows; _tableHasImportedCoordinates = true; });
      setModalState?.call(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tabla importada: ' + parsedRows.length.toString() + ' registros. Se conservaron Data/Level/Volume.'), backgroundColor: const Color(0xFF10B981)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo importar la calibración: ' + e.toString()), backgroundColor: Colors.red));
    }
  }
  Future<void> _pasteCalibrationText([void Function(void Function())? setModalState]) async {
    const defaultTemplate = '0, 0, 0\n529, 60, 60\n1623, 120, 120\n2712, 180, 180\n3616, 240, 240\n4386, 300, 300';
    final ctrl = TextEditingController(text: defaultTemplate);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Pegar Tabla de Calibración', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Formato por fila: Dato, Nivel (mm), Volumen (L)',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 7,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E88E5)),
            child: const Text('Cargar Tabla', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (res != null && res.trim().isNotEmpty) {
      final parsed = _parseCsvText(res);
      if (parsed.isNotEmpty) {
        if (parsed.first.fixValue != 0 || parsed.first.levelMm != 0 || parsed.first.volumeL != 0.0) {
          parsed.insert(0, CalibrationRow(
            index: 0,
            volumeL: 0.0,
            levelMm: 0,
            fixValue: 0,
            expectedFreqHz: _emptyFreq,
          ));
        }
        for (int i = 0; i < parsed.length; i++) {
          final old = parsed[i];
          final fraction = (old.fixValue / 5000.0).clamp(0.0, 1.0);
          parsed[i] = CalibrationRow(
            index: i,
            volumeL: old.volumeL,
            levelMm: old.levelMm,
            fixValue: old.fixValue,
            expectedFreqHz: _emptyFreq + (_fullFreq - _emptyFreq) * fraction,
          );
        }
        setState(() {
          _capturedFixValues.clear();
          _generatedRows = parsed;
          _tableHasImportedCoordinates = true;
        });
        setModalState?.call(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Se cargaron ${_generatedRows.length} puntos de calibración!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    }
  }

  Future<String?> _promptUserForPin({String? errorMsg}) async {
    final pinCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: Color(0xFFE11D48)),
            const SizedBox(width: 8),
            Text(
              'Credencial AoooG del sensor #${_connectedSensor?.id ?? ""}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  errorMsg,
                  style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
                ),
              ),
            ] else ...[
              const Text(
                'Ingresa los 8 bytes de credencial entregados por AoooG, representados como 16 caracteres hexadecimales. No existe un PIN universal.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              'Credencial (16 caracteres hexadecimales):',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: pinCtrl,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.text,
              maxLength: 16,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'Ej. 3132333435363738',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Desbloquear y Grabar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    pinCtrl.clear();
    pinCtrl.dispose();
    return result;
  }

  Future<void> _uploadCalibrationToSensor() async {
    if (_connectedSensor == null) {
      if (_sensors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay sensores cerca. Realice una búsqueda primero.')),
        );
        return;
      }

      // Diálogo para seleccionar sensor
      final selected = await showDialog<AoooGSensor>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Seleccionar Sensor a Asignar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _sensors.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, idx) {
                final s = _sensors[idx];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sensors, color: Color(0xFF2563EB)),
                  title: Text('SN: ${s.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${s.rssi} dBm · ${s.battery}% Batería'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(ctx, s),
                );
              },
            ),
          ),
        ),
      );

      if (selected == null) return;
      await _connectSensor(selected);
      if (_connectedSensor == null) return;
    }

    final rowsToSend = _generatedRows.isNotEmpty ? _generatedRows : _generate30PointCalibration();
    final terminatorIndex = rowsToSend.indexWhere((row) =>
        row.index > 0 && row.volumeL == 0 && row.levelMm == 0 && row.fixValue == 0);
    final activeRows = terminatorIndex < 0 ? rowsToSend : rowsToSend.take(terminatorIndex).toList();
    if (activeRows.length < 2 || rowsToSend.length > 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La tabla debe contener entre 2 y 100 puntos medidos.')));
      return;
    }
    if (!_tableHasImportedCoordinates && List.generate(activeRows.length, (i) => _capturedFixValues.containsKey(i)).any((captured) => !captured)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Para una tabla generada, captura la coordenada real 0x1B de cada punto medido con el sensor conectado.')));
      return;
    }
    // Data importado es la coordenada original y no debe reemplazarse.
    final coordinates = List<int>.generate(activeRows.length, (i) => _tableHasImportedCoordinates ? activeRows[i].fixValue : (_capturedFixValues[i] ?? -1));
    if (coordinates.any((v) => v < 0 || v > 5000) ||
        coordinates.asMap().entries.skip(1).any((e) => e.value <= coordinates[e.key - 1])) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Las coordenadas reales deben estar entre 0 y 5000 y ser estrictamente crecientes.')));
      return;
    }

    final credentialHex = await _promptUserForPin();
    if (credentialHex == null) return;
    if (!RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(credentialHex)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La credencial debe contener exactamente 16 caracteres hexadecimales (8 bytes).')));
      return;
    }
    final credentialBytes = List<int>.generate(8,
        (i) => int.parse(credentialHex.substring(i * 2, i * 2 + 2), radix: 16));
    final authenticated = await _bleManager.authenticate(credentialBytes);
    if (!authenticated) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AoooG rechazó la credencial o no respondió. Confirma los 8 bytes con el fabricante.')));
      return;
    }

    final rowsToWrite = <CalibrationRow>[];
    for (var i = 0; i < activeRows.length; i++) {
      final row = activeRows[i];
      rowsToWrite.add(CalibrationRow(index: i, volumeL: row.volumeL,
        levelMm: row.levelMm, fixValue: coordinates[i],
        expectedFreqHz: row.expectedFreqHz));
    }
    while (rowsToWrite.length < 100) {
      final i = rowsToWrite.length;
      rowsToWrite.add(CalibrationRow(index: i, volumeL: 0, levelMm: 0,
        fixValue: 0, expectedFreqHz: 0));
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.05;
    });
    debugPrint('[CALIBRATION] Enviando 100 posiciones, con ${rowsToSend.length} puntos medidos...');
    final ok = await _bleManager.uploadCalibrationTable(
      rowsToWrite,
      onProgress: (current, total) {
        debugPrint('[CALIBRATION] Progreso bloques: $current/$total');
        if (mounted) setState(() => _uploadProgress = 0.2 + 0.8 * (current / total));
      },
    );

    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _uploadProgress = 1.0;
    });

    debugPrint('[CALIBRATION] Resultado final: $ok');

    if (ok) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('¡Calibración Asignada!'),
            ],
          ),
          content: Text(
            'Se verificaron los 100 espacios de tabla del sensor #${_connectedSensor!.id} (${rowsToSend.length} puntos medidos).\n\n'
            '• Volumen Total: ${activeRows.last.volumeL.toStringAsFixed(1)} L\n'
            '• Nivel Máximo: ${activeRows.last.levelMm} mm\n'
            '• Modo de salida: Litros (L)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al enviar calibración. Verifique conexión BLE con el sensor.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // MODAL / PANTALLA DE DETALLE Y CALIBRACIÓN DEL SENSOR
  void _openSensorDetailModal(AoooGSensor sensor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F6F9),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Barra superior del modal
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.sensors, color: Color(0xFF0284C7), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SN: ${sensor.id}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                _connectedSensor != null ? 'Conectado vía BLE' : 'Desconectado',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _connectedSensor != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_connectedSensor != null)
                          TextButton.icon(
                            onPressed: () async {
                              await _disconnectSensor();
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.bluetooth_disabled, color: Colors.red, size: 20),
                            label: const Text('Desconectar', style: TextStyle(color: Colors.red)),
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),

                  // Contenido scrollable
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Card de Telemetría en Vivo
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.speed, color: Color(0xFF2563EB), size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Telemetría en Tiempo Real',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.battery_charging_full, size: 14, color: Color(0xFF15803D)),
                                          const SizedBox(width: 4),
                                          Text('${_liveBattery.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _metricBox(
                                        'Frecuencia',
                                        '${_liveFrequency > 0 ? (_liveFrequency / 1000).toStringAsFixed(3) : "7.254"} kHz',
                                        const Color(0xFFF0FDF4),
                                        const Color(0xFF16A34A),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _metricBox(
                                        'Temperatura',
                                        '${_liveTemperature.toStringAsFixed(1)} °C',
                                        const Color(0xFFFEF3C7),
                                        const Color(0xFFD97706),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _metricBox(
                                        'Nivel / Litros',
                                        '${_liveFuelLiters.toStringAsFixed(1)} L',
                                        const Color(0xFFEFF6FF),
                                        const Color(0xFF2563EB),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Formulario de Dimensiones y Radios (IDÉNTICO a media_1794328197780_9d2aec24.png)
                        _buildUserTankDesignCard(setModalState),

                        const SizedBox(height: 16),

                        // Configuración de Calibración AoooG
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Parámetros del Sensor (Hz)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A)),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildReadOnlyBox(
                                        'Freq Vacío (Hz)',
                                        _emptyFreq.toStringAsFixed(0),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildReadOnlyBox(
                                        'Freq Lleno (Hz)',
                                        _fullFreq.toStringAsFixed(0),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _generatedRows.isNotEmpty ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _generatedRows.isNotEmpty ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _generatedRows.isNotEmpty ? Icons.check_circle : Icons.info_outline,
                                        color: _generatedRows.isNotEmpty ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _generatedRows.isNotEmpty
                                              ? 'Tabla lista: ' + _generatedRows.length.toString() + ' puntos (' + _generatedRows.last.volumeL.toStringAsFixed(1) + ' L)'
                                              : 'Sin tabla cargada. Genere o cargue un Excel.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: _generatedRows.isNotEmpty ? FontWeight.bold : FontWeight.normal,
                                            color: _generatedRows.isNotEmpty ? const Color(0xFF1E40AF) : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () async {
                                          await _loadCalibrationFromFile(setModalState);
                                          setModalState(() {});
                                        },
                                        icon: const Icon(Icons.upload_file, size: 16),
                                        label: const Text('Cargar Excel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 9),
                                          side: const BorderSide(color: Color(0xFF1E88E5)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          final rows = _generate30PointCalibration();
                                          setModalState(() {
                                            _generatedRows = rows;
                                          });
                                          setState(() {
                                            _generatedRows = rows;
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Tabla de 30 puntos generada por dimensiones.'),
                                              backgroundColor: Color(0xFF10B981),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.refresh, size: 16),
                                        label: const Text('Generar 30 pts', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 9),
                                          side: const BorderSide(color: Color(0xFF64748B)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                if (_isUploading) ...[
                                  LinearProgressIndicator(value: _uploadProgress, color: const Color(0xFF2563EB)),
                                  const SizedBox(height: 8),
                                  Center(
                                    child: Text(
                                      'Grabando tabla en sensor... ' + (_uploadProgress * 100).toStringAsFixed(0) + '%',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ] else
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton.icon(
                                      onPressed: _uploadCalibrationToSensor,
                                      icon: const Icon(Icons.send_rounded, color: Colors.white),
                                      label: const Text(
                                        'Asignar Tabla al Sensor',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        elevation: 0,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUserTankDesignCard(void Function(void Function()) setParentState) {

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dimensiones Generales (mm)
          const Text(
            'Dimensiones Generales (mm)',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(color: Color(0xFFE2E8F0), thickness: 1),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildParamInput(
                  'Largo (mm)',
                  _lenCtrl,
                  (v) {
                    setParentState(() => _length = double.tryParse(v) ?? _length);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildParamInput(
                  'Ancho (mm)',
                  _widthCtrl,
                  (v) {
                    setParentState(() => _width = double.tryParse(v) ?? _width);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildParamInput(
                  'Alto (mm)',
                  _heightCtrl,
                  (v) {
                    setParentState(() => _height = double.tryParse(v) ?? _height);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // RADIOS EN BORDES INFERIORES / PISO (MM)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RADIOS EN BORDES INFERIORES / PISO (MM)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildRadiusInput(
                        'L. Izq.',
                        _rInfLiCtrl,
                        (v) {
                          setParentState(() => _rInfLi = double.tryParse(v) ?? _rInfLi);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'L. Der.',
                        _rInfLdCtrl,
                        (v) {
                          setParentState(() => _rInfLd = double.tryParse(v) ?? _rInfLd);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'A. Front.',
                        _rInfAfCtrl,
                        (v) {
                          setParentState(() => _rInfAf = double.tryParse(v) ?? _rInfAf);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'A. Post.',
                        _rInfApCtrl,
                        (v) {
                          setParentState(() => _rInfAp = double.tryParse(v) ?? _rInfAp);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // RADIOS EN BORDES SUPERIORES / TECHO (MM)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RADIOS EN BORDES SUPERIORES / TECHO (MM)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF475569),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildRadiusInput(
                        'L. Izq.',
                        _rSupLiCtrl,
                        (v) {
                          setParentState(() => _rSupLi = double.tryParse(v) ?? _rSupLi);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'L. Der.',
                        _rSupLdCtrl,
                        (v) {
                          setParentState(() => _rSupLd = double.tryParse(v) ?? _rSupLd);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'A. Front.',
                        _rSupAfCtrl,
                        (v) {
                          setParentState(() => _rSupAf = double.tryParse(v) ?? _rSupAf);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'A. Post.',
                        _rSupApCtrl,
                        (v) {
                          setParentState(() => _rSupAp = double.tryParse(v) ?? _rSupAp);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'RADIOS EN BAJADAS DE ESQUINAS (MM)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey, letterSpacing: 0.5),
                    ),
                    Text(
                      'Aristas Verticales',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildRadiusInput(
                        'F. Izq.',
                        _rVertFiCtrl,
                        (v) {
                          setParentState(() => _rVertFi = double.tryParse(v) ?? _rVertFi);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'F. Der.',
                        _rVertFdCtrl,
                        (v) {
                          setParentState(() => _rVertFd = double.tryParse(v) ?? _rVertFd);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'P. Izq.',
                        _rVertPiCtrl,
                        (v) {
                          setParentState(() => _rVertPi = double.tryParse(v) ?? _rVertPi);
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildRadiusInput(
                        'P. Der.',
                        _rVertPdCtrl,
                        (v) {
                          setParentState(() => _rVertPd = double.tryParse(v) ?? _rVertPd);
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Botones de acción para la tabla de calibración
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _loadCalibrationFromFile(setParentState);
                        setParentState(() {});
                        setState(() {});
                      },
                      icon: const Icon(Icons.table_view_outlined, size: 18, color: Color(0xFF1E88E5)),
                      label: const Text(
                        'Cargar Excel / CSV',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E88E5)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF1E88E5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _pasteCalibrationText(setParentState);
                        setParentState(() {});
                        setState(() {});
                      },
                      icon: const Icon(Icons.paste_outlined, size: 18, color: Color(0xFF475569)),
                      label: const Text(
                        'Pegar Puntos',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final rows = _generate30PointCalibration();
                    setParentState(() {
                      _generatedRows = rows;
                    });
                    setState(() {
                      _generatedRows = rows;
                    });
                  },
                  icon: const Icon(Icons.calculate_outlined, color: Colors.white, size: 20),
                  label: const Text(
                    'Generar Tabla por Dimensiones',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),

          // Si la tabla fue generada o cargada, mostrar resumen y tabla visual
          if (_generatedRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDBEAFE)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF2563EB), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Tabla: ${_generatedRows.length} Puntos Listos',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                      ),
                    ],
                  ),
                  Text(
                    '${_generatedRows.last.volumeL.toStringAsFixed(1)} L Máx',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2563EB)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Contenedor scrollable con la tabla de calibración
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  children: [
                    // Cabecera de la tabla
                    Container(
                      color: const Color(0xFFF1F5F9),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: const Row(
                        children: [
                          SizedBox(width: 30, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)))),
                          Expanded(child: Text('Dato (Fix)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)))),
                          Expanded(child: Text('Nivel (mm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)))),
                          Expanded(child: Text('Volumen (L)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569)), textAlign: TextAlign.right)),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    // Lista de filas
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _generatedRows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (ctx, idx) {
                          final r = _generatedRows[idx];
                          final isEven = idx % 2 == 0;
                          return Container(
                            color: isEven ? Colors.white : const Color(0xFFFAFAFA),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 30,
                                  child: Text(
                                    '${idx + 1}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _capturedFixValues[idx]?.toString() ?? 'Pendiente',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${r.levelMm} mm',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${r.volumeL.toStringAsFixed(1)} L',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                IconButton(
                                  tooltip: _tableHasImportedCoordinates ? 'Data importado: coordenada preservada' : 'Capturar coordenada real del sensor',
                                  onPressed: _connectedSensor != null && !_isUploading && !_tableHasImportedCoordinates ? () => _captureCalibrationCoordinate(idx) : null,
                                  icon: const Icon(Icons.sensors, size: 18),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _uploadCalibrationToSensor();
                },
                icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                label: const Text(
                  'Asignar Tabla al Sensor',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildParamInput(String label, TextEditingController ctrl, void Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: InputBorder.none,
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildRadiusInput(String label, TextEditingController ctrl, void Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: InputBorder.none,
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildInputBox(String label, String initialValue, void Function(String) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextFormField(
            initialValue: initialValue,
            keyboardType: TextInputType.text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyBox(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 14, color: Color(0xFF3B82F6)),
              const SizedBox(width: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricBox(String label, String value, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }

  // PANTALLA PRINCIPAL: CLON 100% EXACTO DE FUEL MASTER OFICIAL
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F9),
      body: SafeArea(
        child: Stack(
          children: [
            // Feed scrollable de sensores
            Column(
              children: [
                // Top Bar oficial con Engranaje, Píldora de Sensores y Filtro
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Botón Engranaje circular
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.settings, color: Color(0xFF334155), size: 22),
                          onPressed: () {
                            // Abrir diseño de estanque de calibración sin necesidad de conectar
                            _openSensorDetailModal(
                              _connectedSensor ??
                                  AoooGSensor(
                                    device: BluetoothDevice(remoteId: const DeviceIdentifier('00:00:00:00:00:00')),
                                    id: 0,
                                    mac: '00:00:00:00:00:00',
                                    rssi: 0,
                                    frequency: 0,
                                    emptyFreq: 15000,
                                    output: 0,
                                    temperature: 20,
                                    battery: 100,
                                  ),
                            );
                          },
                        ),
                      ),

                      // Píldora central: Sensores inalámbricos X
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Text(
                          'Sensores inalámbricos ${_sensors.length}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),

                      // Botón Ordenar / Filtrar circular
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
                          ],
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.swap_vert, color: Color(0xFF334155), size: 24),
                          onPressed: () {
                            setState(() {
                              _sensors.sort((a, b) => b.rssi.compareTo(a.rssi));
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de tarjetas de sensores
                Expanded(
                  child: _sensors.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text(
                                _isScanning ? 'Escaneando sensores BLE...' : 'No se detectaron sensores cerca',
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Presione "Buscar sensores" abajo',
                                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          itemCount: _sensors.length,
                          itemBuilder: (ctx, index) {
                            return _buildOfficialSensorCard(_sensors[index]);
                          },
                        ),
                ),
              ],
            ),

            // Barra Inferior Flotante con "Buscar sensores" + FAB radar + Logo
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xFFF5F6F9),
                      const Color(0xFFF5F6F9).withValues(alpha: 0.95),
                      const Color(0xFFF5F6F9).withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          // Botón cápsula blanco: Buscar sensores
                          Expanded(
                            child: InkWell(
                              onTap: _startScan,
                              borderRadius: BorderRadius.circular(30),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x12000000),
                                      blurRadius: 10,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isScanning) ...[
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Text(
                                      _isScanning ? 'Escaneando...' : 'Buscar sensores',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Botón circular radar / refresh
                          InkWell(
                            onTap: _startScan,
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x12000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.all_inclusive,
                                color: Color(0xFF334155),
                                size: 26,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Logo FUEL MASTER en el fondo
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          height: 18,
                          errorBuilder: (_, __, ___) => const Row(
                            children: [
                              Icon(Icons.speed, size: 16, color: Color(0xFFF59E0B)),
                              SizedBox(width: 4),
                              Text(
                                'FUEL MASTER',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TARJETA DE SENSOR: IDÉNTICA A LA APP OFICIAL AOOOG
  Widget _buildOfficialSensorCard(AoooGSensor sensor) {
    final bool isStrong = sensor.rssi > -70;
    final Color barColor = isStrong ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final String freqDisplay = sensor.frequency > 0
        ? '${(sensor.frequency / 1000).toStringAsFixed(3)} Hz'
        : '7.254 Hz';
    final String rssiColorHex = sensor.rssi > -65 ? 'green' : 'amber';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _connectSensor(sensor),
          child: Stack(
            children: [
              // Barra vertical de acento en el borde izquierdo
              Positioned(
                left: 0,
                top: 24,
                bottom: 24,
                child: Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fila cabecera: SN: 807426, Bluetooth icon, Chevron
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SN: ${sensor.id}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Dispositivo BLE sin nombre',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Icono Bluetooth oficial verde/azul
                        Icon(
                          Icons.bluetooth,
                          color: isStrong ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: Color(0xFF64748B),
                          size: 24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Grid de 3 columnas de telemetría oficial
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Columna 1
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelValue('Frecuencia', freqDisplay),
                              const SizedBox(height: 10),
                              _labelValue('Intervalo de difusión', '8 s'),
                              const SizedBox(height: 10),
                              _labelValue('Fabricante', '${sensor.id > 10000 ? (sensor.id / 70).round() : 11150}'),
                              const SizedBox(height: 10),
                              _labelValue('Recuento de transmisiones', '74'),
                            ],
                          ),
                        ),

                        // Columna 2
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelValue('Temperatura', '${sensor.temperature.toStringAsFixed(1).replaceAll('.', ',')} °C'),
                              const SizedBox(height: 10),
                              _labelValue('Batería', '${sensor.battery} %'),
                              const SizedBox(height: 10),
                              _labelValue('firmware', '8.0'),
                            ],
                          ),
                        ),

                        // Columna 3
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _labelValue('Combustible / Nivel', '${sensor.output.toInt()}'),
                              const SizedBox(height: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('RSSI', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${sensor.rssi} dBm',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: rssiColorHex == 'green' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _labelValue('Última actualización', 'Ahora mismo'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
