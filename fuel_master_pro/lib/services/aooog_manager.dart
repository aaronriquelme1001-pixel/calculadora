import 'dart:async';
import 'dart:typed_data';
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

      await sensor.device.requestMtu(247);
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
    _failPendingCommands();
  }

  void _failPendingCommands() {
    for (final completer in _responseCompleters.values) {
      if (!completer.isCompleted) completer.completeError(StateError('Conexión BLE interrumpida.'));
    }
    _responseCompleters.clear();
  }

  void _onPacketReceived(List<int> data) {
    if (!AoooGProtocol.isValidFrame(data, expectedSensorId: currentSensorId)) return;
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
    if (characteristic == null || sensorId == null || _commandInFlight) return null;

    _commandInFlight = true;
    final completer = Completer<List<int>>();
    _responseCompleters[command] = completer;
    try {
      final frame = AoooGProtocol.buildFrame(sensorId, command, payload);
      await characteristic.write(frame, withoutResponse: false);
      return await completer.future.timeout(timeout);
    } catch (_) {
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

  /// Autentica con contraseña (comando 0x12). Intenta formato ASCII y formato Hex binario
  Future<bool> authenticate(String pin) async {
    final cleanPin = pin.trim();
    
    // Intento 1: Bytes ASCII estándar (8 bytes)
    List<int> asciiBytes = cleanPin.padRight(8, '0').substring(0, 8).codeUnits;
    var resp = await sendCommand(0x12, asciiBytes);
    if (_isSuccessStatus(resp, 0x12)) return true;

    // Intento 2: BCD / Hex si el PIN son dígitos
    if (RegExp(r'^[0-9a-fA-F]{1,16}$').hasMatch(cleanPin)) {
      try {
        final hexStr = cleanPin.padLeft(16, '0').substring(0, 16);
        final hexBytes = <int>[];
        for (int i = 0; i < 16; i += 2) {
          hexBytes.add(int.parse(hexStr.substring(i, i + 2), radix: 16));
        }
        resp = await sendCommand(0x12, hexBytes);
        if (_isSuccessStatus(resp, 0x12)) return true;
      } catch (_) {}
    }

    // Intento 3: PIN por defecto de fábrica AoooG '12345678'
    final defaultBytes = '12345678'.codeUnits;
    resp = await sendCommand(0x12, defaultBytes);
    if (_isSuccessStatus(resp, 0x12)) return true;

    // Intento 4: PIN de ceros '00000000'
    resp = await sendCommand(0x12, '00000000'.codeUnits);
    return _isSuccessStatus(resp, 0x12);
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

  /// Envía tabla de calibración (comando 0x16)
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
        timeout: const Duration(seconds: 6),
      );
      if (!_isSuccessStatus(response, 0x16)) return false;
      onProgress?.call(block + 1, totalBlocks);
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
