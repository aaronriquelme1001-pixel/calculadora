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

  /// Formato AoooG: float32 LE (litros), uint16 LE (nivel), uint16 LE (fix).
  Uint8List toBytes() {
    if (!volumeL.isFinite || volumeL < 0 || volumeL > 1000000) {
      throw ArgumentError.value(volumeL, 'volumeL', 'Volumen fuera de rango.');
    }
    if (levelMm < 0 || levelMm > 0xFFFF) {
      throw ArgumentError.value(levelMm, 'levelMm', 'Nivel fuera de rango uint16.');
    }
    if (fixValue < 0 || fixValue > 5000) {
      throw ArgumentError.value(fixValue, 'fixValue', 'Debe estar entre 0 y 5000.');
    }
    final bd = ByteData(8);
    bd.setFloat32(0, volumeL, Endian.little);
    bd.setUint16(4, levelMm, Endian.little);
    bd.setUint16(6, fixValue, Endian.little);
    return bd.buffer.asUint8List();
  }
}

class AoooGManager {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? writeChar;
  BluetoothCharacteristic? notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  int? currentSensorId;
  final Map<int, Completer<List<int>>> _responseCompleters = {};
  bool _commandInFlight = false;

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

  bool _isSuccessResponse(List<int>? response, int command) {
    return response != null &&
        AoooGProtocol.isValidFrame(
          response,
          expectedSensorId: currentSensorId,
          expectedCommand: command,
        ) &&
        response.length >= 8 &&
        response[6] == 0x00;
  }

  Future<bool> authenticate(List<int> passwordBytes) async {
    if (passwordBytes.length != 8 || passwordBytes.any((b) => b < 0 || b > 0xFF)) {
      return false;
    }
    final response = await sendCommand(0x12, passwordBytes);
    return _isSuccessResponse(response, 0x12);
  }

  Future<Map<String, double>?> readParameters() async {
    final response = await sendCommand(0x0D, []);
    if (!_isSuccessResponse(response, 0x0D) || response!.length < 19) return null;

    try {
      final data = ByteData.sublistView(Uint8List.fromList(response), 6);
      final emptyFrequency = data.getFloat32(4, Endian.little);
      final fullFrequency = data.getFloat32(8, Endian.little);
      if (!emptyFrequency.isFinite ||
          !fullFrequency.isFinite ||
          emptyFrequency <= 0 ||
          fullFrequency <= 0 ||
          emptyFrequency == fullFrequency) {
        return null;
      }
      return {
        'emptyFreq': emptyFrequency,
        'fullFreq': fullFrequency,
      };
    } on RangeError {
      return null;
    }
  }

  bool _validateCalibrationRows(List<CalibrationRow> rows) {
    if (rows.length != 30) return false;
    var previousVolume = -1.0;
    var previousLevel = -1;
    var previousFix = -1;
    for (final row in rows) {
      if (!row.volumeL.isFinite ||
          !row.expectedFreqHz.isFinite ||
          row.expectedFreqHz <= 0 ||
          row.volumeL < 0 ||
          row.levelMm < 0 ||
          row.levelMm > 0xFFFF ||
          row.fixValue < 0 ||
          row.fixValue > 5000 ||
          row.volumeL < previousVolume ||
          row.levelMm <= previousLevel ||
          row.fixValue <= previousFix) {
        return false;
      }
      previousVolume = row.volumeL;
      previousLevel = row.levelMm;
      previousFix = row.fixValue;
      try {
        row.toBytes();
      } catch (_) {
        return false;
      }
    }
    return rows.first.levelMm == 0 &&
        rows.first.fixValue == 0 &&
        rows.first.volumeL == 0 &&
        rows.last.fixValue == 5000 &&
        rows.last.volumeL > 0;
  }

  Future<bool> uploadCalibrationTable(
    List<CalibrationRow> rows, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (connectedDevice == null || !_validateCalibrationRows(rows)) return false;

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
      if (!_isSuccessResponse(response, 0x16)) return false;
      onProgress?.call(block + 1, totalBlocks);
    }

    // No declarar éxito hasta recibir confirmación del modo de salida en litros.
    final outputResponse = await sendCommand(0x19, [0x02]);
    return _isSuccessResponse(outputResponse, 0x19);
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
      } catch (_) {
        // La conexión puede haberse cerrado desde el periférico.
      }
    }
  }
}
