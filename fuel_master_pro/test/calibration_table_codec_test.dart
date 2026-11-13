import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_master_pro/services/calibration_table_codec.dart';

void main() {
  group('CalibrationTableCodec - formato oficial Fuel Master', () {
    final reference = <List<Object?>>[
      ['Data', 'Level', 'Volume'], [0, 0, 0], [100, 20, 6.6], [281, 39, 14.2], [463, 59, 23.0], [644, 78, 31.8], [826, 98, 41.3], [1007, 117, 50.3], [1189, 137, 59.9], [1370, 156, 68.9], [1552, 176, 78.4], [1733, 195, 87.5], [1915, 215, 97.0], [2096, 234, 106.0], [2278, 254, 115.6], [2459, 273, 124.6], [2641, 293, 134.1], [2822, 312, 143.2], [3004, 332, 152.7], [3185, 351, 161.8], [3367, 371, 171.3], [3548, 390, 180.3], [3730, 410, 189.9], [3911, 429, 198.9], [4093, 449, 208.4], [4274, 468, 217.4], [4456, 488, 226.7], [4637, 507, 235.0], [4819, 527, 243.0], [5000, 546, 249.2],
    ];
    test('preserves all 29 reference records and Data/Level/Volume values', () {
      final rows = CalibrationTableCodec.parseMatrix(reference, emptyFreqHz: 15000, fullFreqHz: 10000);
      expect(rows, hasLength(29));
      expect([rows[1].fixValue, rows[1].levelMm, rows[1].volumeL], [100, 20, 6.6]);
      expect([rows.last.fixValue, rows.last.levelMm, rows.last.volumeL], [5000, 546, 249.2]);
    });
    test('maps reordered columns using explicit headers', () {
      final rows = CalibrationTableCodec.parseMatrix([['Volume (L)', 'Data', 'Level (mm)'], [0, 0, 0], [6.6, 100, 20], [249.2, 5000, 546]], emptyFreqHz: 15000, fullFreqHz: 10000);
      expect(rows.map((r) => r.fixValue), [0, 100, 5000]);
      expect(rows.last.volumeL, 249.2);
    });
    test('supports semicolon CSV and decimal comma', () {
      final rows = CalibrationTableCodec.parseDelimitedText('Data;Level;Volume\r\n0;0;0\r\n100;20;6,6\r\n5000;546;249,2', emptyFreqHz: 15000, fullFreqHz: 10000);
      expect(rows, hasLength(3)); expect(rows[1].volumeL, closeTo(6.6, 1e-6)); expect(rows.last.volumeL, closeTo(249.2, 1e-6));
    });
    test('rejects malformed cells instead of silently coercing to zero', () {
      expect(() => CalibrationTableCodec.parseMatrix([['Data', 'Level', 'Volume'], [0, 0, 0], ['bad', 20, 6.6]], emptyFreqHz: 15000, fullFreqHz: 10000), throwsFormatException);
    });
    test('rejects non-monotonic and out-of-range coordinates', () {
      expect(() => CalibrationTableCodec.parseMatrix([['Data', 'Level', 'Volume'], [0, 0, 0], [100, 20, 6.6], [90, 30, 9]], emptyFreqHz: 15000, fullFreqHz: 10000), throwsFormatException);
      expect(() => CalibrationTableCodec.parseMatrix([['Data', 'Level', 'Volume'], [0, 0, 0], [5001, 20, 6.6]], emptyFreqHz: 15000, fullFreqHz: 10000), throwsFormatException);
    });
  });
}
