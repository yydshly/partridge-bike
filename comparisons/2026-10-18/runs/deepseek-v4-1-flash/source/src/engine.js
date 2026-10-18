/* =========================================================================
   鹧鸪骑单车 · Partridge Bike — a tiny hand-rolled WebGL engine
   No dependencies. Low-poly, flat-friendly, built for one charming scene.
   ========================================================================= */
(function (global) {
  'use strict';

  const TAU = Math.PI * 2;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const smoothstep = (e0, e1, x) => {
    const t = clamp((x - e0) / (e1 - e0), 0, 1);
    return t * t * (3 - 2 * t);
  };
  const damp = (a, b, lambda, dt) => lerp(a, b, 1 - Math.exp(-lambda * dt));

  function mulberry32(a) {
    return function () {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  /* --------------------------------- colors -------------------------------- */
  function hex(h) {
    h = h.replace('#', '');
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    return [parseInt(h.slice(0, 2), 16) / 255, parseInt(h.slice(2, 4), 16) / 255, parseInt(h.slice(4, 6), 16) / 255];
  }
  function mixc(a, b, t) { return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]; }
  function scalec(a, f) { return [clamp(a[0] * f, 0, 1), clamp(a[1] * f, 0, 1), clamp(a[2] * f, 0, 1)]; }
  function jitter(c, amt, rnd) {
    const f = 1 + (rnd() - 0.5) * 2 * amt;
    return [clamp(c[0] * f, 0, 1), clamp(c[1] * f, 0, 1), clamp(c[2] * f, 0, 1)];
  }

  /* ---------------------------------- mat4 --------------------------------- */
  const IDENT = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  const m4 = () => new Float32Array(IDENT);
  function m4identity(o) { o.set(IDENT); return o; }
  function m4mul(out, a, b) {
    const a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
    const a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
    const a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
    const a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];
    for (let i = 0; i < 4; i++) {
      const b0 = b[i * 4], b1 = b[i * 4 + 1], b2 = b[i * 4 + 2], b3 = b[i * 4 + 3];
      out[i * 4] = a00 * b0 + a10 * b1 + a20 * b2 + a30 * b3;
      out[i * 4 + 1] = a01 * b0 + a11 * b1 + a21 * b2 + a31 * b3;
      out[i * 4 + 2] = a02 * b0 + a12 * b1 + a22 * b2 + a32 * b3;
      out[i * 4 + 3] = a03 * b0 + a13 * b1 + a23 * b2 + a33 * b3;
    }
    return out;
  }
  function m4translate(out, x, y, z) {
    for (let i = 0; i < 4; i++) out[12 + i] = out[i] * x + out[4 + i] * y + out[8 + i] * z + out[12 + i];
    return out;
  }
  function m4rotX(out, rad) {
    const c = Math.cos(rad), s = Math.sin(rad);
    for (let i = 0; i < 4; i++) {
      const c1 = out[4 + i], c2 = out[8 + i];
      out[4 + i] = c1 * c + c2 * s;
      out[8 + i] = -c1 * s + c2 * c;
    }
    return out;
  }
  function m4rotY(out, rad) {
    const c = Math.cos(rad), s = Math.sin(rad);
    for (let i = 0; i < 4; i++) {
      const c0 = out[i], c2 = out[8 + i];
      out[i] = c0 * c - c2 * s;
      out[8 + i] = c0 * s + c2 * c;
    }
    return out;
  }
  function m4rotZ(out, rad) {
    const c = Math.cos(rad), s = Math.sin(rad);
    for (let i = 0; i < 4; i++) {
      const c0 = out[i], c1 = out[4 + i];
      out[i] = c0 * c + c1 * s;
      out[4 + i] = -c0 * s + c1 * c;
    }
    return out;
  }
  function m4scale(out, x, y, z) {
    for (let i = 0; i < 4; i++) { out[i] *= x; out[4 + i] *= y; out[8 + i] *= z; }
    return out;
  }
  /* T * Ry * Rx * Rz * S */
  function compose(out, px, py, pz, rx, ry, rz, sx, sy, sz) {
    m4identity(out);
    out[12] = px; out[13] = py; out[14] = pz;
    if (ry) m4rotY(out, ry);
    if (rx) m4rotX(out, rx);
    if (rz) m4rotZ(out, rz);
    if (sx !== 1 || sy !== 1 || sz !== 1) m4scale(out, sx === undefined ? 1 : sx, sy === undefined ? 1 : sy, sz === undefined ? 1 : sz);
    return out;
  }
  const tmpA = m4(), tmpB = m4();

  function m4perspective(out, fovy, aspect, near, far) {
    const f = 1 / Math.tan(fovy / 2), nf = 1 / (near - far);
    out.set([f / aspect, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) * nf, -1, 0, 0, 2 * far * near * nf, 0]);
    return out;
  }
  function m4lookAt(out, eye, target, up) {
    let zx = eye[0] - target[0], zy = eye[1] - target[1], zz = eye[2] - target[2];
    let len = Math.hypot(zx, zy, zz) || 1;
    zx /= len; zy /= len; zz /= len;
    let xx = up[1] * zz - up[2] * zy, xy = up[2] * zx - up[0] * zz, xz = up[0] * zy - up[1] * zx;
    len = Math.hypot(xx, xy, xz) || 1; xx /= len; xy /= len; xz /= len;
    const yx = zy * xz - zz * xy, yy = zz * xx - zx * xz, yz = zx * xy - zy * xx;
    out.set([xx, yx, zx, 0, xy, yy, zy, 0, xz, yz, zz, 0,
      -(xx * eye[0] + xy * eye[1] + xz * eye[2]),
      -(yx * eye[0] + yy * eye[1] + yz * eye[2]),
      -(zx * eye[0] + zy * eye[1] + zz * eye[2]), 1]);
    return out;
  }
  function normalMat3(m) {
    const a00 = m[0], a01 = m[1], a02 = m[2];
    const a10 = m[4], a11 = m[5], a12 = m[6];
    const a20 = m[8], a21 = m[9], a22 = m[10];
    let det = a00 * (a11 * a22 - a12 * a21) - a01 * (a10 * a22 - a12 * a20) + a02 * (a10 * a21 - a11 * a20);
    if (Math.abs(det) < 1e-9) det = 1e-9;
    const id = 1 / det;
    const i0 = (a11 * a22 - a12 * a21) * id, i1 = (a02 * a21 - a01 * a22) * id, i2 = (a01 * a12 - a02 * a11) * id;
    const i3 = (a12 * a20 - a10 * a22) * id, i4 = (a00 * a22 - a02 * a20) * id, i5 = (a02 * a10 - a00 * a12) * id;
    const i6 = (a10 * a21 - a11 * a20) * id, i7 = (a01 * a20 - a00 * a21) * id, i8 = (a00 * a11 - a01 * a10) * id;
    // transpose(inverse)
    return new Float32Array([i0, i3, i6, i1, i4, i7, i2, i5, i8]);
  }
  function xformPoint(out, m, p) {
    const x = p[0], y = p[1], z = p[2];
    out[0] = m[0] * x + m[4] * y + m[8] * z + m[12];
    out[1] = m[1] * x + m[5] * y + m[9] * z + m[13];
    out[2] = m[2] * x + m[6] * y + m[10] * z + m[14];
    return out;
  }
  function xformDir(out, m, p) {
    const x = p[0], y = p[1], z = p[2];
    out[0] = m[0] * x + m[4] * y + m[8] * z;
    out[1] = m[1] * x + m[5] * y + m[9] * z;
    out[2] = m[2] * x + m[6] * y + m[10] * z;
    return out;
  }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function norm(v) { const l = Math.hypot(v[0], v[1], v[2]) || 1; return [v[0] / l, v[1] / l, v[2] / l]; }
  function m4fromX(out, o, dir, upHint) {
    const x = norm(dir);
    let z = cross(x, upHint);
    if (Math.hypot(z[0], z[1], z[2]) < 1e-4) z = cross(x, [1, 0, 0]);
    z = norm(z);
    const y = cross(z, x);
    out.set([x[0], x[1], x[2], 0, y[0], y[1], y[2], 0, z[0], z[1], z[2], 0, o[0], o[1], o[2], 1]);
    return out;
  }
  function m4fromY(out, o, dir, refZ) {
    const y = norm(dir);
    let x = cross(y, refZ || [0, 0, 1]);
    if (Math.hypot(x[0], x[1], x[2]) < 1e-4) x = cross(y, [1, 0, 0]);
    x = norm(x);
    const z = cross(x, y);
    out.set([x[0], x[1], x[2], 0, y[0], y[1], y[2], 0, z[0], z[1], z[2], 0, o[0], o[1], o[2], 1]);
    return out;
  }
  function angleLerp(a, b, t) {
    let d = ((b - a + Math.PI) % TAU + TAU) % TAU - Math.PI;
    return a + d * t;
  }

  /* -------------------------------- geometry ------------------------------- */
  function faceNormal(a, b, c) {
    const ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
    const vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2];
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const l = Math.hypot(nx, ny, nz);
    if (l < 1e-10) return null;
    return [nx / l, ny / l, nz / l];
  }

  function sphere(r, seg, rings, smooth) {
    seg = seg || 20; rings = rings || 14;
    smooth = smooth !== false;
    const pos = [], nor = [];
    const P = (iu, iv) => {
      const v = (iv / rings) * Math.PI, u = (iu / seg) * TAU;
      const sv = Math.sin(v);
      return [r * sv * Math.cos(u), r * Math.cos(v), r * sv * Math.sin(u)];
    };
    const tri = (a, b, c) => {
      const fn = faceNormal(a, b, c);
      if (!fn) return;
      if (smooth) {
        for (const p of [a, b, c]) {
          pos.push(p[0], p[1], p[2]);
          const l = Math.hypot(p[0], p[1], p[2]) || 1;
          nor.push(p[0] / l, p[1] / l, p[2] / l);
        }
      } else {
        for (const p of [a, b, c]) { pos.push(p[0], p[1], p[2]); nor.push(fn[0], fn[1], fn[2]); }
      }
    };
    for (let iv = 0; iv < rings; iv++) {
      for (let iu = 0; iu < seg; iu++) {
        const a = P(iu, iv), b = P(iu + 1, iv), c = P(iu + 1, iv + 1), d = P(iu, iv + 1);
        tri(a, b, c);
        tri(a, c, d);
      }
    }
    return { pos: new Float32Array(pos), nor: new Float32Array(nor) };
  }

  function cylinder(rTop, rBottom, h, seg, caps, smooth) {
    seg = seg || 12; caps = caps !== false; smooth = smooth !== false;
    const pos = [], nor = [];
    const half = h / 2;
    const ring = (r) => {
      const out = [];
      for (let i = 0; i < seg; i++) {
        const a = (i / seg) * TAU;
        out.push([r * Math.cos(a), 0, r * Math.sin(a)]);
      }
      return out;
    };
    const top = ring(rTop), bot = ring(rBottom);
    const tri = (a, b, c, n) => {
      const fn = n || faceNormal(a, b, c);
      if (!fn) return;
      for (const p of [a, b, c]) { pos.push(p[0], p[1], p[2]); nor.push(fn[0], fn[1], fn[2]); }
    };
    for (let i = 0; i < seg; i++) {
      const j = (i + 1) % seg;
      const n0 = smooth ? [Math.cos((i / seg) * TAU), 0, Math.sin((i / seg) * TAU)] : null;
      const n1 = smooth ? [Math.cos((j / seg) * TAU), 0, Math.sin((j / seg) * TAU)] : null;
      const b0 = [bot[i][0], -half, bot[i][2]], b1 = [bot[j][0], -half, bot[j][2]];
      const t0 = [top[i][0], half, top[i][2]], t1 = [top[j][0], half, top[j][2]];
      const push = (p, n) => { pos.push(p[0], p[1], p[2]); nor.push(n[0], n[1], n[2]); };
      const sideTri = (a, b, c, na, nb, nc) => {
        const fn = faceNormal(a, b, c);
        if (!fn) return;
        if (smooth) { push(a, na); push(b, nb); push(c, nc); }
        else { push(a, fn); push(b, fn); push(c, fn); }
      };
      sideTri(b0, t0, t1, n0, n1, n1);
      sideTri(b0, t1, b1, n0, n1, n1);
    }
    if (caps) {
      if (rTop > 1e-5) {
        for (let i = 0; i < seg; i++) {
          const j = (i + 1) % seg;
          const c = [0, half, 0];
          const p0 = [top[i][0], half, top[i][2]], p1 = [top[j][0], half, top[j][2]];
          // outward +Y => (center, p1, p0)
          tri(c, p1, p0, [0, 1, 0]);
        }
      }
      if (rBottom > 1e-5) {
        for (let i = 0; i < seg; i++) {
          const j = (i + 1) % seg;
          const c = [0, -half, 0];
          const p0 = [bot[i][0], -half, bot[i][2]], p1 = [bot[j][0], -half, bot[j][2]];
          tri(c, p0, p1, [0, -1, 0]);
        }
      }
    }
    return { pos: new Float32Array(pos), nor: new Float32Array(nor) };
  }

  function torus(R, r, seg, tubeSeg, arcStart, arcEnd) {
    seg = seg || 32; tubeSeg = tubeSeg || 8;
    const a0 = arcStart === undefined ? 0 : arcStart;
    const a1 = arcEnd === undefined ? TAU : arcEnd;
    const pos = [], nor = [];
    const P = (iu, iv) => {
      const u = a0 + ((a1 - a0) * iu) / seg, v = (iv / tubeSeg) * TAU;
      const cu = Math.cos(u), su = Math.sin(u), cv = Math.cos(v), sv = Math.sin(v);
      return { p: [(R + r * cv) * cu, (R + r * cv) * su, r * sv], n: [cv * cu, cv * su, sv] };
    };
    for (let iu = 0; iu < seg; iu++) {
      for (let iv = 0; iv < tubeSeg; iv++) {
        const a = P(iu, iv), b = P(iu + 1, iv), c = P(iu + 1, iv + 1), d = P(iu, iv + 1);
        const push = (x) => { pos.push(x.p[0], x.p[1], x.p[2]); nor.push(x.n[0], x.n[1], x.n[2]); };
        push(a); push(b); push(c);
        push(a); push(c); push(d);
      }
    }
    return { pos: new Float32Array(pos), nor: new Float32Array(nor) };
  }

  function box(w, h, d) {
    const x = w / 2, y = h / 2, z = d / 2;
    const pos = [], nor = [];
    const quad = (a, b, c, dd, n) => {
      for (const p of [a, b, c, a, c, dd]) { pos.push(p[0], p[1], p[2]); nor.push(n[0], n[1], n[2]); }
    };
    quad([-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z], [0, 0, 1]);
    quad([x, -y, -z], [-x, -y, -z], [-x, y, -z], [x, y, -z], [0, 0, -1]);
    quad([x, -y, z], [x, -y, -z], [x, y, -z], [x, y, z], [1, 0, 0]);
    quad([-x, -y, -z], [-x, -y, z], [-x, y, z], [-x, y, -z], [-1, 0, 0]);
    quad([-x, y, z], [x, y, z], [x, y, -z], [-x, y, -z], [0, 1, 0]);
    quad([-x, -y, -z], [x, -y, -z], [x, -y, z], [-x, -y, z], [0, -1, 0]);
    return { pos: new Float32Array(pos), nor: new Float32Array(nor) };
  }

  function quad(w, h) {
    const x = w / 2, y = h / 2;
    return {
      pos: new Float32Array([-x, -y, 0, x, -y, 0, x, y, 0, -x, -y, 0, x, y, 0, -x, y, 0]),
      nor: new Float32Array([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]),
    };
  }

  function disc(r, seg) {
    seg = seg || 20;
    const pos = [], nor = [];
    for (let i = 0; i < seg; i++) {
      const a0 = (i / seg) * TAU, a1 = ((i + 1) / seg) * TAU;
      pos.push(0, 0, 0, r * Math.cos(a0), r * Math.sin(a0), 0, r * Math.cos(a1), r * Math.sin(a1), 0);
      nor.push(0, 0, 1, 0, 0, 1, 0, 0, 1);
    }
    return { pos: new Float32Array(pos), nor: new Float32Array(nor) };
  }

  const cone = (r, h, seg) => cylinder(0, r, h, seg || 12, true, true);

  /* --------------------------------- meshes -------------------------------- */
  class Mesh {
    constructor(seed) {
      this.pos = [];
      this.nor = [];
      this.col = [];
      this.rnd = mulberry32(seed === undefined ? 7 : seed);
    }
    add(geo, mat, color, opts) {
      opts = opts || {};
      const m = mat || IDENT;
      const nm = opts.normalMatrix === false ? null : normalMat3(m);
      const P = geo.pos, N = geo.nor;
      const jit = opts.jitter === undefined ? 0.055 : opts.jitter;
      for (let i = 0; i < P.length; i += 9) {
        const cx = (P[i] + P[i + 3] + P[i + 6]) / 3;
        const cy = (P[i + 1] + P[i + 4] + P[i + 7]) / 3;
        const cz = (P[i + 2] + P[i + 5] + P[i + 8]) / 3;
        let base = typeof color === 'function' ? color(cx, cy, cz, i / 9) : color;
        if (opts.colorFn) base = opts.colorFn(cx, cy, cz, i / 9, base, this);
        const c = jitter(base, jit, this.rnd);
        for (let k = 0; k < 3; k++) {
          const o = i + k * 3;
          const x = P[o], y = P[o + 1], z = P[o + 2];
          this.pos.push(
            m[0] * x + m[4] * y + m[8] * z + m[12],
            m[1] * x + m[5] * y + m[9] * z + m[13],
            m[2] * x + m[6] * y + m[10] * z + m[14]
          );
          const nx = N[o], ny = N[o + 1], nz = N[o + 2];
          this.nor.push(
            nm[0] * nx + nm[3] * ny + nm[6] * nz,
            nm[1] * nx + nm[4] * ny + nm[7] * nz,
            nm[2] * nx + nm[5] * ny + nm[8] * nz
          );
          this.col.push(c[0], c[1], c[2]);
        }
      }
      return this;
    }
    addTri(a, b, c, color, jit) {
      const fn = faceNormal(a, b, c);
      if (!fn) return this;
      const cc = jitter(color, jit === undefined ? 0.05 : jit, this.rnd);
      for (const p of [a, b, c]) {
        this.pos.push(p[0], p[1], p[2]);
        this.nor.push(fn[0], fn[1], fn[2]);
        this.col.push(cc[0], cc[1], cc[2]);
      }
      return this;
    }
    addQuad(a, b, c, d, color, jit) {
      this.addTri(a, b, c, color, jit);
      this.addTri(a, c, d, color, jit);
      return this;
    }
    addEllipsoid(center, radii, color, opts) {
      opts = opts || {};
      const m = compose(tmpB, center[0], center[1], center[2],
        opts.rx || 0, opts.ry || 0, opts.rz || 0, radii[0], radii[1], radii[2]);
      return this.add(this.sphereCache || GEOS.unitSphere, m, color, opts);
    }
    addSegment(a, b, r1, r2, color, opts) {
      opts = opts || {};
      const dir = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
      const len = Math.hypot(dir[0], dir[1], dir[2]);
      if (len < 1e-5) return this;
      const mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2];
      const m = m4fromY(tmpB, mid, dir, opts.refZ || [0, 0, 1]);
      const g = cylinder(r2, r1, len, opts.seg || 8, opts.caps !== false, true);
      return this.add(g, m, color, opts);
    }
    build() {
      return {
        pos: new Float32Array(this.pos),
        nor: new Float32Array(this.nor),
        col: new Float32Array(this.col),
        count: this.pos.length / 3,
      };
    }
  }

  const GEOS = {
    unitSphere: sphere(1, 20, 14, true),
    sphere12: sphere(1, 12, 8, true),
    sphere8: sphere(1, 8, 6, true),
    disc16: disc(1, 16),
  };

  /* ------------------------------- shadow mesh ----------------------------- */
  class ShadowMesh {
    constructor() { this.pos = []; this.uv = []; this.alpha = []; }
    addQuad(center, rx, rz, alpha, rotY) {
      const c = Math.cos(rotY || 0), s = Math.sin(rotY || 0);
      const corners = [[-rx, -rz], [rx, -rz], [rx, rz], [-rx, rz]];
      const uv = [[0, 0], [1, 0], [1, 1], [0, 1]];
      const pts = corners.map(([x, z]) => {
        const wx = x * c - z * s, wz = x * s + z * c;
        return [center[0] + wx, center[1], center[2] + wz];
      });
      const push = (i) => {
        this.pos.push(pts[i][0], pts[i][1], pts[i][2]);
        this.uv.push(uv[i][0], uv[i][1]);
        this.alpha.push(alpha);
      };
      push(0); push(1); push(2); push(0); push(2); push(3);
      return this;
    }
    addRadial(center, rx, rz, alpha, rotY) { return this.addQuad(center, rx, rz, alpha, rotY); }
    build() {
      return {
        pos: new Float32Array(this.pos), uv: new Float32Array(this.uv),
        alpha: new Float32Array(this.alpha), count: this.pos.length / 3,
      };
    }
  }

  /* --------------------------------- shaders ------------------------------- */
  const MAIN_VS = `
    attribute vec3 aPos; attribute vec3 aNormal; attribute vec3 aColor;
    uniform mat4 uProj, uView, uModel; uniform mat3 uNormalMat;
    varying vec3 vN; varying vec3 vC; varying vec3 vP;
    void main(){
      vec4 wp = uModel * vec4(aPos, 1.0);
      vec4 vp = uView * wp;
      gl_Position = uProj * vp;
      vN = normalize(uNormalMat * aNormal);
      vC = aColor;
      vP = vp.xyz;
    }`;
  const MAIN_FS = `
    precision highp float;
    varying vec3 vN; varying vec3 vC; varying vec3 vP;
    uniform vec3 uSunDir, uSunColor, uSkyColor, uGroundColor, uFogColor, uTint;
    uniform float uFogNear, uFogFar, uAlpha, uUnlit;
    void main(){
      vec3 N = normalize(vN);
      vec3 V = normalize(-vP);
      vec3 base = vC * uTint;
      vec3 amb = mix(uGroundColor, uSkyColor, clamp(N.y * 0.5 + 0.5, 0.0, 1.0));
      float ndl = clamp(dot(N, uSunDir) * 0.62 + 0.38, 0.0, 1.0);
      vec3 col = base * (amb + uSunColor * ndl);
      vec3 H = normalize(uSunDir + V);
      col += uSunColor * pow(clamp(dot(N, H), 0.0, 1.0), 40.0) * 0.20;
      float rim = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.0);
      col += (uSunColor * 0.7 + uSkyColor * 0.5) * rim * 0.12;
      float fog = smoothstep(uFogNear, uFogFar, length(vP));
      if (uUnlit > 0.5) col = base;
      col = mix(col, uFogColor, fog);
      gl_FragColor = vec4(col, uAlpha);
    }`;
  const SKY_VS = `
    attribute vec2 aPos; varying vec2 vUV;
    void main(){ vUV = aPos * 0.5 + 0.5; gl_Position = vec4(aPos, 0.999, 1.0); }`;
  const SKY_FS = `
    precision highp float;
    varying vec2 vUV;
    uniform vec3 uRight, uUp, uFwd, uZenith, uHorizon, uHaze, uSunColor, uSunDir;
    uniform float uTanX, uTanY, uStars;
    float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
    void main(){
      vec3 ray = normalize(uFwd + uRight * (vUV.x * 2.0 - 1.0) * uTanX + uUp * (vUV.y * 2.0 - 1.0) * uTanY);
      vec3 col = mix(uHorizon, uZenith, smoothstep(-0.02, 0.42, ray.y));
      col = mix(uHaze, col, smoothstep(-0.12, 0.05, ray.y));
      float sd = max(dot(ray, uSunDir), 0.0);
      col += uSunColor * pow(sd, 6000.0) * 2.6;
      col += uSunColor * pow(sd, 320.0) * 0.50;
      col += uSunColor * pow(sd, 26.0) * 0.09;
      vec2 grid = vec2(atan(ray.z, ray.x) * 150.0, ray.y * 420.0);
      vec2 cell = floor(grid);
      vec2 f = fract(grid) - 0.5;
      float h = hash(cell);
      float star = step(0.988, h) * smoothstep(0.22, 0.02, length(f)) * smoothstep(0.04, 0.30, ray.y) * uStars;
      col += vec3(0.86, 0.92, 1.0) * star * 2.4;
      gl_FragColor = vec4(col, 1.0);
    }`;
  const POINT_VS = `
    attribute vec3 aPos; attribute vec3 aCol; attribute float aSize; attribute float aAlpha;
    uniform mat4 uProj, uView; uniform float uScale;
    varying vec3 vCol; varying float vAlpha;
    void main(){
      vec4 vp = uView * vec4(aPos, 1.0);
      gl_Position = uProj * vp;
      gl_PointSize = clamp(aSize * uScale / max(-vp.z, 0.1), 1.0, 90.0);
      vCol = aCol; vAlpha = aAlpha;
    }`;
  const POINT_FS = `
    precision highp float;
    varying vec3 vCol; varying float vAlpha;
    void main(){
      vec2 d = gl_PointCoord - 0.5;
      float r = length(d);
      float a = smoothstep(0.5, 0.06, r) * vAlpha;
      if (a < 0.01) discard;
      gl_FragColor = vec4(vCol, a);
    }`;
  const SHADOW_VS = `
    attribute vec3 aPos; attribute vec2 aUV; attribute float aAlpha;
    uniform mat4 uProj, uView, uModel;
    varying vec2 vUV; varying float vAlpha;
    void main(){ vUV = aUV; vAlpha = aAlpha; gl_Position = uProj * uView * uModel * vec4(aPos, 1.0); }`;
  const SHADOW_FS = `
    precision highp float;
    varying vec2 vUV; varying float vAlpha;
    uniform sampler2D uTex; uniform float uOpacity; uniform vec3 uColor;
    void main(){
      float a = texture2D(uTex, vUV).a * vAlpha * uOpacity;
      if (a < 0.004) discard;
      gl_FragColor = vec4(uColor, a);
    }`;

  /* -------------------------------- renderer ------------------------------- */
  class Renderer {
    constructor(canvas) {
      this.canvas = canvas;
      const opts = { alpha: false, antialias: true, powerPreference: 'high-performance', preserveDrawingBuffer: false, stencil: false };
      const gl = canvas.getContext('webgl', opts) || canvas.getContext('experimental-webgl', opts);
      if (!gl) throw new Error('WebGL is not available');
      this.gl = gl;
      this.dpr = 1;
      this.main = this.program(MAIN_VS, MAIN_FS);
      this.sky = this.program(SKY_VS, SKY_FS);
      this.points = this.program(POINT_VS, POINT_FS);
      this.shadow = this.program(SHADOW_VS, SHADOW_FS);
      this.uMain = this.uniforms(this.main, ['uProj', 'uView', 'uModel', 'uNormalMat', 'uSunDir', 'uSunColor',
        'uSkyColor', 'uGroundColor', 'uFogColor', 'uTint', 'uFogNear', 'uFogFar', 'uAlpha', 'uUnlit']);
      this.uSky = this.uniforms(this.sky, ['uRight', 'uUp', 'uFwd', 'uZenith', 'uHorizon', 'uHaze', 'uSunColor',
        'uSunDir', 'uTanX', 'uTanY', 'uStars']);
      this.uPoint = this.uniforms(this.points, ['uProj', 'uView', 'uScale']);
      this.uShadow = this.uniforms(this.shadow, ['uProj', 'uView', 'uModel', 'uTex', 'uOpacity', 'uColor']);
      this.skyBuf = this.buffer(new Float32Array([-1, -1, 3, -1, -1, 3]), gl.ARRAY_BUFFER);
      this.shadowTex = this.makeBlobTexture();
      this.pointBuf = gl.createBuffer();
      this.pointData = new Float32Array(0);
      this.proj = m4(); this.view = m4();
      this.scene = null;
      gl.enable(gl.DEPTH_TEST);
      gl.enable(gl.CULL_FACE);
      gl.cullFace(gl.BACK);
      gl.disable(gl.BLEND);
      gl.clearColor(0.2, 0.2, 0.25, 1);
    }
    program(vsSrc, fsSrc) {
      const gl = this.gl;
      const compile = (type, src) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
          const log = gl.getShaderInfoLog(s);
          console.error('Shader compile error:', log, src);
          throw new Error('Shader compile error: ' + log);
        }
        return s;
      };
      const p = gl.createProgram();
      gl.attachShader(p, compile(gl.VERTEX_SHADER, vsSrc));
      gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fsSrc));
      gl.linkProgram(p);
      if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
        const log = gl.getProgramInfoLog(p);
        console.error('Program link error:', log);
        throw new Error('Program link error: ' + log);
      }
      p._attrs = {};
      const n = gl.getProgramParameter(p, gl.ACTIVE_ATTRIBUTES);
      for (let i = 0; i < n; i++) {
        const info = gl.getActiveAttrib(p, i);
        p._attrs[info.name] = gl.getAttribLocation(p, info.name);
      }
      return p;
    }
    uniforms(p, names) {
      const out = {};
      for (const n of names) out[n] = this.gl.getUniformLocation(p, n);
      return out;
    }
    buffer(data, target) {
      const gl = this.gl;
      const b = gl.createBuffer();
      gl.bindBuffer(target || gl.ARRAY_BUFFER, b);
      gl.bufferData(target || gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
      return b;
    }
    makeBlobTexture() {
      const gl = this.gl;
      const c = document.createElement('canvas');
      c.width = c.height = 128;
      const ctx = c.getContext('2d');
      const g = ctx.createRadialGradient(64, 64, 4, 64, 64, 64);
      g.addColorStop(0, 'rgba(255,255,255,1)');
      g.addColorStop(0.45, 'rgba(255,255,255,0.55)');
      g.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, 128, 128);
      const tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, c);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      return tex;
    }
    uploadMesh(cpu) {
      if (!cpu) return null;
      const gl = this.gl;
      return {
        pos: this.buffer(cpu.pos), nor: this.buffer(cpu.nor), col: this.buffer(cpu.col),
        count: cpu.count,
      };
    }
    uploadShadow(cpu) {
      const gl = this.gl;
      return {
        pos: this.buffer(cpu.pos), uv: this.buffer(cpu.uv), alpha: this.buffer(cpu.alpha),
        count: cpu.count,
      };
    }
    resize() {
      const gl = this.gl, canvas = this.canvas;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const w = Math.max(320, Math.round(canvas.clientWidth * dpr));
      const h = Math.max(240, Math.round(canvas.clientHeight * dpr));
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w; canvas.height = h;
      }
      this.dpr = dpr;
      gl.viewport(0, 0, w, h);
      this.aspect = w / h;
      return this.aspect;
    }
    setScene(scene) {
      this.scene = scene;
      this.proj = scene.proj;
      this.view = scene.view;
    }
    begin() {
      const gl = this.gl;
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      gl.disable(gl.BLEND);
      gl.depthMask(true);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    }
    drawSky(sky) {
      const gl = this.gl, p = this.sky, u = this.uSky, s = this.scene;
      gl.useProgram(p);
      gl.disable(gl.DEPTH_TEST);
      gl.depthMask(false);
      gl.disable(gl.CULL_FACE);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.skyBuf);
      const loc = p._attrs.aPos;
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
      gl.uniform3fv(u.uRight, s.right);
      gl.uniform3fv(u.uUp, s.up);
      gl.uniform3fv(u.uFwd, s.fwd);
      gl.uniform3fv(u.uZenith, sky.zenith);
      gl.uniform3fv(u.uHorizon, sky.horizon);
      gl.uniform3fv(u.uHaze, sky.haze);
      gl.uniform3fv(u.uSunColor, sky.disc);
      gl.uniform3fv(u.uSunDir, s.sunDir);
      gl.uniform1f(u.uTanX, s.tanX);
      gl.uniform1f(u.uTanY, s.tanY);
      gl.uniform1f(u.uStars, sky.stars || 0);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      gl.enable(gl.DEPTH_TEST);
      gl.depthMask(true);
      gl.enable(gl.CULL_FACE);
    }
    draw(mesh, model, opts) {
      if (!mesh) return;
      const gl = this.gl, u = this.uMain, s = this.scene;
      opts = opts || {};
      gl.useProgram(this.main);
      gl.uniformMatrix4fv(u.uProj, false, s.proj);
      gl.uniformMatrix4fv(u.uView, false, s.view);
      gl.uniformMatrix4fv(u.uModel, false, model);
      gl.uniformMatrix3fv(u.uNormalMat, false, normalMat3(model));
      gl.uniform3fv(u.uSunDir, s.sunDir);
      gl.uniform3fv(u.uSunColor, s.sunColor);
      gl.uniform3fv(u.uSkyColor, s.skyColor);
      gl.uniform3fv(u.uGroundColor, s.groundColor);
      gl.uniform3fv(u.uFogColor, s.fogColor);
      gl.uniform3fv(u.uTint, opts.tint || s.tint || [1, 1, 1]);
      gl.uniform1f(u.uFogNear, s.fogNear);
      gl.uniform1f(u.uFogFar, s.fogFar);
      gl.uniform1f(u.uAlpha, opts.alpha === undefined ? 1 : opts.alpha);
      gl.uniform1f(u.uUnlit, opts.unlit ? 1 : 0);
      if (opts.doubleSided) gl.disable(gl.CULL_FACE); else gl.enable(gl.CULL_FACE);
      const a = this.main._attrs;
      const bind = (buf, loc, size) => {
        gl.bindBuffer(gl.ARRAY_BUFFER, buf);
        gl.enableVertexAttribArray(loc);
        gl.vertexAttribPointer(loc, size, gl.FLOAT, false, 0, 0);
      };
      bind(mesh.pos, a.aPos, 3);
      bind(mesh.nor, a.aNormal, 3);
      bind(mesh.col, a.aColor, 3);
      gl.drawArrays(gl.TRIANGLES, 0, mesh.count);
    }
    drawShadow(mesh, model, opacity, color) {
      if (!mesh) return;
      const gl = this.gl, u = this.uShadow, s = this.scene;
      gl.useProgram(this.shadow);
      gl.uniformMatrix4fv(u.uProj, false, s.proj);
      gl.uniformMatrix4fv(u.uView, false, s.view);
      gl.uniformMatrix4fv(u.uModel, false, model);
      gl.uniform1f(u.uOpacity, opacity === undefined ? 0.4 : opacity);
      gl.uniform3fv(u.uColor, color || s.shadowColor || [0.13, 0.1, 0.09]);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, this.shadowTex);
      gl.uniform1i(u.uTex, 0);
      const a = this.shadow._attrs;
      gl.bindBuffer(gl.ARRAY_BUFFER, mesh.pos);
      gl.enableVertexAttribArray(a.aPos);
      gl.vertexAttribPointer(a.aPos, 3, gl.FLOAT, false, 0, 0);
      gl.bindBuffer(gl.ARRAY_BUFFER, mesh.uv);
      gl.enableVertexAttribArray(a.aUV);
      gl.vertexAttribPointer(a.aUV, 2, gl.FLOAT, false, 0, 0);
      gl.bindBuffer(gl.ARRAY_BUFFER, mesh.alpha);
      gl.enableVertexAttribArray(a.aAlpha);
      gl.vertexAttribPointer(a.aAlpha, 1, gl.FLOAT, false, 0, 0);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      gl.depthMask(false);
      gl.disable(gl.CULL_FACE);
      gl.drawArrays(gl.TRIANGLES, 0, mesh.count);
      gl.depthMask(true);
      gl.disable(gl.BLEND);
      gl.enable(gl.CULL_FACE);
    }
    drawPoints(pts, scale, additive) {
      if (!pts || !pts.count) return;
      const gl = this.gl, u = this.uPoint, s = this.scene;
      const need = pts.count * 8;
      if (this.pointData.length < need) this.pointData = new Float32Array(need * 2);
      const data = this.pointData;
      data.set(pts.data.subarray(0, need));
      gl.useProgram(this.points);
      gl.uniformMatrix4fv(u.uProj, false, s.proj);
      gl.uniformMatrix4fv(u.uView, false, s.view);
      gl.uniform1f(u.uScale, scale * this.canvas.height * 0.5);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.pointBuf);
      gl.bufferData(gl.ARRAY_BUFFER, data.subarray(0, need), gl.DYNAMIC_DRAW);
      const a = this.points._attrs;
      const stride = 8 * 4;
      gl.enableVertexAttribArray(a.aPos);
      gl.vertexAttribPointer(a.aPos, 3, gl.FLOAT, false, stride, 0);
      gl.enableVertexAttribArray(a.aCol);
      gl.vertexAttribPointer(a.aCol, 3, gl.FLOAT, false, stride, 12);
      gl.enableVertexAttribArray(a.aSize);
      gl.vertexAttribPointer(a.aSize, 1, gl.FLOAT, false, stride, 24);
      gl.enableVertexAttribArray(a.aAlpha);
      gl.vertexAttribPointer(a.aAlpha, 1, gl.FLOAT, false, stride, 28);
      gl.enable(gl.BLEND);
      if (additive) gl.blendFunc(gl.SRC_ALPHA, gl.ONE); else gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      gl.depthMask(false);
      gl.disable(gl.CULL_FACE);
      gl.drawArrays(gl.POINTS, 0, pts.count);
      gl.depthMask(true);
      gl.disable(gl.BLEND);
      gl.enable(gl.CULL_FACE);
    }
  }

  /* -------------------------------- particles ------------------------------ */
  class Particles {
    constructor(max) { this.max = max || 180; this.items = []; this.buf = new Float32Array(max * 8); }
    spawn(p) {
      if (this.items.length >= this.max) this.items.shift();
      this.items.push(p);
    }
    update(dt, gravity) {
      gravity = gravity === undefined ? 0.8 : gravity;
      for (let i = this.items.length - 1; i >= 0; i--) {
        const p = this.items[i];
        p.life -= dt;
        if (p.life <= 0) { this.items.splice(i, 1); continue; }
        p.vy -= gravity * dt;
        p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
        p.vx *= 1 - 1.6 * dt; p.vz *= 1 - 1.6 * dt;
        if (p.y < 0.02) { p.y = 0.02; p.vy *= -0.25; }
      }
    }
    build(scale, dim) {
      const items = this.items;
      const b = this.buf;
      const d = dim === undefined ? 1 : dim;
      for (let i = 0; i < items.length; i++) {
        const p = items[i], o = i * 8;
        const t = clamp(p.life / p.maxLife, 0, 1);
        b[o] = p.x; b[o + 1] = p.y; b[o + 2] = p.z;
        b[o + 3] = p.r; b[o + 4] = p.g; b[o + 5] = p.b;
        b[o + 6] = p.size * (p.grow ? (1.4 - t * 0.4) : 1);
        b[o + 7] = p.alpha * t * d;
      }
      return { data: b, count: items.length };
    }
  }

  global.PB = {
    TAU, clamp, lerp, smoothstep, damp, mulberry32,
    hex, mixc, scalec, jitter,
    m4, m4identity, m4mul, m4translate, m4rotX, m4rotY, m4rotZ, m4scale, compose,
    m4perspective, m4lookAt, normalMat3, xformPoint, xformDir, cross, norm,
    m4fromX, m4fromY, angleLerp,
    geo: { sphere, cylinder, torus, box, quad, disc, cone },
    GEOS, Mesh, ShadowMesh, Renderer, Particles,
  };
})(window);
