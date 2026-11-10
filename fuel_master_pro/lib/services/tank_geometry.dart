import 'dart:math' as math;

class TankGeometryEngine {
  /// Retorna el volumen en Litros correspondiente a una altura hMm dada
  static double calculateVolumeAtHeight({
    required String tankType,
    required double length,
    required double width,
    required double height,
    required double thickness,
    required bool isExternal,
    required double hMm,
    // Radios transversales
    double rInfLi = 0,
    double rInfLd = 0,
    double rSupLi = 0,
    double rSupLd = 0,
    // Radios longitudinales
    double rInfAf = 0,
    double rInfAp = 0,
    double rSupAf = 0,
    double rSupAp = 0,
    // Radio aristas verticales
    double rVert = 0,
    // Escalón retroexcavadora
    double stepWidth = 0,
    double stepHeight = 0,
    String stepSide = 'bottom_right',
    // Doble estanque
    double tank2Length = 0,
    double tank2Width = 0,
    double tank2Height = 0,
    // Forma D
    double dRBottomFront = 200,
    double dRTopFront = 100,
    double dRBackCorners = 40,
    String cylHead = 'flat',
  }) {
    final dimensions = [length, width, height, thickness, hMm];
    if (dimensions.any((value) => !value.isFinite) ||
        length <= 0 || width <= 0 || height <= 0 || thickness < 0) {
      return 0.0;
    }
    const supportedTypes = {
      'rectangular',
      'cylinder_horizontal',
      'elliptical_horizontal',
      'd_shape',
      'step_notch',
      'double_tank',
    };
    final geometryValues = [
      rInfLi, rInfLd, rSupLi, rSupLd,
      rInfAf, rInfAp, rSupAf, rSupAp, rVert,
      stepWidth, stepHeight,
      tank2Length, tank2Width, tank2Height,
      dRBottomFront, dRTopFront, dRBackCorners,
    ];
    if (!supportedTypes.contains(tankType) ||
        geometryValues.any((value) => !value.isFinite || value < 0) ||
        !{'bottom_right', 'bottom_left', 'top_right'}.contains(stepSide) ||
        !{'flat', 'hemispherical'}.contains(cylHead)) {
      return 0.0;
    }

    final t = isExternal ? thickness : 0.0;
    if (2 * t >= length || 2 * t >= width || 2 * t >= height) return 0.0;

    final effL = length - 2 * t;
    final effW = width - 2 * t;
    final effH = height - 2 * t;
    final effH2 = tank2Height > 0
        ? math.max(10.0, tank2Height - (isExternal ? 2 * thickness : 0.0)).toDouble()
        : effH;
    final integrationHeight = (tankType == 'double_tank' ? math.max(effH, effH2) : effH).toDouble();
    final zClamped = math.max(0.0, math.min(integrationHeight, hMm)).toDouble();
    if (zClamped <= 0.0) return 0.0;

    // Replica el aforo web: suma áreas en el punto medio de cada milímetro
    // y aplica interpolación lineal para alturas fraccionarias.
    double sliceArea(double z) => _getSliceArea(
          z: z,
          type: tankType,
          L: effL,
          W: effW,
          H: effH,
          t: t,
          rInfLi: rInfLi,
          rInfLd: rInfLd,
          rSupLi: rSupLi,
          rSupLd: rSupLd,
          rInfAf: rInfAf,
          rInfAp: rInfAp,
          rSupAf: rSupAf,
          rSupAp: rSupAp,
          rVert: rVert,
          stepWidth: stepWidth,
          stepHeight: stepHeight,
          stepSide: stepSide,
          tank2Length: tank2Length,
          tank2Width: tank2Width,
          tank2Height: tank2Height,
          dRBottomFront: dRBottomFront,
          dRTopFront: dRTopFront,
          dRBackCorners: dRBackCorners,
          cylHead: cylHead,
        );

    final wholeMillimetres = zClamped.floor();
    double totalVolumeLitres = 0.0;
    for (var level = 1; level <= wholeMillimetres; level++) {
      totalVolumeLitres += sliceArea(level - 0.5) / 1000000.0;
    }
    final fractionalMillimetre = zClamped - wholeMillimetres;
    if (fractionalMillimetre > 0) {
      totalVolumeLitres +=
          fractionalMillimetre * sliceArea(wholeMillimetres + 0.5) / 1000000.0;
    }
    return totalVolumeLitres;
  }

