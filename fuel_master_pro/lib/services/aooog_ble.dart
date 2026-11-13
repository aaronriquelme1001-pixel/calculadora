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
    for (final byte in bytes) {
      crc ^= byte & 0xff;
      for (var bit = 0; bit < 8; bit++) {
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
    if (sensorId < 0 || sensorId > 0xffffff || command < 0 || command > 0xff ||
        payload.any((byte) => byte < 0 || byte > 0xff) || payload.length > 250) {
      throw ArgumentError('ID, comando o payload fuera de rango.');
    }
    final ll = 5 + payload.length;
    final body = <int>[ll, (sensorId >> 16) & 0xff, (sensorId >> 8) & 0xff,
      sensorId & 0xff, command, ...payload];
    return Uint8List.fromList([0x0c, ...body, crc8(body)]);
  }

  static int _batteryPercent(int code) => (((code - 500) * 100) ~/ 220).clamp(0, 100);

  static AoooGSensor? parseAdvertisement(ScanResult result) {
    final manufacturer = result.advertisementData.manufacturerData;
    final aooog = manufacturer[0xff43];
    final universal = manufacturer[0xffff];

    if (aooog != null) {
      if (aooog.length != 15) return null;
      final id = (aooog[0] << 16) | (aooog[1] << 8) | aooog[2];
      if (id == 0) return null;
      final data = ByteData.sublistView(Uint8List.fromList(aooog));
      final batteryCode = ((aooog[3] & 0x0f) << 8) | aooog[4];
      final temperature = (data.getInt16(5, Endian.big) / 8).round();
      final frequency = data.getFloat32(7, Endian.little);
      final output = data.getFloat32(11, Endian.little);
      if (!frequency.isFinite || !output.isFinite) return null;
      return AoooGSensor(device: result.device, id: id, mac: result.device.remoteId.str,
        rssi: result.rssi, frequency: frequency, emptyFreq: 0, output: output,
        temperature: temperature, battery: _batteryPercent(batteryCode));
    }

    if (universal == null || universal.length != 24 ||
        universal[0] != 0x3f || universal[1] != 0x36 ||
        universal[2] != 0xb4 || universal[5] != 0x5b) return null;
    final id = (universal[6] << 16) | (universal[7] << 8) | universal[8];
    final frequency = ((universal[14] << 8) | universal[15]).toDouble();
    final emptyFrequency = ((universal[18] << 8) | universal[19]).toDouble();
    final output = ((universal[20] << 8) | universal[21]).toDouble();
    return AoooGSensor(device: result.device, id: id, mac: result.device.remoteId.str,
      rssi: result.rssi, frequency: frequency, emptyFreq: emptyFrequency,
      output: output, temperature: universal[22] - 40,
      battery: universal[23].clamp(0, 100));
  }
}
