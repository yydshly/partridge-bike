/* =========================================================================
   鹧鸪骑单车 — application
   ========================================================================= */
(function () {
  'use strict';
  const PB = window.PB;
  const {
    clamp, lerp, damp, smoothstep, hex, mixc,
    m4, m4identity, m4mul, m4fromX, m4fromY, m4rotZ, compose,
    m4perspective, m4lookAt, xformPoint, angleLerp,
  } = PB;

  const $ = (id) => document.getElementById(id);
  const canvas = $('scene');
  const loader = $('loader');
  const fatal = $('fatal');

  function showFatal(err) {
    console.error(err);
    if (fatal) {
      fatal.hidden = false;
      fatal.querySelector('.fatal-msg').textContent = String(err && err.message ? err.message : err);
    }
    if (loader) loader.classList.add('hidden');
  }

  let renderer;
  try {
    renderer = new PB.Renderer(canvas);
  } catch (e) {
    showFatal(e);
    return;
  }

  /* ------------------------------- palettes -------------------------------- */
  const PALETTE_DEFS = [
    {
      key: 'sunset', label: '黄昏',
      zenith: '#263b63', horizon: '#f3a265', haze: '#f5c292', disc: '#ffc27a', stars: 0.0,
      lightSun: '#ffb979', skyAmb: '#4f5878', groundAmb: '#3a2c23', fog: '#dfa77c',
      fogNear: 30, fogFar: 200, shadow: '#1d140f', cloud: '#f6e2cf',
      mote: '#ffe2b0', moteAlpha: 0.30, firefly: 0.0, tint: [1, 1, 1],
      sunDir: [-0.84, 0.13, -0.50],
    },
    {
      key: 'day', label: '白天',
      zenith: '#2f74b8', horizon: '#b9dfe8', haze: '#d9edf1', disc: '#fff3d0', stars: 0.0,
      lightSun: '#e8c99b', skyAmb: '#6f8ba0', groundAmb: '#45483a', fog: '#9fc3cc',
      fogNear: 45, fogFar: 240, shadow: '#2a2f25', cloud: '#fbfaf3',
      mote: '#fff6da', moteAlpha: 0.18, firefly: 0.0, tint: [1, 1, 1],
      sunDir: [-0.45, 0.60, -0.66],
    },
    {
      key: 'night', label: '夜晚',
      zenith: '#060b1a', horizon: '#18233e', haze: '#22304f', disc: '#dfe8ff', stars: 1.0,
      lightSun: '#7c90d6', skyAmb: '#252f4e', groundAmb: '#0c0c15', fog: '#17203a',
      fogNear: 24, fogFar: 170, shadow: '#05060c', cloud: '#3b4866',
      mote: '#ffe9a8', moteAlpha: 0.16, firefly: 1.0, tint: [0.78, 0.86, 1.05],
      sunDir: [-0.60, 0.16, -0.68],
    },
  ];
  const PALETTE_KEYS = ['zenith', 'horizon', 'haze', 'disc', 'lightSun', 'skyAmb', 'groundAmb', 'fog', 'shadow', 'cloud', 'mote'];
  function makePalette(def) {
    const p = { key: def.key, label: def.label, stars: def.stars, fogNear: def.fogNear, fogFar: def.fogFar, moteAlpha: def.moteAlpha, firefly: def.firefly, sunDir: [-0.52, 0.20, -0.78], tint: def.tint || [1, 1, 1] };
    for (const k of PALETTE_KEYS) p[k] = hex(def[k]);
    p.sunDir = PB.norm(def.sunDir || [-0.52, 0.20, -0.78]);
    return p;
  }
  const palettes = PALETTE_DEFS.map(makePalette);
  let paletteTarget = palettes[0];
  const palette = makePalette(PALETTE_DEFS[0]);
  let timeIndex = 0;

  function lerpPalette(dt) {
    const t = 1 - Math.exp(-2.6 * dt);
    for (const k of PALETTE_KEYS) palette[k] = mixc(palette[k], paletteTarget[k], t);
    palette.sunDir = PB.norm([
      lerp(palette.sunDir[0], paletteTarget.sunDir[0], t),
      lerp(palette.sunDir[1], paletteTarget.sunDir[1], t),
      lerp(palette.sunDir[2], paletteTarget.sunDir[2], t),
    ]);
    palette.stars = lerp(palette.stars, paletteTarget.stars, t);
    palette.fogNear = lerp(palette.fogNear, paletteTarget.fogNear, t);
    palette.fogFar = lerp(palette.fogFar, paletteTarget.fogFar, t);
    palette.moteAlpha = lerp(palette.moteAlpha, paletteTarget.moteAlpha, t);
    palette.firefly = lerp(palette.firefly, paletteTarget.firefly, t);
    palette.tint = mixc(palette.tint, paletteTarget.tint, t);
    palette.label = paletteTarget.label;
    palette.key = paletteTarget.key;
  }

  /* --------------------------------- world --------------------------------- */
  const world = PB.buildWorld();
  const W = {
    terrain: renderer.uploadMesh(world.terrain),
    grass: renderer.uploadMesh(world.grass),
    flowers: renderer.uploadMesh(world.flowers),
    trees: renderer.uploadMesh(world.trees),
    fence: renderer.uploadMesh(world.fence),
    mountains: renderer.uploadMesh(world.mountains),
    treeShadows: renderer.uploadShadow(world.treeShadows),
    flock: renderer.uploadMesh(world.flock),
  };

  /* --------------------------------- rider --------------------------------- */
  const rider = PB.buildRider();
  const D = rider.dims;
  const G = {};
  for (const k in rider.meshes) G[k] = renderer.uploadMesh(rider.meshes[k]);
  const IDENT = m4identity(m4());
  const shadowUnit = (() => {
    const sh = new PB.ShadowMesh();
    sh.addQuad([0, 0, 0], 0.5, 0.5, 1, 0);
    return renderer.uploadShadow(sh.build());
  })();

  /* --------------------------------- state --------------------------------- */
  const ride = {
    x: 0, z: 0, heading: -0.45,
    speed: 4.2, cruise: 4.2, steer: 0, lean: 0,
    wheelAngle: 0, crankAngle: 0,
    hopY: 0, hopV: 0, airborne: false,
    distance: 0, dustAcc: 0, bob: 0,
    cadence: 0,
  };
  const PADDOCK_R = 13.8;

  const cam = {
    yaw: 1.05, pitch: 0.14, dist: 7.4,
    wantYaw: 1.05, wantPitch: 0.14, wantDist: 4.5,
    target: [0, 0.95, 0], auto: false, follow: false, track: null, dragging: false,
    pinch: 0, pointers: new Map(),
  };

  const dust = new PB.Particles(180);
  if (window.innerWidth / Math.max(1, window.innerHeight) < 0.9) {
    cam.yaw = -ride.heading + 0.12;
    cam.wantYaw = cam.yaw;
    cam.dist = 7.4;
    cam.wantDist = 4.9;
  }
  const motes = [];
  (function () {
    const rnd = PB.mulberry32(4242);
    for (let i = 0; i < 80; i++) {
      const a = rnd() * Math.PI * 2, r = Math.sqrt(rnd()) * 15;
      motes.push({
        x: Math.cos(a) * r, z: Math.sin(a) * r,
        y: 0.35 + rnd() * 2.6,
        ph: rnd() * Math.PI * 2,
        amp: 0.25 + rnd() * 0.6,
        sp: 0.18 + rnd() * 0.4,
        size: 0.022 + rnd() * 0.035,
        firefly: rnd() > 0.45,
      });
    }
  })();

  let paused = false;
  let shadowDebug = false;
  let simTime = 0;
  let pageTime = 0;
  let hopRequest = false;
  let lastFrame = performance.now();
  let statsTimer = 0;

  /* -------------------------------- controls ------------------------------- */
  const keys = new Set();
  const KEY_HOP = 'Space';

  function onKeyDown(e) {
    if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
    const code = e.code;
    if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Space'].includes(code)) e.preventDefault();
    if (!keys.has(code)) {
      if (code === KEY_HOP) hopRequest = true;
      if (code === 'KeyP') togglePause();
      if (code === 'KeyR') resetRide();
      if (code === 'KeyC') cycleView();
      if (code === 'KeyN') cycleTime();
    }
    keys.add(code);
  }
  function onKeyUp(e) { keys.delete(e.code); }
  window.addEventListener('keydown', onKeyDown);
  window.addEventListener('keyup', onKeyUp);
  window.addEventListener('blur', () => keys.clear());

  /* ------------------------------ pointer orbit ---------------------------- */
  function pointerDown(e) {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    canvas.setPointerCapture(e.pointerId);
    cam.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    cam.dragging = true;
    cam.follow = false;
    cam.track = null;
    document.body.classList.add('grabbing');
    if (cam.pointers.size === 2) {
      const pts = [...cam.pointers.values()];
      cam.pinch = Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
    }
  }
  function pointerMove(e) {
    const p = cam.pointers.get(e.pointerId);
    if (!p) return;
    const dx = e.clientX - p.x, dy = e.clientY - p.y;
    p.x = e.clientX; p.y = e.clientY;
    if (cam.pointers.size >= 2) {
      const pts = [...cam.pointers.values()];
      const d = Math.hypot(pts[0].x - pts[1].x, pts[0].y - pts[1].y);
      if (cam.pinch > 0) {
        cam.wantDist = clamp(cam.wantDist * Math.exp((cam.pinch - d) * 0.007), 2.3, 11);
      }
      cam.pinch = d;
      return;
    }
    cam.wantYaw -= dx * 0.0052;
    cam.wantPitch = clamp(cam.wantPitch + dy * 0.0042, 0.02, 1.30);
  }
  function pointerUp(e) {
    cam.pointers.delete(e.pointerId);
    cam.pinch = 0;
    if (cam.pointers.size === 0) {
      cam.dragging = false;
      document.body.classList.remove('grabbing');
    }
  }
  canvas.addEventListener('pointerdown', pointerDown);
  canvas.addEventListener('pointermove', pointerMove);
  canvas.addEventListener('pointerup', pointerUp);
  canvas.addEventListener('pointercancel', pointerUp);
  canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    cam.wantDist = clamp(cam.wantDist * Math.exp(e.deltaY * 0.0012), 2.3, 11);
  }, { passive: false });
  canvas.addEventListener('dblclick', () => {
    cam.wantYaw = 1.05;
    setView('orbit');
  });

  /* ---------------------------------- views -------------------------------- */
  const views = document.querySelectorAll('[data-view]');
  function setView(name) {
    if (name === 'orbit') {
      cam.follow = false;
      cam.track = null;
      cam.wantPitch = 0.17;
      cam.wantDist = 4.6;
    } else {
      cam.auto = false;
      autoBtn.classList.remove('active');
      autoBtn.setAttribute('aria-pressed', 'false');
      if (name === 'side') {
        cam.follow = false;
        cam.track = 'side';
        cam.wantYaw = -ride.heading;
        cam.wantPitch = 0.10;
        cam.wantDist = 4.3;
      } else if (name === 'front') {
        cam.follow = false;
        cam.track = 'front';
        cam.wantYaw = Math.PI / 2 - ride.heading;
        cam.wantPitch = 0.13;
        cam.wantDist = 4.1;
      } else if (name === 'follow') {
        cam.follow = true;
        cam.track = null;
        cam.wantPitch = 0.19;
        cam.wantDist = 4.4;
      }
    }
    setActiveView(name);
  }
  function setActiveView(name) {
    views.forEach((b) => {
      const on = b.dataset.view === name;
      b.classList.toggle('active', on);
      b.setAttribute('aria-pressed', String(on));
    });
  }
  let currentView = 'orbit';
  views.forEach((b) => b.addEventListener('click', () => { currentView = b.dataset.view; setView(currentView); }));
  function cycleView() {
    const order = ['orbit', 'side', 'front', 'follow'];
    currentView = order[(order.indexOf(currentView) + 1) % order.length];
    setView(currentView);
  }

  /* --------------------------------- UI ------------------------------------ */
  const pauseBtn = $('pauseBtn');
  const autoBtn = $('autoBtn');
  const timeBtn = $('timeBtn');
  const resetBtn = $('resetBtn');
  const speedRange = $('speedRange');
  const speedVal = $('speedVal');
  const statSpeed = $('statSpeed');
  const statCadence = $('statCadence');
  const statDist = $('statDist');
  const statMode = $('statMode');

  function togglePause() {
    paused = !paused;
    pauseBtn.classList.toggle('is-paused', paused);
    pauseBtn.setAttribute('aria-label', paused ? '继续骑行' : '暂停骑行');
    pauseBtn.setAttribute('aria-pressed', String(paused));
    document.body.classList.toggle('paused', paused);
  }
  function cycleTime() {
    timeIndex = (timeIndex + 1) % palettes.length;
    paletteTarget = palettes[timeIndex];
    timeBtn.dataset.mode = paletteTarget.key;
    timeBtn.querySelector('.time-label').textContent = paletteTarget.label;
    timeBtn.setAttribute('aria-label', '切换时间：' + paletteTarget.label);
  }
  function resetRide() {
    ride.x = 0; ride.z = 0; ride.heading = -0.45; ride.speed = 4.2; ride.cruise = 4.2;
    ride.steer = 0; ride.lean = 0; ride.hopY = 0; ride.hopV = 0; ride.airborne = false;
    ride.distance = 0; ride.wheelAngle = 0; ride.crankAngle = 0;
    cam.follow = false;
    cam.track = null;
    const portrait = window.innerWidth / Math.max(1, window.innerHeight) < 0.9;
    cam.wantYaw = portrait ? -ride.heading + 0.12 : 1.05;
    cam.wantPitch = portrait ? 0.16 : 0.14;
    cam.wantDist = portrait ? 4.9 : 4.6;
    cam.yaw = cam.wantYaw + 0.35;
    cam.pitch = 0.2;
    cam.dist = 6.6;
    cam.target = [0, 0.95, 0];
    speedRange.value = '4.2';
    speedVal.textContent = '4.2';
    updateSliderFill();
    setActiveView('orbit');
    currentView = 'orbit';
    dust.items.length = 0;
  }

  pauseBtn.addEventListener('click', togglePause);
  autoBtn.addEventListener('click', () => {
    cam.auto = !cam.auto;
    autoBtn.classList.toggle('active', cam.auto);
    autoBtn.setAttribute('aria-pressed', String(cam.auto));
    if (cam.auto) {
      cam.follow = false;
      cam.track = null;
      setView('orbit');
      cam.auto = true;
      autoBtn.classList.add('active');
      autoBtn.setAttribute('aria-pressed', 'true');
    }
  });
  timeBtn.addEventListener('click', cycleTime);
  resetBtn.addEventListener('click', resetRide);
  function updateSliderFill() {
    const pct = (ride.cruise / 12) * 100;
    speedRange.style.setProperty('--fill', pct.toFixed(1));
  }
  speedRange.addEventListener('input', () => {
    ride.cruise = parseFloat(speedRange.value);
    speedVal.textContent = ride.cruise.toFixed(1);
    updateSliderFill();
  });
  updateSliderFill();

  const hopBtn = $('hopBtn');
  if (hopBtn) {
    hopBtn.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      hopRequest = true;
      hopBtn.classList.add('held');
    });
    hopBtn.addEventListener('pointerup', () => hopBtn.classList.remove('held'));
    hopBtn.addEventListener('pointercancel', () => hopBtn.classList.remove('held'));
    hopBtn.addEventListener('pointerleave', () => hopBtn.classList.remove('held'));
  }
  document.querySelectorAll('[data-hold]').forEach((btn) => {
    const code = btn.dataset.hold;
    const press = (e) => {
      e.preventDefault();
      keys.add(code);
      btn.classList.add('held');
      try { btn.setPointerCapture(e.pointerId); } catch (_) { /* noop */ }
    };
    const release = () => { keys.delete(code); btn.classList.remove('held'); };
    btn.addEventListener('pointerdown', press);
    btn.addEventListener('pointerup', release);
    btn.addEventListener('pointercancel', release);
    btn.addEventListener('pointerleave', release);
  });

  /* ------------------------------ pose helpers ----------------------------- */
  const M = {
    bike: m4(), body: m4(), head: m4(), tail: m4(),
    wheelF: m4(), wheelR: m4(), crank: m4(),
    pedalR: m4(), pedalL: m4(),
    wingR: m4(), wingL: m4(),
    thighR: m4(), thighL: m4(), shinR: m4(), shinL: m4(), footR: m4(), footL: m4(),
  };
  const T1 = m4(), T2 = m4(), T3 = m4(), V1 = [0, 0, 0], V2 = [0, 0, 0];

  function solveKnee(hip, ankle, l1, l2, pole) {
    let dx = ankle[0] - hip[0], dy = ankle[1] - hip[1], dz = ankle[2] - hip[2];
    let d = Math.hypot(dx, dy, dz);
    if (d < 1e-5) d = 1e-5;
    const ux = dx / d, uy = dy / d, uz = dz / d;
    const dd = clamp(d, Math.abs(l1 - l2) + 0.002, l1 + l2 - 0.002);
    const h = (l1 * l1 - l2 * l2 + dd * dd) / (2 * dd);
    const r = Math.sqrt(Math.max(0, l1 * l1 - h * h));
    const dot = pole[0] * ux + pole[1] * uy + pole[2] * uz;
    let px = pole[0] - ux * dot, py = pole[1] - uy * dot, pz = pole[2] - uz * dot;
    let pl = Math.hypot(px, py, pz);
    if (pl < 1e-4) { px = 0; py = 0; pz = 1; pl = 1; }
    px /= pl; py /= pl; pz /= pl;
    return [hip[0] + ux * h + px * r, hip[1] + uy * h + py * r, hip[2] + uz * h + pz * r];
  }

  function spawnDust(x, y, z, power, spread) {
    const rnd = Math.random;
    const a = rnd() * Math.PI * 2;
    dust.spawn({
      x: x + (rnd() - 0.5) * 0.25, y: y + rnd() * 0.12, z: z + (rnd() - 0.5) * 0.25,
      vx: Math.cos(a) * spread * rnd(), vy: 0.5 + rnd() * 0.9 * power, vz: Math.sin(a) * spread * rnd(),
      life: 0.55 + rnd() * 0.65, maxLife: 1.1,
      size: 0.24 + rnd() * 0.4, alpha: 0.35 + rnd() * 0.3, grow: true,
      r: 0.84, g: 0.75, b: 0.6,
    });
  }

  function burst(x, z) {
    for (let i = 0; i < 18; i++) {
      const a = Math.random() * Math.PI * 2, s = 0.6 + Math.random() * 1.6;
      dust.spawn({
        x: x + Math.cos(a) * 0.3, y: 0.05, z: z + Math.sin(a) * 0.3,
        vx: Math.cos(a) * s, vy: 0.6 + Math.random() * 1.3, vz: Math.sin(a) * s,
        life: 0.5 + Math.random() * 0.6, maxLife: 1.1,
        size: 0.18 + Math.random() * 0.35, alpha: 0.28, grow: true,
        r: 0.82, g: 0.73, b: 0.58,
      });
    }
  }

  /* -------------------------------- physics -------------------------------- */
  function updateRide(dt) {
    if (dt <= 0) return;
    let cruise = ride.cruise;
    if (keys.has('KeyW') || keys.has('ArrowUp')) cruise += 3.0 * dt;
    if (keys.has('KeyS') || keys.has('ArrowDown')) cruise -= 5.0 * dt;
    cruise = clamp(cruise, 0, 12);
    if (cruise !== ride.cruise) {
      ride.cruise = cruise;
      speedRange.value = cruise.toFixed(1);
      speedVal.textContent = cruise.toFixed(1);
      updateSliderFill();
    }
    const target = ride.cruise;
    const rate = target > ride.speed ? 3.4 : 6.0;
    const dv = clamp(target - ride.speed, -rate * dt, rate * dt);
    ride.speed += dv;
    if (Math.abs(target - ride.speed) < 0.005) ride.speed = target;

    let steerTarget = 0;
    if (keys.has('KeyD') || keys.has('ArrowRight')) steerTarget += 1;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) steerTarget -= 1;
    ride.steer = damp(ride.steer, steerTarget, 8, dt);

    if (ride.speed > 0.2) {
      const eff = clamp(ride.speed / 5, 0.18, 1);
      ride.heading += ride.steer * 1.45 * eff * dt;
    }

    const fwdX = Math.cos(ride.heading), fwdZ = Math.sin(ride.heading);
    ride.x += fwdX * ride.speed * dt;
    ride.z += fwdZ * ride.speed * dt;
    ride.distance += ride.speed * dt;

    const r = Math.hypot(ride.x, ride.z);
    if (r > PADDOCK_R) {
      const radial = Math.atan2(ride.z, ride.x);
      let tangent = radial + Math.PI / 2;
      if (Math.cos(tangent - ride.heading) < 0) tangent += Math.PI;
      const k = 1 - Math.exp(-2.4 * dt);
      ride.heading = angleLerp(ride.heading, tangent, k);
      ride.speed = Math.min(ride.speed, 5.4);
      const pull = (r - PADDOCK_R) * 0.9 * dt;
      ride.x -= Math.cos(radial) * pull;
      ride.z -= Math.sin(radial) * pull;
    }

    const leanTarget = ride.steer * clamp(ride.speed / 6, 0, 1) * 0.30;
    ride.lean = damp(ride.lean, leanTarget, 6, dt);

    if (hopRequest) {
      hopRequest = false;
      if (!ride.airborne) {
        ride.airborne = true;
        ride.hopV = 3.3;
      }
    }
    if (ride.airborne) {
      ride.hopY += ride.hopV * dt;
      ride.hopV -= 10.0 * dt;
      if (ride.hopY <= 0) {
        ride.hopY = 0;
        ride.hopV = 0;
        ride.airborne = false;
        burst(ride.x, ride.z);
      }
    }

    const wheelSpeed = ride.speed / D.wheelR;
    ride.wheelAngle -= wheelSpeed * dt;
    ride.crankAngle -= (wheelSpeed / 1.7) * dt;
    ride.cadence = (wheelSpeed / 1.7) / (Math.PI * 2) * 60;

    ride.bob = Math.sin(ride.crankAngle * 2) * 0.013 * clamp(ride.speed / 2, 0, 1) + Math.sin(simTime * 1.6) * 0.004;

    if (ride.speed > 0.8) {
      ride.dustAcc += dt * ride.speed * 3.4;
      while (ride.dustAcc > 1) {
        ride.dustAcc -= 1;
        const bx = ride.x - Math.cos(ride.heading) * 0.55 + (Math.random() - 0.5) * 0.18;
        const bz = ride.z - Math.sin(ride.heading) * 0.55 + (Math.random() - 0.5) * 0.18;
        spawnDust(bx, 0.04, bz, 0.8, 0.55);
      }
    } else {
      ride.dustAcc = 0;
    }
    dust.update(dt, 1.1);
  }

  /* --------------------------------- camera -------------------------------- */
  const _target = [0, 0, 0];
  function updateCamera(dt) {
    const aspectNow = canvas.clientWidth / Math.max(1, canvas.clientHeight);
    const lead = aspectNow < 0.9 ? 0.35 : 0.2;
    const wishX = ride.x + Math.cos(ride.heading) * lead;
    const wishZ = ride.z + Math.sin(ride.heading) * lead;
    const wantY = 0.95 + ride.hopY * 0.55;
    const k = 1 - Math.exp(-9 * dt);
    cam.target[0] = lerp(cam.target[0], wishX, k);
    cam.target[1] = lerp(cam.target[1], wantY, k);
    cam.target[2] = lerp(cam.target[2], wishZ, k);

    if (cam.follow) cam.wantYaw = -ride.heading - Math.PI / 2;
    else if (cam.track === 'side') cam.wantYaw = -ride.heading;
    else if (cam.track === 'front') cam.wantYaw = Math.PI / 2 - ride.heading;
    if (cam.auto && !cam.dragging) cam.wantYaw += 0.13 * dt;

    const kc = 1 - Math.exp(-9 * dt);
    cam.yaw = angleLerp(cam.yaw, cam.wantYaw, kc);
    cam.pitch = lerp(cam.pitch, cam.wantPitch, kc);
    cam.dist = lerp(cam.dist, cam.wantDist, kc);

    if (cam.dist < 3.4) cam.pitch = Math.max(cam.pitch, 0.08);

    const portraitBias = aspectNow < 0.9 ? 1.6 : 1;
    const dist = cam.dist * portraitBias;
    const cp = Math.cos(cam.pitch);
    const eye = [
      cam.target[0] + Math.sin(cam.yaw) * cp * dist,
      cam.target[1] + Math.sin(cam.pitch) * dist,
      cam.target[2] + Math.cos(cam.yaw) * cp * dist,
    ];
    if (eye[1] < 0.28) eye[1] = 0.28;
    return eye;
  }

  /* -------------------------------- animation ------------------------------ */
  function poseRider(t) {
    const bikeM = compose(M.bike, ride.x, ride.hopY, ride.z, ride.lean, -ride.heading, 0, 1, 1, 1);
    const hop = ride.hopY;
    const bob = ride.bob;
    const [bbX, bbY] = D.bb;
    const cR = Math.cos(ride.crankAngle), sR = Math.sin(ride.crankAngle);
    const pR = [bbX + cR * D.crankR, bbY + sR * D.crankR, D.pedalZ];
    const pL = [bbX - cR * D.crankR, bbY - sR * D.crankR, -D.pedalZ];

    m4mul(M.wheelR, bikeM, compose(T1, D.wheelX[0], D.wheelR, 0, 0, 0, ride.wheelAngle, 1, 1, 1));
    m4mul(M.wheelF, bikeM, compose(T1, D.wheelX[1], D.wheelR, 0, 0, 0, ride.wheelAngle, 1, 1, 1));
    m4mul(M.crank, bikeM, compose(T1, bbX, bbY, 0, 0, 0, ride.crankAngle, 1, 1, 1));
    m4mul(M.pedalR, bikeM, compose(T1, pR[0], pR[1], pR[2], 0, 0, 0, 1, 1, 1));
    m4mul(M.pedalL, bikeM, compose(T1, pL[0], pL[1], pL[2], 0, 0, 0, 1, 1, 1));

    const sway = -ride.lean * 0.32 + Math.sin(ride.crankAngle * 2) * 0.018;
    const bodyPitch = D.bodyTilt + Math.sin(ride.crankAngle * 2 + 1) * 0.012;
    m4mul(M.body, bikeM, compose(T1, D.body[0], D.body[1] + bob, D.body[2], sway, 0, bodyPitch, 1, 1, 1));

    const nod = Math.sin(ride.crankAngle * 2 + 0.8) * 0.028 + Math.sin(t * 1.25) * 0.016;
    const headTurn = Math.sin(ride.crankAngle) * 0.05 + Math.sin(t * 0.7) * 0.045;
    m4mul(M.head, M.body, compose(T1, D.headLocal[0], D.headLocal[1], D.headLocal[2], nod * 0.6, headTurn, nod, 1, 1, 1));

    m4mul(M.tail, M.body, compose(T1, -0.33, 0.02, 0,
      Math.sin(ride.crankAngle * 2) * 0.04,
      Math.sin(ride.crankAngle * 2 + 0.7) * 0.11 + Math.sin(t * 0.8) * 0.05,
      -0.18 + Math.sin(ride.crankAngle * 2 + 2) * 0.05, 1, 1, 1));

    const flutter = Math.sin(t * 6.4) * 0.022 + (ride.airborne ? 0.28 + Math.sin(t * 21) * 0.30 : 0) + clamp(ride.speed / 12, 0, 0.15) * Math.sin(t * 9);
    for (const side of [1, -1]) {
      const shoulder = xformPoint(V1, M.body, [-0.02, 0.06, side * 0.20]);
      const gi = side > 0 ? 0 : 1;
      const grip = [D.grips[gi][0], D.grips[gi][1], D.grips[gi][2]];
      m4fromX(T1, shoulder, [grip[0] - shoulder[0], grip[1] - shoulder[1], grip[2] - shoulder[2]], [0, 1, 0]);
      m4rotZ(T1, flutter);
      m4mul(side > 0 ? M.wingR : M.wingL, bikeM, T1);
    }

    const hipBase = D.hip[1];
    for (const side of [1, -1]) {
      const pedal = side > 0 ? pR : pL;
      const hip = [D.hip[0], hipBase + bob * 0.45, side * D.hip[2]];
      const ankle = [pedal[0], pedal[1] + 0.062, pedal[2]];
      const knee = solveKnee(hip, ankle, D.legL1, D.legL2, [1, 0, 0]);
      m4fromY(T1, hip, [knee[0] - hip[0], knee[1] - hip[1], knee[2] - hip[2]], [0, 0, 1]);
      m4mul(side > 0 ? M.thighR : M.thighL, bikeM, T1);
      m4fromY(T2, knee, [ankle[0] - knee[0], ankle[1] - knee[1], ankle[2] - knee[2]], [0, 0, 1]);
      m4mul(side > 0 ? M.shinR : M.shinL, bikeM, T2);
      m4mul(side > 0 ? M.footR : M.footL, bikeM, compose(T3, pedal[0], pedal[1] + 0.032, pedal[2], 0, 0, 0, 1, 1, 1));
    }

    return { bikeM };
  }

  /* --------------------------------- render -------------------------------- */
  const proj = m4();
  const view = m4();
  const ident = m4identity(m4());
  const scene = {
    proj, view, right: [0, 0, 0], up: [0, 0, 0], fwd: [0, 0, 0],
    tanX: 1, tanY: 1, sunDir: [0, 0, -1], sunColor: [1, 1, 1], skyColor: [0, 0, 0],
    groundColor: [0, 0, 0], fogColor: [0, 0, 0], fogNear: 20, fogFar: 120,
    tint: [1, 1, 1], shadowColor: [0, 0, 0],
  };

  function buildMoteData(t) {
    const count = motes.length;
    const data = new Float32Array(count * 8);
    const night = palette.firefly;
    for (let i = 0; i < count; i++) {
      const m = motes[i], o = i * 8;
      const x = m.x + Math.sin(t * m.sp + m.ph) * m.amp;
      const y = m.y + Math.sin(t * m.sp * 1.6 + m.ph * 1.7) * 0.22;
      const z = m.z + Math.cos(t * m.sp * 0.8 + m.ph) * m.amp;
      const blink = 0.55 + 0.45 * Math.sin(t * (m.firefly ? 2.3 : 1.1) + m.ph * 3);
      let alpha = palette.moteAlpha * (m.firefly ? 1 : 0.7) * blink;
      if (m.firefly) alpha += night * 0.9 * blink;
      data[o] = x; data[o + 1] = y; data[o + 2] = z;
      if (m.firefly && night > 0.2) {
        data[o + 3] = 1.0; data[o + 4] = 0.88; data[o + 5] = 0.5;
      } else {
        data[o + 3] = 1.0; data[o + 4] = 0.92; data[o + 5] = 0.72;
      }
      data[o + 6] = m.size * (m.firefly ? 1.8 : 1);
      data[o + 7] = clamp(alpha, 0, 1);
    }
    return { data, count };
  }

  function render(t, dt) {
    const aspect = renderer.resize();
    const eye = updateCamera(dt);
    const target = cam.target;
    const fov = 45 * Math.PI / 180;
    m4perspective(proj, fov, aspect, 0.26, 280);
    m4lookAt(view, eye, target, [0, 1, 0]);

    const fwd = PB.norm([target[0] - eye[0], target[1] - eye[1], target[2] - eye[2]]);
    const right = PB.norm(PB.cross(fwd, [0, 1, 0]));
    const up = PB.cross(right, fwd);
    const tanY = Math.tan(fov / 2), tanX = tanY * aspect;

    scene.sunDir = palette.sunDir;
    scene.sunColor = palette.lightSun;
    scene.skyColor = palette.skyAmb;
    scene.groundColor = palette.groundAmb;
    scene.fogColor = palette.fog;
    scene.fogNear = palette.fogNear;
    scene.fogFar = palette.fogFar;
    scene.shadowColor = palette.shadow;
    scene.tint = palette.tint;
    scene.right = right; scene.up = up; scene.fwd = fwd;
    scene.tanX = tanX; scene.tanY = tanY;

    renderer.setScene(scene);
    renderer.begin();
    renderer.drawSky(palette);

    renderer.draw(W.terrain, ident);
    renderer.draw(W.grass, ident, { doubleSided: true });
    renderer.draw(W.flowers, ident, { doubleSided: true });
    renderer.draw(W.trees, ident);
    renderer.draw(W.fence, ident);
    renderer.draw(W.mountains, ident);

    const flockM = compose(T1,
      world.flockCenter[0] + Math.sin(t * 0.03) * 7,
      world.flockCenter[1] + Math.sin(t * 0.21) * 0.4,
      world.flockCenter[2] + Math.cos(t * 0.03) * 7,
      0, Math.sin(t * 0.02) * 0.18, 0, 1, 1, 1);
    renderer.draw(W.flock, flockM, { unlit: true, doubleSided: true });

    poseRider(t);
    renderer.draw(G.frame, M.bike);
    renderer.draw(G.wheel, M.wheelR);
    renderer.draw(G.wheel, M.wheelF);
    renderer.draw(G.crank, M.crank);
    renderer.draw(G.pedal, M.pedalR);
    renderer.draw(G.pedal, M.pedalL);
    renderer.draw(G.body, M.body);
    renderer.draw(G.tail, M.tail);
    renderer.draw(G.head, M.head);
    renderer.draw(G.wing, M.wingR, { doubleSided: true });
    renderer.draw(G.wing, M.wingL, { doubleSided: true });
    renderer.draw(G.thigh, M.thighR);
    renderer.draw(G.thigh, M.thighL);
    renderer.draw(G.shin, M.shinR);
    renderer.draw(G.shin, M.shinL);
    renderer.draw(G.foot, M.footR);
    renderer.draw(G.foot, M.footL);

    // ambient contact shadows
    renderer.drawShadow(W.treeShadows, ident, 0.8);
    const bikeShadowScale = 1 / (1 + ride.hopY * 0.7);
    const shadowColor = shadowDebug ? [1, 0.08, 0.08] : undefined;
    renderer.drawShadow(shadowUnit,
      compose(T1, ride.x, 0.04, ride.z, 0, -ride.heading, 0, 2.05 * bikeShadowScale, 1, 0.92 * bikeShadowScale),
      shadowDebug ? 1 : 0.72 * (1 - ride.hopY * 0.22), shadowColor);
    const bm = M.body;
    renderer.drawShadow(shadowUnit,
      compose(T1, bm[12], 0.045, bm[14], 0, -ride.heading, 0, 0.60 * bikeShadowScale, 1, 0.62 * bikeShadowScale),
      shadowDebug ? 1 : 0.46 * (1 - ride.hopY * 0.3), shadowColor);

    // dust & motes
    renderer.drawPoints(dust.build(1, 1 - palette.firefly * 0.65), 1.0, false);
    renderer.drawPoints(buildMoteData(t), 1.0, true);

    statsTimer += dt;
    if (statsTimer > 0.12) {
      statsTimer = 0;
      statSpeed.textContent = (ride.speed * 3.6).toFixed(1);
      statCadence.textContent = Math.round(ride.cadence * Math.sign(ride.speed || 0));
      statDist.textContent = ride.distance < 1000 ? Math.round(ride.distance) + ' m' : (ride.distance / 1000).toFixed(2) + ' km';
      statMode.textContent = paletteTarget.label + (paused ? ' · 暂停' : ride.airborne ? ' · 腾空' : '');
    }
  }

  /* ---------------------------------- loop --------------------------------- */
  function frame(now) {
    let dt = (now - lastFrame) / 1000;
    lastFrame = now;
    if (dt > 0.06) dt = 0.06;
    if (dt < 0) dt = 0;
    pageTime += dt;
    const simDt = paused ? 0 : dt;
    simTime += simDt;
    lerpPalette(dt);
    updateRide(simDt);
    render(simTime, dt);
    if (loader && !loader.classList.contains('hidden')) {
      setTimeout(() => loader.classList.add('hidden'), 120);
    }
    requestAnimationFrame(frame);
  }

  // count-in: subtle camera push-in at start
  document.addEventListener('visibilitychange', () => { lastFrame = performance.now(); });
  requestAnimationFrame(frame);

  // expose a tiny debug handle for the curious (and for automated checks)
  window.__partridge = {
    get state() { return { ...ride, paused }; },
    setView, cycleTime, togglePause, resetRide,
    setPose(p) { Object.assign(ride, p); cam.target = [ride.x, 0.95, ride.z]; },
    setShadowDebug(v) { shadowDebug = !!v; },
    get palette() { return paletteTarget.key; },
    camera: cam,
    renderer,
  };
})();

