import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'aooog_ble.dart';
import 'tank_geometry.dart';

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
  StreamSubscription? _notifySub;

  int? currentSensorId;
  final _responseCompleters = <int, Completer<List<int>>>{};

  /// Conecta al sensor y descubre características FFF1 y FFF2
  Future<bool> connect(AoooGSensor sensor) async {
    try {
      await sensor.device.connect(
        timeout: const Duration(seconds: 10),
        license: License.nonprofit,
      );
      connectedDevice = sensor.device;
      currentSensorId = sensor.id;

      // Solicitar MTU 247 en Android para transferencias de bloques de 88 bytes
      await sensor.device.requestMtu(247);

      List<BluetoothService> services = await sensor.device.discoverServices();
      for (var s in services) {
        if (s.uuid == AoooGProtocol.serviceUuid) {
          for (var c in s.characteristics) {
            if (c.uuid == AoooGProtocol.writeUuid) writeChar = c;
            if (c.uuid == AoooGProtocol.notifyUuid) notifyChar = c;
          }
        }
      }

      if (writeChar != null && notifyChar != null) {
        await notifyChar!.setNotifyValue(true);
        _notifySub = notifyChar!.onValueReceived.listen(_onPacketReceived);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void _onPacketReceived(List<int> data) {
    if (data.length < 7 || data[0] != 0x0C) return;
    int cmd = data[5];
    if (_responseCompleters.containsKey(cmd)) {
      _responseCompleters[cmd]!.complete(data);
      _responseCompleters.remove(cmd);
    }
  }

  /// Envía comando con timeout y espera respuesta en FFF2
  Future<List<int>?> sendCommand(int cmd, List<int> payload, {Duration timeout = const Duration(seconds: 4)}) async {
    if (writeChar == null || currentSensorId == null) return null;

    final frame = AoooGProtocol.buildFrame(currentSensorId!, cmd, payload);
    final completer = Completer<List<int>>();
    _responseCompleters[cmd] = completer;

    await writeChar!.write(frame, withoutResponse: false);

    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      _responseCompleters.remove(cmd);
      return null;
    }
  }

  /// Autentica con contraseña de 8 bytes (Comando 0x12)
  Future<bool> authenticate(List<int> passwordBytes) async {
    if (passwordBytes.length != 8) return false;
    final res = await sendCommand(0x12, passwordBytes);
    // Respuesta: 0C 06 ID ID ID 12 00 CRC (00 = éxito)
    if (res != null && res.length >= 7 && res[5] == 0x12 && res[6] == 0x00) {
      return true;
    }
    return false;
  }

  /// Lee parámetros actuales (Comando 0x0D): Frecuencia vacía y llena guardadas
  Future<Map<String, double>?> readParameters() async {
    final res = await sendCommand(0x0D, []);
    if (res != null && res.length >= 19 && res[5] == 0x0D) {
      // Offset de payload en trama: 6
      final bd = ByteData.sublistView(Uint8List.fromList(res), 6);
      double emptyF = bd.getFloat32(4, Endian.little);
      double fullF = bd.getFloat32(8, Endian.little);
      return {'emptyFreq': emptyF, 'fullFreq': fullF};
    }
    return null;
  }

  /// Envía tabla de calibración (Comando 0x16) en bloques de 10 puntos (80 bytes por bloque)
  Future<bool> uploadCalibrationTable(
    List<CalibrationRow> rows, {
    Function(int current, int total)? onProgress,
  }) async {
    // La tabla tiene hasta 100 puntos (10 bloques de 10).
    int totalBlocks = (rows.length / 10).ceil();
    if (totalBlocks == 0) totalBlocks = 1;

    for (int b = 0; b < totalBlocks; b++) {
      int startIndex = b * 10;
      List<int> blockPayload = [startIndex];

      for (int i = 0; i < 10; i++) {
        int rIdx = startIndex + i;
        if (rIdx < rows.length) {
          blockPayload.addAll(rows[rIdx].toBytes());
        } else {
          // Relleno de ceros para completar los 80 bytes
          blockPayload.addAll(List.filled(8, 0));
        }
      }

      final res = await sendCommand(0x16, blockPayload, timeout: const Duration(seconds: 5));
      if (res == null || res.length < 7 || res[5] != 0x16 || res[6] != 0x00) {
        return false; // Error en escritura de bloque
      }

      if (onProgress != null) {
        onProgress(b + 1, totalBlocks);
      }
    }

    // Configurar modo de salida a LITROS (0x02) con Comando 0x19
    await sendCommand(0x19, [0x02]);

    return true;
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await connectedDevice?.disconnect();
    connectedDevice = null;
    writeChar = null;
    notifyChar = null;
  }
}
