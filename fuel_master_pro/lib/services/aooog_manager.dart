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
  CalibrationRow({required this.index, required this.volumeL, required this.levelMm,
    required this.fixValue, required this.expectedFreqHz});

  Uint8List toBytes() {
    if (!volumeL.isFinite || volumeL < 0 || volumeL > 1000000 ||
        levelMm < 0 || levelMm > 0xffff || fixValue < 0 || fixValue > 5000) {
      throw ArgumentError('Registro de calibración fuera de rango.');
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
  BluetoothCharacteristic? writeChar, notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  int? currentSensorId;
  int? negotiatedMtu;
  final Map<int, Completer<List<int>>> _pending = {};
  bool _busy = false;

  Future<bool> connect(AoooGSensor sensor) async {
    await disconnect();
    try {
      await sensor.device.connect(timeout: const Duration(seconds: 10), license: License.nonprofit);
      connectedDevice = sensor.device;
      currentSensorId = sensor.id;
      _connectionSub = sensor.device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _clearState();
      });
      negotiatedMtu = await sensor.device.requestMtu(247);
      final services = await sensor.device.discoverServices();
      for (final service in services) {
        if (service.uuid == AoooGProtocol.serviceUuid) {
          for (final c in service.characteristics) {
            if (c.uuid == AoooGProtocol.writeUuid) writeChar = c;
            if (c.uuid == AoooGProtocol.notifyUuid) notifyChar = c;
          }
        }
      }
      if (writeChar == null || notifyChar == null) {
        await disconnect();
        return false;
      }
      await notifyChar!.setNotifyValue(true);
      _notifySub = notifyChar!.onValueReceived.listen(_onPacket, onError: (_) => _failPending());
      return true;
    } catch (_) {
      await disconnect();
      return false;
    }
  }

  void _clearState() {
    unawaited(_connectionSub?.cancel()); _connectionSub = null;
    unawaited(_notifySub?.cancel()); _notifySub = null;
    writeChar = null; notifyChar = null; connectedDevice = null;
    currentSensorId = null; negotiatedMtu = null; _failPending();
  }

  void _failPending() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Conexión BLE interrumpida.'));
    }
    _pending.clear();
  }

  void _onPacket(List<int> packet) {
    if (!AoooGProtocol.isValidFrame(packet, expectedSensorId: currentSensorId)) return;
    final c = _pending[packet[5]];
    if (c != null && !c.isCompleted) { c.complete(List<int>.from(packet)); _pending.remove(packet[5]); }
  }

  Future<List<int>?> sendCommand(int command, List<int> payload,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final characteristic = writeChar;
    final id = currentSensorId;
    if (characteristic == null || id == null || _busy) return null;
    _busy = true;
    final completer = Completer<List<int>>();
    _pending[command] = completer;
    try {
      await characteristic.write(AoooGProtocol.buildFrame(id, command, payload), withoutResponse: false);
      return await completer.future.timeout(timeout);
    } catch (_) { return null; }
    finally { _pending.remove(command); _busy = false; }
  }

  bool _statusOk(List<int>? r, int cmd) =>
      r != null && AoooGProtocol.isValidFrame(r, expectedSensorId: currentSensorId, expectedCommand: cmd) &&
      r.length == 8 && r[6] == 0;

  Future<bool> authenticate(List<int> credentialBytes) async {
    if (credentialBytes.length != 8 || credentialBytes.any((b) => b < 0 || b > 255)) return false;
    return _statusOk(await sendCommand(0x12, credentialBytes), 0x12);
  }

  Future<Map<String, double>?> readParameters() async {
    final r = await sendCommand(0x0d, []);
    if (r == null || !AoooGProtocol.isValidFrame(r, expectedSensorId: currentSensorId,
        expectedCommand: 0x0d) || r.length != 21) return null;
    final d = ByteData.sublistView(Uint8List.fromList(r), 6);
    final empty = d.getFloat32(4, Endian.little);
    final full = d.getFloat32(8, Endian.little);
    if (!empty.isFinite || !full.isFinite || empty <= 0 || full <= 0 || empty == full) return null;
    return {'emptyFreq': empty, 'fullFreq': full};
  }

  Future<double?> readCalibrationCoordinate() async {
    final r = await sendCommand(0x1b, []);
    if (r == null || !AoooGProtocol.isValidFrame(r, expectedSensorId: currentSensorId,
        expectedCommand: 0x1b) || r.length != 12) return null;
    final value = ByteData.sublistView(Uint8List.fromList(r), 6).getFloat32(0, Endian.little);
    if (!value.isFinite || value < 0 || value > 5000) return null;
    return value;
  }

  Future<Uint8List?> readCalibrationBlock(int startIndex) async {
    if (startIndex < 0 || startIndex > 90 || startIndex % 10 != 0) return null;
    final r = await sendCommand(0x15, [startIndex], timeout: const Duration(seconds: 8));
    if (r == null || !AoooGProtocol.isValidFrame(r, expectedSensorId: currentSensorId,
        expectedCommand: 0x15) || r.length != 88) return null;
    return Uint8List.fromList(r.sublist(6, 86));
  }

  bool _validRows(List<CalibrationRow> rows) {
    if (rows.length != 100) return false;
    var terminated = false;
    var lastFix = -1;
    var lastLevel = -1;
    var lastVolume = -1.0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.index != i) return false;
      if (row.volumeL == 0 && row.levelMm == 0 && row.fixValue == 0) { terminated = true; continue; }
      if (terminated || !row.expectedFreqHz.isFinite || row.expectedFreqHz <= 0 ||
          row.volumeL < lastVolume || row.levelMm <= lastLevel ||
          row.fixValue <= lastFix || row.fixValue > 5000) return false;
      try { row.toBytes(); } catch (_) { return false; }
      lastFix = row.fixValue; lastLevel = row.levelMm; lastVolume = row.volumeL;
    }
    return rows.takeWhile((r) => !(r.volumeL == 0 && r.levelMm == 0 && r.fixValue == 0)).length >= 2;
  }

  Future<bool> uploadCalibrationTable(List<CalibrationRow> rows,
      {void Function(int current, int total)? onProgress}) async {
    if (connectedDevice == null || !_validRows(rows)) return false;
    if ((negotiatedMtu ?? 0) < 91) return false;

    // Backup every block before index 0 can erase the current table.
    final backup = <Uint8List>[];
    for (var start = 0; start <= 90; start += 10) {
      final block = await readCalibrationBlock(start);
      if (block == null) return false;
      backup.add(block);
    }

    for (var start = 0; start <= 90; start += 10) {
      final payload = <int>[start];
      for (var i = start; i < start + 10; i++) payload.addAll(rows[i].toBytes());
      if (!_statusOk(await sendCommand(0x16, payload, timeout: const Duration(seconds: 8)), 0x16)) {
        // Do not retry or restart from zero: caller must inspect/restore from backup.
        return false;
      }
      final readBack = await readCalibrationBlock(start);
      final expected = Uint8List.fromList(payload.sublist(1));
      if (readBack == null || !_bytesEqual(readBack, expected)) return false;
      onProgress?.call(start ~/ 10 + 1, 10);
    }
    if (!_statusOk(await sendCommand(0x19, [0x02]), 0x19)) return false;
    final mode = await sendCommand(0x1a, []);
    return mode != null && AoooGProtocol.isValidFrame(mode,
      expectedSensorId: currentSensorId, expectedCommand: 0x1a) &&
      mode.length == 8 && mode[6] == 0x02;
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
    return true;
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel(); _notifySub = null;
    await _connectionSub?.cancel(); _connectionSub = null;
    final device = connectedDevice;
    _clearState();
    if (device != null) { try { await device.disconnect(); } catch (_) {} }
  }
}