  static double _getSliceArea({
    required double z,
    required String type,
    required double L,
    required double W,
    required double H,
    required double t,
    required double rInfLi,
    required double rInfLd,
    required double rSupLi,
    required double rSupLd,
    required double rInfAf,
    required double rInfAp,
    required double rSupAf,
    required double rSupAp,
    required double rVert,
    required double stepWidth,
    required double stepHeight,
    required String stepSide,
    required double tank2Length,
    required double tank2Width,
    required double tank2Height,
    required double dRBottomFront,
    required double dRTopFront,
    required double dRBackCorners,
    required String cylHead,
  }) {
    if (type == 'cylinder_horizontal') {
      double R = H / 2.0;
      double dist = (R - z).abs();
      if (dist >= R) return 0.0;
      final radiusAtHeight = math.sqrt(math.max(0.0, R * R - dist * dist));
      final chordW = 2.0 * radiusAtHeight;
      var area = chordW * L;
      if (cylHead == 'hemispherical') {
        area += math.pi * radiusAtHeight * radiusAtHeight;
      }
      return area;
    } else if (type == 'elliptical_horizontal') {
      double a = W / 2.0;
      double b = H / 2.0;
      double dist = (b - z).abs();
      if (dist >= b) return 0.0;
      double chordW = 2.0 * a * math.sqrt(math.max(0.0, 1.0 - math.pow(dist / b, 2)));
      return chordW * L;
    } else if (type == 'step_notch') {
      double sw = math.min(W * 0.9, stepWidth).toDouble();
      double sh = math.min(H * 0.9, stepHeight).toDouble();
      double effW = W;
      if (stepSide == 'bottom_right' || stepSide == 'bottom_left') {
        effW = (z < sh) ? math.max(0.0, W - sw).toDouble() : W;
      } else {
        effW = (z > (H - sh)) ? math.max(0.0, W - sw).toDouble() : W;
      }
      return effW * L;
    } else if (type == 'double_tank') {
      double L2 = tank2Length > 0 ? math.max(10.0, tank2Length - 2 * t).toDouble() : L;
      double W2 = tank2Width > 0 ? math.max(10.0, tank2Width - 2 * t).toDouble() : W;
      double H2 = tank2Height > 0 ? math.max(10.0, tank2Height - 2 * t).toDouble() : H;
      double a1 = (z <= H) ? (W * L) : 0.0;
      double a2 = (z <= H2) ? (W2 * L2) : 0.0;
      return a1 + a2;
    } else if (type == 'd_shape') {
      dRBottomFront = math.min(math.min(W * 0.8, H * 0.8), dRBottomFront).toDouble();
      dRTopFront = math.min(math.min(W * 0.8, H * 0.8), dRTopFront).toDouble();
      dRBackCorners = math.min(math.min(W * 0.2, H * 0.2), dRBackCorners).toDouble();
      double dxFront = 0.0;
      if (z < dRBottomFront && dRBottomFront > 0) {
        dxFront = dRBottomFront - math.sqrt(math.max(0.0, dRBottomFront * dRBottomFront - math.pow(dRBottomFront - z, 2)));
      } else if (z > (H - dRTopFront) && dRTopFront > 0) {
        double dz = z - (H - dRTopFront);
        dxFront = dRTopFront - math.sqrt(math.max(0.0, dRTopFront * dRTopFront - dz * dz));
      }

      double dxBack = 0.0;
      if (z < dRBackCorners && dRBackCorners > 0) {
        dxBack = dRBackCorners - math.sqrt(math.max(0.0, dRBackCorners * dRBackCorners - math.pow(dRBackCorners - z, 2)));
      } else if (z > (H - dRBackCorners) && dRBackCorners > 0) {
        double dz = z - (H - dRBackCorners);
        dxBack = dRBackCorners - math.sqrt(math.max(0.0, dRBackCorners * dRBackCorners - dz * dz));
      }
      double effW = math.max(0.0, W - dxFront - dxBack).toDouble();
      return effW * L;
    } else {
      // Rectangular con radios
      rInfLi = math.min(math.min(W / 2.0, H / 2.0), rInfLi).toDouble();
      rInfLd = math.min(math.min(W / 2.0, H / 2.0), rInfLd).toDouble();
      rSupLi = math.min(math.min(W / 2.0, H / 2.0), rSupLi).toDouble();
      rSupLd = math.min(math.min(W / 2.0, H / 2.0), rSupLd).toDouble();
      rInfAf = math.min(math.min(L / 2.0, H / 2.0), rInfAf).toDouble();
      rInfAp = math.min(math.min(L / 2.0, H / 2.0), rInfAp).toDouble();
      rSupAf = math.min(math.min(L / 2.0, H / 2.0), rSupAf).toDouble();
      rSupAp = math.min(math.min(L / 2.0, H / 2.0), rSupAp).toDouble();

      double dxL = 0.0;
      if (z < rInfLi && rInfLi > 0) {
        dxL = rInfLi - math.sqrt(math.max(0.0, rInfLi * rInfLi - math.pow(rInfLi - z, 2)));
      } else if (z > (H - rSupLi) && rSupLi > 0) {
        double dz = z - (H - rSupLi);
        dxL = rSupLi - math.sqrt(math.max(0.0, rSupLi * rSupLi - dz * dz));
      }

      double dxR = 0.0;
      if (z < rInfLd && rInfLd > 0) {
        dxR = rInfLd - math.sqrt(math.max(0.0, rInfLd * rInfLd - math.pow(rInfLd - z, 2)));
      } else if (z > (H - rSupLd) && rSupLd > 0) {
        double dz = z - (H - rSupLd);
        dxR = rSupLd - math.sqrt(math.max(0.0, rSupLd * rSupLd - dz * dz));
      }

      double dyF = 0.0;
      if (z < rInfAf && rInfAf > 0) {
        dyF = rInfAf - math.sqrt(math.max(0.0, rInfAf * rInfAf - math.pow(rInfAf - z, 2)));
      } else if (z > (H - rSupAf) && rSupAf > 0) {
        double dz = z - (H - rSupAf);
        dyF = rSupAf - math.sqrt(math.max(0.0, rSupAf * rSupAf - dz * dz));
      }

      double dyB = 0.0;
      if (z < rInfAp && rInfAp > 0) {
        dyB = rInfAp - math.sqrt(math.max(0.0, rInfAp * rInfAp - math.pow(rInfAp - z, 2)));
      } else if (z > (H - rSupAp) && rSupAp > 0) {
        double dz = z - (H - rSupAp);
        dyB = rSupAp - math.sqrt(math.max(0.0, rSupAp * rSupAp - dz * dz));
      }

      double effW = math.max(0.0, W - dxL - dxR).toDouble();
      double effL = math.max(0.0, L - dyF - dyB).toDouble();
      double area = effW * effL;

      final verticalRadius = math.min(math.min(W / 4.0, L / 4.0), rVert).toDouble();
      if (verticalRadius > 0) {
        area -= (4.0 - math.pi) * verticalRadius * verticalRadius;
      }
      return math.max(0.0, area).toDouble();
    }
  }

