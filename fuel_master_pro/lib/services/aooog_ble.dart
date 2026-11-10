import 'dart:async';
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

  AoooGSensor({
    required this.device,
    required this.id,
    required this.mac,
    required this.rssi,
    required this.frequency,
    required this.emptyFreq,
    required this.output,
    required this.temperature,
    required this.battery,
  });
}

class AoooGProtocol {
  static final Guid serviceUuid = Guid("0000FFF0-1212-EFDE-1523-785FEABCD123");
  static final Guid writeUuid   = Guid("0000FFF1-1212-EFDE-1523-785FEABCD123");
  static final Guid notifyUuid  = Guid("0000FFF2-1212-EFDE-1523-785FEABCD123");

  static int crc8(List<int> bytes) {
    int crc = 0;
    for (int b in bytes) {
      crc ^= (b & 0xFF);
      for (int i = 0; i < 8; i++) {
        crc = ((crc & 1) != 0) ? ((crc >> 1) ^ 0x8C) : (crc >> 1);
      }
    }
    return crc & 0xFF;
  }

  static Uint8List buildFrame(int sensorId, int cmd, List<int> payload) {
    int id2 = (sensorId >> 16) & 0xFF;
    int id1 = (sensorId >> 8) & 0xFF;
    int id0 = sensorId & 0xFF;
    int ll = 5 + payload.length;

    List<int> toCrc = [ll, id2, id1, id0, cmd, ...payload];
    int crc = crc8(toCrc);

    return Uint8List.fromList([0x0C, ll, id2, id1, id0, cmd, ...payload, crc]);
  }

  /// Deserializa paquete de broadcast del protocolo Universal/Dominator AoooG
  static AoooGSensor? parseAdvertisement(ScanResult result) {
    List<int>? mData;
    // Buscar FFFF (Universal) o FF43 (AoooG)
    if (result.advertisementData.manufacturerData.containsKey(0xFFFF)) {
      mData = result.advertisementData.manufacturerData[0xFFFF];
    } else if (result.advertisementData.manufacturerData.containsKey(0xFF43)) {
      mData = result.advertisementData.manufacturerData[0xFF43];
    }

    if (mData == null || mData.length < 24) {
      return null;
    }

    // Firma: 3F 36 B4
    if (mData[0] != 0x3F || mData[1] != 0x36 || mData[2] != 0xB4) {
      return null;
    }

    int sensorId = (mData[6] << 16) | (mData[7] << 8) | mData[8];
    int freq = (mData[14] << 8) | mData[15];
    int emptyFreq = (mData[18] << 8) | mData[19];
    int outRaw = (mData[20] << 8) | mData[21];
    int temp = mData[22] - 40;
    int batt = mData[23];

    return AoooGSensor(
      device: result.device,
      id: sensorId,
      mac: result.device.remoteId.str,
      rssi: result.rssi,
      frequency: freq.toDouble(),
      emptyFreq: emptyFreq.toDouble(),
      output: outRaw.toDouble(),
      temperature: temp,
      battery: batt,
    );
  }
}
