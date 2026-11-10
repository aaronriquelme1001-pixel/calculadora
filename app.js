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
      length: 60,
      width: 58,
      height: 600,
      thickness: 0.0,
      dimType: 'internal', // interna directa

      // Radios transversales (W x H)
      r_inf_li: 0,
      r_inf_ld: 0,
      r_sup_li: 0,
      r_sup_ld: 0,

      // Radios longitudinales (L x H)
      r_inf_af: 0,
      r_inf_ap: 0,
      r_sup_af: 0,
      r_sup_ap: 0,

      // Radio aristas verticales (L x W)
      r_vert: 0,

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

    currentLevelMm: 0,

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
        const r_inf_li = Math.min(W / 2, H / 2, Number(state.tank.r_inf_li) || 0);
        const r_inf_ld = Math.min(W / 2, H / 2, Number(state.tank.r_inf_ld) || 0);
        const r_inf_af = Math.min(L / 2, H / 2, Number(state.tank.r_inf_af) || 0);
        const r_inf_ap = Math.min(L / 2, H / 2, Number(state.tank.r_inf_ap) || 0);

        const r_sup_li = Math.min(W / 2, H / 2, Number(state.tank.r_sup_li) || 0);
        const r_sup_ld = Math.min(W / 2, H / 2, Number(state.tank.r_sup_ld) || 0);
        const r_sup_af = Math.min(L / 2, H / 2, Number(state.tank.r_sup_af) || 0);
        const r_sup_ap = Math.min(L / 2, H / 2, Number(state.tank.r_sup_ap) || 0);

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

        const rv = Math.min(W / 4, L / 4, Number(state.tank.r_vert) || 0);
        if (rv > 0) {
          const cornerLostPerVert = (4 - Math.PI) * rv * rv;
          area -= cornerLostPerVert;
        }
        return Math.max(0, area);
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

  function computeCalibrationRows() {
    const H = state.calcCache.effH;
    const maxRow = 30; // EXACTAMENTE 30 FILAS EN TOTAL (Fila 1 Header + Filas 2 a 30)
    const dataMin = Number(state.sensor.dataMin) || 100;
    const dataMax = Number(state.sensor.dataMax) || 4660;
    const V_total = state.calcCache.totalVolume;

    const rows = [];

    // Fila 2: Vacío (0, 0, 0)
    rows.push({
      rowNum: 2,
      dataVal: 0,
      dataFormula: '0',
      levelVal: 0,
      levelFormula: '0',
      volumeVal: 0.0,
      pct: 0.0
    });

    // Fila 3: Punto de inicio con sensorDataMin
    const levelStep1 = Math.round(1 * H / 28);
    const volStep1 = Number(getVolumeAtHeight(levelStep1).toFixed(1));
    rows.push({
      rowNum: 3,
      dataVal: dataMin,
      dataFormula: `${dataMin}`,
      levelVal: levelStep1,
      levelFormula: `ROUND((3-2)*$B$${maxRow}/28, 0)`,
      volumeVal: volStep1,
      pct: V_total > 0 ? Number(((volStep1 / V_total) * 100).toFixed(1)) : 0
    });

    // Filas 4 a 29
    for (let r = 4; r < maxRow; r++) {
      const dataFormula = `ROUND($A$3 + (${r}-3)*($A$${maxRow}-$A$3)/27, 0)`;
      const levelFormula = `ROUND((${r}-2)*$B$${maxRow}/28, 0)`;
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

    // Fila 30: 100% LLENO
    rows.push({
      rowNum: maxRow,
      dataVal: dataMax,
      dataFormula: `${dataMax}`,
      levelVal: H,
      levelFormula: `${H}`,
      volumeVal: V_total,
      pct: 100.0
    });

    state.calcCache.calibrationRows = rows;
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

        ctx.moveTo(ox + r_li, oy);
        ctx.lineTo(ox + dw - r_ld, oy);
        ctx.arcTo(ox + dw, oy, ox + dw, oy - r_ld, r_ld);
        ctx.lineTo(ox + dw, oy - dh + r_sld);
        ctx.arcTo(ox + dw, oy - dh, ox + dw - r_sld, oy - dh, r_sld);
        ctx.lineTo(ox + r_sli, oy - dh);
        ctx.arcTo(ox, oy - dh, ox, oy - dh + r_sli, r_sli);
        ctx.lineTo(ox, oy - r_li);
        ctx.arcTo(ox, oy, ox + r_li, oy, r_li);
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
    let csv = 'Data,Level,Volume\r\n';
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

    setText('telemetryLevelTag', `${state.currentLevelMm} mm`);
    setText('telemetryVolume', `${curVol.toFixed(1)} L`);
    setText('telemetryTotal', `${totalVol.toFixed(1)} L`);
    setText('telemetryEmpty', `${emptyVol.toFixed(1)} L`);
    setText('telemetryPct', `${pct.toFixed(1)} %`);
    setText('telemetryRaw', `${curRaw}`);

    setText('sideTotalVolume', `${totalVol.toFixed(1)} L`);
    setText('sideCurrentLiquid', `${curVol.toFixed(1)} L`);
    setText('sideEmptySpace', `${emptyVol.toFixed(1)} L`);

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
    const r1 = Math.min(Number(state.tank.r_inf_li) || 0, w / 2 - 1, h / 2 - 1);
    const r2 = Math.min(Number(state.tank.r_inf_ld) || 0, w / 2 - 1, h / 2 - 1);
    const r3 = Math.min(Number(state.tank.r_sup_ld) || 0, w / 2 - 1, h / 2 - 1);
    const r4 = Math.min(Number(state.tank.r_sup_li) || 0, w / 2 - 1, h / 2 - 1);

    const x0 = -w / 2;
    const y0 = 0;
    const x1 = w / 2;
    const y1 = h;

    const tankShape = new THREE.Shape();
    tankShape.moveTo(x0 + r1, y0);
    tankShape.lineTo(x1 - r2, y0);
    if (r2 > 0) tankShape.quadraticCurveTo(x1, y0, x1, y0 + r2);
    tankShape.lineTo(x1, y1 - r3);
    if (r3 > 0) tankShape.quadraticCurveTo(x1, y1, x1 - r3, y1);
    tankShape.lineTo(x0 + r4, y1);
    if (r4 > 0) tankShape.quadraticCurveTo(x0, y1, x0, y1 - r4);
    tankShape.lineTo(x0, y0 + r1);
    if (r1 > 0) tankShape.quadraticCurveTo(x0, y0, x0 + r1, y0);

    const extrudeSettings = {
      depth: L,
      bevelEnabled: false,
      steps: 1,
      curveSegments: 16
    };

    const tankGeom = new THREE.ExtrudeGeometry(tankShape, extrudeSettings);
    tankGeom.translate(0, 0, -L / 2);

    const tankMat = new THREE.MeshPhysicalMaterial({
      color: 0x94a3b8,
      metalness: 0.5,
      roughness: 0.2,
      transmission: 0.55,
      transparent: true,
      opacity: 0.38,
      depthWrite: false,
      side: THREE.DoubleSide
    });

    threeTankMesh = new THREE.Mesh(tankGeom, tankMat);
    threeScene.add(threeTankMesh);

    const edgesGeom = new THREE.EdgesGeometry(tankGeom, 25);
    const edgesMat = new THREE.LineBasicMaterial({ color: 0x38bdf8, linewidth: 2, transparent: true, opacity: 0.85 });
    threeTankEdges = new THREE.LineSegments(edgesGeom, edgesMat);
    threeScene.add(threeTankEdges);

    // Líquido Diésel Ámbar
    const curLevel = Math.max(0, Math.min(H, state.currentLevelMm));
    if (curLevel > 1) {
      const liqH = curLevel;
      const liqShape = new THREE.Shape();
      const lr1 = Math.min(r1, liqH);
      const lr2 = Math.min(r2, liqH);

      liqShape.moveTo(x0 + lr1, y0 + 0.5);
      liqShape.lineTo(x1 - lr2, y0 + 0.5);
      if (lr2 > 0) liqShape.quadraticCurveTo(x1, y0 + 0.5, x1, y0 + lr2);
      liqShape.lineTo(x1, y0 + liqH);
      liqShape.lineTo(x0, y0 + liqH);
      liqShape.lineTo(x0, y0 + lr1);
      if (lr1 > 0) liqShape.quadraticCurveTo(x0, y0 + 0.5, x0 + lr1, y0 + 0.5);

      const liqGeom = new THREE.ExtrudeGeometry(liqShape, {
        depth: L - 2,
        bevelEnabled: false,
        steps: 1,
        curveSegments: 16
      });
      liqGeom.translate(0, 0, -(L - 2) / 2);

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
    setVal('r_vert', state.tank.r_vert);

    setVal('sensorDataMin', state.sensor.dataMin);
    setVal('sensorDataMax', state.sensor.dataMax);
    setVal('sensorBottomDead', state.sensor.bottomDeadZone);
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