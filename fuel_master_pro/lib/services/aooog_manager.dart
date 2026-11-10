import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'aooog_ble.dart';

class CalibrationRow {
  final int index;
  final double volumeL;
  final int levelMm;
  final int fixValue;
  final double expectedFreqHz;

  CalibrationRow({
    required this.index,
    required this.volumeL,
    required this.levelMm,
    required this.fixValue,
    required this.expectedFreqHz,
  });

  /// 8 bytes: float32 LE (volume), uint16 LE (level), uint16 LE (fix_value)
  Uint8List toBytes() {
    if (!volumeL.isFinite || volumeL < 0) {
      throw ArgumentError('Volume must be non-negative and finite.');
    }
    if (levelMm < 0 || levelMm > 0xFFFF) {
      throw ArgumentError('Level must fit in uint16.');
    }
    if (fixValue < 0 || fixValue > 5000) {
      throw ArgumentError('fix_value must be in 0..5000 range.');
    }

    final bd = ByteData(8);
    bd.setFloat32(0, volumeL, Endian.little);
    bd.setUint16(4, levelMm, Endian.little);
    bd.setUint16(6, fixValue, Endian.little);
    return bd.buffer.asUint8List();
  }
}

class SensorRealtimeData {
  final double frequencyHz;
  final double temperatureC;
  final double batteryPct;
  final double fuelOutput;
  final double emptyFreqHz;
  final double fullFreqHz;

  SensorRealtimeData({
    required this.frequencyHz,
    required this.temperatureC,
    required this.batteryPct,
    required this.fuelOutput,
    required this.emptyFreqHz,
    required this.fullFreqHz,
  });
}

class AoooGManager {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  int? currentSensorId;
  final _responseCompleters = <int, Completer<List<int>>>{};
  bool _commandInFlight = false;

  /// Callback para telemetría continua en vivo
  void Function(SensorRealtimeData data)? onRealtimeData;

