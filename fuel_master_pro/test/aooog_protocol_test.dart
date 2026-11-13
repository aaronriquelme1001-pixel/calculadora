import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_master_pro/services/aooog_ble.dart';

void main() {
  group('AoooG AG-BFLS public protocol', () {
    test('builds and validates CRC-8/MAXIM-DOW command frames', () {
      final frame = AoooGProtocol.buildFrame(999999, 0x14, const []);
      expect(frame, [0x0c, 0x05, 0x0f, 0x42, 0x3f, 0x14, 0xff]);
      expect(AoooGProtocol.isValidFrame(frame, expectedSensorId: 999999, expectedCommand: 0x14), isTrue);
      final corrupted = Uint8List.fromList(frame)..[6] ^= 0xff;
      expect(AoooGProtocol.isValidFrame(corrupted), isFalse);
    });

    test('uses official battery floor conversion and signed int8 decoding', () {
      expect(AoooGProtocol.batteryPercent(700), 90);
      expect(AoooGProtocol.batteryPercent(715), 97);
      expect(AoooGProtocol.signedInt8(0xfc), -4);
      expect(AoooGProtocol.signedInt8(0x04), 4);
    });

    test('decodes the 13-byte 0x0D parameters layout', () {
      final bytes = Uint8List(13);
      final view = ByteData.sublistView(bytes);
      bytes[0] = 20;
      bytes[2] = 1;
      bytes[3] = 0xfc;
      view.setFloat32(4, 15000, Endian.little);
      view.setFloat32(8, 10000, Endian.little);
      bytes[12] = 2;
      final parsed = AoooGProtocol.parseParameters(bytes);
      expect(parsed?['broadcastInterval'], 20);
      expect(parsed?['continueAfterRestart'], isTrue);
      expect(parsed?['transmitPower'], -4);
      expect(parsed?['emptyFreq'], 15000);
      expect(parsed?['fullFreq'], 10000);
      expect(parsed?['outputMode'], 2);
    });

    test('decodes firmware, BLE address, advertising mode and calibration coordinate', () {
      expect(AoooGProtocol.parseFirmwareVersion([8, 27]), '8.27');
      expect(AoooGProtocol.parseBleAddress([0x66, 0x55, 0x44, 0x33, 0x22, 0x11]),
          '11:22:33:44:55:66');
      expect(AoooGProtocol.parseAdvertisingProtocol([0]), 0);
      expect(AoooGProtocol.parseAdvertisingProtocol([1]), 1);
      final coordinate = Uint8List(4);
      ByteData.sublistView(coordinate).setFloat32(0, 2500, Endian.little);
      expect(AoooGProtocol.parseCalibrationCoordinate(coordinate), 2500);
      expect(AoooGProtocol.parseCalibrationCoordinate([0, 0, 0]), isNull);
    });

    test('marks only documented protected commands as requiring authentication', () {
      for (final command in [0x01, 0x02, 0x04, 0x0a, 0x0c, 0x10, 0x11, 0x16]) {
        expect(AoooGProtocol.isProtectedCommand(command), isTrue);
      }
      for (final command in [0x05, 0x0b, 0x0d, 0x12, 0x14, 0x15, 0x19, 0x1a, 0x1b, 0x20, 0x21, 0x22, 0x26]) {
        expect(AoooGProtocol.isProtectedCommand(command), isFalse);
      }
    });
  });
}
