import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_master_pro/services/tank_geometry.dart';
import 'package:fuel_master_pro/services/aooog_ble.dart';
import 'package:fuel_master_pro/services/aooog_manager.dart';

void main() {

  group('AoooG calibration record serialization', () {
    test('serializes each point as float32 LE + uint16 LE + uint16 LE', () {
      final row = CalibrationRow(
        index: 0,
        volumeL: 12.5,
        levelMm: 256,
        fixValue: 1234,
        expectedFreqHz: 12000,
      );
      final bytes = row.toBytes();
      final data = ByteData.sublistView(bytes);

      expect(bytes.length, 8);
      expect(data.getFloat32(0, Endian.little), closeTo(12.5, 1e-6));
      expect(data.getUint16(4, Endian.little), 256);
      expect(data.getUint16(6, Endian.little), 1234);
    });

    test('rejects values that cannot be represented by the device fields', () {
      final row = CalibrationRow(
        index: 0,
        volumeL: 1,
        levelMm: 100,
        fixValue: 5001,
        expectedFreqHz: 10000,
      );

      expect(row.toBytes, throwsArgumentError);
    });
  });

  group('AoooGProtocol framing', () {
    test('builds a frame with a consistent length and valid CRC', () {
      final frame = AoooGProtocol.buildFrame(
        0x123456,
        0x12,
        List<int>.filled(8, 0x31),
      );

      expect(frame.first, 0x0C);
      expect(frame[1], frame.length - 2);
      expect(
        AoooGProtocol.isValidFrame(
          frame,
          expectedSensorId: 0x123456,
          expectedCommand: 0x12,
        ),
        isTrue,
      );
    });

    test('rejects corrupted CRC and a response from another sensor', () {
      final frame = AoooGProtocol.buildFrame(0x123456, 0x12, [1, 2, 3]);
      final corrupted = List<int>.from(frame);
      corrupted[corrupted.length - 1] = corrupted.last ^ 0xFF;

      expect(AoooGProtocol.isValidFrame(corrupted), isFalse);
      expect(
        AoooGProtocol.isValidFrame(frame, expectedSensorId: 0x654321),
        isFalse,
      );
    });
  });
  group('AG-BFLS protocol response and calibration frame lengths', () {
    test('0x0D parameter response contains exactly 13 payload bytes', () {
      final response = AoooGProtocol.buildFrame(0x123456, 0x0D, List<int>.filled(13, 0));
      expect(response.length, 20);
      expect(AoooGProtocol.isValidFrame(response, expectedCommand: 0x0D), isTrue);
    });

    test('0x1B coordinate response contains exactly four payload bytes', () {
      final response = AoooGProtocol.buildFrame(0x123456, 0x1B, [0, 0, 0, 0]);
      expect(response.length, 11);
      expect(AoooGProtocol.isValidFrame(response, expectedCommand: 0x1B), isTrue);
    });

    test('0x16 calibration write frame is 88 bytes including framing and CRC', () {
      final frame = AoooGProtocol.buildFrame(0x123456, 0x16,
          [0, ...List<int>.filled(80, 0)]);
      expect(frame.length, 88);
      expect(frame[1], 86);
      expect(AoooGProtocol.isValidFrame(frame, expectedCommand: 0x16), isTrue);
    });

    test('0x15 read request carries only the start index', () {
      final frame = AoooGProtocol.buildFrame(0x123456, 0x15, [90]);
      expect(frame.length, 8);
      expect(frame[6], 90);
      expect(AoooGProtocol.isValidFrame(frame, expectedCommand: 0x15), isTrue);
    });
  });

  group('TankGeometryEngine', () {
    test('rectangular tank returns zero, half and full volume correctly', () {
      const length = 850.0;
      const width = 600.0;
      const height = 650.0;
      const expectedFullLitres = length * width * height / 1000000.0;

      double volumeAt(double level) => TankGeometryEngine.calculateVolumeAtHeight(
            tankType: 'rectangular',
            length: length,
            width: width,
            height: height,
            thickness: 0,
            isExternal: false,
            hMm: level,
          );

      expect(volumeAt(0), closeTo(0, 1e-9));
      expect(volumeAt(height / 2), closeTo(expectedFullLitres / 2, 1e-6));
      expect(volumeAt(height), closeTo(expectedFullLitres, 1e-6));
    });

    test('fractional fill height uses the same linear millimetre interpolation as web', () {
      const length = 850.0;
      const width = 600.0;
      const level = 123.25;
      final volume = TankGeometryEngine.calculateVolumeAtHeight(
        tankType: 'rectangular',
        length: length,
        width: width,
        height: 650,
        thickness: 0,
        isExternal: false,
        hMm: level,
      );

      expect(volume, closeTo(length * width * level / 1000000.0, 1e-9));
    });

    test('double tank includes a taller secondary tank above primary height', () {
      final volume = TankGeometryEngine.calculateVolumeAtHeight(
        tankType: 'double_tank',
        length: 100,
        width: 100,
        height: 100,
        thickness: 0,
        isExternal: false,
        hMm: 200,
        tank2Length: 100,
        tank2Width: 100,
        tank2Height: 200,
      );

      // Primary: 1 L. Secondary: 2 L. Equal liquid elevation in both tanks.
      expect(volume, closeTo(3.0, 1e-6));
    });

    test('horizontal cylinder full volume matches analytical capacity', () {
      const radius = 100.0;
      const length = 1000.0;
      final volume = TankGeometryEngine.calculateVolumeAtHeight(
        tankType: 'cylinder_horizontal',
        length: length,
        width: radius * 2,
        height: radius * 2,
        thickness: 0,
        isExternal: false,
        hMm: radius * 2,
      );
      final expected = math.pi * radius * radius * length / 1000000.0;

      expect(volume, closeTo(expected, 0.02));
    });

    test('hemispherical heads add one sphere to the cylindrical body', () {
      const radius = 100.0;
      const length = 1000.0;
      final volume = TankGeometryEngine.calculateVolumeAtHeight(
        tankType: 'cylinder_horizontal',
        length: length,
        width: radius * 2,
        height: radius * 2,
        thickness: 0,
        isExternal: false,
        hMm: radius * 2,
        cylHead: 'hemispherical',
      );
      final expected = (math.pi * radius * radius * length +
              (4.0 / 3.0) * math.pi * radius * radius * radius) /
          1000000.0;

      expect(volume, closeTo(expected, 0.02));
    });

    test('invalid dimensions do not fabricate a minimum-size tank', () {
      final volume = TankGeometryEngine.calculateVolumeAtHeight(
        tankType: 'rectangular',
        length: 0,
        width: 600,
        height: 650,
        thickness: 2,
        isExternal: true,
        hMm: 300,
      );

      expect(volume, 0);
    });
  });

  group('AoooG frequency conversion', () {
    test('frequency endpoints map to empty and full calibration values', () {
      expect(
        TankGeometryEngine.frequencyToFixValue(
          freqHz: 15000,
          emptyFreqHz: 15000,
          fullFreqHz: 10000,
        ),
        closeTo(0, 1e-9),
      );
      expect(
        TankGeometryEngine.frequencyToFixValue(
          freqHz: 10000,
          emptyFreqHz: 15000,
          fullFreqHz: 10000,
        ),
        closeTo(5000, 1e-9),
      );
      expect(
        TankGeometryEngine.fixValueToFrequency(
          fixValue: 2500,
          emptyFreqHz: 15000,
          fullFreqHz: 10000,
        ),
        closeTo(12000, 1e-6),
      );
    });

    test('zero and invalid frequencies are handled without infinity', () {
      expect(
        TankGeometryEngine.frequencyToFixValue(
          freqHz: 0,
          emptyFreqHz: 15000,
          fullFreqHz: 10000,
        ),
        0,
      );
      expect(
        TankGeometryEngine.fixValueToFrequency(
          fixValue: 2500,
          emptyFreqHz: 0,
          fullFreqHz: 10000,
        ),
        0,
      );
    });
  });
}