  /// Conecta al sensor y descubre características FFF1 y FFF2
  Future<bool> connect(AoooGSensor sensor) async {
    await disconnect();
    try {
      await sensor.device.connect(
        timeout: const Duration(seconds: 10),
        license: License.nonprofit,
      );
      connectedDevice = sensor.device;
      currentSensorId = sensor.id;
      _connectionSub = sensor.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _clearConnectionState();
        }
      });

      try {
        await sensor.device.requestMtu(247);
      } catch (_) {}

      final services = await sensor.device.discoverServices();
      for (final service in services) {
        if (service.uuid == AoooGProtocol.serviceUuid) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid == AoooGProtocol.writeUuid) {
              writeChar = characteristic;
            }
            if (characteristic.uuid == AoooGProtocol.notifyUuid) {
              notifyChar = characteristic;
            }
          }
        }
      }

      if (writeChar == null || notifyChar == null) {
        await disconnect();
        return false;
      }
      await notifyChar!.setNotifyValue(true);
      _notifySub = notifyChar!.onValueReceived.listen(
        _onPacketReceived,
        onError: (_) => _failPendingCommands(),
      );
      return true;
    } catch (_) {
      await disconnect();
      return false;
    }
  }

  void _clearConnectionState() {
    unawaited(_connectionSub?.cancel());
    _connectionSub = null;
    unawaited(_notifySub?.cancel());
    _notifySub = null;
    writeChar = null;
    notifyChar = null;
    connectedDevice = null;
    currentSensorId = null;
    _isAuthenticated = false;
    _failPendingCommands();
  }

  void _failPendingCommands() {
    for (final completer in _responseCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Conexión BLE interrumpida.'));
      }
    }
    _responseCompleters.clear();
  }

  void _onPacketReceived(List<int> data) {
    debugPrint('[BLE RX RAW] ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    if (!AoooGProtocol.isValidFrame(data, expectedSensorId: currentSensorId)) {
      debugPrint('[BLE RX] Trama descartada o CRC inválido');
      return;
    }
    final command = data[5];
    final completer = _responseCompleters[command];
    if (completer != null && !completer.isCompleted) {
      completer.complete(List<int>.from(data));
      _responseCompleters.remove(command);
    }
  }

  /// Envía comando con timeout y serialización estricta
  Future<List<int>?> sendCommand(
    int command,
    List<int> payload, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final characteristic = writeChar;
    final sensorId = currentSensorId;
    if (characteristic == null || sensorId == null) {
      debugPrint('[BLE TX] Error: writeChar o sensorId nulo');
      return null;
    }

    // Esperar si hay un comando previo en vuelo
    int waitLimit = 0;
    while (_commandInFlight && waitLimit < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitLimit++;
    }

    _commandInFlight = true;
    final completer = Completer<List<int>>();
    _responseCompleters[command] = completer;
    try {
      final frame = AoooGProtocol.buildFrame(sensorId, command, payload);
      debugPrint('[BLE TX] CMD: 0x${command.toRadixString(16)} (${frame.length} bytes)');
      await characteristic.write(frame, withoutResponse: false);
      final res = await completer.future.timeout(timeout);
      debugPrint('[BLE RX OK] CMD: 0x${command.toRadixString(16)} -> ${res.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      return res;
    } catch (e) {
      debugPrint('[BLE ERR] CMD: 0x${command.toRadixString(16)} fallo: $e');
      return null;
    } finally {
      _responseCompleters.remove(command);
      _commandInFlight = false;
    }
  }

  /// Respuesta exitosa de estado (LL=06, payload[0]=00)
  bool _isSuccessStatus(List<int>? response, int command) {
    return response != null &&
        AoooGProtocol.isValidFrame(
          response,
          expectedSensorId: currentSensorId,
          expectedCommand: command,
        ) &&
        response.length >= 7 &&
        response[6] == 0x00;
  }

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;
  String _lastAcceptedPin = '12345678';
  String get lastAcceptedPin => _lastAcceptedPin;

  /// Autentica con contraseña (comando 0x12)
  /// Prueba candidatos automáticos o el PIN provisto por el usuario
  Future<bool> authenticate([String? explicitPin]) async {
    final cleanPin = explicitPin?.trim() ?? '';
    final sensorId = currentSensorId ?? 0;

    // Generar candidatos de credenciales (exactamente 8 bytes)
    final candidates = <List<int>>[];

    // 1. PIN ingresado explícitamente
    if (cleanPin.isNotEmpty) {
      if (cleanPin.length == 8) {
        candidates.add(cleanPin.codeUnits);
      } else {
        candidates.add(cleanPin.padLeft(8, '0').substring(0, 8).codeUnits);
        candidates.add(cleanPin.padRight(8, '0').substring(0, 8).codeUnits);
      }
      if (RegExp(r'^[0-9a-fA-F]{1,16}$').hasMatch(cleanPin)) {
        try {
          final hexStr = cleanPin.padLeft(16, '0').substring(0, 16);
          final hexBytes = <int>[];
          for (int i = 0; i < 16; i += 2) {
            hexBytes.add(int.parse(hexStr.substring(i, i + 2), radix: 16));
          }
          candidates.add(hexBytes);
        } catch (_) {}
      }
    }

    // 2. Último PIN aceptado (si se configuró)
    if (_lastAcceptedPin.isNotEmpty && _lastAcceptedPin != cleanPin) {
      candidates.add(_lastAcceptedPin.codeUnits);
    }

    // 3. Clave oficial de fábrica AoooG '12345678'
    candidates.add('12345678'.codeUnits);

    // 4. Clave alternativa '00000000'
    candidates.add('00000000'.codeUnits);

    // 5. Claves derivadas del sensor ID / SN
    if (sensorId > 0) {
      final snStr = sensorId.toString();
      candidates.add(snStr.padLeft(8, '0').codeUnits);
      candidates.add(snStr.padRight(8, '0').codeUnits);

      int id2 = (sensorId >> 16) & 0xFF;
      int id1 = (sensorId >> 8) & 0xFF;
      int id0 = sensorId & 0xFF;
      candidates.add([id2, id1, id0, 0, 0, 0, 0, 0]);
      candidates.add([0, 0, 0, 0, 0, id2, id1, id0]);
      candidates.add([0, id2, id1, id0, 0, 0, 0, 0]);
    }

    // 6. Ceros y FFs
    candidates.add(List<int>.filled(8, 0x00));
    candidates.add(List<int>.filled(8, 0xFF));

    // Deduplicar candidatos
    final seen = <String>{};
    final uniqueCandidates = <List<int>>[];
    for (final c in candidates) {
      if (c.length != 8) continue;
      final key = c.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueCandidates.add(c);
      }
    }

    for (final pwdBytes in uniqueCandidates) {
      debugPrint('[AUTH] Probando clave: ${pwdBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      final resp = await sendCommand(0x12, pwdBytes, timeout: const Duration(seconds: 3));
      if (_isSuccessStatus(resp, 0x12)) {
        debugPrint('[AUTH] ¡AUTENTICACIÓN EXITOSA! Clave aceptada.');
        _isAuthenticated = true;
        if (cleanPin.isNotEmpty) _lastAcceptedPin = cleanPin;
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    debugPrint('[AUTH] Ningún candidato fue aceptado por el sensor.');
    _isAuthenticated = false;
    return false;
  }

  /// Lee parámetros guardados (comando 0x0D): Frecuencia vacío y lleno
  Future<Map<String, double>?> readParameters() async {
    final response = await sendCommand(0x0D, []);
    if (response == null || !AoooGProtocol.isValidFrame(response, expectedSensorId: currentSensorId, expectedCommand: 0x0D)) {
      return null;
    }
    if (response.length < 19) return null;

    try {
      final data = ByteData.sublistView(Uint8List.fromList(response), 6);
      final emptyFrequency = data.getFloat32(4, Endian.little);
      final fullFrequency = data.getFloat32(8, Endian.little);
      if (!emptyFrequency.isFinite || !fullFrequency.isFinite || emptyFrequency <= 0 || fullFrequency <= 0) {
        return null;
      }
      return {
        'emptyFreq': emptyFrequency,
        'fullFreq': fullFrequency,
      };
    } catch (_) {
      return null;
    }
  }

  /// Lee telemetría en tiempo real (comando 0x14)
  Future<SensorRealtimeData?> readRealtimeData() async {
    final response = await sendCommand(0x14, []);
    if (response == null || !AoooGProtocol.isValidFrame(response, expectedSensorId: currentSensorId, expectedCommand: 0x14)) {
      return null;
    }
    if (response.length < 28) return null;

    try {
      final data = ByteData.sublistView(Uint8List.fromList(response), 6);
      final fullF = data.getFloat32(6, Endian.little);
      final emptyF = data.getFloat32(10, Endian.little);
      final curF = data.getFloat32(14, Endian.little);
      final curOut = data.getFloat32(18, Endian.little);

      final tempRaw = response[6 + 2];
      final tempC = (tempRaw > 127 ? tempRaw - 256 : tempRaw).toDouble();
      final battCode = (response[6 + 3] << 8) | response[6 + 4];
      final battPct = ((battCode - 500) * 100 / 220).clamp(0, 100).toDouble();

      final res = SensorRealtimeData(
        frequencyHz: curF,
        temperatureC: tempC,
        batteryPct: battPct,
        fuelOutput: curOut,
        emptyFreqHz: emptyF,
        fullFreqHz: fullF,
      );
      onRealtimeData?.call(res);
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Establece punto vacío en vivo (comando 0x10)
  Future<bool> setEmptyPoint() async {
    final resp = await sendCommand(0x10, []);
    return _isSuccessStatus(resp, 0x10);
  }

  /// Establece punto lleno en vivo (comando 0x11)
  Future<bool> setFullPoint() async {
    final resp = await sendCommand(0x11, []);
    return _isSuccessStatus(resp, 0x11);
  }

  /// Reinicia el sensor (comando 0x01)
  Future<bool> restartSensor() async {
    final resp = await sendCommand(0x01, []);
    return _isSuccessStatus(resp, 0x01);
  }

  /// Configura el intervalo de transmisión BLE (comando 0x04)
  Future<bool> setBroadcastInterval(int seconds) async {
    final s = seconds.clamp(1, 255);
    final resp = await sendCommand(0x04, [s]);
    return _isSuccessStatus(resp, 0x04);
  }

  /// Lee el intervalo de transmisión BLE (comando 0x05)
  Future<int?> readBroadcastInterval() async {
    final resp = await sendCommand(0x05, []);
    if (resp != null && resp.length >= 8 && resp[5] == 0x05) {
      return resp[6];
    }
    return null;
  }

  /// Configura el modo de salida (comando 0x19): 00=normalizado (%), 01=mm, 02=litros
  Future<bool> setOutputMode(int mode) async {
    final resp = await sendCommand(0x19, [mode.clamp(0, 2)]);
    return _isSuccessStatus(resp, 0x19);
  }

  /// Lee el modo de salida actual (comando 0x1A)
  Future<int?> readOutputMode() async {
    final resp = await sendCommand(0x1A, []);
    if (resp != null && resp.length >= 8 && resp[5] == 0x1A) {
      return resp[6];
    }
    return null;
  }

  /// Lee un bloque de la tabla de calibración (comando 0x15)
  Future<List<CalibrationRow>?> readCalibrationBlock(int startIndex) async {
    final resp = await sendCommand(0x15, [startIndex.clamp(0, 90)]);
    if (resp == null || resp.length < 87 || resp[5] != 0x15) return null;

    final rows = <CalibrationRow>[];
    final bd = ByteData.sublistView(Uint8List.fromList(resp), 6);
    for (int i = 0; i < 10; i++) {
      final offset = i * 8;
      final vol = bd.getFloat32(offset, Endian.little);
      final lvl = bd.getUint16(offset + 4, Endian.little);
      final fix = bd.getUint16(offset + 6, Endian.little);
      rows.add(CalibrationRow(
        index: startIndex + i,
        volumeL: vol,
        levelMm: lvl,
        fixValue: fix,
        expectedFreqHz: 0,
      ));
    }
    return rows;
  }

  /// Carga la tabla de 30 puntos por bloques (comando 0x16)
  Future<bool> uploadCalibrationTable(
    List<CalibrationRow> rows, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (connectedDevice == null || rows.isEmpty) return false;

    const rowsPerBlock = 10;
    final totalBlocks = (rows.length / rowsPerBlock).ceil();
    for (var block = 0; block < totalBlocks; block++) {
      final startIndex = block * rowsPerBlock;
      final payload = <int>[startIndex];
      for (var offset = 0; offset < rowsPerBlock; offset++) {
        final index = startIndex + offset;
        payload.addAll(index < rows.length ? rows[index].toBytes() : List<int>.filled(8, 0));
      }

      final response = await sendCommand(
        0x16,
        payload,
        timeout: const Duration(seconds: 8),
      );
      if (!_isSuccessStatus(response, 0x16)) return false;
      onProgress?.call(block + 1, totalBlocks);
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Configurar modo de salida a LITROS (0x02)
    await setOutputMode(0x02);
    return true;
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    final device = connectedDevice;
    _clearConnectionState();
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }
}
