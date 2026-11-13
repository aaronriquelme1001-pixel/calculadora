import 'dart:async';
import 'dart:typed_data';
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
    if (!volumeL.isFinite || volumeL < 0 || volumeL > 1000000) {
      throw ArgumentError('Volume must be finite and in 0..1000000 L.');
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
  int? negotiatedMtu;
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
        negotiatedMtu = await sensor.device.requestMtu(247);
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
    negotiatedMtu = null;
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
    if (AoooGProtocol.isProtectedCommand(command) && !_isAuthenticated) {
      debugPrint('[BLE TX] Comando protegido 0x${command.toRadixString(16)} bloqueado: falta autenticación.');
      return null;
    }
    if (command == 0x15 && (negotiatedMtu ?? 0) < 90) {
      debugPrint('[BLE TX] Lectura 0x15 requiere ATT MTU >= 90.');
      return null;
    }
    if (command == 0x16 && (negotiatedMtu ?? 0) < 91) {
      debugPrint('[BLE TX] Escritura 0x16 requiere ATT MTU >= 91.');
      return null;
    }
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
    if (_commandInFlight) {
      debugPrint('[BLE TX] Comando omitido: existe otra solicitud sin respuesta.');
      return null;
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
        response.length == 8 &&
        response[6] == 0x00;
  }

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  /// AoooG entrega exactamente ocho bytes de credencial.
  /// No se prueban claves por defecto ni variantes derivadas del número de serie.
  Future<bool> authenticate(List<int> credentialBytes) async {
    if (credentialBytes.length != 8 ||
        credentialBytes.any((byte) => byte < 0 || byte > 0xff)) {
      _isAuthenticated = false;
      return false;
    }
    final response = await sendCommand(0x12, credentialBytes,
        timeout: const Duration(seconds: 4));
    _isAuthenticated = _isSuccessStatus(response, 0x12);
    return _isAuthenticated;
  }

  /// Lee parámetros guardados (comando 0x0D): Frecuencia vacío y lleno
  Future<Map<String, double>?> readParameters() async {
    final response = await sendCommand(0x0D, []);
    if (response == null ||
        !AoooGProtocol.isValidFrame(response, expectedSensorId: currentSensorId, expectedCommand: 0x0D) ||
        response.length != 20) return null;
    final parsed = AoooGProtocol.parseParameters(response.sublist(6, 19));
    if (parsed == null) return null;
    return {
      'broadcastInterval': (parsed['broadcastInterval'] as int).toDouble(),
      'continueAfterRestart': (parsed['continueAfterRestart'] as bool) ? 1.0 : 0.0,
      'transmitPower': (parsed['transmitPower'] as int).toDouble(),
      'emptyFreq': parsed['emptyFreq'] as double,
      'fullFreq': parsed['fullFreq'] as double,
      'outputMode': (parsed['outputMode'] as int).toDouble(),
    };
  }

  /// Lee telemetría en tiempo real (comando 0x14)
  Future<SensorRealtimeData?> readRealtimeData() async {
    final response = await sendCommand(0x14, []);
    if (response == null || !AoooGProtocol.isValidFrame(response, expectedSensorId: currentSensorId, expectedCommand: 0x14)) {
      return null;
    }
    if (response.length != 29) return null;

    try {
      final data = ByteData.sublistView(Uint8List.fromList(response), 6);
      final battCode = data.getUint16(0, Endian.big);
      final battPct = AoooGProtocol.batteryPercent(battCode).toDouble();
      final tempRaw = data.getInt16(2, Endian.big);
      final tempC = tempRaw / 8.0;
      final fullF = data.getFloat32(6, Endian.little);
      final emptyF = data.getFloat32(10, Endian.little);
      final curF = data.getFloat32(14, Endian.little);
      final curOut = data.getFloat32(18, Endian.little);

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
    if (seconds < 1 || seconds > 255) return false;
    final resp = await sendCommand(0x04, [seconds]);
    if (!_isSuccessStatus(resp, 0x04)) return false;
    return await readBroadcastInterval() == seconds;
  }

  /// Lee el intervalo de transmisión BLE (comando 0x05)
  Future<int?> readBroadcastInterval() async {
    final resp = await sendCommand(0x05, []);
    if (resp != null && AoooGProtocol.isValidFrame(resp, expectedSensorId: currentSensorId, expectedCommand: 0x05) && resp.length == 8) {
      return resp[6];
    }
    return null;
  }

  /// Configura el modo de salida (comando 0x19): 00=normalizado (%), 01=mm, 02=litros
  Future<bool> setOutputMode(int mode) async {
    if (mode < 0 || mode > 2) return false;
    final resp = await sendCommand(0x19, [mode]);
    if (!_isSuccessStatus(resp, 0x19)) return false;
    return await readOutputMode() == mode;
  }

  /// Lee el modo de salida actual (comando 0x1A)
  Future<int?> readOutputMode() async {
    final resp = await sendCommand(0x1A, []);
    if (resp != null &&
        AoooGProtocol.isValidFrame(resp, expectedSensorId: currentSensorId, expectedCommand: 0x1A) &&
        resp.length == 8 && resp[6] <= 2) {
      return resp[6];
    }
    return null;
  }

  Future<int?> readTransmitPower() async {
    final resp = await sendCommand(0x0B, []);
    if (resp == null || !AoooGProtocol.isValidFrame(resp, expectedSensorId: currentSensorId, expectedCommand: 0x0B) || resp.length != 8) return null;
    return AoooGProtocol.signedInt8(resp[6]);
  }

  Future<bool> setTransmitPower(int dbm) async {
    const allowed = {-40, -20, -16, -12, -8, -4, 0, 3, 4};
    if (!allowed.contains(dbm)) return false;
    final resp = await sendCommand(0x0A, [dbm & 0xff]);
    if (!_isSuccessStatus(resp, 0x0A)) return false;
    return await readTransmitPower() == dbm;
  }

  Future<bool> setContinueAfterRestart(bool enabled) async {
    final resp = await sendCommand(0x0C, [enabled ? 1 : 0]);
    if (!_isSuccessStatus(resp, 0x0C)) return false;
    final params = await readParameters();
    return params != null && params['continueAfterRestart'] == (enabled ? 1.0 : 0.0);
  }

  Future<String?> readFirmwareVersion() async {
    final resp = await sendCommand(0x26, [], timeout: const Duration(seconds: 3));
    if (resp == null || !AoooGProtocol.isValidFrame(resp, expectedSensorId: currentSensorId, expectedCommand: 0x26)) return null;
    return AoooGProtocol.parseFirmwareVersion(resp.sublist(6, resp.length - 1));
  }

  Future<String?> readBleAddress() async {
    final resp = await sendCommand(0x20, []);
    if (resp == null || !AoooGProtocol.isValidFrame(resp, expectedSensorId: currentSensorId, expectedCommand: 0x20)) return null;
    return AoooGProtocol.parseBleAddress(resp.sublist(6, resp.length - 1));
  }

  Future<int?> readAdvertisingProtocol() async {
    final resp = await sendCommand(0x21, []);
    if (resp == null || !AoooGProtocol.isValidFrame(resp, expectedSensorId: currentSensorId, expectedCommand: 0x21)) return null;
    return AoooGProtocol.parseAdvertisingProtocol(resp.sublist(6, resp.length - 1));
  }

  Future<bool> setAdvertisingProtocol(int protocol) async {
    if (protocol < 0 || protocol > 1) return false;
    final resp = await sendCommand(0x22, [protocol]);
    if (!_isSuccessStatus(resp, 0x22)) return false;
    return await readAdvertisingProtocol() == protocol;
  }

  Future<Uint8List?> _readCalibrationBlockBytes(int startIndex) async {
    if (startIndex < 0 || startIndex > 90 || startIndex % 10 != 0) return null;
    final response = await sendCommand(0x15, [startIndex],
        timeout: const Duration(seconds: 8));
    if (response == null ||
        !AoooGProtocol.isValidFrame(response, expectedSensorId: currentSensorId, expectedCommand: 0x15) ||
        response.length != 87) return null;
    return Uint8List.fromList(response.sublist(6, 86));
  }

  /// Lee un bloque de diez registros y conserva el índice solicitado.
  Future<List<CalibrationRow>?> readCalibrationBlock(int startIndex) async {
    final bytes = await _readCalibrationBlockBytes(startIndex);
    if (bytes == null) return null;
    final data = ByteData.sublistView(bytes);
    return List<CalibrationRow>.generate(10, (i) {
      final offset = i * 8;
      return CalibrationRow(
        index: startIndex + i,
        volumeL: data.getFloat32(offset, Endian.little),
        levelMm: data.getUint16(offset + 4, Endian.little),
        fixValue: data.getUint16(offset + 6, Endian.little),
        expectedFreqHz: 0,
      );
    });
  }

  /// Lee la coordenada real del sensor (comando 0x1B), no una interpolación.
  Future<double?> readCalibrationCoordinate() async {
    final response = await sendCommand(0x1B, []);
    if (response == null ||
        !AoooGProtocol.isValidFrame(response, expectedSensorId: currentSensorId, expectedCommand: 0x1B) ||
        response.length != 11) return null;
    final value = ByteData.sublistView(Uint8List.fromList(response), 6)
        .getFloat32(0, Endian.little);
    if (!value.isFinite || value < 0 || value > 5000) return null;
    return value;
  }

  Future<double?> readCalibrationCoordinate() async {
    final response = await sendCommand(0x1B, []);
    if (response == null ||
        !AoooGProtocol.isValidFrame(response, expectedSensorId: currentSensorId, expectedCommand: 0x1B)) return null;
    return AoooGProtocol.parseCalibrationCoordinate(response.sublist(6, response.length - 1));
  }

  bool _validCalibrationRows(List<CalibrationRow> rows) {
    if (rows.length != 100) return false;
    var ended = false;
    var active = 0;
    var previousVolume = -1.0;
    var previousLevel = -1;
    var previousFix = -1;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.index != i) return false;
      final isTerminator = row.volumeL == 0 && row.levelMm == 0 && row.fixValue == 0;
      if (i > 0 && isTerminator) {
        ended = true;
        continue;
      }
      if (ended || !row.volumeL.isFinite || row.volumeL < previousVolume ||
          row.levelMm <= previousLevel || row.fixValue <= previousFix ||
          row.fixValue > 5000) return false;
      try { row.toBytes(); } catch (_) { return false; }
      active++;
      previousVolume = row.volumeL;
      previousLevel = row.levelMm;
      previousFix = row.fixValue;
    }
    return active >= 2;
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<bool> _restoreCalibrationBackup(List<Uint8List> backup) async {
    if (backup.length != 10 || connectedDevice == null || !_isAuthenticated) return false;
    for (var block = 0; block < 10; block++) {
      final start = block * 10;
      final payload = <int>[start, ...backup[block]];
      final response = await sendCommand(0x16, payload, timeout: const Duration(seconds: 8));
      if (!_isSuccessStatus(response, 0x16)) return false;
      final check = await _readCalibrationBlockBytes(start);
      if (check == null || !_bytesEqual(check, backup[block])) return false;
    }
    return true;
  }

  /// Requiere autenticación explícita, backup previo y verificación de los 10 bloques.
  /// Requiere autenticación explícita, respaldo previo y verificación de los 10 bloques.
  /// Si falla la escritura o el modo de salida, restaura tabla y modo anteriores.
  Future<bool> uploadCalibrationTable(List<CalibrationRow> rows, {void Function(int current, int total)? onProgress}) async {
    if (connectedDevice == null || !_isAuthenticated || (negotiatedMtu ?? 0) < 91 || !_validCalibrationRows(rows)) return false;
    final originalOutputMode = await readOutputMode();
    if (originalOutputMode == null) return false;
    final backup = <Uint8List>[];
    for (var start = 0; start <= 90; start += 10) {
      final block = await _readCalibrationBlockBytes(start);
      if (block == null) return false;
      backup.add(block);
    }
    Future<bool> rollback() async {
      final tableRestored = await _restoreCalibrationBackup(backup);
      final modeRestored = await setOutputMode(originalOutputMode) && await readOutputMode() == originalOutputMode;
      return tableRestored && modeRestored;
    }
    for (var start = 0; start <= 90; start += 10) {
      final payload = <int>[start];
      for (var i = start; i < start + 10; i++) payload.addAll(rows[i].toBytes());
      final response = await sendCommand(0x16, payload, timeout: const Duration(seconds: 8));
      if (!_isSuccessStatus(response, 0x16)) { await rollback(); return false; }
      final readBack = await _readCalibrationBlockBytes(start);
      final expected = Uint8List.fromList(payload.sublist(1));
      if (readBack == null || !_bytesEqual(readBack, expected)) { await rollback(); return false; }
      onProgress?.call(start ~/ 10 + 1, 10);
    }
    if (!await setOutputMode(0x02) || await readOutputMode() != 0x02) { await rollback(); return false; }
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
