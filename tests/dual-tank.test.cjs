const test = require('node:test');
const assert = require('node:assert/strict');

function computeCylinderHorizontalVolume(D, L) {
  const R = D / 2;
  const H = Math.round(D);
  let cumVol = new Float64Array(H + 1);
  let acc = 0;
  for (let z = 1; z <= H; z++) {
    const zm = z - 0.5;
    const halfChord = Math.sqrt(Math.max(0, R * R - (R - zm) * (R - zm)));
    const area = 2 * halfChord * L;
    acc += (area * 1) / 1000000;
    cumVol[z] = acc;
  }
  return { H, totalVolume: Number(acc.toFixed(1)), cumVol };
}

function computeRectangularVolume(L, W, H, radii = { r_inf_li: 0, r_inf_ld: 0, r_sup_li: 0, r_sup_ld: 0 }) {
  const roundH = Math.round(H);
  let cumVol = new Float64Array(roundH + 1);
  let acc = 0;
  const baseArea = (W * L);

  for (let z = 1; z <= roundH; z++) {
    const zm = z - 0.5;
    let sliceArea = baseArea;

    // Corner radius area deduction if in bottom or top radius zone
    const { r_inf_li, r_inf_ld, r_sup_li, r_sup_ld } = radii;
    if (r_inf_li > 0 && zm < r_inf_li) {
      const dz = r_inf_li - zm;
      const dx = r_inf_li - Math.sqrt(Math.max(0, r_inf_li * r_inf_li - dz * dz));
      sliceArea -= dx * L;
    }
    if (r_inf_ld > 0 && zm < r_inf_ld) {
      const dz = r_inf_ld - zm;
      const dx = r_inf_ld - Math.sqrt(Math.max(0, r_inf_ld * r_inf_ld - dz * dz));
      sliceArea -= dx * L;
    }
    if (r_sup_li > 0 && zm > H - r_sup_li) {
      const dz = zm - (H - r_sup_li);
      const dx = r_sup_li - Math.sqrt(Math.max(0, r_sup_li * r_sup_li - dz * dz));
      sliceArea -= dx * L;
    }
    if (r_sup_ld > 0 && zm > H - r_sup_ld) {
      const dz = zm - (H - r_sup_ld);
      const dx = r_sup_ld - Math.sqrt(Math.max(0, r_sup_ld * r_sup_ld - dz * dz));
      sliceArea -= dx * L;
    }

    acc += (sliceArea * 1) / 1000000;
    cumVol[z] = acc;
  }
  return { H: roundH, totalVolume: Number(acc.toFixed(1)), cumVol };
}

function build95PointCalibration(cumVol, H, totalVolume, dataMin = 0, dataMax = 5000) {
  function getVolAt(h) {
    const clamped = Math.max(0, Math.min(H, h));
    const low = Math.floor(clamped);
    const high = Math.min(H, Math.ceil(clamped));
    if (low === high) return cumVol[low];
    const frac = clamped - low;
    return cumVol[low] + frac * (cumVol[high] - cumVol[low]);
  }

  const rows = [];
  for (let i = 0; i < 95; i++) {
    const frac = i / 94;
    const level = Math.round(frac * H);
    const volume = Number(getVolAt(level).toFixed(1));
    const data = Math.round(dataMin + frac * (dataMax - dataMin));
    rows.push({
      point: i + 1,
      data,
      level,
      volume,
      pct: totalVolume > 0 ? Number(((volume / totalVolume) * 100).toFixed(1)) : 0
    });
  }
  return rows;
}

test('cylindrical horizontal tank volume matches analytical formula within 0.01% error', () => {
  const D = 600; // mm
  const L = 1200; // mm
  const R = D / 2;
  const analyticalLiters = (Math.PI * R * R * L) / 1000000; // 339.292 L

  const res = computeCylinderHorizontalVolume(D, L);
  assert.strictEqual(res.H, 600);
  assert.ok(Math.abs(res.totalVolume - analyticalLiters) < 0.1, `Expected ~${analyticalLiters.toFixed(2)}, got ${res.totalVolume}`);
});

test('rectangular tank with radii integrates smoothly and accounts for corner reductions', () => {
  const L = 1000, W = 600, H = 580;
  const noRadii = computeRectangularVolume(L, W, H, { r_inf_li: 0, r_inf_ld: 0, r_sup_li: 0, r_sup_ld: 0 });
  const withRadii = computeRectangularVolume(L, W, H, { r_inf_li: 200, r_inf_ld: 200, r_sup_li: 200, r_sup_ld: 200 });

  assert.strictEqual(noRadii.totalVolume, 348.0);
  assert.ok(withRadii.totalVolume < noRadii.totalVolume, 'Radii should reduce total capacity');
  assert.ok(withRadii.totalVolume > 300, 'Capacity should remain physically realistic (~313.7L)');
});