  /// Triangulación capacitiva inversa:
  /// Convierte la frecuencia medida f(Hz) a coordenada de calibración 0..5000
  static double frequencyToFixValue({
    required double freqHz,
    required double emptyFreqHz,
    required double fullFreqHz,
  }) {
    if (!freqHz.isFinite || !emptyFreqHz.isFinite || !fullFreqHz.isFinite ||
        freqHz <= 0 || emptyFreqHz <= 0 || fullFreqHz <= 0 || emptyFreqHz == fullFreqHz) {
      return 0.0;
    }
    // Capacidad C es proporcional a 1/f
    double invEmpty = 1.0 / emptyFreqHz;
    double invFull = 1.0 / fullFreqHz;
    double invCur = 1.0 / freqHz;

    double frac = (invCur - invEmpty) / (invFull - invEmpty);
    frac = math.max(0.0, math.min(1.0, frac)).toDouble();

    return frac * 5000.0; // Rango de fix_value del protocolo AoooG
  }

  /// Retorna la frecuencia esperada f(Hz) para una coordenada fix_value dada (0..5000)
  static double fixValueToFrequency({
    required double fixValue,
    required double emptyFreqHz,
    required double fullFreqHz,
  }) {
    if (!fixValue.isFinite || !emptyFreqHz.isFinite || !fullFreqHz.isFinite ||
        emptyFreqHz <= 0 || fullFreqHz <= 0) {
      return 0.0;
    }
    double frac = math.max(0.0, math.min(1.0, fixValue / 5000.0)).toDouble();
    double invEmpty = 1.0 / emptyFreqHz;
    double invFull = 1.0 / fullFreqHz;
    double invCur = invEmpty + (invFull - invEmpty) * frac;
    if (invCur <= 0) return emptyFreqHz;
    return 1.0 / invCur;
  }
}
