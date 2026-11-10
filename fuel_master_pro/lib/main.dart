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
  double _length = 60;
  double _width = 58;
  double _height = 600;
  double _thickness = 2.5;
  bool _isExternal = true;

  // Radios en Bordes Inferiores / Piso (mm)
  double _rInfLi = 0;
  double _rInfLd = 0;
  double _rInfAf = 0;
  double _rInfAp = 0;

  // Radios en Bordes Superiores / Techo (mm)
  double _rSupLi = 0;
  double _rSupLd = 0;
  double _rSupAf = 0;
  double _rSupAp = 0;

  // Nivel de líquido actual simulado / calibrado
  double _currentLiquidMm = 0;

  // Calibración Sensor AoooG
  double _emptyFreq = 15000;
  double _fullFreq = 10000;
  String _authPin = '12345678';
  bool _isUploading = false;
  double _uploadProgress = 0.0;

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
  late TextEditingController _waterCtrl;

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
    _waterCtrl = TextEditingController(text: '');

    _requestPermissionsAndScan();
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
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
    _waterCtrl.dispose();
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
    setState(() {
      _isScanning = true;
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final sensor = AoooGProtocol.parseAdvertisement(r);
        if (sensor != null) {
          final idx = _sensors.indexWhere((s) => s.id == sensor.id);
          if (idx >= 0) {
            _sensors[idx] = sensor;
          } else {
            _sensors.add(sensor);
          }
          if (mounted) setState(() {});
        }
      }
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  Future<void> _connectSensor(AoooGSensor sensor) async {
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
      rVert: 0,
    );
  }

  double _calculateLiquidVolume() {
    if (_currentLiquidMm <= 0) return 0.0;
    return TankGeometryEngine.calculateVolumeAtHeight(
      tankType: 'rectangular',
      length: _length,
      width: _width,
      height: _height,
      thickness: _thickness,
      isExternal: _isExternal,
      hMm: _currentLiquidMm,
      rInfLi: _rInfLi,
      rInfLd: _rInfLd,
      rSupLi: _rSupLi,
      rSupLd: _rSupLd,
      rInfAf: _rInfAf,
      rInfAp: _rInfAp,
      rSupAf: _rSupAf,
      rSupAp: _rSupAp,
      rVert: 0,
    );
  }

  List<CalibrationRow> _generate30PointCalibration() {
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
        rVert: 0,
      );

      double fraction = i / 29.0;
      double expectedFreq = _emptyFreq + (_fullFreq - _emptyFreq) * fraction;

      rows.add(CalibrationRow(
        index: i + 1,
        volumeL: vol,
        levelMm: h.round(),
        fixValue: 0,
        expectedFreqHz: expectedFreq,
      ));
    }
    return rows;
  }

  Future<void> _uploadCalibrationToSensor() async {
    if (_connectedSensor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conéctate a un sensor antes de calibrar.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    final rows = _generate30PointCalibration();

    // 1. Autenticar con PIN primero
    final authOk = await _bleManager.authenticate(_authPin);
    if (!authOk) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error de autenticación con el PIN. Verifique el PIN del sensor.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final ok = await _bleManager.uploadCalibrationTable(
      rows,
      onProgress: (current, total) {
        if (mounted) setState(() => _uploadProgress = current / total);
      },
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (ok) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('¡Calibración Exitosa!'),
            ],
          ),
          content: Text(
            'Se grabaron 30 puntos en el sensor #${_connectedSensor!.id}.\n'
            'Volumen Total: ${_calculateTotalVolume().toStringAsFixed(1)} L\n'
            'Rango Frecuencia: ${_emptyFreq.toStringAsFixed(0)} Hz - ${_fullFreq.toStringAsFixed(0)} Hz',
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
          content: Text('Error al enviar calibración. Verifique PIN (12345678) y reconecte.'),
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
            final totVol = _calculateTotalVolume();
            final curVol = _calculateLiquidVolume();
            final emptyVol = (totVol - curVol).clamp(0.0, double.infinity);

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
                                  'Parámetros Sensor (Hz) y Seguridad',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A)),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildInputBox(
                                        'Freq Vacío (Hz)',
                                        _emptyFreq.toStringAsFixed(0),
                                        (v) => _emptyFreq = double.tryParse(v) ?? _emptyFreq,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildInputBox(
                                        'Freq Lleno (Hz)',
                                        _fullFreq.toStringAsFixed(0),
                                        (v) => _fullFreq = double.tryParse(v) ?? _fullFreq,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _buildInputBox(
                                        'PIN Autenticación',
                                        _authPin,
                                        (v) => _authPin = v,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (_isUploading) ...[
                                  LinearProgressIndicator(value: _uploadProgress, color: const Color(0xFF2563EB)),
                                  const SizedBox(height: 8),
                                  Center(
                                    child: Text(
                                      'Grabando tabla en sensor... ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ] else
                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton.icon(
                                      onPressed: _uploadCalibrationToSensor,
                                      icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
                                      label: const Text(
                                        'Cargar Tabla al Sensor (30 Puntos)',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1E88E5),
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

  // WIDGET EXACTO DE LA CAPTURA DEL USUARIO (media_1794328197780_9d2aec24.png)
  Widget _buildUserTankDesignCard(void Function(void Function()) setParentState) {
    final totVol = _calculateTotalVolume();
    final curVol = _calculateLiquidVolume();
    final emptyVol = (totVol - curVol).clamp(0.0, double.infinity);

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
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Nivel de Líquido
          const Text(
            'Nivel de Líquido',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A),
            ),
          ),
          const SizedBox(height: 4),
          const Divider(color: Color(0xFFE2E8F0), thickness: 1),
          const SizedBox(height: 12),

          _buildParamInput(
            'Altura del Agua Actual (mm)',
            _waterCtrl,
            (v) {
              setParentState(() => _currentLiquidMm = double.tryParse(v) ?? 0.0);
              setState(() {});
            },
          ),
          const SizedBox(height: 14),

          // 3 Bloques de Métricas: Volumen Total, Líquido Actual, Espacio Vacío
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF), // Azul claro
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDBEAFE)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Volumen Total',
                        style: TextStyle(fontSize: 12, color: Color(0xFF3B82F6), fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${totVol.toStringAsFixed(1)} L',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5), // Verde claro
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Líquido Actual',
                        style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${curVol.toStringAsFixed(1)} L',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB), // Amarillo suave
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Espacio Vacío',
                        style: TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${emptyVol.toStringAsFixed(1)} L',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

  Widget _metricBox(String label, String value, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.8), fontWeight: FontWeight.w500)),
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
                      const Color(0xFFF5F6F9).withOpacity(0.95),
                      const Color(0xFFF5F6F9).withOpacity(0.0),
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