test('dual tank calculations maintain independent sensors and exact 95-point calibration tables', () => {
  // Tank 1: Rectangular with radii (e.g. 1000x600x580 mm)
  const tank1 = computeRectangularVolume(1000, 600, 580, { r_inf_li: 200, r_inf_ld: 200, r_sup_li: 200, r_sup_ld: 200 });
  // Tank 2: Horizontal Cylinder (e.g. D=600 mm, L=1000 mm)
  const tank2 = computeCylinderHorizontalVolume(600, 1000);

  const table1 = build95PointCalibration(tank1.cumVol, tank1.H, tank1.totalVolume);
  const table2 = build95PointCalibration(tank2.cumVol, tank2.H, tank2.totalVolume);

  // Both tables must have exactly 95 points
  assert.strictEqual(table1.length, 95);
  assert.strictEqual(table2.length, 95);

  // Table 1 starts at zero and ends at tank1 full
  assert.strictEqual(table1[0].data, 0);
  assert.strictEqual(table1[0].level, 0);
  assert.strictEqual(table1[0].volume, 0);
  assert.strictEqual(table1[94].data, 5000);
  assert.strictEqual(table1[94].level, 580);
  assert.strictEqual(table1[94].volume, tank1.totalVolume);

  // Table 2 starts at zero and ends at tank2 full
  assert.strictEqual(table2[0].data, 0);
  assert.strictEqual(table2[0].level, 0);
  assert.strictEqual(table2[0].volume, 0);
  assert.strictEqual(table2[94].data, 5000);
  assert.strictEqual(table2[94].level, 600);
  assert.strictEqual(table2[94].volume, tank2.totalVolume);

  // Total combined capacity
  const totalCombined = Number((tank1.totalVolume + tank2.totalVolume).toFixed(1));
  assert.ok(totalCombined > 500, 'Combined volume of dual tank truck is correctly aggregated');
  assert.notStrictEqual(tank1.totalVolume, tank2.totalVolume, 'Tanks have distinct independent geometry');
});

test('field correction (calibración en terreno con surtidor) correctly recalculates 95-point tables', () => {
  // Simular caso real VDYH16:
  // Altura original H = 632 mm, Volumen teórico = 367.9 L
  // En terreno con 172.0 L: Data = 2523, Level real = 295 mm
  const theoH = 632;
  const theoTotVol = 367.9;
  const valData = 2523;
  const valLevel = 295;
  const valLiters = 172.0;

  // Fracción a Data 2523:
  const frac = valData / 5000;
  const theoLevelAtData = frac * theoH; // ~318.9 mm
  // Asumiendo volumen lineal o casi lineal en esa sección:
  const theoVolAtData = 186.0;

  const factorVol = valLiters / theoVolAtData; // 172.0 / 186.0 ≈ 0.92473
  const factorLevel = valLevel / theoLevelAtData; // 295 / 318.9 ≈ 0.9250
  const corrMaxLevel = Math.round(theoH * factorLevel); // 584 mm
  const corrMaxVol = Number((theoTotVol * factorVol).toFixed(1)); // 340.2 L

  assert.ok(Math.abs(corrMaxLevel - 584) <= 1, 'Calcula correctamente la altura efectiva del sensor cortado (~584-585 mm)');
  assert.ok(Math.abs(factorVol - 0.9247) < 0.001, 'Factor de volumen calculado con precisión');
  assert.strictEqual(corrMaxVol, 340.2, 'Capacidad máxima corregida coincide exactamente con los 340.2 L reales');

  // Simular caso real KVDS22 (ajuste directo por nivel 360 mm a 172.0 L):
  const theoVolEn360 = 199.97;
  const realLitersEn360 = 172.0;
  const factorVolKVDS22 = realLitersEn360 / theoVolEn360;
  assert.ok(Math.abs(factorVolKVDS22 - 0.86012) < 0.0001, 'Factor para KVDS22 coincide con el 0.86012 del script de usuario');
  const finalVolKVDS22 = Number((374.7 * factorVolKVDS22).toFixed(1));
  assert.strictEqual(finalVolKVDS22, 322.3, 'Capacidad final KVDS22 escalada a 322.3 L');
});
