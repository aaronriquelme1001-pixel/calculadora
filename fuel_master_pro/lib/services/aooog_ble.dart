import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AoooGSensor {
  final BluetoothDevice device;
  final int id;
  final String mac;
  final int rssi;
  final double frequency;
  final double emptyFreq;
  final double output;
  final int temperature;
  final int battery;

  AoooGSensor({required this.device, required this.id, required this.mac,
    required this.rssi, required this.frequency, required this.emptyFreq,
    required this.output, required this.temperature, required this.battery});
}

class AoooGProtocol {
  static final Guid serviceUuid = Guid("0000FFF0-1212-EFDE-1523-785FEABCD123");
  static final Guid writeUuid = Guid("0000FFF1-1212-EFDE-1523-785FEABCD123");
  static final Guid notifyUuid = Guid("0000FFF2-1212-EFDE-1523-785FEABCD123");

  static int crc8(List<int> bytes) {
    var crc = 0;
    for (final b in bytes) {
      crc ^= b & 0xff;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0x8c : crc >> 1;
      }
    }
    return crc & 0xff;
  }

  static bool isValidFrame(List<int> data, {int? expectedSensorId, int? expectedCommand}) {
    if (data.length < 7 || data[0] != 0x0c || data[1] != data.length - 2) return false;
    final id = (data[2] << 16) | (data[3] << 8) | data[4];
    if (expectedSensorId != null && id != expectedSensorId) return false;
    if (expectedCommand != null && data[5] != expectedCommand) return false;
    return crc8(data.sublist(1, data.length - 1)) == data.last;
  }

  static Uint8List buildFrame(int sensorId, int command, List<int> payload) {
    if (sensorId < 0 || sensorId > 0xffffff || command < 0 || command > 255 ||
        payload.any((b) => b < 0 || b > 255) || payload.length > 250) {
      throw ArgumentError('ID, comando o payload fuera de rango.');
    }
    final ll = 5 + payload.length;
    final body = <int>[ll, (sensorId >> 16) & 255, (sensorId >> 8) & 255,
      sensorId & 255, command, ...payload];
    return Uint8List.fromList([0x0c, ...body, crc8(body)]);
  }

  static int _batteryPercent(int code) =>
      (((code - 500) * 100) ~/ 220).clamp(0, 100);

  static AoooGSensor? parseAdvertisement(ScanResult result) {
    final data = result.advertisementData.manufacturerData;
    final aooog = data[0xff43];
    final universal = data[0xffff];
    final bytes = aooog ?? universal;
    if (bytes == null) return null;

    if (aooog != null) {
      if (bytes.length != 15) return null;
      final id = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2];
      if (id == 0) return null;
      final bd = ByteData.sublistView(Uint8List.fromList(bytes));
      final batteryCode = ((bytes[3] & 0x0f) << 8) | bytes[4];
      final temperature = (bd.getInt16(5, Endian.big) / 8).round();
      final frequency = bd.getFloat32(7, Endian.little);
      final output = bd.getFloat32(11, Endian.little);
      if (!frequency.isFinite || !output.isFinite) return null;
      return AoooGSensor(device: result.device, id: id, mac: result.device.remoteId.str,
        rssi: result.rssi, frequency: frequency, emptyFreq: 0, output: output,
        temperature: temperature, battery: _batteryPercent(batteryCode));
    }

    if (bytes.length != 24 || bytes[0] != 0x3f || bytes[1] != 0x36 ||
        bytes[2] != 0xb4 || bytes[5] != 0x5b) return null;
    final id = (bytes[6] << 16) | (bytes[7] << 8) | bytes[8];
    final frequency = ((bytes[14] << 8) | bytes[15]).toDouble();
    final empty = ((bytes[18] << 8) | bytes[19]).toDouble();
    final output = ((bytes[20] << 8) | bytes[21]).toDouble();
    return AoooGSensor(device: result.device, id: id, mac: result.device.remoteId.str,
      rssi: result.rssi, frequency: frequency, emptyFreq: empty, output: output,
      temperature: bytes[22] - 40, battery: bytes[23].clamp(0, 100));
  }
}
