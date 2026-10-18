/* =========================================================================
   鹧鸪骑单车 — scene & characters
   ========================================================================= */
(function (global) {
  'use strict';
  const PB = global.PB;
  const {
    TAU, clamp, lerp, smoothstep, mulberry32,
    hex, mixc, scalec, jitter,
    m4, compose, m4mul, xformPoint, xformDir, m4fromX, m4fromY,
    geo, GEOS, Mesh, ShadowMesh,
  } = PB;

  const V3 = (x, y, z) => [x, y, z];

  /* ------------------------------- terrain --------------------------------- */
  function groundHeight(x, z) {
    const r = Math.hypot(x, z);
    if (r < 22) return 0;
    const t = smoothstep(22, 52, r);
    const n = Math.sin(x * 0.055 + 0.4) * Math.cos(z * 0.048 - 0.8) * 1.5 +
      Math.sin(x * 0.11 - 1.1) * Math.cos(z * 0.093 + 2.0) * 0.55;
    return t * (1.1 + n);
  }

  function hash1(x, z) {
    const s = Math.sin(x * 12.9898 + z * 78.233) * 43758.5453;
    return s - Math.floor(s);
  }

  function buildTerrain() {
    const size = 240, div = 120;
    const step = size / div;
    const half = size / 2;
    const mesh = new Mesh(3);
    const grassA = hex('#799a54'), grassB = hex('#8aa65d'), grassC = hex('#5f8147'), dry = hex('#a3a15f');
    const pos = [], nor = [], col = [];
    const H = (x, z) => groundHeight(x, z);
    for (let i = 0; i < div; i++) {
      for (let j = 0; j < div; j++) {
        const x0 = -half + i * step, z0 = -half + j * step;
        const x1 = x0 + step, z1 = z0 + step;
        const p00 = [x0, H(x0, z0), z0], p10 = [x1, H(x1, z0), z0];
        const p11 = [x1, H(x1, z1), z1], p01 = [x0, H(x0, z1), z1];
        const cx = (x0 + x1) * 0.5, cz = (z0 + z1) * 0.5;
        const n1 = 0.5 + 0.5 * Math.sin(cx * 0.31 + cz * 0.17) * Math.cos(cz * 0.23 - cx * 0.12);
        const n2 = hash1(Math.floor(cx * 0.7), Math.floor(cz * 0.7));
        let c = mixc(grassA, grassB, n1);
        c = mixc(c, grassC, clamp((n2 - 0.72) * 1.6, 0, 0.7));
        if (n2 > 0.9) c = mixc(c, dry, 0.55);
        const r = Math.hypot(cx, cz);
        // subtle trail-ring of worn grass around the paddock edge
        const ring = Math.exp(-Math.pow((r - 15.4) / 1.4, 2)) * 0.35;
        c = mixc(c, dry, ring);
        for (const tri of [[p00, p11, p10], [p00, p01, p11]]) {
          const a = tri[0], b = tri[1], cc = tri[2];
          const fn = PB.cross([b[0] - a[0], b[1] - a[1], b[2] - a[2]], [cc[0] - a[0], cc[1] - a[1], cc[2] - a[2]]);
          const l = Math.hypot(fn[0], fn[1], fn[2]);
          if (l < 1e-8) continue;
          const nx = fn[0] / l, ny = fn[1] / l, nz = fn[2] / l;
          const tint = jitter(c, 0.05, mesh.rnd);
          for (const p of tri) {
            pos.push(p[0], p[1], p[2]);
            nor.push(nx, ny, nz);
            col.push(tint[0], tint[1], tint[2]);
          }
        }
      }
    }
    return { pos: new Float32Array(pos), nor: new Float32Array(nor), col: new Float32Array(col), count: pos.length / 3 };
  }

  /* ------------------------------- grass tufts ------------------------------ */
  function blade(mesh, x, y, z, h, lean, angle, color) {
    const dx = Math.cos(angle) * lean, dz = Math.sin(angle) * lean;
    const w = 0.03 + mesh.rnd() * 0.018;
    const ax = x - Math.sin(angle) * w, az = z + Math.cos(angle) * w;
    const bx = x + Math.sin(angle) * w, bz = z - Math.cos(angle) * w;
    const tip = [x + dx, y + h, z + dz];
    const c = jitter(color, 0.12, mesh.rnd);
    const n = [0.2, 1, 0.1];
    for (const p of [[ax, y, az], [bx, y, bz], tip]) {
      mesh.pos.push(p[0], p[1], p[2]);
      mesh.nor.push(n[0], n[1], n[2]);
      mesh.col.push(c[0], c[1], c[2]);
    }
  }

  function buildGrass(rnd) {
    const mesh = new Mesh(9);
    const c1 = hex('#648b4d'), c2 = hex('#527a43'), c3 = hex('#93aa5d');
    for (let i = 0; i < 3200; i++) {
      const a = rnd() * TAU, r = 2 + Math.sqrt(rnd()) * 30;
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      if (Math.hypot(x, z) < 1.2) continue;
      const y = groundHeight(x, z);
      const col = mixc(c1, rnd() > 0.6 ? c3 : c2, rnd());
      const count = 3 + (rnd() * 3 | 0);
      for (let k = 0; k < count; k++) {
        blade(mesh, x + (rnd() - 0.5) * 0.24, y, z + (rnd() - 0.5) * 0.24,
          0.10 + rnd() * 0.18, 0.04 + rnd() * 0.11, rnd() * TAU, col);
      }
    }
    return mesh.build();
  }

  /* -------------------------------- flowers -------------------------------- */
  function buildFlowers(rnd) {
    const mesh = new Mesh(14);
    const stem = hex('#4f7a3f');
    const petals = [hex('#f4e6c4'), hex('#f0c657'), hex('#d9a7c7'), hex('#f7f2e4')];
    for (let i = 0; i < 190; i++) {
      const a = rnd() * TAU, r = 2.4 + Math.sqrt(rnd()) * 27;
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      if (Math.hypot(x, z) < 2.2) continue;
      const y = groundHeight(x, z);
      const h = 0.11 + rnd() * 0.14;
      mesh.addSegment([x, y, z], [x + (rnd() - 0.5) * 0.03, y + h, z + (rnd() - 0.5) * 0.03], 0.008, 0.006, stem, { seg: 4, jitter: 0.08 });
      const pc = petals[(rnd() * petals.length) | 0];
      const top = [x, y + h, z];
      const rot = rnd() * TAU;
      for (let p = 0; p < 4; p++) {
        const ang = rot + (p / 4) * TAU;
        const px = top[0] + Math.cos(ang) * 0.032, pz = top[2] + Math.sin(ang) * 0.032;
        const m = compose(m4(), px, top[1] + 0.005, pz, -Math.PI / 2 + 0.25, 0, 0, 0.035, 0.035, 1);
        mesh.add(GEOS.disc16, m, pc, { jitter: 0.07 });
      }
      const m2 = compose(m4(), top[0], top[1] + 0.012, top[2], -Math.PI / 2, 0, 0, 0.016, 0.016, 0.016);
      mesh.add(GEOS.sphere8, m2, hex('#e3a63f'), { jitter: 0.05 });
    }
    return mesh.build();
  }

  /* --------------------------------- trees --------------------------------- */
  function buildTree(mesh, x, z, scale, kind, rnd) {
    const y = groundHeight(x, z);
    const trunkC = hex('#6b4c37'), trunkD = hex('#5b3f2e');
    const green = [hex('#4d7a45'), hex('#5d8a4c'), hex('#3f6b43'), hex('#6e9550')];
    if (kind === 'pine') {
      mesh.addSegment([x, y, z], [x, y + 1.2 * scale, z], 0.15 * scale, 0.1 * scale, trunkC, { seg: 6, jitter: 0.04 });
      for (let i = 0; i < 3; i++) {
        const cy = y + (0.9 + i * 0.55) * scale;
        const rr = (0.75 - i * 0.19) * scale;
        const m = compose(m4(), x, cy, z, 0, rnd() * TAU, 0, rr, 1, rr);
        mesh.add(geo.cone(1, 0.85 * scale, 8), m, green[(i + 1) % green.length], { jitter: 0.07 });
      }
    } else {
      mesh.addSegment([x, y, z], [x, y + 1.1 * scale, z], 0.16 * scale, 0.11 * scale, trunkC, { seg: 6, jitter: 0.04 });
      // two little branches
      mesh.addSegment([x, y + 1.0 * scale, z], [x + 0.45 * scale, y + 1.35 * scale, z + 0.2 * scale], 0.06 * scale, 0.03 * scale, trunkD, { seg: 4, jitter: 0.04 });
      const blobs = 3 + (rnd() * 3 | 0);
      for (let i = 0; i < blobs; i++) {
        const ang = rnd() * TAU, rr = rnd() * 0.55 * scale;
        const bx = x + Math.cos(ang) * rr, bz = z + Math.sin(ang) * rr;
        const by = y + (1.65 + rnd() * 0.9) * scale;
        const s = (0.55 + rnd() * 0.45) * scale;
        const m = compose(m4(), bx, by, bz, 0, rnd() * TAU, 0, s, s * (0.75 + rnd() * 0.4), s);
        mesh.add(GEOS.sphere12, m, green[(rnd() * green.length) | 0], { jitter: 0.09 });
      }
    }
  }

  /* --------------------------------- fence --------------------------------- */
  function buildFence(rnd) {
    const mesh = new Mesh(21);
    const wood = hex('#8b6a4a'), woodD = hex('#75563c');
    const R = 19.2, posts = 60;
    for (let i = 0; i < posts; i++) {
      const a = (i / posts) * TAU;
      const x = Math.cos(a) * R, z = Math.sin(a) * R;
      const y = groundHeight(x, z);
      const h = 1.02 + (rnd() - 0.5) * 0.1;
      mesh.add(geo.box(0.13, h, 0.13), compose(m4(), x, y + h / 2, z, 0, -a, 0, 1, 1, 1), woodD, { jitter: 0.05 });
      // cap
      mesh.add(geo.cone(0.11, 0.12, 4), compose(m4(), x, y + h + 0.06, z, 0, -a, 0, 1, 1, 1), wood, { jitter: 0.04 });
    }
    for (let i = 0; i < posts; i++) {
      const a0 = (i / posts) * TAU, a1 = ((i + 1) / posts) * TAU;
      const p0 = [Math.cos(a0) * R, groundHeight(Math.cos(a0) * R, Math.sin(a0) * R), Math.sin(a0) * R];
      const p1 = [Math.cos(a1) * R, groundHeight(Math.cos(a1) * R, Math.sin(a1) * R), Math.sin(a1) * R];
      for (const hh of [0.38, 0.72]) {
        mesh.addSegment([p0[0], p0[1] + hh + (rnd() - 0.5) * 0.03, p0[2]],
          [p1[0], p1[1] + hh + (rnd() - 0.5) * 0.03, p1[2]], 0.035, 0.035, wood, { seg: 4, caps: false, jitter: 0.05 });
      }
    }
    return mesh.build();
  }

  /* -------------------------------- mountains ------------------------------- */
  function buildMountains(rnd) {
    const mesh = new Mesh(33);
    const cols = [hex('#6d6d86'), hex('#7a748c'), hex('#5f6579'), hex('#777287')];
    // soft, overlapping ridges instead of hard pyramids
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * TAU + (rnd() - 0.5) * 0.16;
      const r = 115 + rnd() * 45;
      const w = 30 + rnd() * 30;
      const h = 6 + rnd() * 9;
      const d = 20 + rnd() * 26;
      const m = compose(m4(), Math.cos(a) * r, -3 + h * 0.3, Math.sin(a) * r, 0, rnd() * TAU, 0, w, h, d);
      const base = cols[(rnd() * cols.length) | 0];
      mesh.add(GEOS.sphere12, m, base, {
        jitter: 0.035,
        colorFn: (x, y, z, idx, c) => mixc(c, hex('#a49aab'), clamp(y + 0.45, 0, 1) * 0.25),
      });
    }
    return mesh.build();
  }

  /* ---------------------------------- flock --------------------------------- */
  function buildFlock() {
    const mesh = new Mesh(909);
    const dark = hex('#3b2b23'), wingC = hex('#4a3529');
    const formation = [[0, 0], [-1.5, 0.85], [1.5, 0.85], [-3.0, 1.7], [3.0, 1.7], [-4.5, 2.55]];
    const heading = 0.55;
    const cs = Math.cos(heading), sn = Math.sin(heading);
    for (const [fx, fz] of formation) {
      const bx = fx * cs - fz * sn, bz = fx * sn + fz * cs;
      const P = (lx, ly, lz) => [bx + lx * cs - lz * sn, ly, bz + lx * sn + lz * cs];
      mesh.add(GEOS.sphere8, compose(m4(), bx, 0, bz, 0, -heading, 0, 0.26, 0.075, 0.075), dark, { jitter: 0.02 });
      const hp = P(0.25, 0.01, 0);
      mesh.add(GEOS.sphere8, compose(m4(), hp[0], 0.012, hp[2], 0, -heading, 0, 0.07, 0.06, 0.06), dark, { jitter: 0.02 });
      mesh.addTri(P(0.14, 0.01, 0.02), P(-0.5, 0.12, 0.72), P(0.10, 0.01, 0.24), wingC, 0.02);
      mesh.addTri(P(0.14, 0.01, -0.02), P(0.10, 0.01, -0.24), P(-0.5, 0.12, -0.72), wingC, 0.02);
    }
    return mesh.build();
  }

  function buildWorld() {
    const rnd = mulberry32(20261018);
    const terrain = buildTerrain();
    const grass = buildGrass(rnd);
    const flowers = buildFlowers(rnd);
    const treeMesh = new Mesh(77);
    const treeList = [];
    // ring of trees outside the paddock, denser in the distance
    for (let i = 0; i < 52; i++) {
      const a = rnd() * TAU;
      const r = 22.5 + Math.pow(rnd(), 0.75) * 36;
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      const s = 0.8 + rnd() * 0.9;
      const kind = rnd() > 0.55 ? 'pine' : 'round';
      buildTree(treeMesh, x, z, s, kind, rnd);
      if (r < 42) treeList.push({ x, z, s, kind });
    }
    // a few close bushes just outside the fence
    for (let i = 0; i < 14; i++) {
      const a = rnd() * TAU, r = 20.4 + rnd() * 2.2;
      const x = Math.cos(a) * r, z = Math.sin(a) * r;
      const s = 0.35 + rnd() * 0.3;
      const y = groundHeight(x, z);
      for (let k = 0; k < 3; k++) {
        treeMesh.add(GEOS.sphere8, compose(m4(), x + (rnd() - 0.5) * 0.5, y + 0.3 + rnd() * 0.25, z + (rnd() - 0.5) * 0.5,
          0, rnd() * TAU, 0, s * (0.8 + rnd() * 0.5), s * 0.75, s * (0.8 + rnd() * 0.5)),
          hex('#4c7744'), { jitter: 0.1 });
      }
    }
    const fence = buildFence(rnd);
    const mountains = buildMountains(rnd);
    const flock = buildFlock();

    // static soft shadows under trees
    const sh = new ShadowMesh();
    for (const t of treeList) {
      const y = groundHeight(t.x, t.z) + 0.045;
      sh.addQuad([t.x + 0.35, y, t.z + 0.35], 1.4 * t.s, 1.5 * t.s, 0.30, rnd() * TAU);
    }
    const treeShadows = sh.build();

    return {
      terrain, grass, flowers, trees: treeMesh.build(), fence, mountains, treeShadows, flock,
      flockCenter: [-41, 10.6, -56],
      groundHeight,
    };
  }

  /* ======================================================================== */
  /*                                  RIDER                                   */
  /* ======================================================================== */
  const DIMS = {
    wheelR: 0.46,
    wheelX: [-0.62, 0.62],
    bb: [0.0, 0.34],
    crankR: 0.14,
    pedalZ: 0.10,
    seat: [-0.30, 0.99],
    headTop: [0.45, 0.92],
    body: [-0.16, 1.40, 0],
    bodyTilt: -0.14,
    bodyRadii: [0.34, 0.29, 0.25],
    hip: [-0.08, 1.14, 0.11],
    legL1: 0.47,
    legL2: 0.47,
    grips: [[0.52, 1.06, 0.205], [0.52, 1.06, -0.205]],
    headLocal: [0.15, 0.31, 0],
  };

  const COL = {
    frame: hex('#3e8f83'),
    frameD: hex('#2f746a'),
    cream: hex('#eee1c4'),
    tire: hex('#2b2724'),
    rim: hex('#e9dcc0'),
    spoke: hex('#cbbfa8'),
    metal: hex('#b9b2a3'),
    saddle: hex('#6c4a34'),
    saddleD: hex('#583b29'),
    wicker: hex('#b98b57'),
    beak: hex('#e3a03f'),
    leg: hex('#d98a4f'),
    body: hex('#8d6c50'),
    bodyD: hex('#70543e'),
    belly: hex('#d8bd97'),
    crown: hex('#6a4a35'),
    face: hex('#e8d7bb'),
    eyeRing: hex('#c05a41'),
    tail: hex('#7c5a42'),
    creamF: hex('#e3d1b1'),
  };

  function buildWheel() {
    const m = new Mesh(201);
    const R = DIMS.wheelR;
    m.add(geo.torus(R - 0.055, 0.055, 34, 8), m4(), COL.tire, { jitter: 0.03 });
    m.add(geo.torus(R - 0.115, 0.016, 34, 6), m4(), COL.rim, { jitter: 0.02 });
    const hub = compose(m4(), 0, 0, 0, Math.PI / 2, 0, 0, 1, 1, 1);
    m.add(geo.cylinder(0.045, 0.045, 0.13, 10, true, true), hub, COL.metal, { jitter: 0.03 });
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * TAU;
      m.addSegment([0.04 * Math.cos(a), 0.04 * Math.sin(a), 0.035],
        [(R - 0.13) * Math.cos(a), (R - 0.13) * Math.sin(a), 0.035],
        0.0065, 0.0065, COL.spoke, { seg: 4, caps: false, jitter: 0.02 });
    }
    // coloured spoke-bead so the spin reads clearly
    const ang = 0.9;
    m.add(GEOS.sphere8, compose(m4(), (R - 0.095) * Math.cos(ang), (R - 0.095) * Math.sin(ang), 0.043, 0, 0, 0, 0.03, 0.03, 0.012),
      hex('#d8653c'), { jitter: 0.02 });
    return m.build();
  }

  function chainPath() {
    const [cx, cy] = DIMS.bb;
    const r1 = 0.115, r2 = 0.055;
    const c2 = [DIMS.wheelX[0], DIMS.wheelR];
    const pts = [];
    pts.push([c2[0], c2[1] + r2]);
    pts.push([cx, cy + r1]);
    for (let i = 1; i <= 8; i++) {
      const a = Math.PI / 2 - (i / 8) * Math.PI;
      pts.push([cx + Math.cos(a) * r1, cy + Math.sin(a) * r1]);
    }
    pts.push([c2[0], c2[1] - r2]);
    for (let i = 1; i <= 8; i++) {
      const a = -Math.PI / 2 - (i / 8) * Math.PI;
      pts.push([c2[0] + Math.cos(a) * r2, c2[1] + Math.sin(a) * r2]);
    }
    return pts;
  }

  function buildFrame() {
    const m = new Mesh(301);
    const R = DIMS.wheelR;
    const bb = DIMS.bb, seat = DIMS.seat, headTop = DIMS.headTop;
    const headBot = [0.50, 0.735];
    const rearDrop = [DIMS.wheelX[0], R], frontDrop = [DIMS.wheelX[1], R];
    const j = { jitter: 0.025 };

    // frame tubes
    m.addSegment([bb[0], bb[1], 0], [seat[0], seat[1], 0], 0.036, 0.032, COL.frame, { seg: 8, ...j });
    m.addSegment([bb[0], bb[1], 0], [headBot[0], headBot[1], 0], 0.038, 0.03, COL.frame, { seg: 8, ...j });
    m.addSegment([seat[0], seat[1] - 0.02, 0], [headTop[0], headTop[1] - 0.03, 0], 0.03, 0.028, COL.frame, { seg: 8, ...j });
    m.addSegment([headBot[0], headBot[1], 0], [headTop[0], headTop[1], 0], 0.045, 0.045, COL.cream, { seg: 10, ...j });
    // stays
    for (const z of [-0.055, 0.055]) {
      m.addSegment([rearDrop[0], rearDrop[1], z * 2.1], [bb[0], bb[1], z], 0.019, 0.019, COL.frameD, { seg: 6, ...j });
      m.addSegment([rearDrop[0], rearDrop[1], z * 1.6], [seat[0], seat[1] - 0.05, z * 1.3], 0.016, 0.016, COL.frameD, { seg: 6, ...j });
    }
    // fork
    for (const z of [-0.055, 0.055]) {
      m.addSegment([headTop[0] - 0.02, headTop[1] - 0.03, z * 1.2], [frontDrop[0], frontDrop[1], z * 1.6], 0.022, 0.017, COL.cream, { seg: 6, ...j });
    }
    // seat post + saddle
    m.addSegment([seat[0], seat[1] - 0.02, 0], [-0.315, 1.10, 0], 0.023, 0.023, COL.metal, { seg: 6, ...j });
    m.add(GEOS.sphere12, compose(m4(), -0.30, 1.115, 0, 0.04, 0, -0.06, 0.205, 0.055, 0.135), COL.saddle, { jitter: 0.03 });
    m.add(GEOS.sphere12, compose(m4(), -0.135, 1.125, 0, 0, 0, -0.06, 0.11, 0.038, 0.07), COL.saddleD, { jitter: 0.03 });
    // stem + handlebar
    m.addSegment([headTop[0], headTop[1], 0], [0.505, 1.045, 0], 0.026, 0.024, COL.metal, { seg: 6, ...j });
    const barPts = [[0.505, 1.045, -0.245], [0.535, 1.07, -0.10], [0.535, 1.07, 0.10], [0.505, 1.045, 0.245]];
    for (let i = 0; i < barPts.length - 1; i++) {
      m.addSegment(barPts[i], barPts[i + 1], 0.017, 0.017, COL.metal, { seg: 6, ...j });
    }
    // grips
    for (const z of [-1, 1]) {
      m.addSegment([0.515, 1.05, z * 0.15], [0.50, 1.043, z * 0.255], 0.027, 0.026, COL.saddle, { seg: 8, ...j });
    }
    // bell
    m.add(GEOS.sphere8, compose(m4(), 0.52, 1.085, 0.10, 0, 0, 0, 0.032, 0.024, 0.032), hex('#d9a84a'), { jitter: 0.02 });
    // headlamp
    m.add(geo.cylinder(0.05, 0.055, 0.07, 12, true, true), compose(m4(), 0.505, 0.94, 0, 0, 0, Math.PI / 2, 1, 1, 1), COL.metal, { jitter: 0.02 });
    m.add(GEOS.disc16, compose(m4(), 0.541, 0.94, 0, 0, Math.PI / 2, 0, 0.045, 0.045, 1), hex('#f6e6b8'), { jitter: 0.01 });

    // fenders
    for (const wx of DIMS.wheelX) {
      m.add(geo.torus(0.505, 0.024, 22, 5, Math.PI * 0.13, Math.PI * 0.87),
        compose(m4(), wx, R, 0, 0, 0, 0, 1, 1, 1), COL.cream, { jitter: 0.02 });
      // fender stays
      m.addSegment([wx - 0.18, R + 0.28, 0.03], [wx, R - 0.20, 0.06], 0.007, 0.007, COL.metal, { seg: 4, caps: false, ...j });
    }

    // chain
    const cpts = chainPath();
    for (let i = 0; i < cpts.length - 1; i++) {
      m.addSegment([cpts[i][0], cpts[i][1], 0.078], [cpts[i + 1][0], cpts[i + 1][1], 0.078], 0.009, 0.009, hex('#5a544a'), { seg: 4, caps: false, jitter: 0.02 });
    }
    // rear sprocket
    m.add(geo.disc(0.058, 12), compose(m4(), DIMS.wheelX[0], R, 0.078, 0, 0, 0, 1, 1, 1), hex('#8a8377'), { jitter: 0.02 });

    /* basket, woven */
    const bx = 0.735, by = 1.005, bz = 0, bw = 0.24, bh = 0.19, bd = 0.30;
    const wick = COL.wicker;
    const wall = 0.018;
    m.add(geo.box(bw, wall, bd), compose(m4(), bx, by - bh / 2, bz, 0, 0, 0, 1, 1, 1), scalec(wick, 0.85), { jitter: 0.04 });
    for (const s of [-1, 1]) {
      m.add(geo.box(wall, bh, bd), compose(m4(), bx + s * bw / 2, by, bz, 0, 0, 0, 1, 1, 1), wick, { jitter: 0.04 });
      m.add(geo.box(bw, bh, wall), compose(m4(), bx, by, bz + s * bd / 2, 0, 0, 0, 1, 1, 1), wick, { jitter: 0.04 });
    }
    for (let i = 0; i < 7; i++) {
      const t = (i / 6 - 0.5) * (bw - 0.03);
      m.add(geo.box(0.012, bh + 0.012, 0.012), compose(m4(), bx + t, by, bz + bd / 2 + 0.002, 0, 0, 0, 1, 1, 1), scalec(wick, 1.08), { jitter: 0.05 });
    }
    for (let i = 0; i < 2; i++) {
      const yy = by - bh / 2 + 0.045 + i * 0.08;
      m.add(geo.box(bw + 0.01, 0.012, bd + 0.01), compose(m4(), bx, yy, bz, 0, 0, 0, 1, 1, 1), scalec(wick, 0.9), { jitter: 0.04 });
    }
    // top rim
    m.add(geo.box(bw + 0.025, 0.026, bd + 0.025), compose(m4(), bx, by + bh / 2 + 0.01, bz, 0, 0, 0, 1, 1, 1), scalec(wick, 0.78), { jitter: 0.04 });
    // flowers in the basket
    const fcol = [hex('#f2d06b'), hex('#f7f0df'), hex('#e59ac0')];
    for (let i = 0; i < 3; i++) {
      const fx = bx + (i - 1) * 0.05, fz = bz + (i === 1 ? 0.045 : -0.045);
      const fh = 0.15 + i * 0.025;
      m.addSegment([fx, by + 0.02, fz], [fx + 0.015, by + fh, fz], 0.007, 0.005, hex('#4d7a3f'), { seg: 4, jitter: 0.03 });
      const hx = fx + 0.015, hy = by + fh, hz = fz;
      for (let p = 0; p < 5; p++) {
        const a = (p / 5) * TAU;
        m.add(GEOS.sphere8, compose(m4(), hx + Math.cos(a) * 0.026, hy + 0.006, hz + Math.sin(a) * 0.026, 0, 0, 0, 0.03, 0.012, 0.03), fcol[i], { jitter: 0.04 });
      }
      m.add(GEOS.sphere8, compose(m4(), hx, hy + 0.014, hz, 0, 0, 0, 0.018, 0.014, 0.018), hex('#d99a36'), { jitter: 0.03 });
    }

    /* kickstand? no. tiny rear reflector */
    m.add(geo.box(0.04, 0.05, 0.01), compose(m4(), -0.63, 0.55, 0.04, 0, 0, 0.3, 1, 1, 1), hex('#d05a3a'), { jitter: 0.02 });

    return m.build();
  }

  function buildCrank() {
    const m = new Mesh(401);
    const zc = 0.085;
    m.add(geo.torus(0.108, 0.012, 24, 5), compose(m4(), 0, 0, zc, 0, 0, 0, 1, 1, 1), COL.metal, { jitter: 0.02 });
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * TAU;
      m.addSegment([0, 0, zc], [Math.cos(a) * 0.10, Math.sin(a) * 0.10, zc], 0.012, 0.008, COL.metal, { seg: 4, caps: false, jitter: 0.02 });
    }
    m.add(geo.cylinder(0.026, 0.026, 0.06, 8, true, true), compose(m4(), 0, 0, zc, Math.PI / 2, 0, 0, 1, 1, 1), COL.metal, { jitter: 0.02 });
    m.addSegment([0, 0, 0.10], [DIMS.crankR, 0, 0.10], 0.018, 0.016, COL.metal, { seg: 6, ...{ jitter: 0.02 } });
    m.addSegment([0, 0, -0.10], [-DIMS.crankR, 0, -0.10], 0.018, 0.016, COL.metal, { seg: 6, ...{ jitter: 0.02 } });
    return m.build();
  }

  function buildPedal() {
    const m = new Mesh(402);
    m.add(geo.box(0.13, 0.022, 0.085), compose(m4(), 0, 0, 0, 0, 0, 0, 1, 1, 1), hex('#4a423a'), { jitter: 0.03 });
    m.add(geo.box(0.105, 0.008, 0.06), compose(m4(), 0, 0.015, 0, 0, 0, 0, 1, 1, 1), hex('#8b7f6c'), { jitter: 0.02 });
    m.add(geo.cylinder(0.014, 0.014, 0.12, 6, true, true), compose(m4(), 0, 0, 0, Math.PI / 2, 0, 0, 1, 1, 1), COL.metal, { jitter: 0.02 });
    return m.build();
  }

  function buildBody() {
    const m = new Mesh(501);
    const [rx, ry, rz] = DIMS.bodyRadii;

    // speckled body — colour by height & flank, dots layered on top
    const base = COL.body, dark = COL.bodyD, belly = COL.belly;
    m.add(GEOS.unitSphere, compose(m4(), 0, 0, 0, 0, 0, 0, rx, ry, rz), base, {
      jitter: 0.022,
      colorFn: (x, y, z) => {
        let out = mixc(dark, base, clamp(0.45 + y * 1.7, 0, 1));
        const low = smoothstep(-0.15, -0.95, y);
        const front = smoothstep(0.0, 0.85, x) * (1 - smoothstep(0.15, 0.8, y));
        return mixc(out, belly, clamp(low * 0.5 + front * 0.5, 0, 0.72));
      },
    });
    // neck
    m.addSegment([0.10, 0.16, 0], [0.145, 0.31, 0], 0.12, 0.095, mixc(base, belly, 0.35), { seg: 10, jitter: 0.05 });
    // speckles on flanks
    for (let side = -1; side <= 1; side += 2) {
      for (let i = 0; i < 13; i++) {
        const u = (i / 13) * TAU + side * 0.4;
        const px = Math.cos(u) * (0.18 + (i % 3) * 0.045);
        const py = Math.sin(u * 1.7) * 0.12 + 0.02;
        const t = 1 - (px * px) / (rx * rx) - (py * py) / (ry * ry);
        if (t <= 0) continue;
        const pz = side * rz * Math.sqrt(t) * 0.985;
        const big = i % 4 === 0;
        m.add(GEOS.sphere8, compose(m4(), px, py, pz, 0, 0, 0, big ? 0.028 : 0.018, big ? 0.02 : 0.014, 0.012),
          i % 3 === 0 ? hex('#e6d5b8') : hex('#45352a'), { jitter: 0.03 });
      }
    }
    // a few speckles on the pale breast
    for (let i = 0; i < 7; i++) {
      const px = 0.14 + (i / 7) * 0.14;
      const py = 0.03 - (i % 3) * 0.065;
      const t = 1 - (px * px) / (rx * rx) - (py * py) / (ry * ry);
      if (t <= 0) continue;
      const pz = ((i % 2) ? 1 : -1) * rz * Math.sqrt(t) * 0.96;
      m.add(GEOS.sphere8, compose(m4(), px, py, pz, 0, 0, 0, 0.018, 0.014, 0.011), hex('#8a6a50'), { jitter: 0.03 });
    }
    // little dark necklace
    for (let i = 0; i < 7; i++) {
      const a = (i / 6 - 0.5) * 1.4;
      m.add(GEOS.sphere8, compose(m4(), 0.13 + Math.cos(a) * 0.05, 0.20 + Math.sin(a) * 0.02, Math.sin(a) * 0.095, 0, 0, 0, 0.022, 0.014, 0.012), hex('#4b3529'), { jitter: 0.03 });
    }
    return m.build();
  }

  function buildHead() {
    const m = new Mesh(502);
    m.add(GEOS.unitSphere, compose(m4(), 0, 0, 0, 0, 0, 0, 0.155, 0.15, 0.148), COL.crown, {
      jitter: 0.022,
      colorFn: (x, y, z) => {
        const crown = smoothstep(-0.1, 0.6, y);
        const face = smoothstep(-0.05, 0.55, x) * (1 - smoothstep(0.1, 0.75, y));
        let out = mixc(COL.face, COL.crown, crown);
        out = mixc(out, COL.face, face * 0.55);
        return out;
      },
    });
    // eyes
    for (const s of [-1, 1]) {
      m.add(GEOS.disc16, compose(m4(), 0.076, 0.032, s * 0.129, 0, s > 0 ? 0 : Math.PI, 0, 0.049, 0.049, 1), COL.eyeRing, { jitter: 0.02 });
      m.add(GEOS.sphere8, compose(m4(), 0.078, 0.03, s * 0.137, 0, 0, 0, 0.034, 0.035, 0.022), hex('#1b1512'), { jitter: 0.01 });
      m.add(GEOS.sphere8, compose(m4(), 0.09, 0.043, s * 0.154, 0, 0, 0, 0.011, 0.011, 0.008), hex('#fffaf0'), { jitter: 0.0 });
    }
    // beak
    m.add(geo.cone(0.052, 0.15, 8), compose(m4(), 0.198, 0.012, 0, 0, 0, -Math.PI / 2, 1, 1, 1), COL.beak, { jitter: 0.03 });
    m.add(geo.cone(0.034, 0.10, 8), compose(m4(), 0.175, -0.024, 0, 0, 0, -Math.PI / 2 - 0.06, 1, 1, 1), scalec(COL.beak, 0.82), { jitter: 0.03 });
    // crest
    for (let i = 0; i < 3; i++) {
      m.addSegment([-0.015 + i * 0.025, 0.135, (i - 1) * 0.028], [-0.06 + i * 0.035, 0.20, (i - 1) * 0.045], 0.011, 0.004, COL.crown, { seg: 4, jitter: 0.03 });
    }
    return m.build();
  }

  function buildTail() {
    const m = new Mesh(503);
    // compact fan of tail feathers, springing back and up from the tail root
    for (let i = -3; i <= 3; i++) {
      const spread = i * 0.14;
      const baseM = compose(m4(), 0, 0.015 + Math.abs(i) * 0.004, 0, 0, spread, -0.30 - Math.abs(i) * 0.025, 1, 1, 1);
      const local = compose(m4(), -0.16, 0, 0, 0, 0, 0, 0.17, 0.02, 0.05);
      m.add(GEOS.sphere8, m4mul(m4(), baseM, local), COL.tail, {
        jitter: 0.03,
        colorFn: (x) => x < -0.55 ? COL.creamF : COL.tail,
      });
      const tip = compose(m4(), -0.30, -0.002, 0, 0, 0, 0, 0.045, 0.015, 0.036);
      m.add(GEOS.sphere8, m4mul(m4(), baseM, tip), hex('#d6c09c'), { jitter: 0.025 });
    }
    // coverts hiding the feather roots
    m.add(GEOS.sphere8, compose(m4(), -0.03, 0.03, 0, 0, 0, 0, 0.09, 0.07, 0.10), mixc(COL.body, COL.tail, 0.5), { jitter: 0.04 });
    return m.build();
  }

  function buildWing() {
    const m = new Mesh(504);
    m.add(GEOS.sphere8, compose(m4(), 0, 0, 0, 0, 0, 0, 0.085, 0.075, 0.05), mixc(COL.body, COL.bodyD, 0.3), { jitter: 0.05 });
    const segs = [
      [0.13, -0.01, 0.15, 0.075, 0.028],
      [0.27, -0.02, 0.14, 0.064, 0.025],
      [0.41, -0.03, 0.12, 0.055, 0.023],
    ];
    for (const [x, y, lx, ly, lz2] of segs) {
      m.add(GEOS.sphere12, compose(m4(), x, y, 0, 0, 0, 0, lx, ly, lz2), COL.body, {
        jitter: 0.04,
        colorFn: (xx, yy) => yy > 0.03 ? mixc(COL.body, COL.bodyD, 0.35) : COL.body,
      });
    }
    // wing bars
    m.add(GEOS.sphere8, compose(m4(), 0.21, -0.015, 0, 0, 0, 0, 0.016, 0.062, 0.030), COL.creamF, { jitter: 0.03 });
    m.add(GEOS.sphere8, compose(m4(), 0.34, -0.03, 0, 0, 0, 0, 0.015, 0.052, 0.027), COL.creamF, { jitter: 0.03 });
    // primary feathers near the grip
    for (let i = 0; i < 4; i++) {
      m.add(GEOS.sphere8, compose(m4(), 0.55 + i * 0.022, -0.03 - i * 0.024, (i - 1.5) * 0.005,
        0, (i - 1.5) * 0.07, -0.12 - i * 0.05, 0.105, 0.019, 0.017),
        mixc(COL.bodyD, COL.tail, 0.45), {
        jitter: 0.035,
        colorFn: (x) => x > 0.5 ? COL.creamF : mixc(COL.bodyD, COL.tail, 0.45),
      });
    }
    // trailing secondaries
    for (let i = 0; i < 3; i++) {
      m.add(GEOS.sphere8, compose(m4(), 0.36 - i * 0.03, -0.085 - i * 0.01, 0.006,
        0, 0, -0.65 - i * 0.06, 0.085, 0.014, 0.02), mixc(COL.bodyD, COL.tail, 0.5), { jitter: 0.03 });
    }
    return m.build();
  }

  function buildLegs() {
    const L1 = DIMS.legL1, L2 = DIMS.legL2;
    const thigh = new Mesh(505);
    thigh.add(geo.cylinder(0.052, 0.078, L1, 10, true, true), compose(m4(), 0, L1 / 2, 0, 0, 0, 0, 1, 1, 1), COL.leg, { jitter: 0.04 });
    // feathered drumstick
    thigh.add(GEOS.sphere12, compose(m4(), 0, 0.085, 0, 0, 0, 0, 0.095, 0.125, 0.085), mixc(COL.bodyD, COL.leg, 0.35), {
      jitter: 0.06,
      colorFn: (x, y) => y < -0.25 ? mixc(COL.bodyD, COL.leg, 0.2) : mixc(COL.body, COL.bodyD, 0.3),
    });
    thigh.add(GEOS.sphere8, compose(m4(), 0, L1, 0, 0, 0, 0, 0.052, 0.052, 0.052), COL.leg, { jitter: 0.03 });

    const shin = new Mesh(506);
    shin.add(geo.cylinder(0.03, 0.045, L2, 8, true, true), compose(m4(), 0, L2 / 2, 0, 0, 0, 0, 1, 1, 1), COL.leg, { jitter: 0.04 });
    shin.add(GEOS.sphere8, compose(m4(), 0, L2 - 0.015, 0, 0, 0, 0, 0.042, 0.038, 0.042), COL.leg, { jitter: 0.03 });
    // scaly rings
    for (let i = 0; i < 4; i++) {
      shin.add(geo.torus(0.035, 0.004, 8, 4), compose(m4(), 0, 0.09 + i * 0.075, 0, Math.PI / 2, 0, 0, 1, 1, 1), scalec(COL.leg, 0.8), { jitter: 0.02 });
    }

    const foot = new Mesh(507);
    foot.add(GEOS.sphere8, compose(m4(), 0.025, 0.005, 0, 0, 0, 0, 0.085, 0.03, 0.055), COL.leg, { jitter: 0.03 });
    for (let i = -1; i <= 1; i++) {
      const a = i * 0.45;
      const ex = 0.025 + Math.cos(a) * 0.135, ez = Math.sin(a) * 0.135;
      foot.addSegment([0.03, 0.0, 0], [ex, -0.004, ez], 0.016, 0.007, COL.leg, { seg: 4, jitter: 0.03 });
      foot.add(geo.cone(0.009, 0.04, 5), compose(m4(), ex + 0.012, -0.006, ez, 0, 0, -Math.PI / 2, 1, 1, 1), hex('#c9a06a'), { jitter: 0.02 });
    }
    // back toe
    foot.addSegment([0.0, 0.0, 0], [-0.075, -0.004, 0], 0.014, 0.006, COL.leg, { seg: 4, jitter: 0.03 });
    return { thigh: thigh.build(), shin: shin.build(), foot: foot.build() };
  }

  function buildRider() {
    const wheel = buildWheel();
    const frame = buildFrame();
    const crank = buildCrank();
    const pedal = buildPedal();
    const body = buildBody();
    const head = buildHead();
    const tail = buildTail();
    const wing = buildWing();
    const legs = buildLegs();
    return {
      meshes: { wheel, frame, crank, pedal, body, head, tail, wing, thigh: legs.thigh, shin: legs.shin, foot: legs.foot },
      dims: DIMS,
      colors: COL,
    };
  }

  global.PB.buildWorld = buildWorld;
  global.PB.buildRider = buildRider;
  global.PB.groundHeight = groundHeight;
})(window);
