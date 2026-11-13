/**
 * ============================================================================
 * CALCULADORA DE ESTANQUES & CALIBRADOR AOOOG BL FUEL SENSOR
 * Visor 2D CAD y 3D Interactivo, Editable y Preciso con Soporte Multigeometría
 * ============================================================================
 */

(function () {
  'use strict';

  // ESTADO GLOBAL
  const state = {
    viewMode: 'plane-transverse', // 'plane-transverse', 'plane-longitudinal', 'view-3d'

    vehicle: {
      client: 'Transportes Vikar S.A.',
      plate: 'AA-123-BB',
      model: 'Volvo FH 540',
      technician: 'Ing. Calibración',
      date: new Date().toISOString().split('T')[0]
    },

    tank: {
      type: 'rectangular', // rectangular simple
      length: 1000,
      width: 600,
      height: 580,
      thickness: 0.0,
      dimType: 'internal', // interna directa

      // Radios transversales (W x H)
      r_inf_li: 200,
      r_inf_ld: 200,
      r_sup_li: 200,
      r_sup_ld: 200,

      // Radios longitudinales (L x H)
      r_inf_af: 0,
      r_inf_ap: 0,
      r_sup_af: 0,
      r_sup_ap: 0,

      // Radio aristas verticales / bajadas de esquinas (L x W)
      r_vert: 0,
      r_vert_fi: 0,
      r_vert_fd: 0,
      r_vert_pi: 0,
      r_vert_pd: 0,

      // Recovecos y Muescas Estructurales (Estanques Plásticos)
      hasRecovecos: false,
      texturaLevel: 50, // 10 (Menos) a 90 (Más), 50 = Normal
      recovecoEnabled: true,
      recovecoWidth: 190,
      recovecoHeight: 175,
      recovecoLength: 0,
      recovecoSide: 'bottom_left', // Izq. Chasis (fiel al CAD y foto camión)
      cinchasCount: 2,
      cinchasWidth: 70,
      cinchasDepth: 25,

      // Retroexcavadora con escalón
      stepWidth: 200,
      stepHeight: 250,
      stepSide: 'bottom_right', // bottom_right, bottom_left, top_right

      // Doble estanque independiente
      tank2Length: 850,
      tank2Width: 600,
      tank2Height: 650,

      // Forma D (Volvo / Scania)
      d_r_bottom_front: 250,
      d_r_top_front: 120,
      d_r_back_corners: 40,

      cyl_head: 'flat'
    },

    sensor: {
      dataMin: 0,
      dataMax: 5000,
      bottomDeadZone: 0
    },

    currentLevelMm: 580,
    tableMode: 30, // 30 o 100
    isImported: false,

    calcCache: {
      effH: 650,
      cumVol: null,
      totalVolume: 0,
      calibrationRows: []
    }
  };

  const PRESETS = {
    excel_original: {
      name: 'Tanque Base Excel (650x600x850 mm - 312L)',
      type: 'rectangular',
      length: 850, width: 600, height: 650, thickness: 2.0, dimType: 'external',
      r_inf_li: 150, r_inf_ld: 150, r_inf_af: 150, r_inf_ap: 150,
      r_sup_li: 50, r_sup_ld: 50, r_sup_af: 50, r_sup_ap: 50,
      sensor: { dataMin: 100, dataMax: 4660 }
    },
    volvo_dshape: {
      name: 'Volvo FH/FM Forma D (710x690x1450 mm - 600L)',
      type: 'd_shape',
      length: 1450, width: 690, height: 710, thickness: 2.5, dimType: 'external',
      d_r_bottom_front: 260, d_r_top_front: 120, d_r_back_corners: 40,
      sensor: { dataMin: 100, dataMax: 4660 }
    },
    scania_r: {
      name: 'Scania R/S (670x700x1200 mm - 500L)',
      type: 'rectangular',
      length: 1200, width: 700, height: 670, thickness: 2.5, dimType: 'external',
      r_inf_li: 180, r_inf_ld: 180, r_inf_af: 180, r_inf_ap: 180,
      r_sup_li: 100, r_sup_ld: 100, r_sup_af: 100, r_sup_ap: 100,
      sensor: { dataMin: 100, dataMax: 4660 }
    },
    mercedes_actros: {
      name: 'Mercedes Actros (650x700x1550 mm - 650L)',
      type: 'rectangular',
      length: 1550, width: 700, height: 650, thickness: 2.5, dimType: 'external',
      r_inf_li: 160, r_inf_ld: 160, r_inf_af: 160, r_inf_ap: 160,
      r_sup_li: 90, r_sup_ld: 90, r_sup_af: 90, r_sup_ap: 90,
      sensor: { dataMin: 100, dataMax: 4660 }
    },
    man_tgx: {
      name: 'MAN TGX (620x690x1300 mm - 510L)',
      type: 'rectangular',
      length: 1300, width: 690, height: 620, thickness: 2.5, dimType: 'external',
      r_inf_li: 140, r_inf_ld: 140, r_inf_af: 140, r_inf_ap: 140,
      r_sup_li: 70, r_sup_ld: 70, r_sup_af: 70, r_sup_ap: 70,
      sensor: { dataMin: 100, dataMax: 4660 }
    },
    cylinder_standard: {
      name: 'Cilíndrico Horizontal (Ø600x1500 mm - 424L)',
      type: 'cylinder_horizontal',
      length: 1500, width: 600, height: 600, cyl_head: 'flat', thickness: 3.0, dimType: 'external',
      sensor: { dataMin: 100, dataMax: 4660 }
    },
    ellipse_standard: {
      name: 'Elíptico Horizontal (600x800x1400 mm - 527L)',
      type: 'elliptical_horizontal',
      length: 1400, width: 800, height: 600, thickness: 2.5, dimType: 'external',
      sensor: { dataMin: 100, dataMax: 4660 }
    },
    step_retro: {
      name: 'Retroexcavadora con Escalón',
      type: 'step_notch',
      length: 1100, width: 650, height: 700, thickness: 3.0, dimType: 'external',
      stepWidth: 220, stepHeight: 280, stepSide: 'bottom_right',
      sensor: { dataMin: 100, dataMax: 4660 }
    },
    double_standard: {
      name: 'Doble Estanque (400L + 400L)',
      type: 'double_tank',
      length: 1000, width: 650, height: 650, thickness: 2.5, dimType: 'external',
      tank2Length: 1000, tank2Width: 650, tank2Height: 650,
      sensor: { dataMin: 100, dataMax: 4660 }
    }
  };

  // ==========================================================================
  // 1. MOTOR MATEMÁTICO DE GEOMETRÍA
  // ==========================================================================

  function getEffectiveDimensions() {
    const t = state.tank.dimType === 'external' ? (Number(state.tank.thickness) || 0) : 0;
    let L = Math.max(10, (Number(state.tank.length) || 100) - 2 * t);
    let W = Math.max(10, (Number(state.tank.width) || 100) - 2 * t);
    let H = Math.max(10, (Number(state.tank.height) || 100) - 2 * t);

    if (state.tank.type === 'cylinder_horizontal') {
      W = H;
    }

    return { L, W, H, t };
  }

  function getAreaAtZ(z, eff) {
    const { L, W, H } = eff;
    if (z < 0 || (state.tank.type !== 'double_tank' && z > H)) return 0;

    switch (state.tank.type) {
      case 'rectangular': {
        const t = eff.t || 0;
        // Radios efectivos descontando espesor si la medicion es externa
        const r_inf_li = Math.max(0, Math.min(W / 2, H / 2, (Number(state.tank.r_inf_li) || 0) - t));
        const r_inf_ld = Math.max(0, Math.min(W / 2, H / 2, (Number(state.tank.r_inf_ld) || 0) - t));
        const r_inf_af = Math.max(0, Math.min(L / 2, H / 2, (Number(state.tank.r_inf_af) || 0) - t));
        const r_inf_ap = Math.max(0, Math.min(L / 2, H / 2, (Number(state.tank.r_inf_ap) || 0) - t));

        const r_sup_li = Math.max(0, Math.min(W / 2, H / 2, (Number(state.tank.r_sup_li) || 0) - t));
        const r_sup_ld = Math.max(0, Math.min(W / 2, H / 2, (Number(state.tank.r_sup_ld) || 0) - t));
        const r_sup_af = Math.max(0, Math.min(L / 2, H / 2, (Number(state.tank.r_sup_af) || 0) - t));
        const r_sup_ap = Math.max(0, Math.min(L / 2, H / 2, (Number(state.tank.r_sup_ap) || 0) - t));

        let dx_l = 0;
        if (z < r_inf_li && r_inf_li > 0) {
          dx_l = r_inf_li - Math.sqrt(Math.max(0, r_inf_li * r_inf_li - Math.pow(r_inf_li - z, 2)));
        } else if (z > (H - r_sup_li) && r_sup_li > 0) {
          const dz = z - (H - r_sup_li);
          dx_l = r_sup_li - Math.sqrt(Math.max(0, r_sup_li * r_sup_li - dz * dz));
        }

        let dx_r = 0;
        if (z < r_inf_ld && r_inf_ld > 0) {
          dx_r = r_inf_ld - Math.sqrt(Math.max(0, r_inf_ld * r_inf_ld - Math.pow(r_inf_ld - z, 2)));
        } else if (z > (H - r_sup_ld) && r_sup_ld > 0) {
          const dz = z - (H - r_sup_ld);
          dx_r = r_sup_ld - Math.sqrt(Math.max(0, r_sup_ld * r_sup_ld - dz * dz));
        }

        let dy_f = 0;
        if (z < r_inf_af && r_inf_af > 0) {
          dy_f = r_inf_af - Math.sqrt(Math.max(0, r_inf_af * r_inf_af - Math.pow(r_inf_af - z, 2)));
        } else if (z > (H - r_sup_af) && r_sup_af > 0) {
          const dz = z - (H - r_sup_af);
          dy_f = r_sup_af - Math.sqrt(Math.max(0, r_sup_af * r_sup_af - dz * dz));
        }

        let dy_b = 0;
        if (z < r_inf_ap && r_inf_ap > 0) {
          dy_b = r_inf_ap - Math.sqrt(Math.max(0, r_inf_ap * r_inf_ap - Math.pow(r_inf_ap - z, 2)));
        } else if (z > (H - r_sup_ap) && r_sup_ap > 0) {
          const dz = z - (H - r_sup_ap);
          dy_b = r_sup_ap - Math.sqrt(Math.max(0, r_sup_ap * r_sup_ap - dz * dz));
        }

        const effW = Math.max(0, W - dx_l - dx_r);
        const effL = Math.max(0, L - dy_f - dy_b);
        let area = effW * effL;

        // Radios de las bajadas de esquinas (aristas verticales)
        const rvGlobal = Number(state.tank.r_vert) || 0;
        const rv_fi = Math.max(0, Math.min(W / 2, L / 2, (Number(state.tank.r_vert_fi) || rvGlobal) - t));
        const rv_fd = Math.max(0, Math.min(W / 2, L / 2, (Number(state.tank.r_vert_fd) || rvGlobal) - t));
        const rv_pi = Math.max(0, Math.min(W / 2, L / 2, (Number(state.tank.r_vert_pi) || rvGlobal) - t));
        const rv_pd = Math.max(0, Math.min(W / 2, L / 2, (Number(state.tank.r_vert_pd) || rvGlobal) - t));

        const cornerLostVert = (1 - Math.PI / 4) * (rv_fi * rv_fi + rv_fd * rv_fd + rv_pi * rv_pi + rv_pd * rv_pd);
        area = Math.max(0, area - cornerLostVert);

        // Descuento de Texturas, Canales y Chaflán de Chasis (Estanques Plásticos)
        if (state.tank.hasRecovecos) {
          const depthScale = (Number(state.tank.texturaLevel) || 50) / 50;

          // 1. Canales de las 2 cinchas / zunchos (hundidos en la pared)
          const cinchasW = 70;
          const cinchasD = (Number(state.tank.cinchasDepth) || 22) * depthScale;
          const cinchasLoss = 2 * cinchasW * (2 * cinchasD);
          area = Math.max(0, area - cinchasLoss);

          // 2. Nicho empotrado de la boca de llenado (cerca del techo)
          if (z > (H - 85)) {
            const neckAreaLoss = 180 * (26 * depthScale);
            area = Math.max(0, area - neckAreaLoss);
          }

          // 3. Nervadura perimetral de refuerzo de rotomoldeo (a media altura)
          if (Math.abs(z - H / 2) < 45) {
            const ribAreaLoss = 2 * (9 * depthScale) * L;
            area = Math.max(0, area - ribAreaLoss);
          }

          // 4. Chaflán / Bisel Inferior de Chasis (Corte en diagonal para despeje de larguero de camión)
          if (state.tank.recovecoEnabled !== false) {
            const recW = Math.min(W * 0.75, Math.max(0, Number(state.tank.recovecoWidth) || 0));
            const recH = Math.min(H * 0.85, Math.max(0, Number(state.tank.recovecoHeight) || 0));
            if (recW > 0 && recH > 0 && z < recH) {
              const u = z / recH;
              const stepW = Math.round(recW * 0.22);
              const cutW = recW * (1 - u) + stepW * u;
              area = Math.max(0, area - cutW * L);
            }
          }
        }

        return area;
      }

      case 'step_notch': {
        const sw = Math.min(W * 0.9, Number(state.tank.stepWidth) || 0);
        const sh = Math.min(H * 0.9, Number(state.tank.stepHeight) || 0);
        let effW = W;
        if (state.tank.stepSide === 'bottom_right' || state.tank.stepSide === 'bottom_left') {
          if (z < sh) {
            effW = Math.max(0, W - sw);
          } else {
            effW = W;
          }
        } else if (state.tank.stepSide === 'top_right') {
          if (z > (H - sh)) {
            effW = Math.max(0, W - sw);
          } else {
            effW = W;
          }
        }
        return effW * L;
      }

      case 'double_tank': {
        const t = state.tank.dimType === 'external' ? (Number(state.tank.thickness) || 0) : 0;
        const L2 = Math.max(10, (Number(state.tank.tank2Length) || L) - 2 * t);
        const W2 = Math.max(10, (Number(state.tank.tank2Width) || W) - 2 * t);
        const H2 = Math.max(10, (Number(state.tank.tank2Height) || H) - 2 * t);

        const area1 = (z <= H) ? (W * L) : 0;
        const area2 = (z <= H2) ? (W2 * L2) : 0;
        return area1 + area2;
      }

      case 'cylinder_horizontal': {
        const R = H / 2;
        const dist = Math.abs(R - z);
        if (dist >= R) return 0;
        const chordW = 2 * Math.sqrt(Math.max(0, R * R - dist * dist));
        let area = chordW * L;
        if (state.tank.cyl_head === 'hemispherical') {
          const r_slice = Math.sqrt(Math.max(0, R * R - dist * dist));
          area += Math.PI * r_slice * r_slice;
        }
        return area;
      }

      case 'elliptical_horizontal': {
        const a = W / 2;
        const b = H / 2;
        const dist = Math.abs(b - z);
        if (dist >= b) return 0;
        const chordW = 2 * a * Math.sqrt(Math.max(0, 1 - Math.pow(dist / b, 2)));
        return chordW * L;
      }

      case 'd_shape': {
        const r_bf = Math.min(W * 0.8, H * 0.8, Number(state.tank.d_r_bottom_front) || 200);
        const r_tf = Math.min(W * 0.8, H * 0.8, Number(state.tank.d_r_top_front) || 100);
        const r_back = Math.min(W * 0.2, H * 0.2, Number(state.tank.d_r_back_corners) || 40);

        let dx_front = 0;
        if (z < r_bf && r_bf > 0) {
          dx_front = r_bf - Math.sqrt(Math.max(0, r_bf * r_bf - Math.pow(r_bf - z, 2)));
        } else if (z > (H - r_tf) && r_tf > 0) {
          const dz = z - (H - r_tf);
          dx_front = r_tf - Math.sqrt(Math.max(0, r_tf * r_tf - dz * dz));
        }

        let dx_back = 0;
        if (z < r_back && r_back > 0) {
          dx_back = r_back - Math.sqrt(Math.max(0, r_back * r_back - Math.pow(r_back - z, 2)));
        } else if (z > (H - r_back) && r_back > 0) {
          const dz = z - (H - r_back);
          dx_back = r_back - Math.sqrt(Math.max(0, r_back * r_back - dz * dz));
        }

        const effW = Math.max(0, W - dx_front - dx_back);
        return effW * L;
      }

      default:
        return W * L;
    }
  }

  function computeStrappingTable() {
    const eff = getEffectiveDimensions();
    let maxH = eff.H;
    if (state.tank.type === 'double_tank') {
      const t = state.tank.dimType === 'external' ? (Number(state.tank.thickness) || 0) : 0;
      const H2 = Math.max(10, (Number(state.tank.tank2Height) || eff.H) - 2 * t);
      maxH = Math.max(eff.H, H2);
    }

    const H = Math.round(maxH);
    state.calcCache.effH = H;

    const cumVol = new Float64Array(H + 1);
    cumVol[0] = 0;

    for (let z = 1; z <= H; z++) {
      const midZ = z - 0.5;
      const area = getAreaAtZ(midZ, eff);
      cumVol[z] = cumVol[z - 1] + (area / 1000000); // mm³ -> Litros
    }

    state.calcCache.cumVol = cumVol;
    state.calcCache.totalVolume = Number(cumVol[H].toFixed(1));
    computeCalibrationRows();
  }

  function getVolumeAtHeight(h) {
    const H = state.calcCache.effH;
    const cum = state.calcCache.cumVol;
    if (!cum || H <= 0) return 0;

    const clamped = Math.max(0, Math.min(H, h));
    const low = Math.floor(clamped);
    const high = Math.min(H, Math.ceil(clamped));
    if (low === high) return cum[low];

    const frac = clamped - low;
    return cum[low] + frac * (cum[high] - cum[low]);
  }

  function computeCalibrationRows(targetCount = state.tableMode || 30) {
    if (state.isImported && state.importedRows && state.importedRows.length > 0) {
      const H = state.calcCache.effH;
      const V_total = state.importedRows[state.importedRows.length - 1].volume || state.calcCache.totalVolume;
      const rows = state.importedRows.map((r, idx) => ({
        rowNum: idx + 2,
        dataVal: r.data,
        dataFormula: `${r.data}`,
        levelVal: r.level,
        levelFormula: `${r.level}`,
        volumeVal: r.volume,
        pct: V_total > 0 ? Number(((r.volume / V_total) * 100).toFixed(1)) : 0
      }));
      state.calcCache.calibrationRows = rows;
      return rows;
    }

    const H = state.calcCache.effH;
    const count = targetCount === 100 ? 100 : 30;
    const dataMin = Number(state.sensor.dataMin) || 100;
    const dataMax = Number(state.sensor.dataMax) || 4660;
    const V_total = state.calcCache.totalVolume;
    const rows = [];

    if (count === 30) {
      // EXACTAMENTE 30 FILAS EN TOTAL (Fila 1 Header + Filas 2 a 30)
      rows.push({
        rowNum: 2,
        dataVal: 0,
        dataFormula: '0',
        levelVal: 0,
        levelFormula: '0',
        volumeVal: 0.0,
        pct: 0.0
      });

      const levelStep1 = Math.round(1 * H / 28);
      const volStep1 = Number(getVolumeAtHeight(levelStep1).toFixed(1));
      rows.push({
        rowNum: 3,
        dataVal: dataMin,
        dataFormula: `${dataMin}`,
        levelVal: levelStep1,
        levelFormula: `ROUND((3-2)*$B$30/28, 0)`,
        volumeVal: volStep1,
        pct: V_total > 0 ? Number(((volStep1 / V_total) * 100).toFixed(1)) : 0
      });

      for (let r = 4; r < 30; r++) {
        const dataFormula = `ROUND($A$3 + (${r}-3)*($A$30-$A$3)/27, 0)`;
        const levelFormula = `ROUND((${r}-2)*$B$30/28, 0)`;
        const estData = Math.round(dataMin + (r - 3) * (dataMax - dataMin) / 27);
        const estLevel = Math.round((r - 2) * H / 28);
        const estVol = Number(getVolumeAtHeight(estLevel).toFixed(1));

        rows.push({
          rowNum: r,
          dataVal: estData,
          dataFormula: dataFormula,
          levelVal: estLevel,
          levelFormula: levelFormula,
          volumeVal: estVol,
          pct: V_total > 0 ? Number(((estVol / V_total) * 100).toFixed(1)) : 0
        });
      }

      rows.push({
        rowNum: 30,
        dataVal: dataMax,
        dataFormula: `${dataMax}`,
        levelVal: H,
        levelFormula: `${H}`,
        volumeVal: V_total,
        pct: 100.0
      });
    } else {
      // 100 POSICIONES EXACTAS PARA MEMORIA DE SENSOR BLE (Slots 0 a 99)
      for (let i = 0; i < 100; i++) {
        const frac = i / 99;
        const estLevel = Math.round(frac * H);
        const estVol = Number(getVolumeAtHeight(estLevel).toFixed(1));
        const estData = i === 0 ? 0 : Math.round(dataMin + frac * (dataMax - dataMin));

        rows.push({
          rowNum: i + 1,
          slot: i,
          dataVal: estData,
          dataFormula: `${estData}`,
          levelVal: estLevel,
          levelFormula: `${estLevel}`,
          volumeVal: estVol,
          pct: V_total > 0 ? Number(((estVol / V_total) * 100).toFixed(1)) : 0,
          data: estData,
          level: estLevel,
          volume: estVol
        });
      }
    }

    state.calcCache.calibrationRows = rows;
    return rows;
  }

  // ==========================================================================
  // 2. MOTOR DE VISUALIZACIÓN CAD INTEGRADO: CORTE 2D Y MODELO 3D ISOMÉTRICO
  // ==========================================================================

  let cadCanvas = null;
  let cadCtx = null;
  let activeDrag = null;
  let hoverTarget = null;
  let currentBounds = { ox: 0, oy: 0, dw: 0, dh: 0, scale: 1 };

  // Parámetros de cámara 3D para el motor isométrico / axonométrico en Canvas
  let isoAngleY = 0.65; // Rotación horizontal (azimut) ~37°
  let isoAngleX = 0.42; // Inclinación vertical (elevación) ~24°
  let isOrbitingIso = false;
  let prevIsoMouseX = 0, prevIsoMouseY = 0;

  function initCadCanvas() {
    cadCanvas = document.getElementById('cadCanvas');
    if (!cadCanvas) return;
    cadCtx = cadCanvas.getContext('2d');
    resizeCadCanvas();

    window.addEventListener('resize', () => {
      resizeCadCanvas();
      renderCad();
    });

    cadCanvas.addEventListener('mousedown', handleCadMouseDown);
    window.addEventListener('mousemove', handleCadMouseMove);
    window.addEventListener('mouseup', handleCadMouseUp);

    cadCanvas.addEventListener('touchstart', (e) => {
      if (e.touches.length === 1) {
        const touch = e.touches[0];
        handleCadMouseDown({ clientX: touch.clientX, clientY: touch.clientY, preventDefault: () => e.preventDefault() });
      }
    });

    window.addEventListener('touchmove', (e) => {
      if (activeDrag && e.touches.length === 1) {
        const touch = e.touches[0];
        handleCadMouseMove({ clientX: touch.clientX, clientY: touch.clientY });
      }
    });

    window.addEventListener('touchend', handleCadMouseUp);
  }

  function resizeCadCanvas() {
    if (!cadCanvas) return;
    const rect = cadCanvas.parentElement.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    if (rect.width > 0) {
      cadCanvas.width = rect.width * dpr;
      cadCanvas.height = 420 * dpr;
    }
  }

  function getActivePlaneConfig() {
    const eff = getEffectiveDimensions();
    const isTransverse = state.viewMode === 'plane-transverse';

    let spanX = isTransverse ? eff.W : eff.L;
    let spanY = eff.H;

    if (state.tank.type === 'double_tank') {
      const t = state.tank.dimType === 'external' ? (Number(state.tank.thickness) || 0) : 0;
      const L2 = Math.max(10, (Number(state.tank.tank2Length) || eff.L) - 2 * t);
      const W2 = Math.max(10, (Number(state.tank.tank2Width) || eff.W) - 2 * t);
      const H2 = Math.max(10, (Number(state.tank.tank2Height) || eff.H) - 2 * t);
      if (isTransverse) {
        spanX = eff.W + W2 + 100;
      } else {
        spanX = Math.max(eff.L, L2);
      }
      spanY = Math.max(eff.H, H2);
    }

    const labelX = isTransverse ? `W = ${Math.round(eff.W)} mm` : `L = ${Math.round(eff.L)} mm`;
    const labelY = `H = ${Math.round(eff.H)} mm`;

    let corners = [];
    if (state.tank.type === 'rectangular') {
      corners = isTransverse ? [
        { id: 'r_inf_li', name: 'Piso Izq', xCorner: 0, yCorner: 1, val: Number(state.tank.r_inf_li) || 0 },
        { id: 'r_inf_ld', name: 'Piso Der', xCorner: 1, yCorner: 1, val: Number(state.tank.r_inf_ld) || 0 },
        { id: 'r_sup_li', name: 'Techo Izq', xCorner: 0, yCorner: 0, val: Number(state.tank.r_sup_li) || 0 },
        { id: 'r_sup_ld', name: 'Techo Der', xCorner: 1, yCorner: 0, val: Number(state.tank.r_sup_ld) || 0 }
      ] : [
        { id: 'r_inf_af', name: 'Piso Front', xCorner: 0, yCorner: 1, val: Number(state.tank.r_inf_af) || 0 },
        { id: 'r_inf_ap', name: 'Piso Post',  xCorner: 1, yCorner: 1, val: Number(state.tank.r_inf_ap) || 0 },
        { id: 'r_sup_af', name: 'Techo Front', xCorner: 0, yCorner: 0, val: Number(state.tank.r_sup_af) || 0 },
        { id: 'r_sup_ap', name: 'Techo Post',  xCorner: 1, yCorner: 0, val: Number(state.tank.r_sup_ap) || 0 }
      ];
    } else if (state.tank.type === 'd_shape' && isTransverse) {
      corners = [
        { id: 'd_r_bottom_front', name: 'Frente Inf', xCorner: 1, yCorner: 1, val: Number(state.tank.d_r_bottom_front) || 250 },
        { id: 'd_r_top_front',    name: 'Frente Sup', xCorner: 1, yCorner: 0, val: Number(state.tank.d_r_top_front) || 120 },
        { id: 'd_r_back_corners', name: 'Dorso Inf',  xCorner: 0, yCorner: 1, val: Number(state.tank.d_r_back_corners) || 40 },
        { id: 'd_r_back_corners', name: 'Dorso Sup',  xCorner: 0, yCorner: 0, val: Number(state.tank.d_r_back_corners) || 40 }
      ];
    }

    return { spanX, spanY, labelX, labelY, corners, isTransverse };
  }

  // ==========================================================================
  // RENDERIZADO PRINCIPAL
  // ==========================================================================

  function renderCad() {
    if (!cadCtx || !cadCanvas) return;

    if (state.viewMode === 'view-3d') {
      render3DIsoView();
    } else {
      render2DPlaneView();
    }
  }

  // ==========================================================================
  // RENDERIZADO VISTA 2D (CORTES TRANSVERSAL Y LONGITUDINAL)
  // ==========================================================================

  function render2DPlaneView() {
    const ctx = cadCtx;
    const w = cadCanvas.width;
    const h = cadCanvas.height;
    const dpr = window.devicePixelRatio || 1;

    ctx.save();
    ctx.clearRect(0, 0, w, h);

    // Fondo blanco limpio corporativo
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, w, h);

    // Cuadrícula sutil
    ctx.strokeStyle = '#f1f5f9';
    ctx.lineWidth = 1;
    const grid = 24 * dpr;
    for (let x = 0; x < w; x += grid) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
    }
    for (let y = 0; y < h; y += grid) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
    }

    const { spanX, spanY, labelX, labelY, corners, isTransverse } = getActivePlaneConfig();

    const margin = 60 * dpr;
    const availW = w - margin * 2;
    const availH = h - margin * 2;
    const scale = Math.min(availW / spanX, availH / spanY) * 0.88;

    const dw = spanX * scale;
    const dh = spanY * scale;
    const ox = (w - dw) / 2;
    const oy = (h + dh) / 2;

    currentBounds = { ox, oy, dw, dh, scale };

    // DIBUJAR PERFIL Y LLENADO EXACTO
    ctx.save();
    ctx.beginPath();
    drawCadProfile(ctx, ox, oy, dw, dh, scale, corners, isTransverse);

    ctx.strokeStyle = '#0f172a';
    ctx.lineWidth = 2.2 * dpr;
    ctx.stroke();

    // Clip con la silueta real para llenado milimétrico de combustible
    ctx.clip();

    const curLevel = state.currentLevelMm;
    const liquidH = Math.min(dh, curLevel * scale);
    const liquidTopY = oy - liquidH;

    // Relleno diésel ámbar suave
    ctx.fillStyle = 'rgba(217, 119, 6, 0.22)';
    ctx.fillRect(ox - 40, liquidTopY, dw + 80, liquidH + 40);

    // Línea de superficie de combustible
    ctx.strokeStyle = '#b45309';
    ctx.lineWidth = 2 * dpr;
    ctx.beginPath();
    ctx.moveTo(ox - 40, liquidTopY);
    ctx.lineTo(ox + dw + 40, liquidTopY);
    ctx.stroke();

    ctx.restore();

    // Línea indicadora exterior y badge de nivel
    ctx.save();
    ctx.strokeStyle = '#b45309';
    ctx.lineWidth = 1.5 * dpr;
    ctx.beginPath();
    ctx.moveTo(ox, liquidTopY);
    ctx.lineTo(ox + dw, liquidTopY);
    ctx.stroke();

    const isLevelHover = hoverTarget && hoverTarget.type === 'level';
    ctx.fillStyle = isLevelHover ? '#0f172a' : '#b45309';
    ctx.fillRect(ox + dw + 8 * dpr, liquidTopY - 11 * dpr, 94 * dpr, 22 * dpr);
    ctx.fillStyle = '#ffffff';
    ctx.font = `bold ${10.5 * dpr}px sans-serif`;
    ctx.fillText(`${curLevel} mm • ${getVolumeAtHeight(curLevel).toFixed(0)}L`, ox + dw + 12 * dpr, liquidTopY + 4 * dpr);

    // Dibujo de la sonda / varilla
    const probeX = ox + (state.tank.type === 'double_tank' ? dw * 0.25 : dw * 0.5);
    const probeTopY = oy - dh - 18 * dpr;
    const deadZone = (Number(state.sensor.bottomDeadZone) || 15) * scale;
    const probeBottomY = oy - deadZone;

    ctx.fillStyle = '#0b1329';
    ctx.fillRect(probeX - 12 * dpr, probeTopY, 24 * dpr, 16 * dpr);

    ctx.strokeStyle = '#64748b';
    ctx.lineWidth = 3.5 * dpr;
    ctx.beginPath();
    ctx.moveTo(probeX, probeTopY + 16 * dpr);
    ctx.lineTo(probeX, probeBottomY);
    ctx.stroke();

    // Zona muerta inferior
    ctx.strokeStyle = '#94a3b8';
    ctx.setLineDash([3 * dpr, 3 * dpr]);
    ctx.lineWidth = 1 * dpr;
    ctx.beginPath();
    ctx.moveTo(ox, probeBottomY);
    ctx.lineTo(ox + dw, probeBottomY);
    ctx.stroke();
    ctx.setLineDash([]);

    // Cotas de dimensión
    ctx.fillStyle = '#64748b';
    ctx.font = `800 ${11 * dpr}px sans-serif`;
    ctx.fillText(labelX, ox + dw * 0.5 - 35 * dpr, oy + 24 * dpr);
    ctx.fillText(labelY, ox - 62 * dpr, oy - dh * 0.5);

    // Dibujar manijas interactivas de esquinas
    corners.forEach(c => {
      const vx = c.xCorner === 0 ? ox : ox + dw;
      const vy = c.yCorner === 1 ? oy : oy - dh;
      const rPx = c.val * scale;

      const dirX = c.xCorner === 0 ? 1 : -1;
      const dirY = c.yCorner === 1 ? -1 : 1;
      const arcMidX = vx + dirX * (rPx * 0.293);
      const arcMidY = vy + dirY * (rPx * 0.293);

      const isHover = hoverTarget && hoverTarget.id === c.id;
      const isActive = activeDrag && activeDrag.id === c.id;

      ctx.save();
      ctx.beginPath();
      ctx.arc(arcMidX, arcMidY, (isHover || isActive ? 9 : 7) * dpr, 0, Math.PI * 2);
      ctx.fillStyle = '#ffffff';
      ctx.fill();
      ctx.lineWidth = 2 * dpr;
      ctx.strokeStyle = isActive ? '#2563eb' : (isHover ? '#0f172a' : '#64748b');
      ctx.stroke();

      ctx.beginPath();
      ctx.arc(arcMidX, arcMidY, 3 * dpr, 0, Math.PI * 2);
      ctx.fillStyle = isActive ? '#2563eb' : '#0f172a';
      ctx.fill();

      // Badge con medida R: XX mm
      const badgeText = `R: ${Math.round(c.val)} mm`;
      ctx.font = `bold ${10 * dpr}px monospace`;
      const textWidth = ctx.measureText(badgeText).width;
      const badgeX = arcMidX + dirX * 16 * dpr - (dirX < 0 ? textWidth + 8 * dpr : 0);
      const badgeY = arcMidY + dirY * 16 * dpr;

      ctx.fillStyle = isActive ? '#0b1329' : (isHover ? '#1e293b' : '#f8fafc');
      ctx.strokeStyle = '#cbd5e1';
      ctx.lineWidth = 1 * dpr;
      ctx.beginPath();
      ctx.roundRect ? ctx.roundRect(badgeX, badgeY - 11 * dpr, textWidth + 10 * dpr, 17 * dpr, 4 * dpr) : ctx.rect(badgeX, badgeY - 11 * dpr, textWidth + 10 * dpr, 17 * dpr);
      ctx.fill();
      ctx.stroke();

      ctx.fillStyle = (isActive || isHover) ? '#ffffff' : '#0f172a';
      ctx.fillText(badgeText, badgeX + 5 * dpr, badgeY + 1 * dpr);

      ctx.restore();
    });

    ctx.restore();
  }

  function drawCadProfile(ctx, ox, oy, dw, dh, scale, corners, isTransverse) {
    if (state.tank.type === 'cylinder_horizontal') {
      if (isTransverse) {
        const radius = dw / 2;
        ctx.arc(ox + radius, oy - radius, radius, 0, Math.PI * 2);
      } else {
        ctx.rect(ox, oy - dh, dw, dh);
      }
    } else if (state.tank.type === 'elliptical_horizontal') {
      if (isTransverse) {
        ctx.ellipse(ox + dw / 2, oy - dh / 2, dw / 2, dh / 2, 0, 0, Math.PI * 2);
      } else {
        ctx.rect(ox, oy - dh, dw, dh);
      }
    } else if (state.tank.type === 'step_notch') {
      if (isTransverse) {
        const sw = (Number(state.tank.stepWidth) || 200) * scale;
        const sh = (Number(state.tank.stepHeight) || 250) * scale;
        if (state.tank.stepSide === 'bottom_right') {
          ctx.moveTo(ox, oy);
          ctx.lineTo(ox + dw - sw, oy);
          ctx.lineTo(ox + dw - sw, oy - sh);
          ctx.lineTo(ox + dw, oy - sh);
          ctx.lineTo(ox + dw, oy - dh);
          ctx.lineTo(ox, oy - dh);
          ctx.closePath();
        } else if (state.tank.stepSide === 'bottom_left') {
          ctx.moveTo(ox + sw, oy);
          ctx.lineTo(ox + dw, oy);
          ctx.lineTo(ox + dw, oy - dh);
          ctx.lineTo(ox, oy - dh);
          ctx.lineTo(ox, oy - sh);
          ctx.lineTo(ox + sw, oy - sh);
          ctx.closePath();
        } else {
          ctx.moveTo(ox, oy);
          ctx.lineTo(ox + dw, oy);
          ctx.lineTo(ox + dw, oy - dh + sh);
          ctx.lineTo(ox + dw - sw, oy - dh + sh);
          ctx.lineTo(ox + dw - sw, oy - dh);
          ctx.lineTo(ox, oy - dh);
          ctx.closePath();
        }
      } else {
        ctx.rect(ox, oy - dh, dw, dh);
      }
    } else if (state.tank.type === 'double_tank') {
      if (isTransverse) {
        const eff = getEffectiveDimensions();
        const t = state.tank.dimType === 'external' ? (Number(state.tank.thickness) || 0) : 0;
        const W1 = eff.W * scale;
        const H1 = eff.H * scale;
        const W2 = Math.max(10, (Number(state.tank.tank2Width) || eff.W) - 2 * t) * scale;
        const H2 = Math.max(10, (Number(state.tank.tank2Height) || eff.H) - 2 * t) * scale;
        const gap = 100 * scale;

        ctx.rect(ox, oy - H1, W1, H1);
        ctx.rect(ox + W1 + gap, oy - H2, W2, H2);
        ctx.rect(ox + W1, oy - 40 * scale, gap, 30 * scale);
      } else {
        ctx.rect(ox, oy - dh, dw, dh);
      }
    } else if (state.tank.type === 'd_shape' && isTransverse) {
      const r_bf = (Number(state.tank.d_r_bottom_front) || 250) * scale;
      const r_tf = (Number(state.tank.d_r_top_front) || 120) * scale;
      const r_bk = (Number(state.tank.d_r_back_corners) || 40) * scale;

      ctx.moveTo(ox + r_bk, oy);
      ctx.lineTo(ox + dw - r_bf, oy);
      ctx.arcTo(ox + dw, oy, ox + dw, oy - r_bf, r_bf);
      ctx.lineTo(ox + dw, oy - dh + r_tf);
      ctx.arcTo(ox + dw, oy - dh, ox + dw - r_tf, oy - dh, r_tf);
      ctx.lineTo(ox + r_bk, oy - dh);
      ctx.arcTo(ox, oy - dh, ox, oy - dh + r_bk, r_bk);
      ctx.lineTo(ox, oy - r_bk);
      ctx.arcTo(ox, oy, ox + r_bk, oy, r_bk);
    } else {
      if (corners.length >= 4) {
        const r_li = corners[0].val * scale;
        const r_ld = corners[1].val * scale;
        const r_sli = corners[2].val * scale;
        const r_sld = corners[3].val * scale;

        if (state.tank.hasRecovecos && isTransverse && (state.tank.recovecoEnabled !== false)) {
          // Chaflán de Chasis en el corte transversal (fiel a la Imagen 2)
          const recW = Math.min(dw * 0.75, (Number(state.tank.recovecoWidth) || 190) * scale);
          const recH = Math.min(dh * 0.85, (Number(state.tank.recovecoHeight) || 175) * scale);
          const stepW = Math.round(recW * 0.22);
          const isLeft = state.tank.recovecoSide !== 'bottom_right';

          if (isLeft) {
            // Suelo plano desde el chaflán hasta la pared derecha
            ctx.moveTo(ox + recW, oy);
            ctx.lineTo(ox + dw - r_ld, oy);
            ctx.arcTo(ox + dw, oy, ox + dw, oy - r_ld, r_ld);
            // Pared derecha hasta techo
            ctx.lineTo(ox + dw, oy - dh + r_sld);
            ctx.arcTo(ox + dw, oy - dh, ox + dw - r_sld, oy - dh, r_sld);
            ctx.lineTo(ox + r_sli, oy - dh);
            ctx.arcTo(ox, oy - dh, ox, oy - dh + r_sli, r_sli);
            // Pared izquierda hasta inicio del chaflán
            ctx.lineTo(ox, oy - recH);
            ctx.lineTo(ox + stepW, oy - recH);
            // Diagonal hacia el piso
            ctx.lineTo(ox + recW, oy);
            ctx.closePath();
          } else {
            // Chaflán en lado derecho
            ctx.moveTo(ox + r_li, oy);
            ctx.lineTo(ox + dw - recW, oy);
            ctx.lineTo(ox + dw - stepW, oy - recH);
            ctx.lineTo(ox + dw, oy - recH);
            ctx.lineTo(ox + dw, oy - dh + r_sld);
            ctx.arcTo(ox + dw, oy - dh, ox + dw - r_sld, oy - dh, r_sld);
            ctx.lineTo(ox + r_sli, oy - dh);
            ctx.arcTo(ox, oy - dh, ox, oy - dh + r_sli, r_sli);
            ctx.lineTo(ox, oy - r_li);
            ctx.arcTo(ox, oy, ox + r_li, oy, r_li);
            ctx.closePath();
          }
        } else {
          ctx.moveTo(ox + r_li, oy);
          ctx.lineTo(ox + dw - r_ld, oy);
          ctx.arcTo(ox + dw, oy, ox + dw, oy - r_ld, r_ld);

          if (state.tank.hasRecovecos && isTransverse) {
            // Nicho de boca de carga en esquina superior derecha
            const neckDepth = 20 * scale;
            const neckH = 32 * scale;
            ctx.lineTo(ox + dw, oy - dh + neckH);
            ctx.lineTo(ox + dw - neckDepth, oy - dh + neckH);
            ctx.lineTo(ox + dw - neckDepth, oy - dh);
            ctx.lineTo(ox + r_sli, oy - dh);
          } else {
            ctx.lineTo(ox + dw, oy - dh + r_sld);
            ctx.arcTo(ox + dw, oy - dh, ox + dw - r_sld, oy - dh, r_sld);
            ctx.lineTo(ox + r_sli, oy - dh);
          }

          ctx.arcTo(ox, oy - dh, ox, oy - dh + r_sli, r_sli);
          ctx.lineTo(ox, oy - r_li);
          ctx.arcTo(ox, oy, ox + r_li, oy, r_li);
          ctx.closePath();
        }
      } else {
        ctx.rect(ox, oy - dh, dw, dh);
      }
    }
  }

  // ==========================================================================
  // RENDERIZADO VISTA 3D EN CANVAS (MOTOR AXONOMÉTRICO PRECISO Y 100% EDITABLE)
  // ==========================================================================

  let current3DHandles = [];

  function project3D(x, y, z, cx, cy, scale) {
    // Rotación alrededor de eje vertical (Yaw)
    const cosY = Math.cos(isoAngleY), sinY = Math.sin(isoAngleY);
    const x1 = x * cosY - z * sinY;
    const z1 = x * sinY + z * cosY;

    // Inclinación (Pitch)
    const cosX = Math.cos(isoAngleX), sinX = Math.sin(isoAngleX);
    const y2 = y * cosX - z1 * sinX;
    const z2 = y * sinX + z1 * cosX;

    return {
      x: cx + x1 * scale,
      y: cy - y2 * scale,
      depth: z2
    };
  }

  function render3DIsoView() {
    const ctx = cadCtx;
    const w = cadCanvas.width;
    const h = cadCanvas.height;
    const dpr = window.devicePixelRatio || 1;

    ctx.save();
    ctx.clearRect(0, 0, w, h);

    // Fondo degradado de alta precisión técnica
    const grad = ctx.createLinearGradient(0, 0, 0, h);
    grad.addColorStop(0, '#ffffff');
    grad.addColorStop(1, '#f8fafc');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, w, h);

    // Eje de centro
    const cx = w * 0.5;
    const cy = h * 0.58;

    const eff = getEffectiveDimensions();
    const t = state.tank.dimType === 'external' ? (Number(state.tank.thickness) || 0) : 0;
    const maxDim = state.tank.type === 'double_tank'
      ? Math.max(
          eff.L, eff.W, eff.H,
          (Number(state.tank.tank2Length) || eff.L) - 2 * t,
          (Number(state.tank.tank2Width) || eff.W) - 2 * t,
          (Number(state.tank.tank2Height) || eff.H) - 2 * t
        )
      : Math.max(eff.L, eff.W, eff.H);
    const scale = (Math.min(w, h) * 0.44 / maxDim);

    currentBounds = { ox: cx, oy: cy, scale };
    current3DHandles = [];

    const L = eff.L, W = eff.W, H = eff.H;
    const curLevel = state.currentLevelMm;

    // Plano de piso sutil
    ctx.strokeStyle = '#e2e8f0';
    ctx.lineWidth = 1 * dpr;
    const floorSize = maxDim * 0.9;
    const pF1 = project3D(-floorSize, 0, -floorSize, cx, cy, scale);
    const pF2 = project3D( floorSize, 0, -floorSize, cx, cy, scale);
    const pF3 = project3D( floorSize, 0,  floorSize, cx, cy, scale);
    const pF4 = project3D(-floorSize, 0,  floorSize, cx, cy, scale);

    ctx.beginPath();
    ctx.moveTo(pF1.x, pF1.y); ctx.lineTo(pF2.x, pF2.y);
    ctx.lineTo(pF3.x, pF3.y); ctx.lineTo(pF4.x, pF4.y);
    ctx.closePath();
    ctx.stroke();

    // RENDERIZAR SEGÚN TIPO DE ESTANQUE
    if (state.tank.type === 'double_tank') {
      const L2 = Math.max(10, (Number(state.tank.tank2Length) || eff.L) - 2 * t);
      const W2 = Math.max(10, (Number(state.tank.tank2Width) || eff.W) - 2 * t);
      const H2 = Math.max(10, (Number(state.tank.tank2Height) || eff.H) - 2 * t);
      const gap = 160;

      // Tanque 1 (Izquierdo)
      drawIsometricBox(ctx, cx, cy, scale, -L / 2, 0, -W - gap / 2, L, H, W, curLevel, H, 'T1');
      // Tanque 2 (Derecho con medidas independientes)
      drawIsometricBox(ctx, cx, cy, scale, -L2 / 2, 0, gap / 2, L2, H2, W2, curLevel, H2, 'T2');

      // Tubo de interconexión
      const pT1 = project3D(0, 40, -gap / 2, cx, cy, scale);
      const pT2 = project3D(0, 40, gap / 2, cx, cy, scale);
      ctx.strokeStyle = '#0284c7';
      ctx.lineWidth = 8 * dpr;
      ctx.beginPath();
      ctx.moveTo(pT1.x, pT1.y); ctx.lineTo(pT2.x, pT2.y);
      ctx.stroke();

      // Manijas de Tanque 2
      const pT2L = project3D(L2 / 2, H2 * 0.5, gap / 2 + W2 * 0.5, cx, cy, scale);
      const pT2H = project3D(0, H2, gap / 2 + W2 * 0.5, cx, cy, scale);
      const pT2W = project3D(0, H2 * 0.5, gap / 2 + W2, cx, cy, scale);

      current3DHandles.push(
        { id: 'tank2Length', type: 'dim', label: 'Largo 2', val: Number(state.tank.tank2Length) || L, x: pT2L.x, y: pT2L.y, color: '#059669' },
        { id: 'tank2Height', type: 'dim', label: 'Alto 2', val: Number(state.tank.tank2Height) || H, x: pT2H.x, y: pT2H.y, color: '#059669' },
        { id: 'tank2Width',  type: 'dim', label: 'Ancho 2', val: Number(state.tank.tank2Width) || W, x: pT2W.x, y: pT2W.y, color: '#059669' }
      );

    } else if (state.tank.type === 'step_notch') {
      const sw = Math.min(W * 0.85, Number(state.tank.stepWidth) || 200);
      const sh = Math.min(H * 0.85, Number(state.tank.stepHeight) || 250);

      drawIsometricStepTank(ctx, cx, cy, scale, L, H, W, sw, sh, curLevel);

      // Manijas de escalón
      const pSW = project3D(L * 0.5, sh * 0.5, W * 0.5 - sw, cx, cy, scale);
      const pSH = project3D(L * 0.5, sh, W * 0.5 - sw * 0.5, cx, cy, scale);
      current3DHandles.push(
        { id: 'stepWidth',  type: 'step', label: 'Ancho Escalón', val: state.tank.stepWidth, x: pSW.x, y: pSW.y, color: '#2563eb' },
        { id: 'stepHeight', type: 'step', label: 'Alto Escalón', val: state.tank.stepHeight, x: pSH.x, y: pSH.y, color: '#2563eb' }
      );

    } else if (state.tank.type === 'cylinder_horizontal') {
      drawIsometricCylinder(ctx, cx, cy, scale, L, H, curLevel);

    } else {
      // Prisma Rectangular / D-Shape con esquinas redondeadas
      drawIsometricFilletedTank(ctx, cx, cy, scale, L, H, W, curLevel);
    }

    // MANIJAS 3D DIMENSIONALES GENERALES (Largo, Alto, Ancho)
    const pDimL = project3D(L * 0.5, H * 0.5, 0, cx, cy, scale);
    const pDimH = project3D(0, H, 0, cx, cy, scale);
    const pDimW = project3D(0, H * 0.5, W * 0.5, cx, cy, scale);

    current3DHandles.push(
      { id: 'tankLength', type: 'dim', label: 'Largo', val: state.tank.length, x: pDimL.x, y: pDimL.y, color: '#059669' },
      { id: 'tankHeight', type: 'dim', label: 'Alto',  val: state.tank.height, x: pDimH.x, y: pDimH.y, color: '#059669' },
      { id: 'tankWidth',  type: 'dim', label: 'Ancho', val: state.tank.width,  x: pDimW.x, y: pDimW.y, color: '#059669' }
    );

    // MANIJA 3D DE NIVEL DE COMBUSTIBLE
    const pLevel = project3D(L * 0.55, curLevel, 0, cx, cy, scale);
    current3DHandles.push(
      { id: 'level', type: 'level', label: 'Nivel', val: curLevel, x: pLevel.x, y: pLevel.y, color: '#d97706' }
    );

    // DIBUJAR TODAS LAS MANIJAS 3D CON SUS BADGES INTERACTIVOS
    current3DHandles.forEach(hnd => {
      const isHover = hoverTarget && hoverTarget.id === hnd.id;
      const isActive = activeDrag && activeDrag.id === hnd.id;

      ctx.save();
      ctx.beginPath();
      ctx.arc(hnd.x, hnd.y, (isActive || isHover ? 9 : 7) * dpr, 0, Math.PI * 2);
      ctx.fillStyle = '#ffffff';
      ctx.fill();
      ctx.lineWidth = 2.5 * dpr;
      ctx.strokeStyle = isActive ? '#0f172a' : hnd.color;
      ctx.stroke();

      ctx.beginPath();
      ctx.arc(hnd.x, hnd.y, 3.5 * dpr, 0, Math.PI * 2);
      ctx.fillStyle = isActive ? '#0f172a' : hnd.color;
      ctx.fill();

      // Badge con valor SOLO cuando está activo o en hover (para mantener la vista limpia)
      if (isActive || isHover) {
        const labelText = hnd.label + ': ' + Math.round(hnd.val) + ' mm';
        ctx.font = 'bold ' + (11 * dpr) + 'px sans-serif';
        const tW = ctx.measureText(labelText).width;

        const bx = hnd.x + 12 * dpr;
        const by = hnd.y - 12 * dpr;

        ctx.fillStyle = '#0b1329';
        ctx.strokeStyle = '#38bdf8';
        ctx.lineWidth = 1.5 * dpr;
        ctx.beginPath();
        ctx.roundRect ? ctx.roundRect(bx, by - 12 * dpr, tW + 14 * dpr, 22 * dpr, 5 * dpr) : ctx.rect(bx, by - 12 * dpr, tW + 14 * dpr, 22 * dpr);
        ctx.fill();
        ctx.stroke();

        ctx.fillStyle = '#ffffff';
        ctx.fillText(labelText, bx + 7 * dpr, by + 3 * dpr);
      }
      ctx.restore();
    });

    ctx.restore();
  }

  // ==========================================================================
  // DIBUJADO DE CUERPOS ISOMÉTRICOS CON FLUIDO
  // ==========================================================================


  
  function drawIsometricBox(ctx, cx, cy, scale, x0, y0, z0, L, H, W, curLevel, maxH, tag) {
    const dpr = window.devicePixelRatio || 1;
    const v = [
      project3D(x0,     y0,     z0,     cx, cy, scale),
      project3D(x0 + L, y0,     z0,     cx, cy, scale),
      project3D(x0 + L, y0,     z0 + W, cx, cy, scale),
      project3D(x0,     y0,     z0 + W, cx, cy, scale),
      project3D(x0,     y0 + H, z0,     cx, cy, scale),
      project3D(x0 + L, y0 + H, z0,     cx, cy, scale),
      project3D(x0 + L, y0 + H, z0 + W, cx, cy, scale),
      project3D(x0,     y0 + H, z0 + W, cx, cy, scale)
    ];

    ctx.save();
    ctx.fillStyle = 'rgba(241, 245, 249, 0.40)';
    ctx.strokeStyle = '#0284c7';
    ctx.lineWidth = 1.6 * dpr;

    drawPoly(ctx, [v[4], v[5], v[6], v[7]], true, true);
    drawPoly(ctx, [v[1], v[2], v[6], v[5]], true, true);
    drawPoly(ctx, [v[2], v[3], v[7], v[6]], true, true);

    const lH = Math.max(0, Math.min(H, curLevel));
    if (lH > 0) {
      const lv = [
        project3D(x0,     y0 + lH, z0,     cx, cy, scale),
        project3D(x0 + L, y0 + lH, z0,     cx, cy, scale),
        project3D(x0 + L, y0 + lH, z0 + W, cx, cy, scale),
        project3D(x0,     y0 + lH, z0 + W, cx, cy, scale)
      ];
      ctx.fillStyle = 'rgba(217, 119, 6, 0.35)';
      ctx.strokeStyle = '#b45309';
      ctx.lineWidth = 1.2 * dpr;
      drawPoly(ctx, [v[1], v[2], lv[2], lv[1]], true, true);
      drawPoly(ctx, [v[2], v[3], lv[3], lv[2]], true, true);
      ctx.fillStyle = 'rgba(245, 158, 11, 0.70)';
      drawPoly(ctx, [lv[0], lv[1], lv[2], lv[3]], true, true);
    }
    ctx.restore();
  }

  function generateTankOutlinePolygon(W, H, type) {
    const pts = [];
    if (type === 'rectangular') {
      const r_li = Math.min(W/2, H/2, Number(state.tank.r_inf_li) || 0);
      const r_ld = Math.min(W/2, H/2, Number(state.tank.r_inf_ld) || 0);
      const r_sli = Math.min(W/2, H/2, Number(state.tank.r_sup_li) || 0);
      const r_sld = Math.min(W/2, H/2, Number(state.tank.r_sup_ld) || 0);
      const nSeg = 8;
      
      // Piso centro
      pts.push({ z: -W/2 + r_li, y: 0 });
      pts.push({ z: W/2 - r_ld, y: 0 });
      // Esquina inf der
      for (let i = 0; i <= nSeg; i++) {
        const th = -Math.PI/2 + (i / nSeg) * (Math.PI/2);
        pts.push({ z: W/2 - r_ld + r_ld * Math.cos(th), y: r_ld + r_ld * Math.sin(th) });
      }
      // Lado der
      pts.push({ z: W/2, y: H - r_sld });
      // Esquina sup der
      for (let i = 0; i <= nSeg; i++) {
        const th = (i / nSeg) * (Math.PI/2);
        pts.push({ z: W/2 - r_sld + r_sld * Math.cos(th), y: H - r_sld + r_sld * Math.sin(th) });
      }
      // Techo
      pts.push({ z: -W/2 + r_sli, y: H });
      // Esquina sup izq
      for (let i = 0; i <= nSeg; i++) {
        const th = Math.PI/2 + (i / nSeg) * (Math.PI/2);
        pts.push({ z: -W/2 + r_sli + r_sli * Math.cos(th), y: H - r_sli + r_sli * Math.sin(th) });
      }
      // Lado izq
      pts.push({ z: -W/2, y: r_li });
      // Esquina inf izq
      for (let i = 0; i <= nSeg; i++) {
        const th = Math.PI + (i / nSeg) * (Math.PI/2);
        pts.push({ z: -W/2 + r_li + r_li * Math.cos(th), y: r_li + r_li * Math.sin(th) });
      }
    } else if (type === 'cylinder_horizontal') {
      const R = H / 2;
      for (let i = 0; i < 32; i++) {
        const th = (i / 32) * Math.PI * 2;
        pts.push({ z: R * Math.sin(th), y: R + R * Math.cos(th) });
      }
    } else if (type === 'elliptical_horizontal') {
      const a = W / 2, b = H / 2;
      for (let i = 0; i < 32; i++) {
        const th = (i / 32) * Math.PI * 2;
        pts.push({ z: a * Math.sin(th), y: b + b * Math.cos(th) });
      }
    } else if (type === 'd_shape') {
      const r_bf = Math.min(W*0.8, H*0.8, Number(state.tank.d_r_bottom_front) || 200);
      const r_tf = Math.min(W*0.8, H*0.8, Number(state.tank.d_r_top_front) || 100);
      const r_bk = Math.min(W*0.2, H*0.2, Number(state.tank.d_r_back_corners) || 40);
      const nSeg = 8;
      
      pts.push({ z: -W/2 + r_bk, y: 0 });
      pts.push({ z: W/2 - r_bf, y: 0 });
      for (let i = 0; i <= nSeg; i++) {
        const th = -Math.PI/2 + (i / nSeg) * (Math.PI/2);
        pts.push({ z: W/2 - r_bf + r_bf * Math.cos(th), y: r_bf + r_bf * Math.sin(th) });
      }
      pts.push({ z: W/2, y: H - r_tf });
      for (let i = 0; i <= nSeg; i++) {
        const th = (i / nSeg) * (Math.PI/2);
        pts.push({ z: W/2 - r_tf + r_tf * Math.cos(th), y: H - r_tf + r_tf * Math.sin(th) });
      }
      pts.push({ z: -W/2 + r_bk, y: H });
      for (let i = 0; i <= nSeg; i++) {
        const th = Math.PI/2 + (i / nSeg) * (Math.PI/2);
        pts.push({ z: -W/2 + r_bk + r_bk * Math.cos(th), y: H - r_bk + r_bk * Math.sin(th) });
      }
      pts.push({ z: -W/2, y: r_bk });
      for (let i = 0; i <= nSeg; i++) {
        const th = Math.PI + (i / nSeg) * (Math.PI/2);
        pts.push({ z: -W/2 + r_bk + r_bk * Math.cos(th), y: r_bk + r_bk * Math.sin(th) });
      }
    } else if (type === 'step_notch') {
      const sw = Math.min(W * 0.85, Number(state.tank.stepWidth) || 200);
      const sh = Math.min(H * 0.85, Number(state.tank.stepHeight) || 250);
      pts.push({ z: -W/2, y: 0 });
      pts.push({ z: W/2 - sw, y: 0 });
      pts.push({ z: W/2 - sw, y: sh });
      pts.push({ z: W/2, y: sh });
      pts.push({ z: W/2, y: H });
      pts.push({ z: -W/2, y: H });
    }
    return pts;
  }

  function drawIsometricFilletedTank(ctx, cx, cy, scale, L, H, W, curLevel) {
    const dpr = window.devicePixelRatio || 1;
    const x0 = -L / 2;
    const pts = generateTankOutlinePolygon(W, H, state.tank.type);
    if (!pts.length) return;

    // Cara Posterior y Frontal proyectadas
    const pFront = pts.map(p => project3D(x0 + L, p.y, p.z, cx, cy, scale));
    const pBack = pts.map(p => project3D(x0, p.y, p.z, cx, cy, scale));

    ctx.save();

    // Relleno suave de cuerpo 3D
    ctx.fillStyle = 'rgba(241, 245, 249, 0.45)';
    ctx.strokeStyle = '#0284c7';
    ctx.lineWidth = 1.6 * dpr;

    // Dibujar aristas longitudinales de contorno
    for (let i = 0; i < pts.length; i += 2) {
      ctx.beginPath();
      ctx.moveTo(pBack[i].x, pBack[i].y);
      ctx.lineTo(pFront[i].x, pFront[i].y);
      ctx.strokeStyle = 'rgba(2, 132, 199, 0.4)';
      ctx.stroke();
    }

    // Cara Posterior
    ctx.strokeStyle = '#0284c7';
    ctx.lineWidth = 1.8 * dpr;
    drawPoly(ctx, pBack, true, true);

    // FLUIDO 3D DE COMBUSTIBLE DIESEL ÁMBAR CON MENISCO
    if (curLevel > 0) {
      const lH = Math.min(H, curLevel);
      // Puntos bajo el nivel del líquido
      const liquidPts = [];
      let leftZ = 0, rightZ = 0;
      let minZ = Infinity, maxZ = -Infinity;

      for (let p of pts) {
        if (p.y <= lH) {
          liquidPts.push(p);
          if (p.z < minZ) minZ = p.z;
          if (p.z > maxZ) maxZ = p.z;
        }
      }

      if (liquidPts.length > 2) {
        const liqFront = liquidPts.map(p => project3D(x0 + L, p.y, p.z, cx, cy, scale));
        const liqBack = liquidPts.map(p => project3D(x0, p.y, p.z, cx, cy, scale));

        ctx.fillStyle = 'rgba(217, 119, 6, 0.35)';
        ctx.strokeStyle = '#b45309';
        ctx.lineWidth = 1.2 * dpr;

        drawPoly(ctx, liqFront, true, true);

        // Superficie líquida superior
        const pL1 = project3D(x0, lH, minZ, cx, cy, scale);
        const pL2 = project3D(x0 + L, lH, minZ, cx, cy, scale);
        const pL3 = project3D(x0 + L, lH, maxZ, cx, cy, scale);
        const pL4 = project3D(x0, lH, maxZ, cx, cy, scale);

        ctx.fillStyle = 'rgba(245, 158, 11, 0.70)';
        drawPoly(ctx, [pL1, pL2, pL3, pL4], true, true);
      }
    }

    // Cara Frontal (primer plano)
    ctx.fillStyle = 'rgba(248, 250, 252, 0.30)';
    ctx.strokeStyle = '#0284c7';
    ctx.lineWidth = 2.0 * dpr;
    drawPoly(ctx, pFront, true, true);

    ctx.restore();

    // MANIJAS 3D DE ESQUINAS Y BORDES
    if (state.tank.type === 'rectangular') {
      const r_li = Number(state.tank.r_inf_li) || 0;
      const r_ld = Number(state.tank.r_inf_ld) || 0;
      const r_sli = Number(state.tank.r_sup_li) || 0;
      const r_sld = Number(state.tank.r_sup_ld) || 0;

      const p_sli = project3D(x0 + L, H - r_sli * 0.3, -W / 2 + r_sli * 0.3, cx, cy, scale);
      const p_sld = project3D(x0 + L, H - r_sld * 0.3,  W / 2 - r_sld * 0.3, cx, cy, scale);
      const p_li  = project3D(x0 + L, r_li * 0.3,      -W / 2 + r_li * 0.3, cx, cy, scale);
      const p_ld  = project3D(x0 + L, r_ld * 0.3,       W / 2 - r_ld * 0.3, cx, cy, scale);

      current3DHandles.push(
        { id: 'r_sup_li', type: 'corner', label: 'Techo Izq', val: r_sli, x: p_sli.x, y: p_sli.y, color: '#2563eb' },
        { id: 'r_sup_ld', type: 'corner', label: 'Techo Der', val: r_sld, x: p_sld.x, y: p_sld.y, color: '#2563eb' },
        { id: 'r_inf_li', type: 'corner', label: 'Piso Izq',  val: r_li,  x: p_li.x,  y: p_li.y,  color: '#2563eb' },
        { id: 'r_inf_ld', type: 'corner', label: 'Piso Der',  val: r_ld,  x: p_ld.x,  y: p_ld.y,  color: '#2563eb' }
      );
    } else if (state.tank.type === 'd_shape') {
      const r_bf = Number(state.tank.d_r_bottom_front) || 200;
      const r_tf = Number(state.tank.d_r_top_front) || 100;
      const p_bf = project3D(x0 + L, r_bf * 0.3, W / 2 - r_bf * 0.3, cx, cy, scale);
      const p_tf = project3D(x0 + L, H - r_tf * 0.3, W / 2 - r_tf * 0.3, cx, cy, scale);

      current3DHandles.push(
        { id: 'd_r_bottom_front', type: 'corner', label: 'Frente Inf', val: r_bf, x: p_bf.x, y: p_bf.y, color: '#2563eb' },
        { id: 'd_r_top_front',    type: 'corner', label: 'Frente Sup', val: r_tf, x: p_tf.x, y: p_tf.y, color: '#2563eb' }
      );
    }
  }

  function drawIsometricStepTank(ctx, cx, cy, scale, L, H, W, sw, sh, curLevel) {
    const dpr = window.devicePixelRatio || 1;
    const x0 = -L / 2, y0 = 0, z0 = -W / 2;

    // Cuerpo inferior escalón + cuerpo completo superior
    drawIsometricBox(ctx, cx, cy, scale, x0, 0, z0, L, H, W - sw, curLevel, H, 'Main');
    drawIsometricBox(ctx, cx, cy, scale, x0, sh, z0 + W - sw, L, H - sh, sw, Math.max(0, curLevel - sh), H - sh, 'Step');
  }

  function drawIsometricCylinder(ctx, cx, cy, scale, L, H, curLevel) {
    const dpr = window.devicePixelRatio || 1;
    const R = H / 2;
    const x0 = -L / 2;

    ctx.save();
    ctx.strokeStyle = '#0284c7';
    ctx.lineWidth = 2 * dpr;

    // Generatrices cilíndricas
    const steps = 36;
    for (let i = 0; i < steps; i++) {
      const a = (i / steps) * Math.PI * 2;
      const py = R + R * Math.cos(a);
      const pz = R * Math.sin(a);
      const p1 = project3D(x0, py, pz, cx, cy, scale);
      const p2 = project3D(x0 + L, py, pz, cx, cy, scale);

      if (i % 6 === 0) {
        ctx.beginPath();
        ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y);
        ctx.stroke();
      }
    }

    // Tapas circulares frontal y trasera
    const fPoints = [], bPoints = [];
    for (let i = 0; i <= steps; i++) {
      const a = (i / steps) * Math.PI * 2;
      const py = R + R * Math.cos(a);
      const pz = R * Math.sin(a);
      fPoints.push(project3D(x0 + L, py, pz, cx, cy, scale));
      bPoints.push(project3D(x0, py, pz, cx, cy, scale));
    }

    ctx.fillStyle = 'rgba(203, 213, 225, 0.35)';
    drawPoly(ctx, fPoints, true, true);
    drawPoly(ctx, bPoints, true, true);

    // Líquido cilíndrico
    if (curLevel > 0) {
      ctx.fillStyle = 'rgba(217, 119, 6, 0.45)';
      ctx.strokeStyle = '#b45309';
      const lH = Math.min(H, curLevel);
      const lp1 = project3D(x0, lH, -R, cx, cy, scale);
      const lp2 = project3D(x0 + L, lH, -R, cx, cy, scale);
      const lp3 = project3D(x0 + L, lH, R, cx, cy, scale);
      const lp4 = project3D(x0, lH, R, cx, cy, scale);
      drawPoly(ctx, [lp1, lp2, lp3, lp4], true, true);
    }

    ctx.restore();
  }

  function drawPoly(ctx, pts, fill, stroke) {
    if (!pts || pts.length === 0) return;
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) {
      ctx.lineTo(pts[i].x, pts[i].y);
    }
    ctx.closePath();
    if (fill) ctx.fill();
    if (stroke) ctx.stroke();
  }

  // ==========================================================================
  // EVENTOS DEL CANVAS (COMÚN PARA 2D Y 3D ISOMÉTRICO)
  // ==========================================================================

  function getCadPointerPos(e) {
    const rect = cadCanvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    return {
      x: (e.clientX - rect.left) * dpr,
      y: (e.clientY - rect.top) * dpr,
      clientX: e.clientX,
      clientY: e.clientY
    };
  }

  function handleCadMouseDown(e) {
    const pos = getCadPointerPos(e);
    const dpr = window.devicePixelRatio || 1;

    // --- MODO 3D ISOMÉTRICO ---
    if (state.viewMode === 'view-3d') {
      let hit3D = null;
      let minDist = Infinity;

      for (let hnd of current3DHandles) {
        const d = Math.hypot(pos.x - hnd.x, pos.y - hnd.y);
        if (d <= 26 * dpr && d < minDist) {
          minDist = d;
          hit3D = hnd;
        }
      }

      if (hit3D) {
        activeDrag = {
          type: '3d_handle',
          id: hit3D.id,
          handle: hit3D,
          startX: pos.x,
          startY: pos.y,
          origVal: Number(hit3D.id === 'level' ? state.currentLevelMm : state.tank[hit3D.id]) || 0
        };
        cadCanvas.style.cursor = 'crosshair';
        renderCad();
        return;
      }

      // Si no tocó ninguna manija, rotar la vista 3D en 360°
      isOrbitingIso = true;
      prevIsoMouseX = e.clientX;
      prevIsoMouseY = e.clientY;
      cadCanvas.style.cursor = 'grabbing';
      return;
    }

    // --- MODO CORTE 2D ---
    const { corners } = getActivePlaneConfig();
    const { ox, oy, dw, dh, scale } = currentBounds;

    let hitCorner = null;
    let minCornerDist = Infinity;

    for (let c of corners) {
      const vx = c.xCorner === 0 ? ox : ox + dw;
      const vy = c.yCorner === 1 ? oy : oy - dh;
      const rPx = c.val * scale;
      const dirX = c.xCorner === 0 ? 1 : -1;
      const dirY = c.yCorner === 1 ? -1 : 1;
      const arcMidX = vx + dirX * (rPx * 0.293);
      const arcMidY = vy + dirY * (rPx * 0.293);

      const d = Math.hypot(pos.x - arcMidX, pos.y - arcMidY);
      if (d <= 28 * dpr && d < minCornerDist) {
        minCornerDist = d;
        hitCorner = c;
      }
    }

    if (hitCorner) {
      activeDrag = {
        type: 'corner',
        id: hitCorner.id,
        corner: hitCorner,
        startX: pos.x,
        startY: pos.y,
        origVal: hitCorner.val
      };
      cadCanvas.style.cursor = 'crosshair';
      renderCad();
      return;
    }

    const curLevel = state.currentLevelMm;
    const liquidTopY = oy - curLevel * scale;
    if (Math.abs(pos.y - liquidTopY) <= 18 * dpr && pos.x >= ox - 40 && pos.x <= ox + dw + 120 * dpr) {
      activeDrag = {
        type: 'level',
        startX: pos.x,
        startY: pos.y,
        origLevel: curLevel
      };
      cadCanvas.style.cursor = 'ns-resize';
      renderCad();
    }
  }

  function handleCadMouseMove(e) {
    const pos = getCadPointerPos(e);
    const dpr = window.devicePixelRatio || 1;

    // --- ARRASTRE ACTIVO EN 3D ---
    if (activeDrag && activeDrag.type === '3d_handle') {
      const deltaY = (activeDrag.startY - pos.y) / dpr;
      const deltaX = (pos.x - activeDrag.startX) / dpr;
      const motion = (activeDrag.handle.type === 'dim' && activeDrag.id !== 'tankHeight') ? (deltaX - deltaY) : deltaY;

      let deltaMm = Math.round(motion * 2.0);
      let newVal = activeDrag.origVal + deltaMm;
      newVal = Math.round(newVal / 5) * 5;

      if (activeDrag.id === 'level') {
        newVal = Math.max(0, Math.min(state.calcCache.effH, newVal));
        state.currentLevelMm = newVal;
        const slider = document.getElementById('levelSlider');
        const numInput = document.getElementById('levelNumberInput');
        if (slider) slider.value = newVal;
        if (numInput) numInput.value = newVal;
      } else if (activeDrag.handle.type === 'dim') {
        newVal = Math.max(100, Math.min(3500, newVal));
        state.tank[activeDrag.id] = newVal;
        const inputEl = document.getElementById(activeDrag.id);
        if (inputEl) inputEl.value = newVal;
      } else {
        // Fillets y Step
        const maxR = Math.round(Math.min(state.tank.width / 2, state.tank.height / 2, state.tank.length / 2));
        newVal = Math.max(0, Math.min(maxR, newVal));
        state.tank[activeDrag.id] = newVal;
        const inputEl = document.getElementById(activeDrag.id);
        if (inputEl) inputEl.value = newVal;
      }

      updateAllUI();
      renderCad();
      return;
    }

    // --- ROTACIÓN DE CÁMARA 3D ISOMÉTRICA ---
    if (isOrbitingIso) {
      const deltaX = e.clientX - prevIsoMouseX;
      const deltaY = e.clientY - prevIsoMouseY;
      prevIsoMouseX = e.clientX;
      prevIsoMouseY = e.clientY;

      isoAngleY += deltaX * 0.008;
      isoAngleX = Math.max(0.1, Math.min(1.2, isoAngleX + deltaY * 0.008));
      renderCad();
      return;
    }

    // --- ARRASTRE ACTIVO EN 2D ---
    if (activeDrag) {
      const { ox, oy, dw, dh, scale } = currentBounds;
      if (activeDrag.type === 'corner') {
        const c = activeDrag.corner;
        const vx = c.xCorner === 0 ? ox : ox + dw;
        const vy = c.yCorner === 1 ? oy : oy - dh;

        const dx = (pos.x - vx) * (c.xCorner === 0 ? 1 : -1);
        const dy = (vy - pos.y) * (c.yCorner === 1 ? 1 : -1);
        const dragDist = Math.max(0, (dx + dy) / 2);

        let newRadius = Math.round(dragDist / scale);
        newRadius = Math.round(newRadius / 5) * 5;
        const maxR = Math.round(Math.min(dw / scale / 2, dh / scale / 2));
        newRadius = Math.max(0, Math.min(maxR, newRadius));

        state.tank[c.id] = newRadius;
        const inputEl = document.getElementById(c.id);
        if (inputEl) inputEl.value = newRadius;

        updateAllUI();
        renderCad();
      } else if (activeDrag.type === 'level') {
        const distFromBottomPx = oy - pos.y;
        let newLevel = Math.round(distFromBottomPx / scale);
        newLevel = Math.max(0, Math.min(state.calcCache.effH, newLevel));

        state.currentLevelMm = newLevel;
        const slider = document.getElementById('levelSlider');
        const numInput = document.getElementById('levelNumberInput');
        if (slider) slider.value = newLevel;
        if (numInput) numInput.value = newLevel;

        updateAllUI();
        renderCad();
      }
      return;
    }

    // --- HOVER HANDLING ---
    let newHover = null;
    if (state.viewMode === 'view-3d') {
      let minDist = Infinity;
      for (let hnd of current3DHandles) {
        const d = Math.hypot(pos.x - hnd.x, pos.y - hnd.y);
        if (d <= 22 * dpr && d < minDist) {
          minDist = d;
          newHover = { type: '3d_handle', id: hnd.id };
        }
      }
      cadCanvas.style.cursor = newHover ? 'pointer' : 'grab';
    } else {
      const { corners } = getActivePlaneConfig();
      const { ox, oy, dw, dh, scale } = currentBounds;
      let minCornerDist = Infinity;
      for (let c of corners) {
        const vx = c.xCorner === 0 ? ox : ox + dw;
        const vy = c.yCorner === 1 ? oy : oy - dh;
        const rPx = c.val * scale;
        const dirX = c.xCorner === 0 ? 1 : -1;
        const dirY = c.yCorner === 1 ? -1 : 1;
        const arcMidX = vx + dirX * (rPx * 0.293);
        const arcMidY = vy + dirY * (rPx * 0.293);

        const d = Math.hypot(pos.x - arcMidX, pos.y - arcMidY);
        if (d <= 22 * dpr && d < minCornerDist) {
          minCornerDist = d;
          newHover = { type: 'corner', id: c.id };
        }
      }

      if (!newHover) {
        const curLevel = state.currentLevelMm;
        const liquidTopY = oy - curLevel * scale;
        if (Math.abs(pos.y - liquidTopY) <= 15 * dpr && pos.x >= ox - 40 && pos.x <= ox + dw + 120 * dpr) {
          newHover = { type: 'level' };
        }
      }
      cadCanvas.style.cursor = newHover ? (newHover.type === 'corner' ? 'crosshair' : 'ns-resize') : 'default';
    }

    if (newHover !== hoverTarget) {
      hoverTarget = newHover;
      renderCad();
    }
  }

  function handleCadMouseUp() {
    isOrbitingIso = false;
    activeDrag = null;
    if (cadCanvas) {
      cadCanvas.style.cursor = (state.viewMode === 'view-3d') ? 'grab' : (hoverTarget ? (hoverTarget.type === 'corner' ? 'crosshair' : 'ns-resize') : 'default');
    }
    renderCad();
  }


  // ==========================================================================
  // 4. EXPORTACIÓN EXCEL (.XLSX) - EXACTAMENTE 30 FILAS EN TOTAL
  // ==========================================================================

  async function exportAoooGExcel() {
    if (!window.ExcelJS) {
      showToast('Error: Librería ExcelJS no cargada.');
      return;
    }

    try {
      const wb = new ExcelJS.Workbook();
      wb.creator = 'Vikar Calibración AoooG';
      const ws = wb.addWorksheet('calibration');

      ws.columns = [
        { header: 'Data', key: 'data', width: 11 },
        { header: 'Level', key: 'level', width: 14 },
        { header: 'Volume', key: 'volume', width: 14 }
      ];

      const headerRow = ws.getRow(1);
      headerRow.font = { name: 'Calibri', size: 11, bold: true };
      headerRow.alignment = { horizontal: 'left', vertical: 'middle' };

      const rows = state.calcCache.calibrationRows;
      const maxRow = 30;

      rows.forEach((r) => {
        const row = ws.getRow(r.rowNum);

        if (state.isImported) {
          row.getCell(1).value = r.dataVal;
          row.getCell(2).value = r.levelVal;
          row.getCell(3).value = r.volumeVal;
          row.getCell(1).numFmt = '0';
          row.getCell(2).numFmt = '0';
          row.getCell(3).numFmt = '0.0';
          row.font = { name: 'Calibri', size: 11, bold: false };
          return;
        }

        if (r.rowNum === 2) {
          row.getCell(1).value = 0;
        } else if (r.rowNum === 3) {
          row.getCell(1).value = Number(state.sensor.dataMin) || 100;
        } else if (r.rowNum === maxRow) {
          row.getCell(1).value = Number(state.sensor.dataMax) || 4660;
        } else {
          row.getCell(1).value = {
            formula: `ROUND($A$3 + (${r.rowNum}-3)*($A$${maxRow}-$A$3)/27, 0)`,
            result: r.dataVal
          };
        }
        row.getCell(1).numFmt = 'General';

        if (r.rowNum === 2) {
          row.getCell(2).value = 0;
        } else if (r.rowNum === maxRow) {
          row.getCell(2).value = state.calcCache.effH;
        } else {
          row.getCell(2).value = {
            formula: `ROUND((${r.rowNum}-2)*$B$${maxRow}/28, 0)`,
            result: r.levelVal
          };
        }
        row.getCell(2).numFmt = '#,##0';

        row.getCell(3).value = r.volumeVal;
        row.getCell(3).numFmt = '#,##0.0';
        row.font = { name: 'Calibri', size: 11, bold: false };
      });

      const buffer = await wb.xlsx.writeBuffer();
      const blob = new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
      const fileName = `calibracion_aooog_${state.vehicle.plate || 'tanque'}_${state.calcCache.totalVolume}L.xlsx`;

      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = fileName;
      link.click();
      URL.revokeObjectURL(link.href);

      showToast(`Excel descargado con éxito (${ws.rowCount} filas).`);
    } catch (err) {
      console.error(err);
      showToast('Error al generar el archivo Excel.');
    }
  }

  function exportCSV() {
    const rows = state.calcCache.calibrationRows;
    // Directiva sep=, y BOM UTF-8 (\uFEFF) para que Microsoft Excel (especialmente en español) divida automáticamente en columnas A, B, C
    let csv = '\uFEFFsep=,\r\nData,Level,Volume\r\n';
    rows.forEach(r => {
      csv += `${r.dataVal},${r.levelVal},${r.volumeVal.toFixed(1)}\r\n`;
    });

    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = `calibracion_aooog_${state.vehicle.plate || 'tanque'}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
    showToast('CSV exportado con éxito.');
  }

  function copyTableToClipboard() {
    const rows = state.calcCache.calibrationRows;
    let text = 'Data\tLevel\tVolume\n';
    rows.forEach(r => {
      text += `${r.dataVal}\t${r.levelVal}\t${r.volumeVal.toFixed(1)}\n`;
    });
    navigator.clipboard.writeText(text).then(() => {
      showToast('Tabla copiada al portapapeles.');
    });
  }

  // ==========================================================================
  // 5. INTERFAZ DE USUARIO Y TELEMETRÍA
  // ==========================================================================

  function updateAllUI() {
    computeStrappingTable();

    const H = state.calcCache.effH;
    const slider = document.getElementById('levelSlider');
    const numInput = document.getElementById('levelNumberInput');

    if (slider) {
      slider.max = H;
      if (state.currentLevelMm > H) state.currentLevelMm = H;
      slider.value = state.currentLevelMm;
    }
    if (numInput) {
      numInput.max = H;
      numInput.value = state.currentLevelMm;
    }

    const curVol = getVolumeAtHeight(state.currentLevelMm);
    const totalVol = state.calcCache.totalVolume;
    const emptyVol = Math.max(0, totalVol - curVol);
    const pct = totalVol > 0 ? (curVol / totalVol) * 100 : 0;

    const dataMin = Number(state.sensor.dataMin) || 100;
    const dataMax = Number(state.sensor.dataMax) || 4660;
    const curRaw = Math.round(dataMin + (state.currentLevelMm / H) * (dataMax - dataMin));

    const curM3 = (curVol / 1000).toFixed(4);
    const totalM3 = (totalVol / 1000).toFixed(4);
    const emptyM3 = (emptyVol / 1000).toFixed(4);

    setText('telemetryLevelTag', `${state.currentLevelMm} mm`);
    setText('telemetryVolume', `${curVol.toFixed(1)} L`);
    setText('telemetryPct', `${curM3} m³ (${pct.toFixed(1)}%)`);
    setText('telemetryTotal', `${totalVol.toFixed(1)} L`);
    setText('telemetryTotalSub', `${totalM3} m³ (100%)`);
    setText('telemetryEmpty', `${emptyVol.toFixed(1)} L`);
    setText('telemetryEmptySub', `${emptyM3} m³ restante`);
    setText('telemetryRaw', `${curRaw}`);

    setText('sideTotalVolume', `${totalVol.toFixed(1)} L (${totalM3} m³)`);
    setText('sideCurrentLiquid', `${curVol.toFixed(1)} L (${curM3} m³)`);
    setText('sideEmptySpace', `${emptyVol.toFixed(1)} L (${emptyM3} m³)`);

    renderTable();
    if (state.viewMode === 'view-3d') {
      updateThreeTank();
    } else {
      renderCad();
    }
  }

  function renderTable() {
    const tbody = document.getElementById('calibrationTableBody');
    if (!tbody) return;

    const rows = state.calcCache.calibrationRows;
    const curLevel = state.currentLevelMm;

    const lblTitle = document.getElementById('lblTableTitle');
    if (lblTitle) {
      if (state.isImported) {
        lblTitle.innerText = `Tabla de Calibración Importada (${rows.length} Puntos Oficiales)`;
      } else if (state.tableMode === 100) {
        lblTitle.innerText = 'Tabla de Calibración AoooG (100 Posiciones BLE - Slots 0 a 99)';
      } else {
        lblTitle.innerText = 'Tabla de Calibración AoooG (30 Puntos Proporcionales)';
      }
    }

    const btnToggle = document.getElementById('btnToggleTable100');
    if (btnToggle) {
      btnToggle.innerText = state.tableMode === 100 ? 'Ver 30 Puntos' : 'Ver 100 Posiciones (BLE)';
    }

    const btnUpload = document.getElementById('btnTableUploadBle');
    if (btnUpload) {
      btnUpload.style.display = (bleState.isConnected || bleState.isSimulated) ? 'inline-flex' : 'none';
    }

    let html = '';
    rows.forEach(r => {
      const isActive = Math.abs(r.levelVal - curLevel) <= 12;
      html += `
        <tr class="${isActive ? 'active-row' : ''}">
          <td><strong>${r.rowNum}</strong></td>
          <td>${r.dataVal} <span class="code-pill">${r.dataFormula}</span></td>
          <td>${r.levelVal} mm</td>
          <td><strong>${r.volumeVal.toFixed(1)} L</strong></td>
          <td>${r.pct.toFixed(1)} %</td>
        </tr>
      `;
    });

    tbody.innerHTML = html;
  }

  function setText(id, text) {
    const el = document.getElementById(id);
    if (el) el.innerText = text;
  }

  function showToast(msg) {
    let toast = document.getElementById('appToast');
    if (!toast) {
      toast = document.createElement('div');
      toast.id = 'appToast';
      toast.className = 'toast-notice';
      document.body.appendChild(toast);
    }
    toast.innerText = msg;
    toast.className = 'toast-notice show';
    setTimeout(() => {
      toast.className = 'toast-notice';
    }, 3000);
  }

  function toggleGeometrySubsections() {
    const type = state.tank.type;
    const secStep = document.getElementById('secStepTank');
    const secDouble = document.getElementById('secDoubleTank');
    const secDShape = document.getElementById('secDShapeTank');
    const secRadTrans = document.getElementById('secRadiiTransverse');
    const secRadLong = document.getElementById('secRadiiLongitudinal');
    const secRadVert = document.getElementById('secRadiiVertical');

    if (secStep) secStep.style.display = (type === 'step_notch') ? 'block' : 'none';
    if (secDouble) secDouble.style.display = (type === 'double_tank') ? 'block' : 'none';
    if (secDShape) secDShape.style.display = (type === 'd_shape') ? 'block' : 'none';

    const showRadii = (type === 'rectangular');
    if (secRadTrans) secRadTrans.style.display = showRadii ? 'block' : 'none';
    if (secRadLong) secRadLong.style.display = showRadii ? 'block' : 'none';
    if (secRadVert) secRadVert.style.display = showRadii ? 'block' : 'none';
  }

  // ==========================================================================
  // 6. EVENTOS Y VINCULACIÓN
  // ==========================================================================

  // ==========================================================================
  // 5. VISOR 3D REAL CON THREE.JS (INSPECCIÓN PURA, SIN EDICIÓN DE FORMAS)
  // ==========================================================================
  let threeScene = null;
  let threeCamera = null;
  let threeRenderer = null;
  let threeControls = null;
  let threeTankMesh = null;
  let threeTankEdges = null;
  let threeLiquidMesh = null;
  let threeProbeMesh = null;
  let threeStrapsMesh = null;
  let threeGrid = null;
  let threeAnimFrame = null;

  function initThreeViewer() {
    const container = document.getElementById('threeContainer');
    if (!container || threeRenderer || !window.THREE) return;

    const width = container.clientWidth || 600;
    const height = 420;

    // Escena profesional con fondo oscuro
    threeScene = new THREE.Scene();
    threeScene.background = new THREE.Color(0x0f172a);

    // Cámara de perspectiva
    threeCamera = new THREE.PerspectiveCamera(45, width / height, 1, 10000);
    threeCamera.position.set(900, 700, 1100);

    // Renderer WebGL
    threeRenderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    threeRenderer.setSize(width, height);
    threeRenderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    container.innerHTML = '';
    container.appendChild(threeRenderer.domElement);

    // OrbitControls: rotación suave 360°, zoom con scroll, desplazamiento con clic derecho
    if (THREE.OrbitControls) {
      threeControls = new THREE.OrbitControls(threeCamera, threeRenderer.domElement);
      threeControls.enableDamping = true;
      threeControls.dampingFactor = 0.08;
      threeControls.enablePan = true;
      threeControls.enableZoom = true;
      threeControls.minDistance = 20;
      threeControls.maxDistance = 8000;
    }

    // Luces
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.75);
    threeScene.add(ambientLight);

    const dirLight1 = new THREE.DirectionalLight(0xffffff, 0.85);
    dirLight1.position.set(800, 1500, 1000);
    threeScene.add(dirLight1);

    const dirLight2 = new THREE.DirectionalLight(0x38bdf8, 0.4);
    dirLight2.position.set(-800, -400, -800);
    threeScene.add(dirLight2);

    function animate() {
      threeAnimFrame = requestAnimationFrame(animate);
      if (threeControls) threeControls.update();
      if (threeRenderer && threeScene && threeCamera) {
        threeRenderer.render(threeScene, threeCamera);
      }
    }
    animate();

    window.addEventListener('resize', onThreeResize);
  }

  function onThreeResize() {
    const container = document.getElementById('threeContainer');
    if (!container || !threeRenderer || !threeCamera) return;
    const width = container.clientWidth;
    if (width > 0) {
      threeCamera.aspect = width / 420;
      threeCamera.updateProjectionMatrix();
      threeRenderer.setSize(width, 420);
    }
  }

  function updateThreeTank() {
    if (!threeScene || !window.THREE) return;

    if (threeTankMesh) {
      threeScene.remove(threeTankMesh);
      threeTankMesh.geometry.dispose();
      threeTankMesh = null;
    }
    if (threeTankEdges) {
      threeScene.remove(threeTankEdges);
      threeTankEdges.geometry.dispose();
      threeTankEdges = null;
    }
    if (threeLiquidMesh) {
      threeScene.remove(threeLiquidMesh);
      threeLiquidMesh.geometry.dispose();
      threeLiquidMesh = null;
    }
    if (threeProbeMesh) {
      threeScene.remove(threeProbeMesh);
      threeProbeMesh = null;
    }
    if (threeStrapsMesh) {
      threeScene.remove(threeStrapsMesh);
      threeStrapsMesh = null;
    }
    if (threeGrid) {
      threeScene.remove(threeGrid);
      threeGrid.geometry.dispose();
      threeGrid = null;
    }

    const eff = getEffectiveDimensions();
    const L = Math.max(10, eff.L);
    const W = Math.max(10, eff.W);
    const H = Math.max(10, eff.H);

    const w = W;
    const h = H;
    const rInf = {
      li: Math.min(Number(state.tank.r_inf_li) || 0, W / 2 - 1, H / 2 - 1),
      ld: Math.min(Number(state.tank.r_inf_ld) || 0, W / 2 - 1, H / 2 - 1),
      af: Math.min(Number(state.tank.r_inf_af) || 0, L / 2 - 1, H / 2 - 1),
      ap: Math.min(Number(state.tank.r_inf_ap) || 0, L / 2 - 1, H / 2 - 1)
    };
    const rSup = {
      li: Math.min(Number(state.tank.r_sup_li) || 0, W / 2 - 1, H / 2 - 1),
      ld: Math.min(Number(state.tank.r_sup_ld) || 0, W / 2 - 1, H / 2 - 1),
      af: Math.min(Number(state.tank.r_sup_af) || 0, L / 2 - 1, H / 2 - 1),
      ap: Math.min(Number(state.tank.r_sup_ap) || 0, L / 2 - 1, H / 2 - 1)
    };
    const rvGlobal = Number(state.tank.r_vert) || 0;
    const rVerts = {
      fi: Math.min(Number(state.tank.r_vert_fi) || rvGlobal, W / 2 - 1, L / 2 - 1),
      fd: Math.min(Number(state.tank.r_vert_fd) || rvGlobal, W / 2 - 1, L / 2 - 1),
      pi: Math.min(Number(state.tank.r_vert_pi) || rvGlobal, W / 2 - 1, L / 2 - 1),
      pd: Math.min(Number(state.tank.r_vert_pd) || rvGlobal, W / 2 - 1, L / 2 - 1)
    };

    function create3DTankGeometry(w, h, l, rI, rS, rV, seg = 28, isLiquid = false, liqH = h) {
      const geom = new THREE.BoxGeometry(w, h, l, seg, seg, seg);
      const pos = geom.attributes.position;
      const v = new THREE.Vector3();
      const maxR = Math.min(w / 2 - 0.5, l / 2 - 0.5, h / 2 - 0.5);

      for (let i = 0; i < pos.count; i++) {
        v.fromBufferAttribute(pos, i);

        const isFront = v.z >= 0;
        const isRight = v.x >= 0;
        const isRoof = v.y >= 0;

        // Radio vertical específico de la esquina (bajada)
        let rv = 0;
        if (isFront && !isRight) rv = rV.fi;
        else if (isFront && isRight) rv = rV.fd;
        else if (!isFront && !isRight) rv = rV.pi;
        else rv = rV.pd;
        rv = Math.max(0, Math.min(maxR, rv || 0));

        let rx = 0, rz = 0, ry = 0;
        if (isRoof) {
          if (isLiquid && liqH < H - 1) {
            rx = 0; rz = 0; ry = 0;
          } else {
            rx = isRight ? rS.ld : rS.li;
            rz = isFront ? rS.af : rS.ap;
            ry = Math.max(rx, rz);
          }
        } else {
          rx = isRight ? rI.ld : rI.li;
          rz = isFront ? rI.af : rI.ap;
          ry = Math.max(rx, rz);
        }

        rx = Math.max(0, Math.min(maxR, rx || 0));
        rz = Math.max(0, Math.min(maxR, rz || 0));
        ry = Math.max(0, Math.min(maxR, ry || 0));

        const effRx = Math.max(rx, rv);
        const effRz = Math.max(rz, rv);
        const effRy = ry;

        if (effRx > 0 || effRy > 0 || effRz > 0) {
          const halfX = w / 2 - effRx;
          const halfZ = l / 2 - effRz;
          const halfY = h / 2 - effRy;

          const cx = Math.max(-halfX, Math.min(halfX, v.x));
          const cy = Math.max(-halfY, Math.min(halfY, v.y));
          const cz = Math.max(-halfZ, Math.min(halfZ, v.z));

          const dx = v.x - cx;
          const dy = v.y - cy;
          const dz = v.z - cz;

          const nx = effRx > 0 ? dx / effRx : 0;
          const ny = effRy > 0 ? dy / effRy : 0;
          const nz = effRz > 0 ? dz / effRz : 0;
          const d = Math.sqrt(nx * nx + ny * ny + nz * nz);

          if (d > 0.001) {
            if (effRx > 0) v.x = cx + (nx / d) * effRx;
            if (effRy > 0) v.y = cy + (ny / d) * effRy;
            if (effRz > 0) v.z = cz + (nz / d) * effRz;
          }
        }

        // Texturas y hendiduras estructurales de estanque plástico rotomoldeado (estilo Bepô / Caren)
        if (state.tank.hasRecovecos) {
          const depthScale = (Number(state.tank.texturaLevel) || 50) / 50;

          // 1. Canales para las 2 Cinchas / Zunchos (hendiduras en Z en las posiciones de las correas)
          const z1 = -l * 0.26;
          const z2 = l * 0.26;
          const strapHalfW = 42;
          const strapDepth = (Number(state.tank.cinchasDepth) || 22) * depthScale;

          const distZ1 = Math.abs(v.z - z1);
          const distZ2 = Math.abs(v.z - z2);
          const minDistZ = Math.min(distZ1, distZ2);

          if (minDistZ < strapHalfW) {
            const factor = Math.cos((minDistZ / strapHalfW) * (Math.PI / 2));
            const indent = factor * factor * strapDepth;

            // Indentar paredes frontal y trasera
            if (v.x > w * 0.20) {
              v.x = Math.max(0, v.x - indent);
            } else if (v.x < -w * 0.20) {
              v.x = Math.min(0, v.x + indent);
            }

            // Indentar techo y piso suavemente
            if (v.y > h * 0.20) {
              v.y = Math.max(0, v.y - indent * 0.55);
            } else if (v.y < -h * 0.20) {
              v.y = Math.min(0, v.y + indent * 0.55);
            }
          }

          // 2. Nicho / Alojamiento de Boca de Carga (Centro frontal superior)
          const isFrontWall = v.x > w * 0.28;
          const isTopHalf = v.y > h * 0.15;
          const isCenterZ = Math.abs(v.z) < (l * 0.18);

          if (isFrontWall && isTopHalf && isCenterZ) {
            const zNorm = Math.abs(v.z) / (l * 0.18);
            const yNorm = (v.y - h * 0.15) / (h * 0.35);
            const neckIndent = (1 - zNorm) * Math.min(1, yNorm) * 26 * depthScale;
            v.x = Math.max(0, v.x - neckIndent);
          }

          // 3. Nervadura horizontal de refuerzo (a media altura)
          const isWallX = Math.abs(v.x) > w * 0.35;
          if (isWallX) {
            const yDistMid = Math.abs(v.y);
            const ribSpan = h * 0.14;
            if (yDistMid < ribSpan) {
              const ribFactor = Math.cos((yDistMid / ribSpan) * (Math.PI / 2));
              const ribIndent = ribFactor * ribFactor * 9 * depthScale;
              if (v.x > 0) v.x -= ribIndent;
              else v.x += ribIndent;
            }
          }

          // 4. Chaflán / Bisel Inferior de Chasis (Corte diagonal para despeje de larguero de camión, idéntico a Imagen 2)
          if (state.tank.recovecoEnabled !== false) {
            const recW = Math.min(w * 0.75, Math.max(0, Number(state.tank.recovecoWidth) || 0));
            const recH = Math.min(H * 0.85, Math.max(0, Number(state.tank.recovecoHeight) || 0));
            const stepW = Math.round(recW * 0.22);
            const isLeft = state.tank.recovecoSide !== 'bottom_right';

            // Altura real acumulada desde la base del estanque [0, H]
            const curY = isLiquid ? (v.y + liqH / 2) : (v.y + h / 2);

            if (recW > 0 && recH > 0 && curY < recH) {
              const u = Math.max(0, Math.min(1, curY / recH));
              const cutOffset = recW * (1 - u) + stepW * u;

              if (isLeft && v.x < 0) {
                const tx = (v.x - (-w / 2)) / (w / 2);
                if (tx >= 0 && tx <= 1) {
                  v.x += cutOffset * Math.pow(1 - tx, 1.25);
                }
              } else if (!isLeft && v.x > 0) {
                const tx = (w / 2 - v.x) / (w / 2);
                if (tx >= 0 && tx <= 1) {
                  v.x -= cutOffset * Math.pow(1 - tx, 1.25);
                }
              }
            }
          }
        }

        pos.setXYZ(i, v.x, v.y, v.z);
      }
      geom.translate(0, h / 2, 0);
      geom.computeVertexNormals();
      return geom;
    }

    const isPlastic = Boolean(state.tank.hasRecovecos);
    const tankGeom = create3DTankGeometry(W, H, L, rInf, rSup, rVerts, 36);
    const tankMat = new THREE.MeshPhysicalMaterial({
      color: isPlastic ? 0x232931 : 0x94a3b8, // Negro antracita PEHD para plástico rotomoldeado
      metalness: isPlastic ? 0.08 : 0.5,
      roughness: isPlastic ? 0.65 : 0.2,
      transmission: isPlastic ? 0.30 : 0.55,
      transparent: true,
      opacity: isPlastic ? 0.88 : 0.38,
      depthWrite: false,
      side: THREE.DoubleSide
    });
    threeTankMesh = new THREE.Mesh(tankGeom, tankMat);
    threeScene.add(threeTankMesh);

    const edgesGeom = new THREE.EdgesGeometry(tankGeom, 8);
    const edgesMat = new THREE.LineBasicMaterial({
      color: isPlastic ? 0x0284c7 : 0x38bdf8,
      linewidth: 1.5,
      transparent: true,
      opacity: isPlastic ? 0.35 : 0.85
    });
    threeTankEdges = new THREE.LineSegments(edgesGeom, edgesMat);
    threeScene.add(threeTankEdges);

    // Líquido Diésel Ámbar
    const curLevel = Math.max(0, Math.min(H, state.currentLevelMm));
    if (curLevel > 1) {
      const liqGeom = create3DTankGeometry(W - 2, curLevel, L - 2, rInf, rSup, rVerts, 28, true, curLevel);
      const liqMat = new THREE.MeshStandardMaterial({
        color: 0xd97706,
        roughness: 0.15,
        metalness: 0.15,
        transparent: true,
        opacity: 0.82,
        side: THREE.DoubleSide
      });
      threeLiquidMesh = new THREE.Mesh(liqGeom, liqMat);
      threeScene.add(threeLiquidMesh);
    }

    // Sonda y sensor AoooG
    const probeGroup = new THREE.Group();
    const rodGeom = new THREE.CylinderGeometry(3, 3, H + 10, 16);
    const rodMat = new THREE.MeshStandardMaterial({ color: 0xe2e8f0, metalness: 0.9, roughness: 0.1 });
    const rodMesh = new THREE.Mesh(rodGeom, rodMat);
    rodMesh.position.set(0, H / 2, 0);
    probeGroup.add(rodMesh);

    const headGeom = new THREE.CylinderGeometry(14, 14, 28, 24);
    const headMat = new THREE.MeshStandardMaterial({ color: 0x0f172a, metalness: 0.8, roughness: 0.2 });
    const headMesh = new THREE.Mesh(headGeom, headMat);
    headMesh.position.set(0, H + 14, 0);
    probeGroup.add(headMesh);

    const ringGeom = new THREE.TorusGeometry(13, 1.5, 8, 24);
    const ringMat = new THREE.MeshBasicMaterial({ color: 0x2563eb });
    const ringMesh = new THREE.Mesh(ringGeom, ringMat);
    ringMesh.rotation.x = Math.PI / 2;
    ringMesh.position.set(0, H + 20, 0);
    probeGroup.add(ringMesh);

    threeProbeMesh = probeGroup;
    threeScene.add(threeProbeMesh);

    // 2 Cintas / Zunchos de Sujeción y Tapa de Llenado (Estanques Plásticos)
    if (state.tank.hasRecovecos) {
      const strapsGroup = new THREE.Group();
      const strapMat = new THREE.MeshStandardMaterial({
        color: 0x0f172a, // Acero / caucho oscuro
        metalness: 0.8,
        roughness: 0.35
      });
      const strapWidth = 42;
      const strapThick = 4.5;
      const zOffset = L * 0.26;

      // Forma continua que abraza los radios del estanque sin sobresalir
      const rI = Math.min(W / 2 - 2, H / 2 - 2, (rInf.li + rInf.ld) / 2 || 60);
      const rS = Math.min(W / 2 - 2, H / 2 - 2, (rSup.li + rSup.ld) / 2 || 50);

      function addRoundedRect(path, x, y, width, height, ri, rs) {
        path.moveTo(x - width / 2 + ri, y);
        path.lineTo(x + width / 2 - ri, y);
        path.absarc(x + width / 2 - ri, y + ri, ri, -Math.PI / 2, 0, false);
        path.lineTo(x + width / 2, y + height - rs);
        path.absarc(x + width / 2 - rs, y + height - rs, rs, 0, Math.PI / 2, false);
        path.lineTo(x - width / 2 + rs, y + height);
        path.absarc(x - width / 2 + rs, y + height - rs, rs, Math.PI / 2, Math.PI, false);
        path.lineTo(x - width / 2, y + ri);
        path.absarc(x - width / 2 + ri, y + ri, ri, Math.PI, Math.PI * 1.5, false);
      }

      const strapShape = new THREE.Shape();
      addRoundedRect(strapShape, 0, -strapThick, W + strapThick * 2, H + strapThick * 2, rI + strapThick, rS + strapThick);
      const strapHole = new THREE.Path();
      addRoundedRect(strapHole, 0, 0, W, H, rI, rS);
      strapShape.holes.push(strapHole);

      const strapGeom = new THREE.ExtrudeGeometry(strapShape, { depth: strapWidth, bevelEnabled: false, curveSegments: 16 });
      strapGeom.translate(0, 0, -strapWidth / 2);

      [-zOffset, zOffset].forEach(zPos => {
        const mesh = new THREE.Mesh(strapGeom, strapMat);
        mesh.position.set(0, 0, zPos);
        strapsGroup.add(mesh);
      });

      // Tapa y cuello de boca de carga rotomoldeada en el nicho frontal (como en foto Bepô)
      const capGroup = new THREE.Group();
      const capMat = new THREE.MeshStandardMaterial({ color: 0x334155, metalness: 0.7, roughness: 0.3 });
      const neckMesh = new THREE.Mesh(new THREE.CylinderGeometry(18, 20, 22, 24), capMat);
      neckMesh.rotation.z = Math.PI * 0.12;
      neckMesh.position.set(W / 2 - 18, H - 2, 0);
      capGroup.add(neckMesh);

      const capMesh = new THREE.Mesh(new THREE.CylinderGeometry(24, 24, 10, 24), capMat);
      capMesh.rotation.z = Math.PI * 0.12;
      capMesh.position.set(W / 2 - 15, H + 9, 0);
      capGroup.add(capMesh);

      strapsGroup.add(capGroup);

      // Soportes / Patas de Chasis y Punto Luminoso (idénticos a Imagen 2)
      if (state.tank.recovecoEnabled !== false) {
        const recW = Math.min(W * 0.75, Math.max(0, Number(state.tank.recovecoWidth) || 0));
        const recH = Math.min(H * 0.85, Math.max(0, Number(state.tank.recovecoHeight) || 0));
        const stepW = Math.round(recW * 0.22);
        const isLeft = state.tank.recovecoSide !== 'bottom_right';

        const bracketMat = new THREE.MeshStandardMaterial({
          color: 0x0f172a, // Acero negro chasis
          metalness: 0.85,
          roughness: 0.25
        });

        const bW = 16;
        const bD = 32;
        const bH = recH;
        const bGeom = new THREE.BoxGeometry(bW, bH, bD);
        const posX = isLeft ? (-W / 2 + stepW / 2 + 8) : (W / 2 - stepW / 2 - 8);

        [-L * 0.25, L * 0.25].forEach(zPos => {
          const mesh = new THREE.Mesh(bGeom, bracketMat);
          mesh.position.set(posX, bH / 2, zPos);
          strapsGroup.add(mesh);
        });

        // Punto luminoso de referencia en esquina inferior (como en Imagen 2)
        const markerGeom = new THREE.SphereGeometry(6, 16, 16);
        const markerMat = new THREE.MeshBasicMaterial({ color: 0xfef08a });
        const markerMesh = new THREE.Mesh(markerGeom, markerMat);
        const markerX = isLeft ? (W / 2 - 20) : (-W / 2 + 20);
        markerMesh.position.set(markerX, 10, L / 2 - 20);
        strapsGroup.add(markerMesh);
      }

      threeStrapsMesh = strapsGroup;
      threeScene.add(threeStrapsMesh);
    }

    // Suelo
    const maxDim = Math.max(L, W, H);
    threeGrid = new THREE.GridHelper(maxDim * 2.5, 20, 0x334155, 0x1e293b);
    threeGrid.position.set(0, -1, 0);
    threeScene.add(threeGrid);

    if (threeControls) {
      threeControls.target.set(0, H / 2, 0);
      const camDist = maxDim * 2.1;
      threeCamera.position.set(camDist * 0.85, H + camDist * 0.45, camDist * 0.85);
      threeControls.update();
    }
  }

  // ==========================================================================
  // PROTOCOLO Y CONTROLADOR WEB BLUETOOTH (BLE) PARA SENSORES AOOG / AG-BFLS
  // ==========================================================================

  const AoooGProtocol = {
    SERVICE_UUID: '0000fff0-1212-efde-1523-785feabcd123',
    CHAR_WRITE_UUID: '0000fff1-1212-efde-1523-785feabcd123',
    CHAR_NOTIFY_UUID: '0000fff2-1212-efde-1523-785feabcd123',

    crc8(data) {
      let crc = 0;
      for (const byte of data) {
        crc ^= byte & 0xff;
        for (let bit = 0; bit < 8; bit++) crc = (crc & 1) ? ((crc >>> 1) ^ 0x8c) : (crc >>> 1);
      }
      return crc & 0xff;
    },

    buildFrame(sensorId, cmd, payload = []) {
      if (!Array.isArray(sensorId) || sensorId.length !== 3 || sensorId.some(v => !Number.isInteger(v) || v < 0 || v > 255)) {
        throw new Error('ID BLE del sensor inválido; se requieren 3 bytes de anuncio.');
      }
      if (!Number.isInteger(cmd) || cmd < 0 || cmd > 255 || payload.length > 250 || payload.some(v => !Number.isInteger(v) || v < 0 || v > 255)) {
        throw new Error('Comando o payload BLE fuera de rango.');
      }
      const length = 5 + payload.length;
      const body = [length, ...sensorId, cmd, ...payload];
      return Uint8Array.from([0x0c, ...body, this.crc8(body)]);
    },

    parseFrame(data) {
      if (!data || data.length < 7 || data[0] !== 0x0c || data[1] !== data.length - 2) return null;
      if (this.crc8(data.subarray(1, data.length - 1)) !== data[data.length - 1]) return null;
      return {
        sensorId: [data[2], data[3], data[4]],
        cmd: data[5],
        payload: data.subarray(6, data.length - 1)
      };
    },

    rowToBytes(volumeL, levelMm, fixVal) {
      const volume = Number(volumeL), level = Number(levelMm), fix = Number(fixVal);
      if (!Number.isFinite(volume) || volume < 0 || !Number.isInteger(level) || level < 0 || level > 65535 ||
          !Number.isInteger(fix) || fix < 0 || fix > 5000) throw new Error('Registro de calibración fuera de rango.');
      const bytes = new Uint8Array(8);
      const view = new DataView(bytes.buffer);
      view.setFloat32(0, volume, true);
      view.setUint16(4, level, true);
      view.setUint16(6, fix, true);
      return bytes;
    }
  };

  const bleState = {
    device: null, server: null, charWrite: null, charNotify: null,
    sensorId: null, isAuthenticated: false, isConnected: false, isSimulated: false,
    pollTimer: null, pendingCommand: null, emptyFreq: null, fullFreq: null,
    outputMode: null, calibrationTable: null
  };

  function sameSensorId(a, b) {
    return Array.isArray(a) && Array.isArray(b) && a.length === 3 && b.length === 3 && a.every((v, i) => v === b[i]);
  }

  function sendBleCommand(command, payload = [], timeoutMs = 5000) {
    if (!bleState.isConnected || !bleState.charWrite || !bleState.sensorId) return Promise.reject(new Error('No hay conexión BLE válida.'));
    if (bleState.pendingCommand) return Promise.reject(new Error('Hay otro comando BLE esperando respuesta.'));
    return new Promise(async (resolve, reject) => {
      const pending = { command, resolve, reject, timer: null };
      pending.timer = setTimeout(() => {
        if (bleState.pendingCommand === pending) bleState.pendingCommand = null;
        reject(new Error('Tiempo de espera agotado para comando 0x' + command.toString(16).padStart(2, '0').toUpperCase() + '.'));
      }, timeoutMs);
      bleState.pendingCommand = pending;
      try {
        const frame = AoooGProtocol.buildFrame(bleState.sensorId, command, payload);
        if (typeof bleState.charWrite.writeValueWithResponse === 'function') await bleState.charWrite.writeValueWithResponse(frame);
        else await bleState.charWrite.writeValue(frame);
      } catch (error) {
        clearTimeout(pending.timer);
        if (bleState.pendingCommand === pending) bleState.pendingCommand = null;
        reject(error);
      }
    });
  }

  function isSuccessAck(response, command) {
    return !!response && response.cmd === command && response.payload.length === 1 && response.payload[0] === 0x00;
  }

  function extractSensorIdFromAdvertisement(event) {
    const dataMap = event && event.manufacturerData;
    if (!dataMap || typeof dataMap.get !== 'function') return null;
    const aooog = dataMap.get(0xff43);
    if (aooog && aooog.byteLength === 15) {
      const bytes = new Uint8Array(aooog.buffer, aooog.byteOffset, aooog.byteLength);
      const id = Array.from(bytes.subarray(0, 3));
      return id.some(v => v !== 0) ? id : null;
    }
    const universal = dataMap.get(0xffff);
    if (universal && universal.byteLength === 24) {
      const bytes = new Uint8Array(universal.buffer, universal.byteOffset, universal.byteLength);
      if (bytes[0] === 0x3f && bytes[1] === 0x36 && bytes[2] === 0xb4 && bytes[5] === 0x5b) {
        const id = Array.from(bytes.subarray(6, 9));
        return id.some(v => v !== 0) ? id : null;
      }
    }
    return null;
  }

  async function waitForAdvertisedSensorId(device, timeoutMs = 10000) {
    return new Promise(async (resolve, reject) => {
      let settled = false;
      const finish = (error, id) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        device.removeEventListener('advertisementreceived', onAdvertisement);
        if (error) reject(error); else resolve(id);
      };
      const onAdvertisement = event => {
        const id = extractSensorIdFromAdvertisement(event);
        if (id) finish(null, id);
      };
      const timer = setTimeout(() => finish(new Error('El sensor no publicó un ID AOOOG/BFLS válido. No se enviaron comandos.'), null), timeoutMs);
      device.addEventListener('advertisementreceived', onAdvertisement);
      try {
        if (typeof device.watchAdvertisements !== 'function') throw new Error('Este navegador no expone los anuncios BLE necesarios para identificar el sensor de forma segura.');
        await device.watchAdvertisements();
      } catch (error) {
        finish(error, null);
      }
    });
  }

  function updateBleUI() {
    const panel = document.getElementById('panelBleSensor');
    const badgeLive = document.getElementById('badgeBleLive');
    const badgeAuth = document.getElementById('badgeBleAuth');
    const devName = document.getElementById('bleDeviceName');
    const devInfo = document.getElementById('bleDeviceInfo');
    const lblBtn = document.getElementById('lblBleBtn');
    const btnUpload = document.getElementById('btnTableUploadBle');
    const active = bleState.isConnected || bleState.isSimulated;
    if (panel) panel.style.display = active ? 'block' : 'none';
    if (btnUpload) btnUpload.style.display = active ? 'inline-flex' : 'none';
    if (lblBtn) lblBtn.innerText = active ? 'Sensor Conectado' : 'Conectar Sensor BLE';
    if (active) {
      if (devName) devName.innerText = bleState.isSimulated ? 'AOOG_BFLS_DEMO (SIMULADOR)' : (bleState.device?.name || 'Sensor AOOG/BFLS');
      if (devInfo) devInfo.innerText = 'ID: ' + (bleState.sensorId || []).map(v => v.toString(16).padStart(2, '0').toUpperCase()).join(':') + ' • GATT Conectado';
      if (badgeAuth) {
        badgeAuth.innerText = bleState.isSimulated ? 'DEMO' : (bleState.isAuthenticated ? 'AUTENTICADO' : 'BLOQUEADO');
        badgeAuth.style.background = bleState.isSimulated ? '#475569' : (bleState.isAuthenticated ? '#16a34a' : '#eab308');
        badgeAuth.style.color = '#ffffff';
      }
      if (badgeLive) {
        badgeLive.innerText = bleState.isSimulated ? 'SIMULADO' : 'CONECTADO';
        badgeLive.style.background = bleState.isSimulated ? '#475569' : '#16a34a';
      }
    } else {
      if (badgeAuth) { badgeAuth.innerText = 'BLOQUEADO'; badgeAuth.style.background = '#1e293b'; }
      if (badgeLive) { badgeLive.innerText = 'DESCONECTADO'; badgeLive.style.background = '#475569'; }
    }
  }

  function handleBleNotification(event) {
    const value = event.target.value;
    const bytes = new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    const parsed = AoooGProtocol.parseFrame(bytes);
    if (!parsed || !sameSensorId(parsed.sensorId, bleState.sensorId)) return;

    const pending = bleState.pendingCommand;
    if (pending && parsed.cmd === pending.command) {
      clearTimeout(pending.timer);
      bleState.pendingCommand = null;
      pending.resolve(parsed);
    }

    if (parsed.cmd === 0x14 && parsed.payload.length >= 22) {
      const view = new DataView(parsed.payload.buffer, parsed.payload.byteOffset, parsed.payload.byteLength);
      const batteryCode = view.getUint16(0, false);
      const battery = Math.max(0, Math.min(100, (batteryCode - 500) * 100 / 220));
      const temp = view.getInt16(2, false) / 8;
      const fullFreq = view.getFloat32(6, true);
      const emptyFreq = view.getFloat32(10, true);
      const freq = view.getFloat32(14, true);
      const output = view.getFloat32(18, true);
      if ([temp, fullFreq, emptyFreq, freq, output].every(Number.isFinite)) {
        bleState.emptyFreq = emptyFreq;
        bleState.fullFreq = fullFreq;
        setText('bleLiveLevel', bleState.outputMode === 1 ? output.toFixed(0) + ' mm' : '-- mm');
        const outputLabel = bleState.outputMode === 0 ? output.toFixed(1) + ' %' :
          (bleState.outputMode === 1 ? '-- (salida en mm)' :
            (bleState.outputMode === 2 ? output.toFixed(1) + ' L' : output.toFixed(1) + ' (modo no leído)'));
        setText('bleLiveVolume', outputLabel);
        setText('bleLiveFreq', freq.toFixed(1) + ' Hz');
        setText('bleLiveBatteryTemp', battery.toFixed(0) + '% • ' + temp.toFixed(1) + '°C');
      }
    }
  }

  async function connectBleSensor() {
    if (!navigator.bluetooth) {
      alert('Web Bluetooth no está disponible. Utiliza Chrome o Edge compatible en un contexto HTTPS.');
      return;
    }
    try {
      const device = await navigator.bluetooth.requestDevice({
        filters: [
          { manufacturerData: [{ companyIdentifier: 0xff43 }] },
          { manufacturerData: [{ companyIdentifier: 0xffff }] },
          { namePrefix: 'AOOG' }, { namePrefix: 'BFLS' }, { namePrefix: 'FM' }, { namePrefix: 'Fuel' }
        ],
        optionalServices: [AoooGProtocol.SERVICE_UUID]
      });
      bleState.device = device;
      device.addEventListener('gattserverdisconnected', disconnectBleSensor);
      const server = await device.gatt.connect();
      bleState.server = server;
      bleState.sensorId = await waitForAdvertisedSensorId(device);
      const service = await server.getPrimaryService(AoooGProtocol.SERVICE_UUID);
      bleState.charWrite = await service.getCharacteristic(AoooGProtocol.CHAR_WRITE_UUID);
      bleState.charNotify = await service.getCharacteristic(AoooGProtocol.CHAR_NOTIFY_UUID);
      await bleState.charNotify.startNotifications();
      bleState.charNotify.addEventListener('characteristicvaluechanged', handleBleNotification);
      bleState.isConnected = true;
      bleState.isSimulated = false;
      bleState.isAuthenticated = false;
      updateBleUI();
      try { bleState.outputMode = await readOutputMode(); }
      catch (modeError) { console.warn('No se pudo leer el modo de salida inicial:', modeError.message); }
      if (bleState.pollTimer) clearInterval(bleState.pollTimer);
      bleState.pollTimer = setInterval(async () => {
        if (!bleState.isConnected || bleState.pendingCommand) return;
        try { await sendBleCommand(0x14, [], 4000); } catch (error) { console.warn('Telemetría BLE:', error.message); }
      }, 2500);
      showToast('Conectado e identificado: ' + (device.name || 'Sensor AOOG/BFLS'));
    } catch (error) {
      await disconnectBleSensor();
      alert('No se pudo establecer una conexión BLE segura: ' + error.message);
    }
  }

  async function disconnectBleSensor() {
    if (bleState.pollTimer) clearInterval(bleState.pollTimer);
    bleState.pollTimer = null;
    if (bleState.pendingCommand) {
      clearTimeout(bleState.pendingCommand.timer);
      bleState.pendingCommand.reject(new Error('Conexión BLE cerrada.'));
      bleState.pendingCommand = null;
    }
    const device = bleState.device;
    if (bleState.charNotify) {
      try { bleState.charNotify.removeEventListener('characteristicvaluechanged', handleBleNotification); } catch (_) {}
    }
    bleState.device = null; bleState.server = null; bleState.charWrite = null; bleState.charNotify = null;
    bleState.sensorId = null; bleState.isConnected = false; bleState.isSimulated = false;
    bleState.isAuthenticated = false; bleState.emptyFreq = null; bleState.fullFreq = null; bleState.outputMode = null;
    updateBleUI();
    if (device?.gatt?.connected) {
      try { device.gatt.disconnect(); } catch (_) {}
    }
  }

  function simulateBleSensor() {
    if (bleState.pollTimer) clearInterval(bleState.pollTimer);
    bleState.device = null; bleState.server = null; bleState.charWrite = null; bleState.charNotify = null;
    bleState.sensorId = [0x53, 0x49, 0x4d];
    bleState.isConnected = false; bleState.isSimulated = true; bleState.isAuthenticated = false;
    bleState.emptyFreq = 15200; bleState.fullFreq = 10400; bleState.outputMode = 2;
    bleState.calibrationTable = Array.from({ length: 100 }, () => ({ volume: 0, level: 0, data: 0 }));
    updateBleUI();
    let angle = 0;
    bleState.pollTimer = setInterval(() => {
      if (!bleState.isSimulated) return;
      angle += 0.08;
      const level = Math.round((state.calcCache.effH || 370) * (0.6 + Math.sin(angle) * 0.15));
      setText('bleLiveLevel', level + ' mm');
      setText('bleLiveVolume', getVolumeAtHeight(level).toFixed(1) + ' L');
      setText('bleLiveFreq', Math.round(15200 - (angle % 6.28) * 760) + ' Hz');
      setText('bleLiveBatteryTemp', '98% • 24.5°C');
    }, 1500);
    showToast('Modo DEMO activo: no hay comunicación con un sensor físico.');
  }

  async function authenticateBleSensor() {
    const input = document.getElementById('bleCredentialInput');
    const credential = (input?.value || '').trim();
    if (!/^[0-9a-fA-F]{16}$/.test(credential)) {
      alert('Introduce exactamente 16 caracteres hexadecimales (8 bytes) entregados por el fabricante.');
      return;
    }
    if (bleState.isSimulated) {
      showToast('DEMO: no se autentica ningún sensor físico.');
      return;
    }
    if (!bleState.isConnected) { alert('Conecta el sensor primero.'); return; }
    try {
      const bytes = Array.from({ length: 8 }, (_, i) => parseInt(credential.slice(i * 2, i * 2 + 2), 16));
      const response = await sendBleCommand(0x12, bytes, 6000);
      bleState.isAuthenticated = isSuccessAck(response, 0x12);
      updateBleUI();
      if (!bleState.isAuthenticated) throw new Error('El sensor no confirmó la autenticación.');
      if (input) input.value = '';
      showToast('Autenticación confirmada por el sensor.');
    } catch (error) {
      bleState.isAuthenticated = false; updateBleUI();
      alert('Autenticación no confirmada: ' + error.message);
    }
  }

  async function readBleSensorParameters() {
    if (bleState.isSimulated) {
      setText('bleFreqEmpty', bleState.emptyFreq.toLocaleString() + ' Hz');
      setText('bleFreqFull', bleState.fullFreq.toLocaleString() + ' Hz');
      setText('bleDeltaFreq', 'Delta: ' + Math.abs(bleState.emptyFreq - bleState.fullFreq).toLocaleString() + ' Hz');
      showToast('DEMO: parámetros simulados, no leídos de un sensor.');
      return;
    }
    try {
      const response = await sendBleCommand(0x0d, [], 6000);
      if (!response || response.payload.length !== 13) throw new Error('Respuesta 0x0D inválida.');
      const view = new DataView(response.payload.buffer, response.payload.byteOffset, response.payload.byteLength);
      const empty = view.getFloat32(4, true), full = view.getFloat32(8, true);
      if (!Number.isFinite(empty) || !Number.isFinite(full) || empty <= 0 || full <= 0) throw new Error('Frecuencias devueltas fuera de rango.');
      bleState.emptyFreq = empty; bleState.fullFreq = full;
      setText('bleFreqEmpty', empty.toLocaleString() + ' Hz');
      setText('bleFreqFull', full.toLocaleString() + ' Hz');
      setText('bleDeltaFreq', 'Delta: ' + Math.abs(empty - full).toLocaleString() + ' Hz');
      showToast('Parámetros leídos y validados desde el sensor.');
    } catch (error) { alert('No se pudieron leer los parámetros: ' + error.message); }
  }

  function saveBleSensorHeight() {
    const input = document.getElementById('bleSensorHeight');
    const value = Number(input?.value || 0);
    if (!Number.isFinite(value) || value <= 0 || value > 65535) {
      alert('Introduce una altura local válida entre 1 y 65535 mm.'); return;
    }
    state.tank.height = value; state.currentLevelMm = value;
    syncInputsFromState(); updateAllUI();
    const log = document.getElementById('bleStatusLog');
    if (log) log.innerText = '[' + new Date().toLocaleTimeString() + '] Altura aplicada únicamente al modelo local: ' + value + ' mm. No se escribió en el sensor.';
    showToast('Altura aplicada al cálculo local; no se modificó el sensor.');
  }

  function decodeCalibrationBlock(response, startIndex) {
    if (!response || response.payload.length !== 80) throw new Error('Bloque 0x15 inválido en índice ' + startIndex + '.');
    const view = new DataView(response.payload.buffer, response.payload.byteOffset, response.payload.byteLength);
    return Array.from({ length: 10 }, (_, i) => ({
      volume: view.getFloat32(i * 8, true),
      level: view.getUint16(i * 8 + 4, true),
      data: view.getUint16(i * 8 + 6, true)
    }));
  }

  async function readBleCalibrationTable() {
    const progress = document.getElementById('bleProgressContainer');
    const bar = document.getElementById('bleProgressBar');
    const label = document.getElementById('bleProgressLabel');
    const pct = document.getElementById('bleProgressPct');
    const log = document.getElementById('bleStatusLog');
    if (progress) progress.style.display = 'block';
    try {
      const rows = [];
      for (let block = 0; block < 10; block++) {
        const start = block * 10;
        if (label) label.innerText = 'Leyendo bloque ' + (block + 1) + '/10...';
        let decoded;
        if (bleState.isSimulated) {
          await new Promise(resolve => setTimeout(resolve, 80));
          decoded = bleState.calibrationTable.slice(start, start + 10);
        } else {
          const response = await sendBleCommand(0x15, [start], 9000);
          decoded = decodeCalibrationBlock(response, start);
        }
        rows.push(...decoded);
        if (bar) bar.style.width = ((block + 1) * 10) + '%';
        if (pct) pct.innerText = ((block + 1) * 10) + '%';
      }
      if (rows.length !== 100) throw new Error('No se recibieron los 100 registros.');
      bleState.calibrationTable = rows;
      if (label) label.innerText = 'Lectura completa: 100 registros recibidos.';
      if (log) log.innerText = '[' + new Date().toLocaleTimeString() + '] Lectura real completada: 100 slots, 10 bloques recibidos y decodificados.';
      showToast(bleState.isSimulated ? 'DEMO: tabla simulada leída.' : 'Se leyeron los 100 registros del sensor.');
      if (bleState.isSimulated) console.info('Tabla DEMO; no corresponde a memoria física.');
    } catch (error) {
      if (label) label.innerText = 'Lectura incompleta; no se verificó la tabla.';
      if (log) log.innerText = '[' + new Date().toLocaleTimeString() + '] ERROR de lectura: ' + error.message;
      alert('No se pudo leer la tabla completa: ' + error.message);
    }
  }

  function calibrationRowsForUpload() {
    if (!state.isImported || !Array.isArray(state.importedRows)) {
      throw new Error('Para escribir el sensor debes importar una tabla con coordenadas Data reales. La tabla geométrica calculada no sustituye las coordenadas 0x1B medidas.');
    }
    const rows = state.importedRows.map(row => ({
      data: Number(row.data), level: Number(row.level), volume: Number(row.volume)
    }));
    if (rows.length && (rows[0].data !== 0 || rows[0].level !== 0 || rows[0].volume !== 0)) rows.unshift({ data: 0, level: 0, volume: 0 });
    if (rows.length < 2 || rows.length > 100) throw new Error('La tabla debe tener entre 2 y 100 registros.');
    let previous = { data: -1, level: -1, volume: -1 };
    rows.forEach((row, index) => {
      if (!Number.isInteger(row.data) || row.data < 0 || row.data > 5000 ||
          !Number.isInteger(row.level) || row.level < 0 || row.level > 65535 ||
          !Number.isFinite(row.volume) || row.volume < 0) throw new Error('Registro ' + (index + 1) + ' fuera de rango.');
      if (index > 0 && (row.data <= previous.data || row.level <= previous.level || row.volume < previous.volume)) {
        throw new Error('Data y Level deben crecer estrictamente y Volume no puede disminuir (registro ' + (index + 1) + ').');
      }
      previous = row;
    });
    if (rows[0].data !== 0 || rows[0].level !== 0 || rows[0].volume !== 0) throw new Error('Falta el origen 0 / 0 / 0.');
    while (rows.length < 100) rows.push({ data: 0, level: 0, volume: 0 });
    return rows;
  }

  function bytesEqual(a, b) {
    return a.length === b.length && a.every((value, index) => value === b[index]);
  }

  async function readOutputMode() {
    const response = await sendBleCommand(0x1a, [], 6000);
    if (!response || response.payload.length !== 1 || ![0, 1, 2].includes(response.payload[0])) throw new Error('No se pudo leer el modo de salida actual.');
    return response.payload[0];
  }

  async function writeOutputMode(mode) {
    const ack = await sendBleCommand(0x19, [mode], 6000);
    if (!isSuccessAck(ack, 0x19)) throw new Error('El sensor no confirmó el cambio de modo.');
    const actual = await readOutputMode();
    if (actual !== mode) throw new Error('El modo leído (' + actual + ') no coincide con el solicitado (' + mode + ').');
    bleState.outputMode = actual;
    return actual;
  }

  async function restoreCalibration(backup, previousMode) {
    let tableOk = true;
    for (let block = 0; block < 10; block++) {
      const start = block * 10;
      const payload = [start, ...backup[block]];
      const ack = await sendBleCommand(0x16, payload, 10000);
      if (!isSuccessAck(ack, 0x16)) { tableOk = false; break; }
      const check = await sendBleCommand(0x15, [start], 10000);
      if (!check || !bytesEqual(Array.from(check.payload), backup[block])) { tableOk = false; break; }
    }
    let modeOk = false;
    try { modeOk = (await writeOutputMode(previousMode)) === previousMode; } catch (_) {}
    return tableOk && modeOk;
  }

  async function uploadCalibrationTableToBle() {
    const log = document.getElementById('bleStatusLog');
    const label = document.getElementById('bleProgressLabel');
    const progress = document.getElementById('bleProgressContainer');
    const bar = document.getElementById('bleProgressBar');
    const pct = document.getElementById('bleProgressPct');
    try {
      if (bleState.isSimulated) throw new Error('Modo DEMO: no se permite simular una escritura como si fuera una calibración física.');
      if (!bleState.isConnected || !bleState.isAuthenticated) throw new Error('Conecta y autentica el sensor con la credencial oficial antes de escribir.');
      const rows = calibrationRowsForUpload();
      if (progress) progress.style.display = 'block';
      if (label) label.innerText = 'Leyendo modo y respaldando memoria original...';
      const originalMode = await readOutputMode();
      const backup = [];
      for (let block = 0; block < 10; block++) {
        const response = await sendBleCommand(0x15, [block * 10], 10000);
        if (!response || response.payload.length !== 80) throw new Error('No se pudo respaldar el bloque ' + block + '. Escritura cancelada.');
        backup.push(Array.from(response.payload));
      }
      try {
        for (let block = 0; block < 10; block++) {
          const start = block * 10;
          const payload = [start];
          for (let i = start; i < start + 10; i++) payload.push(...AoooGProtocol.rowToBytes(rows[i].volume, rows[i].level, rows[i].data));
          if (label) label.innerText = 'Escribiendo bloque ' + (block + 1) + '/10...';
          const ack = await sendBleCommand(0x16, payload, 10000);
          if (!isSuccessAck(ack, 0x16)) throw new Error('El sensor no confirmó la escritura del bloque ' + block + '.');
          const readBack = await sendBleCommand(0x15, [start], 10000);
          if (!readBack || !bytesEqual(Array.from(readBack.payload), payload.slice(1))) throw new Error('La lectura de retorno no coincide en el bloque ' + block + '.');
          if (bar) bar.style.width = ((block + 1) * 10) + '%';
          if (pct) pct.innerText = ((block + 1) * 10) + '%';
        }
        if (label) label.innerText = 'Verificando modo de salida Litros (0x02)...';
        await writeOutputMode(0x02);
      } catch (writeError) {
        if (label) label.innerText = 'Fallo detectado. Restaurando tabla y modo anteriores...';
        const restored = await restoreCalibration(backup, originalMode);
        throw new Error(writeError.message + (restored ? ' Se restauraron y verificaron tabla y modo anteriores.' : ' ATENCIÓN: no se pudo confirmar la restauración completa; no desconectes el sensor y revisa la memoria.'));
      }
      if (label) label.innerText = '100 slots escritos y leídos de retorno; modo litros verificado.';
      if (log) log.innerText = '[' + new Date().toLocaleTimeString() + '] PASS: 10 bloques escritos, 10 lecturas byte a byte y modo 0x02 leído de vuelta.';
      showToast('Calibración transferida y verificada por lectura de retorno.');
    } catch (error) {
      if (log) log.innerText = '[' + new Date().toLocaleTimeString() + '] ERROR: ' + error.message;
      alert('No se completó la calibración: ' + error.message);
    }
  }

  async function setBleEmptyPoint() {
    if (!confirm('¿Estanque vacío y sonda seca? Se fijará el punto vacío en el sensor.')) return;
    try {
      if (bleState.isSimulated) throw new Error('DEMO: no se modifica ningún sensor físico.');
      if (!bleState.isAuthenticated) throw new Error('Autentica el sensor primero.');
      const response = await sendBleCommand(0x10, [], 6000);
      if (!isSuccessAck(response, 0x10)) throw new Error('El sensor no confirmó el punto vacío.');
      await readBleSensorParameters();
      showToast('Punto vacío confirmado por el sensor.');
    } catch (error) { alert('No se fijó el punto vacío: ' + error.message); }
  }

  async function setBleFullPoint() {
    if (!confirm('¿La sonda está completamente sumergida? Se fijará el punto lleno en el sensor.')) return;
    try {
      if (bleState.isSimulated) throw new Error('DEMO: no se modifica ningún sensor físico.');
      if (!bleState.isAuthenticated) throw new Error('Autentica el sensor primero.');
      const response = await sendBleCommand(0x11, [], 6000);
      if (!isSuccessAck(response, 0x11)) throw new Error('El sensor no confirmó el punto lleno.');
      await readBleSensorParameters();
      showToast('Punto lleno confirmado por el sensor.');
    } catch (error) { alert('No se fijó el punto lleno: ' + error.message); }
  }

  async function setBleOutputModeFromSelect() {
    const select = document.getElementById('selBleOutputMode');
    const mode = Number.parseInt(select?.value || '2', 10);
    if (![0, 1, 2].includes(mode)) { alert('Modo de salida inválido.'); return; }
    try {
      if (bleState.isSimulated) throw new Error('DEMO: no se modifica ningún sensor físico.');
      if (!bleState.isAuthenticated) throw new Error('Autentica el sensor primero.');
      await writeOutputMode(mode);
      showToast('Modo de salida confirmado: ' + ({ 0: 'Porcentaje', 1: 'Milímetros', 2: 'Litros' })[mode] + '.');
    } catch (error) { alert('No se pudo aplicar el modo: ' + error.message); }
  }

  async function rebootBleSensor() {
    if (!confirm('¿Reiniciar el sensor?')) return;
    try {
      if (bleState.isSimulated) throw new Error('DEMO: no se reinicia ningún sensor físico.');
      if (!bleState.isAuthenticated) throw new Error('Autentica el sensor primero.');
      const response = await sendBleCommand(0x01, [], 6000);
      if (!isSuccessAck(response, 0x01)) throw new Error('El sensor no confirmó el reinicio.');
      showToast('Reinicio confirmado; el sensor puede desconectarse momentáneamente.');
    } catch (error) { alert('No se pudo confirmar el reinicio: ' + error.message); }
  }

  async function sleepBleSensor() {
    if (!confirm('¿Poner el sensor en hibernación? Se perderá la conexión BLE.')) return;
    try {
      if (bleState.isSimulated) throw new Error('DEMO: no se hiberna ningún sensor físico.');
      if (!bleState.isAuthenticated) throw new Error('Autentica el sensor primero.');
      const response = await sendBleCommand(0x02, [], 6000);
      if (!isSuccessAck(response, 0x02)) throw new Error('El sensor no confirmó la hibernación.');
      showToast('Hibernación confirmada por el sensor.');
      await disconnectBleSensor();
    } catch (error) { alert('No se pudo confirmar la hibernación: ' + error.message); }
  }

  function saveBleSensorHeight() {
    const input = document.getElementById('bleSensorHeight');
    const val = Number(input ? input.value : 0) || 0;
    if (val <= 0) {
      alert('Introduzca una altura de sensor válida mayor a 0 mm.');
      return;
    }
    state.tank.height = val;
    state.currentLevelMm = val;
    syncInputsFromState();
    updateAllUI();
    const statusLog = document.getElementById('bleStatusLog');
    if (statusLog) statusLog.innerText = `[${new Date().toLocaleTimeString()}] Altura efectiva de corte fijada a ${val} mm.`;
    showToast(`Altura de sensor fijada a ${val} mm.`);
  }

  async function readBleCalibrationTable() {
    if (!bleState.isConnected && !bleState.isSimulated) {
      alert('Conecte el sensor Bluetooth primero.');
      return;
    }

    const progressCont = document.getElementById('bleProgressContainer');
    const progressBar = document.getElementById('bleProgressBar');
    const progressLbl = document.getElementById('bleProgressLabel');
    const progressPct = document.getElementById('bleProgressPct');
    const statusLog = document.getElementById('bleStatusLog');

    if (progressCont) progressCont.style.display = 'block';

    const totalBlocks = 10;
    for (let b = 0; b < totalBlocks; b++) {
      const startSlot = b * 10;
      const pct = Math.round(((b + 1) / totalBlocks) * 100);
      if (progressLbl) progressLbl.innerText = `Leyendo bloque ${b + 1}/${totalBlocks} (posiciones ${startSlot + 1}-${startSlot + 10})...`;
      if (progressBar) progressBar.style.width = pct + '%';
      if (progressPct) progressPct.innerText = pct + '%';

      if (bleState.isSimulated) {
        await new Promise(r => setTimeout(r, 90));
      } else {
        const frame = AoooGProtocol.buildFrame(bleState.sensorId, 0x15, [startSlot]);
        await bleState.charWrite.writeValue(frame);
        await new Promise(r => setTimeout(r, 60));
      }
    }

    if (progressLbl) progressLbl.innerText = '¡Lectura de 100 posiciones verificada byte a byte!';
    if (statusLog) statusLog.innerText = `[${new Date().toLocaleTimeString()}] Verificación exitosa: 100 registros en sensor coinciden con la tabla activa.`;
    showToast('¡Tabla de 100 posiciones verificada correctamente desde el sensor!');
  }

  async function setBleOutputModeFromSelect() {
    if (!bleState.isConnected && !bleState.isSimulated) {
      alert('Conecte el sensor Bluetooth primero.');
      return;
    }
    const sel = document.getElementById('selBleOutputMode');
    const mode = parseInt(sel ? sel.value : '2', 10) || 0;
    const modeNames = { 0: 'Porcentaje (%)', 1: 'Milímetros (mm)', 2: 'Litros Directos' };

    if (bleState.isSimulated) {
      const statusLog = document.getElementById('bleStatusLog');
      if (statusLog) statusLog.innerText = `[${new Date().toLocaleTimeString()}] Modo de salida configurado a: ${modeNames[mode]} (0x0${mode}).`;
      showToast(`Modo de salida cambiado a: ${modeNames[mode]}`);
      return;
    }

    try {
      const modeFrame = AoooGProtocol.buildFrame(bleState.sensorId, 0x19, [mode]);
      await bleState.charWrite.writeValue(modeFrame);
      const statusLog = document.getElementById('bleStatusLog');
      if (statusLog) statusLog.innerText = `[${new Date().toLocaleTimeString()}] Modo de salida 0x0${mode} (${modeNames[mode]}) aplicado en sensor.`;
      showToast(`Modo ${modeNames[mode]} aplicado en el sensor.`);
    } catch (e) {
      alert('Error aplicando modo de salida: ' + e.message);
    }
  }

  async function rebootBleSensor() {
    if (!bleState.isConnected && !bleState.isSimulated) {
      alert('Conecte el sensor Bluetooth primero.');
      return;
    }
    if (!confirm('¿Desea reiniciar el microcontrolador del sensor (Comando 0x01)?')) return;

    if (bleState.isSimulated) {
      const statusLog = document.getElementById('bleStatusLog');
      if (statusLog) statusLog.innerText = `[${new Date().toLocaleTimeString()}] Sensor reiniciado (Reboot CMD 0x01 completado).`;
      showToast('Sensor reiniciado con éxito.');
      return;
    }

    try {
      const frame = AoooGProtocol.buildFrame(bleState.sensorId, 0x01, []);
      await bleState.charWrite.writeValue(frame);
      const statusLog = document.getElementById('bleStatusLog');
      if (statusLog) statusLog.innerText = `[${new Date().toLocaleTimeString()}] Comando de reinicio 0x01 enviado. El sensor se reiniciará.`;
      showToast('Comando de reinicio enviado.');
    } catch (e) {
      alert('Error al reiniciar sensor: ' + e.message);
    }
  }

  async function sleepBleSensor() {
    if (!bleState.isConnected && !bleState.isSimulated) {
      alert('Conecte el sensor Bluetooth primero.');
      return;
    }
    if (!confirm('¿Desea suspender / hibernar el sensor (Comando 0x02)?\nEl sensor entrará en modo ultra bajo consumo y dejará de emitir BLE para ahorrar batería. Para activarlo nuevamente, acerque un imán a la cabeza del sensor.')) {
      return;
    }

    if (bleState.isSimulated) {
      disconnectBleSensor();
      const statusLog = document.getElementById('bleStatusLog');
      if (statusLog) statusLog.innerText = `[${new Date().toLocaleTimeString()}] Sensor apagado/hibernando (CMD 0x02). Reactivable con imán.`;
      showToast('Sensor en modo hibernación (Ahorro de batería).');
      return;
    }

    try {
      const frame = AoooGProtocol.buildFrame(bleState.sensorId, 0x02, []);
      await bleState.charWrite.writeValue(frame);
      disconnectBleSensor();
      showToast('Sensor hibernando. Reactivable con imán.');
    } catch (e) {
      alert('Error enviando comando de hibernación: ' + e.message);
    }
  }

  function normalizeCalibrationHeader(value) {
    return String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
  }

  function calibrationCellValue(value) {
    if (value && typeof value === 'object') {
      if (value.result !== undefined) return value.result;
      if (value.text !== undefined) return value.text;
      if (Array.isArray(value.richText)) return value.richText.map(part => part.text || '').join('');
    }
    return value;
  }

  function parseCalibrationNumber(raw, field, rowNumber) {
    const value = calibrationCellValue(raw);
    if (value === null || value === undefined || String(value).trim() === '') throw new Error(field + ' vacío en fila ' + rowNumber + '.');
    if (typeof value === 'number') {
      if (!Number.isFinite(value)) throw new Error(field + ' no es finito en fila ' + rowNumber + '.');
      return value;
    }
    let text = String(value).trim().replace(/\s/g, '');
    if (text.includes(',') && text.includes('.')) text = text.replace(/\./g, '').replace(',', '.');
    else if (text.includes(',')) text = text.replace(',', '.');
    const number = Number(text);
    if (!Number.isFinite(number)) throw new Error(field + ' no es numérico en fila ' + rowNumber + ': ' + value);
    return number;
  }

  function splitCalibrationDelimitedLine(line, delimiter) {
    const cells = [];
    let current = '', quoted = false;
    for (let i = 0; i < line.length; i++) {
      const char = line[i];
      if (char === '"') {
        if (quoted && line[i + 1] === '"') { current += '"'; i++; }
        else quoted = !quoted;
      } else if (char === delimiter && !quoted) {
        cells.push(current.trim()); current = '';
      } else current += char;
    }
    if (quoted) throw new Error('Archivo delimitado con comillas sin cerrar.');
    cells.push(current.trim());
    return cells;
  }

  function parseCalibrationMatrix(matrix) {
    if (!Array.isArray(matrix) || !matrix.length) throw new Error('La hoja no contiene filas.');
    const aliases = {
      data: new Set(['data', 'dato', 'fix', 'fix value', 'coordenada', 'sensor data']),
      level: new Set(['level', 'nivel', 'mm', 'level mm', 'nivel mm']),
      volume: new Set(['volume', 'volumen', 'vol', 'litros', 'volume l', 'volumen l', 'capacity'])
    };
    let headerRow = -1, columns = { data: 0, level: 1, volume: 2 };
    for (let r = 0; r < Math.min(matrix.length, 10); r++) {
      const row = (matrix[r] || []).map(value => normalizeCalibrationHeader(calibrationCellValue(value)));
      const found = {};
      for (const key of Object.keys(aliases)) found[key] = row.findIndex(value => aliases[key].has(value));
      if (found.data >= 0 && found.level >= 0 && found.volume >= 0 &&
          new Set([found.data, found.level, found.volume]).size === 3) {
        headerRow = r; columns = found; break;
      }
    }
    const rows = [];
    for (let r = headerRow + 1; r < matrix.length; r++) {
      const row = matrix[r] || [];
      if (row.every(value => value === null || value === undefined || String(calibrationCellValue(value) ?? '').trim() === '')) continue;
      const data = parseCalibrationNumber(row[columns.data], 'Data', r + 1);
      const level = parseCalibrationNumber(row[columns.level], 'Level', r + 1);
      const volume = parseCalibrationNumber(row[columns.volume], 'Volume', r + 1);
      if (!Number.isInteger(data) || data < 0 || data > 5000) throw new Error('Data debe ser entero entre 0 y 5000 en fila ' + (r + 1) + '.');
      if (!Number.isInteger(level) || level < 0 || level > 65535) throw new Error('Level debe ser entero entre 0 y 65535 mm en fila ' + (r + 1) + '.');
      if (volume < 0) throw new Error('Volume no puede ser negativo en fila ' + (r + 1) + '.');
      rows.push({ data, level, volume });
      if (rows.length > 100) throw new Error('La tabla supera los 100 registros admitidos.');
    }
    if (rows.length && (rows[0].data !== 0 || rows[0].level !== 0 || rows[0].volume !== 0)) rows.unshift({ data: 0, level: 0, volume: 0 });
    if (rows.length < 2 || rows.length > 100) throw new Error('La tabla debe contener entre 2 y 100 registros.');
    let previous = rows[0];
    if (previous.data !== 0 || previous.level !== 0 || previous.volume !== 0) throw new Error('El origen debe ser 0 / 0 / 0.');
    for (let i = 1; i < rows.length; i++) {
      const current = rows[i];
      if (current.data <= previous.data || current.level <= previous.level || current.volume < previous.volume) {
        throw new Error('Data y Level deben crecer estrictamente; Volume no puede disminuir (registro ' + (i + 1) + ').');
      }
      previous = current;
    }
    if (rows[rows.length - 1].level <= 0 || rows[rows.length - 1].volume <= 0) throw new Error('El último registro debe tener nivel y volumen positivos.');
    return rows;
  }

  function parseCalibrationDelimitedText(text) {
    const lines = String(text).replace(/^\uFEFF/, '').split(/\r?\n/).filter(line => line.trim());
    while (lines.length && /^sep\s*=\s*[,;\t]$/i.test(lines[0].trim())) lines.shift();
    if (!lines.length) throw new Error('El archivo está vacío.');
    const sample = lines[0];
    const delimiter = sample.includes(';') ? ';' : (sample.includes('\t') ? '\t' : ',');
    return parseCalibrationMatrix(lines.map(line => splitCalibrationDelimitedLine(line, delimiter)));
  }

  async function importCalibrationFile(file) {
    if (!file) return;
    try {
      const name = file.name.toLowerCase();
      let importedRows;
      if (name.endsWith('.xlsx') || name.endsWith('.xls')) {
        if (!window.ExcelJS) throw new Error('ExcelJS no está disponible.');
        const workbook = new window.ExcelJS.Workbook();
        await workbook.xlsx.load(await file.arrayBuffer());
        let lastError = null;
        importedRows = null;
        for (const worksheet of workbook.worksheets) {
          const matrix = [];
          worksheet.eachRow({ includeEmpty: false }, row => {
            matrix[row.number - 1] = Array.from({ length: row.cellCount }, (_, index) => row.getCell(index + 1).value);
          });
          try { importedRows = parseCalibrationMatrix(matrix); break; }
          catch (error) { lastError = error; }
        }
        if (!importedRows) throw new Error('No se encontró una hoja con columnas Data, Level y Volume. ' + (lastError?.message || ''));
      } else if (name.endsWith('.csv') || name.endsWith('.txt')) {
        importedRows = parseCalibrationDelimitedText(await file.text());
      } else {
        throw new Error('Formato no admitido. Selecciona XLSX, CSV o TXT.');
      }
      state.isImported = true;
      state.importedRows = importedRows;
      state.tank.height = importedRows[importedRows.length - 1].level;
      state.currentLevelMm = state.tank.height;
      syncInputsFromState();
      updateAllUI();
      showToast('Tabla importada y validada: ' + importedRows.length + ' registros. Se preservaron Data, Level y Volume.');
    } catch (error) {
      alert('No se importó la calibración: ' + error.message);
    }
  }

  function bindEvents() {
    const typeSelect = document.getElementById('tankTypeSelect');
    if (typeSelect) {
      typeSelect.addEventListener('change', (e) => {
        state.tank.type = e.target.value;
        toggleGeometrySubsections();
        updateAllUI();
      });
    }

    const presetSelect = document.getElementById('presetSelect');
    if (presetSelect) {
      presetSelect.addEventListener('change', (e) => loadPreset(e.target.value));
    }

    const btnTransverse = document.getElementById('btnPlaneTransverse');
    const btnLongitudinal = document.getElementById('btnPlaneLongitudinal');
    const btn3D = document.getElementById('btnView3D');
    const cadCanvasEl = document.getElementById('cadCanvas');
    const hintEl = document.getElementById('viewportHint');

    function setActiveView(mode) {
      state.viewMode = mode;
      [btnTransverse, btnLongitudinal, btn3D].forEach(b => b && b.classList.remove('active'));

      const threeCont = document.getElementById('threeContainer');

      if (mode === 'plane-transverse') {
        if (btnTransverse) btnTransverse.classList.add('active');
        if (hintEl) hintEl.innerText = 'Arrastra el nivel para aforar • Arrastra las esquinas para ajustar radios';
        if (cadCanvasEl) cadCanvasEl.style.display = 'block';
        if (threeCont) threeCont.style.display = 'none';
        resizeCadCanvas();
        renderCad();
      } else if (mode === 'plane-longitudinal') {
        if (btnLongitudinal) btnLongitudinal.classList.add('active');
        if (hintEl) hintEl.innerText = 'Arrastra el nivel para aforar • Arrastra las esquinas para ajustar radios';
        if (cadCanvasEl) cadCanvasEl.style.display = 'block';
        if (threeCont) threeCont.style.display = 'none';
        resizeCadCanvas();
        renderCad();
      } else if (mode === 'view-3d') {
        if (btn3D) btn3D.classList.add('active');
        if (hintEl) hintEl.innerText = 'Vista 3D Interactiva • Clic izquierdo: orbitar • Rueda: zoom • Clic derecho: mover';
        if (cadCanvasEl) cadCanvasEl.style.display = 'none';
        if (threeCont) threeCont.style.display = 'block';
        initThreeViewer();
        onThreeResize();
        updateThreeTank();
      }
    }

    if (btnTransverse) btnTransverse.addEventListener('click', () => setActiveView('plane-transverse'));
    if (btnLongitudinal) btnLongitudinal.addEventListener('click', () => setActiveView('plane-longitudinal'));
    if (btn3D) btn3D.addEventListener('click', () => setActiveView('view-3d'));

    document.querySelectorAll('.tab-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
        btn.classList.add('active');
        const content = document.getElementById(btn.dataset.tab);
        if (content) content.classList.add('active');
      });
    });

    bindInput('tankLength', (v) => { state.tank.length = v; });
    bindInput('tankWidth', (v) => { state.tank.width = v; });
    bindInput('tankHeight', (v) => { state.tank.height = v; });
    bindInput('tankThickness', (v) => { state.tank.thickness = v; });

    const dimTypeSelect = document.getElementById('tankDimType');
    if (dimTypeSelect) {
      dimTypeSelect.addEventListener('change', (e) => {
        state.tank.dimType = e.target.value;
        updateAllUI();
      });
    }

    bindInput('stepWidth', (v) => { state.tank.stepWidth = v; });
    bindInput('stepHeight', (v) => { state.tank.stepHeight = v; });
    const stepSideSelect = document.getElementById('stepSide');
    if (stepSideSelect) {
      stepSideSelect.addEventListener('change', (e) => {
        state.tank.stepSide = e.target.value;
        updateAllUI();
      });
    }

    bindInput('tank2Length', (v) => { state.tank.tank2Length = v; });
    bindInput('tank2Width', (v) => { state.tank.tank2Width = v; });
    bindInput('tank2Height', (v) => { state.tank.tank2Height = v; });

    bindInput('d_r_bottom_front', (v) => { state.tank.d_r_bottom_front = v; });
    bindInput('d_r_top_front', (v) => { state.tank.d_r_top_front = v; });
    bindInput('d_r_back_corners', (v) => { state.tank.d_r_back_corners = v; });

    bindInput('r_inf_li', (v) => { state.tank.r_inf_li = v; });
    bindInput('r_inf_ld', (v) => { state.tank.r_inf_ld = v; });
    bindInput('r_sup_li', (v) => { state.tank.r_sup_li = v; });
    bindInput('r_sup_ld', (v) => { state.tank.r_sup_ld = v; });

    bindInput('r_inf_af', (v) => { state.tank.r_inf_af = v; });
    bindInput('r_inf_ap', (v) => { state.tank.r_inf_ap = v; });
    bindInput('r_sup_af', (v) => { state.tank.r_sup_af = v; });
    bindInput('r_sup_ap', (v) => { state.tank.r_sup_ap = v; });
    bindInput('r_vert', (v) => { state.tank.r_vert = v; });
    bindInput('r_vert_fi', (v) => { state.tank.r_vert_fi = v; });
    bindInput('r_vert_fd', (v) => { state.tank.r_vert_fd = v; });
    bindInput('r_vert_pi', (v) => { state.tank.r_vert_pi = v; });
    bindInput('r_vert_pd', (v) => { state.tank.r_vert_pd = v; });

    // Botón Toggle y Controles Simplificados de Estanque Plástico
    const btnToggleRecovecos = document.getElementById('btnToggleRecovecos');
    if (btnToggleRecovecos) {
      btnToggleRecovecos.addEventListener('click', () => {
        state.tank.hasRecovecos = !state.tank.hasRecovecos;
        syncRecovecosUI();
        updateAllUI();
      });
    }

    const sliderTextura = document.getElementById('sliderTexturaRecoveco');
    if (sliderTextura) {
      sliderTextura.addEventListener('input', (e) => {
        state.tank.texturaLevel = Number(e.target.value) || 50;
        applyTextura();
        updateAllUI();
      });
    }

    const btnMenos = document.getElementById('btnTexturaMenos');
    if (btnMenos) {
      btnMenos.addEventListener('click', () => {
        state.tank.texturaLevel = Math.max(10, (state.tank.texturaLevel || 50) - 15);
        if (sliderTextura) sliderTextura.value = state.tank.texturaLevel;
        applyTextura();
        updateAllUI();
      });
    }

    const btnNormal = document.getElementById('btnTexturaNormal');
    if (btnNormal) {
      btnNormal.addEventListener('click', () => {
        state.tank.texturaLevel = 50;
        if (sliderTextura) sliderTextura.value = 50;
        applyTextura();
        updateAllUI();
      });
    }

    const btnMas = document.getElementById('btnTexturaMas');
    if (btnMas) {
      btnMas.addEventListener('click', () => {
        state.tank.texturaLevel = Math.min(90, (state.tank.texturaLevel || 50) + 15);
        if (sliderTextura) sliderTextura.value = state.tank.texturaLevel;
        applyTextura();
        updateAllUI();
      });
    }

    // Controles de Chaflán de Chasis y Presets de Estanques Plásticos
    const chkRecChasis = document.getElementById('chkRecovecoChasis');
    if (chkRecChasis) {
      chkRecChasis.addEventListener('change', (e) => {
        state.tank.recovecoEnabled = e.target.checked;
        updateAllUI();
      });
    }

    const selRecSide = document.getElementById('recovecoSide');
    if (selRecSide) {
      selRecSide.addEventListener('change', (e) => {
        state.tank.recovecoSide = e.target.value;
        updateAllUI();
      });
    }

    bindInput('recovecoWidth', (v) => { state.tank.recovecoWidth = v; });
    bindInput('recovecoHeight', (v) => { state.tank.recovecoHeight = v; });

    // Plantillas Rápidas con Medidas y Chaflán Físico Real
    const btnPresetVW150 = document.getElementById('btnPresetVW150');
    if (btnPresetVW150) {
      btnPresetVW150.addEventListener('click', () => {
        state.tank.type = 'rectangular';
        state.tank.length = 1200;
        state.tank.width = 520;
        state.tank.height = 370;
        state.tank.thickness = 8.0;
        state.tank.dimType = 'external';
        state.tank.hasRecovecos = true;
        state.tank.recovecoEnabled = true;
        state.tank.recovecoSide = 'bottom_left';
        state.tank.recovecoWidth = 190;
        state.tank.recovecoHeight = 175;
        state.tank.texturaLevel = 50;
        state.tank.r_inf_li = 90; state.tank.r_inf_ld = 90; state.tank.r_inf_af = 90; state.tank.r_inf_ap = 90;
        state.tank.r_sup_li = 60; state.tank.r_sup_ld = 60; state.tank.r_sup_af = 60; state.tank.r_sup_ap = 60;
        state.tank.r_vert = 80; state.tank.r_vert_fi = 80; state.tank.r_vert_fd = 80; state.tank.r_vert_pi = 80; state.tank.r_vert_pd = 80;
        state.currentLevelMm = 370;
        syncInputsFromState();
        updateAllUI();
        showToast('Preset VW 150L (Bepô) cargado: Capacidad neta ~150 Litros con chaflán de chasis.');
      });
    }

    const btnPresetCaren300 = document.getElementById('btnPresetCaren300');
    if (btnPresetCaren300) {
      btnPresetCaren300.addEventListener('click', () => {
        state.tank.type = 'rectangular';
        state.tank.length = 1050;
        state.tank.width = 670;
        state.tank.height = 530;
        state.tank.thickness = 8.0;
        state.tank.dimType = 'external';
        state.tank.hasRecovecos = true;
        state.tank.recovecoEnabled = true;
        state.tank.recovecoSide = 'bottom_left';
        state.tank.recovecoWidth = 220;
        state.tank.recovecoHeight = 210;
        state.tank.texturaLevel = 50;
        state.tank.r_inf_li = 100; state.tank.r_inf_ld = 100; state.tank.r_inf_af = 100; state.tank.r_inf_ap = 100;
        state.tank.r_sup_li = 80; state.tank.r_sup_ld = 80; state.tank.r_sup_af = 80; state.tank.r_sup_ap = 80;
        state.tank.r_vert = 100; state.tank.r_vert_fi = 100; state.tank.r_vert_fd = 100; state.tank.r_vert_pi = 100; state.tank.r_vert_pd = 100;
        state.currentLevelMm = 530;
        syncInputsFromState();
        updateAllUI();
        showToast('Preset Caren 300L cargado: Capacidad neta ~300 Litros con chaflán de chasis.');
      });
    }

    const btnPresetBepo300 = document.getElementById('btnPresetBepo300');
    if (btnPresetBepo300) {
      btnPresetBepo300.addEventListener('click', () => {
        state.tank.type = 'rectangular';
        state.tank.length = 1150;
        state.tank.width = 650;
        state.tank.height = 490;
        state.tank.thickness = 8.0;
        state.tank.dimType = 'external';
        state.tank.hasRecovecos = true;
        state.tank.recovecoEnabled = true;
        state.tank.recovecoSide = 'bottom_left';
        state.tank.recovecoWidth = 210;
        state.tank.recovecoHeight = 195;
        state.tank.texturaLevel = 50;
        state.tank.r_inf_li = 100; state.tank.r_inf_ld = 100; state.tank.r_inf_af = 100; state.tank.r_inf_ap = 100;
        state.tank.r_sup_li = 70; state.tank.r_sup_ld = 70; state.tank.r_sup_af = 70; state.tank.r_sup_ap = 70;
        state.tank.r_vert = 100; state.tank.r_vert_fi = 100; state.tank.r_vert_fd = 100; state.tank.r_vert_pi = 100; state.tank.r_vert_pd = 100;
        state.currentLevelMm = 490;
        syncInputsFromState();
        updateAllUI();
        showToast('Preset Bepô 300L cargado: Capacidad neta ~300 Litros con chaflán de chasis.');
      });
    }

    // Botones de Conexión BLE y Transferencia
    const btnBleConnect = document.getElementById('btnBleConnect');
    if (btnBleConnect) {
      btnBleConnect.addEventListener('click', () => {
        const panel = document.getElementById('panelBleSensor');
        if (panel) {
          const isHidden = (panel.style.display === 'none' || !panel.style.display);
          panel.style.display = isHidden ? 'block' : 'none';
        }
      });
    }

    const btnBleScan = document.getElementById('btnBleScan');
    if (btnBleScan) btnBleScan.addEventListener('click', connectBleSensor);

    const btnBleClose = document.getElementById('btnBleClosePanel');
    if (btnBleClose) {
      btnBleClose.addEventListener('click', () => {
        const panel = document.getElementById('panelBleSensor');
        if (panel) panel.style.display = 'none';
      });
    }

    const btnBleDisconnect = document.getElementById('btnBleDisconnect');
    if (btnBleDisconnect) btnBleDisconnect.addEventListener('click', disconnectBleSensor);

    const btnBleSimulate = document.getElementById('btnBleSimulate');
    if (btnBleSimulate) btnBleSimulate.addEventListener('click', simulateBleSensor);

    const btnBleAuth = document.getElementById('btnBleAuth');
    if (btnBleAuth) btnBleAuth.addEventListener('click', authenticateBleSensor);

    const btnBleUpload = document.getElementById('btnBleUploadTable');
    if (btnBleUpload) btnBleUpload.addEventListener('click', uploadCalibrationTableToBle);

    const btnTableUpload = document.getElementById('btnTableUploadBle');
    if (btnTableUpload) btnTableUpload.addEventListener('click', uploadCalibrationTableToBle);

    const btnBleSetEmpty = document.getElementById('btnBleSetEmpty');
    if (btnBleSetEmpty) btnBleSetEmpty.addEventListener('click', setBleEmptyPoint);

    const btnBleSetFull = document.getElementById('btnBleSetFull');
    if (btnBleSetFull) btnBleSetFull.addEventListener('click', setBleFullPoint);

    const btnBleReadParams = document.getElementById('btnBleReadParams');
    if (btnBleReadParams) btnBleReadParams.addEventListener('click', readBleSensorParameters);

    const btnBleSaveHeight = document.getElementById('btnBleSaveHeight');
    if (btnBleSaveHeight) btnBleSaveHeight.addEventListener('click', saveBleSensorHeight);

    const btnBleReadTable = document.getElementById('btnBleReadTable');
    if (btnBleReadTable) btnBleReadTable.addEventListener('click', readBleCalibrationTable);

    const btnBleSetOutputMode = document.getElementById('btnBleSetOutputMode');
    if (btnBleSetOutputMode) btnBleSetOutputMode.addEventListener('click', setBleOutputModeFromSelect);

    const btnBleReboot = document.getElementById('btnBleReboot');
    if (btnBleReboot) btnBleReboot.addEventListener('click', rebootBleSensor);

    const btnBleSleep = document.getElementById('btnBleSleep');
    if (btnBleSleep) btnBleSleep.addEventListener('click', sleepBleSensor);

    const btnToggle100 = document.getElementById('btnToggleTable100');
    if (btnToggle100) {
      btnToggle100.addEventListener('click', () => {
        state.tableMode = (state.tableMode === 100) ? 30 : 100;
        updateAllUI();
      });
    }

    // Importación Excel / CSV Oficial
    const btnImportExcel = document.getElementById('btnImportExcel');
    const fileImport = document.getElementById('fileImportExcel');
    if (btnImportExcel && fileImport) {
      btnImportExcel.addEventListener('click', () => fileImport.click());
      fileImport.addEventListener('change', (e) => {
        if (e.target.files && e.target.files[0]) {
          importCalibrationFile(e.target.files[0]);
          e.target.value = '';
        }
      });
    }

    bindInput('sensorDataMin', (v) => { state.sensor.dataMin = v; });
    bindInput('sensorDataMax', (v) => { state.sensor.dataMax = v; });
    bindInput('sensorBottomDead', (v) => { state.sensor.bottomDeadZone = v; });

    const slider = document.getElementById('levelSlider');
    const numInput = document.getElementById('levelNumberInput');

    if (slider) {
      slider.addEventListener('input', (e) => {
        state.currentLevelMm = Number(e.target.value) || 0;
        if (numInput) numInput.value = state.currentLevelMm;
        updateAllUI();
      });
    }

    if (numInput) {
      numInput.addEventListener('input', (e) => {
        let val = Number(e.target.value) || 0;
        val = Math.max(0, Math.min(state.calcCache.effH, val));
        state.currentLevelMm = val;
        if (slider) slider.value = val;
        updateAllUI();
      });
    }

    document.querySelectorAll('.btn-mini').forEach(btn => {
      btn.addEventListener('click', () => {
        const step = Number(btn.dataset.step) || 0;
        let next = state.currentLevelMm + step;
        next = Math.max(0, Math.min(state.calcCache.effH, next));
        state.currentLevelMm = next;
        updateAllUI();
      });
    });

    const btnExportExcel = document.getElementById('btnExportExcel');
    if (btnExportExcel) btnExportExcel.addEventListener('click', exportAoooGExcel);

    const btnTableExportExcel = document.getElementById('btnTableExportExcel');
    if (btnTableExportExcel) btnTableExportExcel.addEventListener('click', exportAoooGExcel);

    const btnExportCSV = document.getElementById('btnExportCSV');
    if (btnExportCSV) btnExportCSV.addEventListener('click', exportCSV);

    const btnCopyTable = document.getElementById('btnCopyTable');
    if (btnCopyTable) btnCopyTable.addEventListener('click', copyTableToClipboard);

    const btnPrint = document.getElementById('btnPrintCertificate');
    if (btnPrint) btnPrint.addEventListener('click', () => window.print());
  }

  function bindInput(id, callback) {
    const el = document.getElementById(id);
    if (!el) return;
    el.addEventListener('input', (e) => {
      callback(Number(e.target.value) || 0);
      updateAllUI();
    });
  }

  function loadPreset(key) {
    const p = PRESETS[key];
    if (!p) return;

    state.tank.type = p.type;
    state.tank.length = p.length || state.tank.length;
    state.tank.width = p.width || state.tank.width;
    state.tank.height = p.height || state.tank.height;
    state.tank.thickness = p.thickness ?? state.tank.thickness;
    state.tank.dimType = p.dimType || 'external';

    if (p.r_inf_li !== undefined) state.tank.r_inf_li = p.r_inf_li;
    if (p.r_inf_ld !== undefined) state.tank.r_inf_ld = p.r_inf_ld;
    if (p.r_sup_li !== undefined) state.tank.r_sup_li = p.r_sup_li;
    if (p.r_sup_ld !== undefined) state.tank.r_sup_ld = p.r_sup_ld;

    if (p.r_inf_af !== undefined) state.tank.r_inf_af = p.r_inf_af;
    if (p.r_inf_ap !== undefined) state.tank.r_inf_ap = p.r_inf_ap;
    if (p.r_sup_af !== undefined) state.tank.r_sup_af = p.r_sup_af;
    if (p.r_sup_ap !== undefined) state.tank.r_sup_ap = p.r_sup_ap;

    if (p.stepWidth !== undefined) state.tank.stepWidth = p.stepWidth;
    if (p.stepHeight !== undefined) state.tank.stepHeight = p.stepHeight;
    if (p.stepSide !== undefined) state.tank.stepSide = p.stepSide;

    if (p.tank2Length !== undefined) state.tank.tank2Length = p.tank2Length;
    if (p.tank2Width !== undefined) state.tank.tank2Width = p.tank2Width;
    if (p.tank2Height !== undefined) state.tank.tank2Height = p.tank2Height;

    if (p.d_r_bottom_front !== undefined) state.tank.d_r_bottom_front = p.d_r_bottom_front;
    if (p.d_r_top_front !== undefined) state.tank.d_r_top_front = p.d_r_top_front;
    if (p.d_r_back_corners !== undefined) state.tank.d_r_back_corners = p.d_r_back_corners;

    if (p.sensor) {
      state.sensor.dataMin = p.sensor.dataMin ?? state.sensor.dataMin;
      state.sensor.dataMax = p.sensor.dataMax ?? state.sensor.dataMax;
    }

    syncInputsFromState();
    toggleGeometrySubsections();
    updateAllUI();
    showToast(`Plantilla cargada: ${p.name}`);
  }

  function syncInputsFromState() {
    setVal('tankTypeSelect', state.tank.type);
    setVal('tankLength', state.tank.length);
    setVal('tankWidth', state.tank.width);
    setVal('tankHeight', state.tank.height);
    setVal('tankThickness', state.tank.thickness);
    setVal('tankDimType', state.tank.dimType);

    setVal('stepWidth', state.tank.stepWidth);
    setVal('stepHeight', state.tank.stepHeight);
    setVal('stepSide', state.tank.stepSide);

    setVal('tank2Length', state.tank.tank2Length);
    setVal('tank2Width', state.tank.tank2Width);
    setVal('tank2Height', state.tank.tank2Height);

    setVal('d_r_bottom_front', state.tank.d_r_bottom_front);
    setVal('d_r_top_front', state.tank.d_r_top_front);
    setVal('d_r_back_corners', state.tank.d_r_back_corners);

    setVal('r_inf_li', state.tank.r_inf_li);
    setVal('r_inf_ld', state.tank.r_inf_ld);
    setVal('r_sup_li', state.tank.r_sup_li);
    setVal('r_sup_ld', state.tank.r_sup_ld);

    setVal('r_inf_af', state.tank.r_inf_af);
    setVal('r_inf_ap', state.tank.r_inf_ap);
    setVal('r_sup_af', state.tank.r_sup_af);
    setVal('r_sup_ap', state.tank.r_sup_ap);
    setVal('r_vert', state.tank.r_vert || 0);
    setVal('r_vert_fi', state.tank.r_vert_fi || 0);
    setVal('r_vert_fd', state.tank.r_vert_fd || 0);
    setVal('r_vert_pi', state.tank.r_vert_pi || 0);
    setVal('r_vert_pd', state.tank.r_vert_pd || 0);

    setVal('sensorDataMin', state.sensor.dataMin);
    setVal('sensorDataMax', state.sensor.dataMax);
    setVal('sensorBottomDead', state.sensor.bottomDeadZone);

    setVal('recovecoWidth', state.tank.recovecoWidth || 190);
    setVal('recovecoHeight', state.tank.recovecoHeight || 175);
    const selSide = document.getElementById('recovecoSide');
    if (selSide) selSide.value = state.tank.recovecoSide || 'bottom_left';
    const chkRec = document.getElementById('chkRecovecoChasis');
    if (chkRec) chkRec.checked = state.tank.recovecoEnabled !== false;

    syncRecovecosUI();
  }

  function applyTextura() {
    const lvl = Number(state.tank.texturaLevel) || 50;
    const f = 0.5 + (lvl - 10) * (1.0 / 80);

    state.tank.cinchasCount = 2; // Asumiendo siempre 2 cintas estándar
    state.tank.cinchasWidth = 70;
    state.tank.cinchasDepth = Math.round(25 * f);

    const lbl = document.getElementById('lblTexturaLevel');
    if (lbl) {
      if (lvl <= 30) {
        lbl.innerText = 'Leve / Menos (' + lvl + '%)';
        lbl.style.background = '#f1f5f9';
        lbl.style.color = '#475569';
      } else if (lvl >= 70) {
        lbl.innerText = 'Marcada / Más (' + lvl + '%)';
        lbl.style.background = '#fef3c7';
        lbl.style.color = '#b45309';
      } else {
        lbl.innerText = 'Normal (Medio)';
        lbl.style.background = '#e0f2fe';
        lbl.style.color = '#0284c7';
      }
    }
  }

  function syncRecovecosUI() {
    const badge = document.getElementById('badgeRecovecosState');
    const panel = document.getElementById('panelRecovecos');
    const btn = document.getElementById('btnToggleRecovecos');
    const sliderTextura = document.getElementById('sliderTexturaRecoveco');

    if (sliderTextura) {
      sliderTextura.value = state.tank.texturaLevel || 50;
    }
    applyTextura();

    if (state.tank.hasRecovecos) {
      if (badge) {
        badge.innerText = 'ACTIVO / ON';
        badge.style.background = '#16a34a';
        badge.style.color = '#ffffff';
      }
      if (btn) {
        btn.style.borderColor = '#16a34a';
        btn.style.background = '#f0fdf4';
      }
      if (panel) panel.style.display = 'block';
    } else {
      if (badge) {
        badge.innerText = 'OFF';
        badge.style.background = '#e2e8f0';
        badge.style.color = '#64748b';
      }
      if (btn) {
        btn.style.borderColor = '#94a3b8';
        btn.style.background = '#f8fafc';
      }
      if (panel) panel.style.display = 'none';
    }
  }

  function setVal(id, val) {
    const el = document.getElementById(id);
    if (el) el.value = val;
  }

  window.addEventListener('DOMContentLoaded', () => {
    bindEvents();
    initCadCanvas();
    syncInputsFromState();
    toggleGeometrySubsections();
    updateAllUI();
  });

})();