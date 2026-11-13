import 'dart:math' as math;

import 'aooog_manager.dart';

/// Importación y validación de tablas AOOG BFLS. Data se conserva como fixValue.
class CalibrationTableCodec {
  static List<CalibrationRow> parseMatrix(List<List<Object?>> matrix, {required double emptyFreqHz, required double fullFreqHz}) {
    if (matrix.isEmpty) throw const FormatException('La hoja no contiene filas.');
    var dataCol = -1, levelCol = -1, volumeCol = -1, headerRow = -1;
    for (var r = 0; r < math.min(matrix.length, 10); r++) {
      final cells = matrix[r];
      for (var c = 0; c < cells.length; c++) {
        final h = _normalize(cells[c]?.toString() ?? '');
        if (_isDataHeader(h)) dataCol = c;
        if (_isLevelHeader(h)) levelCol = c;
        if (_isVolumeHeader(h)) volumeCol = c;
      }
      if (dataCol >= 0 && levelCol >= 0 && volumeCol >= 0 && dataCol != levelCol && dataCol != volumeCol && levelCol != volumeCol) { headerRow = r; break; }
      dataCol = levelCol = volumeCol = -1;
    }
    if (headerRow < 0) { dataCol = 0; levelCol = 1; volumeCol = 2; headerRow = -1; }
    final rows = <CalibrationRow>[];
    for (var r = headerRow + 1; r < matrix.length; r++) {
      final cells = matrix[r];
      if (cells.every((v) => v == null || v.toString().trim().isEmpty)) continue;
      final data = _number(_cell(cells, dataCol), 'Data', r + 1);
      final level = _number(_cell(cells, levelCol), 'Level', r + 1);
      final volume = _number(_cell(cells, volumeCol), 'Volume', r + 1);
      if (data != data.roundToDouble()) throw FormatException('Data debe ser entero en fila ${r + 1}.');
      if (level != level.roundToDouble()) throw FormatException('Level debe ser entero en fila ${r + 1}.');
      if (data < 0 || data > 5000) throw FormatException('Data fuera de rango 0..5000 en fila ${r + 1}.');
      if (level < 0 || level > 65535) throw FormatException('Level fuera de rango uint16 en fila ${r + 1}.');
      if (volume < 0) throw FormatException('Volume no puede ser negativo en fila ${r + 1}.');
      final fix = data.toInt(), mm = level.toInt();
      rows.add(CalibrationRow(index: rows.length, volumeL: volume, levelMm: mm, fixValue: fix, expectedFreqHz: _frequencyForFix(fix, emptyFreqHz, fullFreqHz)));
      if (rows.length > 100) throw const FormatException('La tabla supera los 100 registros admitidos.');
    }
    if (rows.isEmpty) throw const FormatException('No se encontraron registros numéricos.');
    if (rows.first.fixValue != 0 || rows.first.levelMm != 0 || rows.first.volumeL != 0) rows.insert(0, CalibrationRow(index: 0, volumeL: 0, levelMm: 0, fixValue: 0, expectedFreqHz: emptyFreqHz));
    final indexed = [for (var i = 0; i < rows.length; i++) CalibrationRow(index: i, volumeL: rows[i].volumeL, levelMm: rows[i].levelMm, fixValue: rows[i].fixValue, expectedFreqHz: rows[i].expectedFreqHz)];
    validate(indexed);
    return indexed;
  }
  static List<CalibrationRow> parseDelimitedText(String text, {required double emptyFreqHz, required double fullFreqHz}) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) throw const FormatException('El archivo está vacío.');
    final first = lines.first; final delimiter = first.contains(';') ? ';' : (first.contains('\t') ? '\t' : ',');
    return parseMatrix([for (final line in lines) _splitDelimited(line, delimiter)], emptyFreqHz: emptyFreqHz, fullFreqHz: fullFreqHz);
  }
  static void validate(List<CalibrationRow> rows) {
    if (rows.length < 2 || rows.length > 100) throw const FormatException('La tabla debe contener entre 2 y 100 registros.');
    if (rows.first.fixValue != 0 || rows.first.levelMm != 0 || rows.first.volumeL != 0) throw const FormatException('El primer registro debe ser 0 / 0 / 0.');
    var previousFix = -1, previousLevel = -1; var previousVolume = -1.0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.index != i) throw FormatException('Índice inconsistente en registro ${i + 1}.');
      if (!row.volumeL.isFinite || row.volumeL < 0 || row.volumeL > 1000000 || row.levelMm < 0 || row.levelMm > 65535 || row.fixValue < 0 || row.fixValue > 5000) throw FormatException('Registro ${i + 1} fuera de rango.');
      if (i > 0 && (row.fixValue <= previousFix || row.levelMm <= previousLevel || row.volumeL < previousVolume)) throw FormatException('Data y Level deben crecer; Volume no puede disminuir (registro ${i + 1}).');
      row.toBytes(); previousFix = row.fixValue; previousLevel = row.levelMm; previousVolume = row.volumeL;
    }
    if (rows.last.volumeL <= 0 || rows.last.levelMm <= 0 || rows.last.fixValue <= 0) throw const FormatException('El último registro debe tener volumen y nivel positivos.');
  }
  static String _normalize(String value) => value.toLowerCase().trim().replaceAll('á', 'a').replaceAll('é', 'e').replaceAll('í', 'i').replaceAll('ó', 'o').replaceAll('ú', 'u').replaceAll('ü', 'u').replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  static bool _isDataHeader(String h) => h == 'data' || h == 'dato' || h.contains('fix') || h.contains('coordenada') || h == 'sensor data';
  static bool _isLevelHeader(String h) => h == 'level' || h == 'nivel' || h.contains('level mm') || h.contains('nivel mm') || h == 'mm';
  static bool _isVolumeHeader(String h) => h == 'volume' || h == 'volumen' || h == 'vol' || h.contains('volume l') || h.contains('volumen l') || h.contains('litro') || h == 'capacity';
  static Object? _cell(List<Object?> row, int index) => index >= 0 && index < row.length ? row[index] : null;
  static double _number(Object? raw, String field, int row) {
    if (raw == null || raw.toString().trim().isEmpty) throw FormatException('$field vacío en fila $row.');
    if (raw is num && raw.toDouble().isFinite) return raw.toDouble();
    var value = raw.toString().trim().replaceAll(' ', '');
    if (value.contains(',') && value.contains('.')) value = value.replaceAll('.', '').replaceAll(',', '.'); else if (value.contains(',')) value = value.replaceAll(',', '.');
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) throw FormatException('$field no es numérico en fila $row: "$raw".');
    return parsed;
  }
  static List<Object?> _splitDelimited(String line, String delimiter) {
    final cells = <Object?>[]; final buffer = StringBuffer(); var quoted = false;
    for (var i = 0; i < line.length; i++) { final char = line[i]; if (char == '"') { if (quoted && i + 1 < line.length && line[i + 1] == '"') { buffer.write('"'); i++; } else { quoted = !quoted; } } else if (char == delimiter && !quoted) { cells.add(buffer.toString().trim()); buffer.clear(); } else { buffer.write(char); } }
    cells.add(buffer.toString().trim()); return cells;
  }
  static double _frequencyForFix(int fix, double empty, double full) {
    if (!empty.isFinite || !full.isFinite || empty <= 0 || full <= 0) return 0;
    final fraction = (fix / 5000).clamp(0.0, 1.0); final inverse = (1 / empty) + ((1 / full) - (1 / empty)) * fraction;
    return inverse > 0 ? 1 / inverse : 0;
  }
}
