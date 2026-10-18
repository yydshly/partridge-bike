import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const $ = s => document.querySelector(s);
const canvas = $('#scene');
const stage = $('#stage');
const scene = new THREE.Scene();
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.8));
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.2;
const camera = new THREE.PerspectiveCamera(34, 1, .1, 100);
const orbit = new OrbitControls(camera, canvas);
orbit.enableDamping = true;
orbit.dampingFactor = .07;
orbit.enablePan = false;
orbit.minDistance = 5.4;
orbit.maxDistance = 21;
orbit.minPolarAngle = .32;
orbit.maxPolarAngle = Math.PI / 2 - .04;
orbit.autoRotateSpeed = .65;
const vec = (x, y, z) => new THREE.Vector3(x, y, z);
const M = (color, roughness = .85, metalness = 0) => new THREE.MeshStandardMaterial({ color, roughness, metalness });
const mat = {
  grass: M('#bbc68b'), edge: M('#97aa72'), road: M('#e7d9b9'), line: M('#fff3d2'),
  rubber: M('#3d4439'), rim: M('#e6dcbd', .5, .15), steel: M('#85958a', .32, .6),
  mint: M('#62a593', .35, .25), mintLight: M('#b8d1ae', .4, .2), seat: M('#764d36'),
  feather: M('#877158'), featherDark: M('#5c4b3b'), featherLight: M('#c5ae87'),
  belly: M('#c3beaa'), cream: M('#eee0b9'), bib: M('#383a30'), crown: M('#846343'),
  orange: M('#cf7243'), eyeRing: M('#c8894a'), eye: M('#211f1c', .12), white: M('#fff9df', .3),
  scarf: M('#c46c41'), trunk: M('#8d7c55'), leaf: M('#82985c'), leafLight: M('#a3b36e'),
  flower: M('#fff4d2'), yellow: M('#e6b14e'), lilac: M('#b49cb6'), stone: M('#c1c3a9'),
};
const hemi = new THREE.HemisphereLight('#fff4d9', '#81986b', 2.7);
scene.add(hemi);
const sun = new THREE.DirectionalLight('#fff0d4', 3.3);
sun.position.set(-3, 8, 5);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -7, right: 7, top: 7, bottom: -7, near: .5, far: 24 });
sun.shadow.normalBias = .025;
sun.shadow.bias = -.00015;
sun.shadow.radius = 4;
scene.add(sun);
const fill = new THREE.DirectionalLight('#ebffed', 1.2);
fill.position.set(4, 4, -5);
scene.add(fill);

const sphereGeo = new THREE.SphereGeometry(1, 32, 24);
const lowSphereGeo = new THREE.IcosahedronGeometry(1, 2);
const cylinderGeo = new THREE.CylinderGeometry(1, 1, 1, 12);
function mesh(geo, material, parent, position = [0, 0, 0]) {
  const m = new THREE.Mesh(geo, material);
  m.position.set(...position);
  m.castShadow = true; m.receiveShadow = true;
  parent.add(m); return m;
}
function ellipsoid(parent, material, p, s, low = false) {
  const m = mesh(low ? lowSphereGeo : sphereGeo, material, parent, p); m.scale.set(...s); return m;
}
function bar(parent, a, b, radius, material) {
  const m = mesh(cylinderGeo, material, parent);
  setBar(m, a, b, radius); return m;
}
function setBar(m, a, b, radius) {
  const start = Array.isArray(a) ? vec(...a) : a;
  const end = Array.isArray(b) ? vec(...b) : b;
  const d = end.clone().sub(start);
  m.position.copy(start).add(end).multiplyScalar(.5);
  m.scale.set(radius, d.length(), radius);
  m.quaternion.setFromUnitVectors(vec(0, 1, 0), d.normalize());
}
function curveTube(parent, points, radius, material, segments = 30) {
  return mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(points.map(p => vec(...p))), segments, radius, 8, false), material, parent);
}
function torus(parent, radius, thickness, material, p = [0, 0, 0]) {
  return mesh(new THREE.TorusGeometry(radius, thickness, 10, 64), material, parent, p);
}
function box(parent, material, p, s) {
  const m = mesh(new THREE.BoxGeometry(...s), material, parent, p); return m;
}

// A small landscape made entirely from geometry, with a moving trail under the bicycle.
const island = new THREE.Group(); scene.add(island);
const soil = mesh(new THREE.CylinderGeometry(4.3, 4.18, .3, 96), mat.edge, island, [0, -.23, 0]);
soil.scale.set(1.13, 1, .69);
const lawn = mesh(new THREE.CylinderGeometry(4.31, 4.31, .09, 96), mat.grass, island, [0, -.035, 0]);
lawn.scale.set(1.13, 1, .69);
const roadShape = new THREE.Shape();
roadShape.moveTo(-4.45, -.7); roadShape.lineTo(4.45, -.7); roadShape.quadraticCurveTo(4.81, -.7, 4.81, 0);
roadShape.quadraticCurveTo(4.81, .7, 4.45, .7); roadShape.lineTo(-4.45, .7); roadShape.quadraticCurveTo(-4.81, .7, -4.81, 0); roadShape.quadraticCurveTo(-4.81, -.7, -4.45, -.7);
const road = mesh(new THREE.ShapeGeometry(roadShape), mat.road, island, [0, .014, 0]); road.rotation.x = -Math.PI / 2;
const dashes = [];
for (let i = 0; i < 12; i++) dashes.push(box(island, mat.line, [-4.4 + i * .8, .022, .45], [.32, .008, .028]));
const shadowFloor = mesh(new THREE.PlaneGeometry(200, 200), new THREE.ShadowMaterial({ opacity: .12 }), scene, [0, -.4, 0]);
shadowFloor.rotation.x = -Math.PI / 2; shadowFloor.castShadow = false;
let seed = 731;
const random = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
function tuft(parent, x, z, scale = 1) {
  const g = new THREE.Group(); g.position.set(x, .035, z); g.scale.setScalar(scale); parent.add(g);
  for (let j = 0; j < 4; j++) {
    const blade = mesh(new THREE.ConeGeometry(.035, .23 + random() * .14, 3), j % 2 ? mat.leaf : mat.leafLight, g, [(j - 1.5) * .045, .13, random() * .07]);
    blade.rotation.z = (j - 1.5) * .23;
  } return g;
}
function flower(parent, x, z, color, height = .32) {
  const g = new THREE.Group(); parent.add(g); g.position.set(x, .03, z);
  bar(g, [0, 0, 0], [.035, height, 0], .012, mat.leaf);
  const leaf = ellipsoid(g, mat.leaf, [.065, height * .45, 0], [.095, .025, .04]); leaf.rotation.z = .5;
  for (let j = 0; j < 5; j++) { const a = j * Math.PI * 2 / 5; ellipsoid(g, color, [.035 + Math.cos(a) * .06, height + Math.sin(a) * .06, .015], [.046, .049, .024]); }
  ellipsoid(g, mat.yellow, [.035, height, .04], [.03, .03, .02]); return g;
}
const scenery = [];
for (let i = 0; i < 42; i++) {
  const x = random() * 8.6 - 4.3;
  const z = (random() > .5 ? 1 : -1) * (.9 + random() * 1.35);
  if (Math.pow(x / 4.7, 2) + Math.pow(z / 2.7, 2) > .87) continue;
  const g = tuft(island, x, z, .7 + random() * .65); scenery.push({ g, x });
  if (i % 3 === 0) flower(island, x + .1, z, i % 2 ? mat.lilac : mat.flower, .19 + random() * .2);
}
for (let i = 0; i < 10; i++) {
  const x = random() * 8 - 4, z = (i % 2 ? -1 : 1) * (.95 + random() * .35);
  ellipsoid(island, mat.stone, [x, .09, z], [.1 + random() * .07, .07, .08], true);
}
// A sculpted little tree and trail sign sit behind the rider.
const tree = new THREE.Group(); tree.position.set(-2.9, .02, -1.45); island.add(tree);
bar(tree, [0, 0, 0], [-.03, 1.55, 0], .075, mat.trunk);
bar(tree, [0, .7, 0], [-.4, 1.35, .03], .04, mat.trunk);
bar(tree, [0, 1.05, 0], [.33, 1.65, .04], .04, mat.trunk);
ellipsoid(tree, mat.leaf, [0, 1.8, 0], [.67, .87, .52], true);
ellipsoid(tree, mat.leafLight, [-.4, 1.5, .09], [.44, .52, .43], true);
ellipsoid(tree, mat.leafLight, [.34, 1.92, .01], [.42, .56, .39], true);
const sign = new THREE.Group(); sign.position.set(2.8, .02, -1.5); sign.rotation.y = -.15; island.add(sign);
bar(sign, [0, 0, 0], [0, .9, 0], .037, mat.trunk);
const signTexture = document.createElement('canvas'); signTexture.width = 512; signTexture.height = 160;
const sc = signTexture.getContext('2d'); sc.fillStyle = '#f3e5bf'; sc.fillRect(0, 0, 512, 160); sc.fillStyle = '#667d4f'; sc.font = 'bold 62px sans-serif'; sc.textAlign = 'center'; sc.fillText('慢 慢 骑  →', 256, 104);
const tex = new THREE.CanvasTexture(signTexture); tex.colorSpace = THREE.SRGBColorSpace;
const signBoard = box(sign, mat.cream, [.09, .8, 0], [.93, .3, .07]);
const signFace = mesh(new THREE.PlaneGeometry(.89, .28), new THREE.MeshStandardMaterial({ map: tex, roughness: .9 }), sign, [.09, .8, .036]);
const clouds = new THREE.Group(); scene.add(clouds);
const moon = ellipsoid(scene, new THREE.MeshStandardMaterial({ color: '#fff1c1', emissive: '#ffe2a0', emissiveIntensity: .65, roughness: 1 }), [-2.2, 4.2, -2.5], [.25, .25, .25]);
moon.visible = false; moon.castShadow = false;
const cloudMat = M('#fff8e7');
for (const [x, y, z, s] of [[-2.2, 4.2, -2.5, .6], [2.3, 4.5, -3.4, .48]]) {
  const c = new THREE.Group(); c.position.set(x, y, z); c.scale.setScalar(s); clouds.add(c);
  [[0, 0, 0, .63, .29, .3], [-.4, -.03, 0, .35, .26, .29], [.06, .16, 0, .31, .34, .3], [.45, -.04, 0, .3, .23, .26]].forEach(v => { const m = ellipsoid(c, cloudMat, v.slice(0, 3), v.slice(3)); m.castShadow = false; });
}

const cycle = new THREE.Group(); scene.add(cycle);
const wheelRadius = .6, wheelY = .65;
const wheelGroups = [];
for (const x of [-1.15, 1.18]) {
  const wheel = new THREE.Group(); wheel.position.set(x, wheelY, 0); cycle.add(wheel); wheelGroups.push(wheel);
  torus(wheel, wheelRadius, .055, mat.rubber);
  torus(wheel, .555, .024, mat.rim);
  torus(wheel, .515, .009, mat.steel);
  for (let i = 0; i < 24; i++) { const a = i / 24 * Math.PI * 2; bar(wheel, [0, 0, i % 2 ? .035 : -.035], [Math.sin(a) * .52, Math.cos(a) * .52, 0], .006, mat.steel); }
  bar(wheel, [0, 0, -.12], [0, 0, .12], .06, mat.steel);
  box(wheel, mat.yellow, [0, .4, .012], [.035, .09, .035]);
  const fender = mesh(new THREE.TorusGeometry(.69, .026, 8, 48, Math.PI * .9), mat.mintLight, cycle, [x, wheelY, 0]); fender.rotation.z = Math.PI * .05;
}
const rear = [-1.15, wheelY, 0], front = [1.18, wheelY, 0], crankCenter = [-.12, .78, 0], seatTube = [-.53, 1.56, 0], headset = [.83, 1.55, 0];
[[rear, seatTube], [rear, crankCenter], [seatTube, crankCenter], [crankCenter, headset], [seatTube, headset]].forEach(([a, b]) => bar(cycle, a, b, .045, mat.mint));
bar(cycle, [.78, 1.63, 0], [.92, 1.35, 0], .058, mat.mint);
for (const z of [-.1, .1]) { bar(cycle, [.85, 1.5, z], [front[0], front[1], z], .027, mat.mint); bar(cycle, [-.53, 1.5, z], [-1.15, wheelY, z], .023, mat.mint); }
bar(cycle, [-.53, 1.5, 0], [-.59, 1.78, 0], .027, mat.steel);
ellipsoid(cycle, mat.seat, [-.62, 1.8, 0], [.3, .065, .17]);
bar(cycle, [.82, 1.56, 0], [.74, 1.95, 0], .025, mat.steel);
curveTube(cycle, [[.74, 1.95, 0], [.85, 2.03, 0], [.85, 2.03, .33], [.69, 1.98, .4]], .025, mat.steel);
curveTube(cycle, [[.85, 2.03, 0], [.85, 2.03, -.33], [.69, 1.98, -.4]], .025, mat.steel);
for (const z of [-.4, .4]) { bar(cycle, [.69, 1.98, z], [.91, 1.98, z], .039, mat.seat); }
ellipsoid(cycle, mat.yellow, [.85, 2.1, .18], [.065, .045, .065]);
const lampMat = new THREE.MeshStandardMaterial({ color: '#fff0b7', emissive: '#ffda86', emissiveIntensity: .15 });
ellipsoid(cycle, mat.steel, [1.0, 1.62, 0], [.1, .09, .09]);
ellipsoid(cycle, lampMat, [1.065, 1.62, 0], [.045, .07, .07]);
const headlight = new THREE.PointLight('#ffe2a0', 0, 5); headlight.position.set(1.2, 1.65, 0); cycle.add(headlight);
curveTube(cycle, [[.83, 1.98, .13], [.95, 1.73, .15], [.94, 1.37, .12]], .008, mat.rubber);
// Chain, sprockets, crank arms and pedals are separate pieces.
torus(cycle, .18, .018, mat.steel, [-.12, .78, .14]);
torus(cycle, .09, .013, mat.steel, [-1.15, .65, .14]);
curveTube(cycle, [[-.1, .95, .145], [-1.16, .74, .145], [-1.23, .65, .145], [-1.14, .56, .145], [-.1, .61, .145], [.06, .78, .145], [-.1, .95, .145]], .012, mat.rubber);
const crank = new THREE.Group(); crank.position.set(-.12, .78, 0); cycle.add(crank);
bar(crank, [0, 0, -.17], [0, 0, .17], .036, mat.steel);
const pedalPivots = [];
for (const side of [-1, 1]) {
  const a = side === 1 ? 0 : Math.PI;
  const x = Math.cos(a) * .26, y = Math.sin(a) * .26;
  bar(crank, [0, 0, side * .18], [x, y, side * .18], .025, mat.steel);
  const p = new THREE.Group(); p.position.set(x, y, side * .29); crank.add(p);
  box(p, mat.rubber, [0, 0, 0], [.19, .045, .22]);
  box(p, mat.yellow, [0, -.003, side * .114], [.1, .025, .006]); pedalPivots.push(p);
}

// The partridge: rounded body, short tail, buff face, dark necklace and barred flanks.
const bird = new THREE.Group(); cycle.add(bird);
bird.position.set(-.33, 2.26, 0);
const body = ellipsoid(bird, mat.feather, [-.1, -.03, 0], [.62, .65, .46]); body.rotation.z = -.15;
ellipsoid(bird, mat.belly, [.19, -.07, 0], [.43, .55, .43]);
ellipsoid(bird, mat.cream, [.37, .05, 0], [.25, .35, .35]);
const tail = new THREE.Group(); tail.position.set(-.62, -.03, 0); bird.add(tail);
for (let i = 0; i < 5; i++) { const f = ellipsoid(tail, i % 2 ? mat.featherDark : mat.crown, [-.17 - Math.abs(i - 2) * .013, .09, (i - 2) * .085], [.3, .085, .075]); f.rotation.z = -.27; f.rotation.y = (i - 2) * .1; }
for (const side of [-1, 1]) {
  for (let j = 0; j < 6; j++) {
    const x = -.46 + j * .125;
    const z = side * (.32 + Math.sin(j / 6 * Math.PI) * .1);
    const stripe = curveTube(bird, [[x - .08, -.1, z * .98], [x - .02, -.26, z], [x + .06, -.39, z * .91]], .024, j % 2 ? mat.featherDark : mat.cream, 12);
  }
  const wing = new THREE.Group(); wing.position.set(-.12, .08, side * .405); wing.rotation.z = -.12; bird.add(wing);
  ellipsoid(wing, mat.featherDark, [-.08, -.03, 0], [.39, .29, .085]);
  for (let row = 0; row < 3; row++) for (let j = 0; j < 5 - row; j++) {
    const f = ellipsoid(wing, (j + row) % 3 === 0 ? mat.featherLight : mat.feather, [-.28 + j * .118 + row * .03, .12 - row * .12, side * (.055 + row * .008)], [.115, .09, .035]); f.rotation.z = -.3;
    ellipsoid(wing, mat.cream, [f.position.x + .035, f.position.y + .024, side * (.088 + row * .008)], [.023, .012, .007]);
  }
}
const head = new THREE.Group(); head.position.set(.23, .57, 0); bird.add(head);
ellipsoid(head, mat.crown, [0, .03, 0], [.41, .41, .35]);
ellipsoid(head, mat.cream, [.135, -.03, 0], [.34, .31, .34]);
// Curved cheek patches on both sides and a clear dark collar under the throat.
for (const side of [-1, 1]) {
  curveTube(head, [[-.15, .12, side * .3], [-.13, -.1, side * .323], [.015, -.25, side * .285], [.23, -.26, side * .16]], .035, mat.bib, 22);
  const eyeRoot = new THREE.Group(); eyeRoot.position.set(.18, .085, side * .293); eyeRoot.rotation.y = side * .15; head.add(eyeRoot);
  ellipsoid(eyeRoot, mat.eyeRing, [0, 0, 0], [.091, .096, .032]);
  ellipsoid(eyeRoot, mat.eye, [.005, .003, side * .023], [.062, .067, .026]);
  ellipsoid(eyeRoot, mat.white, [.018, .026, side * .047], [.018, .021, .01]);
  curveTube(head, [[-.02, .24, side * .277], [.11, .252, side * .29], [.29, .21, side * .258]], .027, mat.cream, 16);
}
const beak = mesh(new THREE.ConeGeometry(.105, .26, 20), mat.orange, head, [.485, -.025, 0]); beak.rotation.z = -Math.PI / 2; beak.scale.z = .74;
curveTube(head, [[.39, -.052, .063], [.49, -.055, .046], [.597, -.055, 0]], .006, mat.featherDark, 10);
for (let i = 0; i < 5; i++) { const f = ellipsoid(head, i % 2 ? mat.featherLight : mat.crown, [-.11 + i * .065, .365, 0], [.1, .075, .15]); f.rotation.z = -.2; }
const scarf = torus(bird, .225, .047, mat.scarf, [.22, .325, 0]); scarf.rotation.x = Math.PI / 2; scarf.scale.x = 1.15;
const ribbon = new THREE.Group(); ribbon.position.set(-.04, .34, -.15); bird.add(ribbon);
const ribbonA = ellipsoid(ribbon, mat.scarf, [-.22, .03, 0], [.27, .066, .036]);
const ribbonB = ellipsoid(ribbon, mat.scarf, [-.18, -.06, -.03], [.2, .055, .03]); ribbonB.rotation.z = .3;

// Reaching wing tips remain at the handlebar as the torso gently moves.
const wingTips = [], legs = [];
for (const side of [-1, 1]) {
  const upper = bar(cycle, [0, 2.3, side * .38], [.52, 2.03, side * .4], .11, mat.feather);
  const lower = bar(cycle, [.52, 2.03, side * .4], [.77, 2.01, side * .4], .074, mat.featherDark);
  upper.geometry = sphereGeo;
  lower.geometry = sphereGeo;
  lower.scale.y *= .65;
  for (let j = 0; j < 4; j++) {
    const feather = ellipsoid(upper, j % 2 ? mat.featherLight : mat.feather, [side * .08, -.6 + j * .36, side * .65], [.8, .33, .34]);
    feather.rotation.z = -.2;
  }
  ellipsoid(cycle, mat.feather, [.76, 2.02, side * .4], [.13, .065, .09]);
  wingTips.push({ side, upper, lower });
  const thigh = bar(cycle, [-.4, 1.9, side * .26], [.1, 1.4, side * .28], .082, mat.featherLight);
  const shin = bar(cycle, [.1, 1.4, side * .28], [.14, .8, side * .29], .032, mat.orange);
  const knee = ellipsoid(cycle, mat.orange, [0, 1, side * .29], [.046, .046, .046]);
  const foot = new THREE.Group(); cycle.add(foot);
  for (let j = 0; j < 3; j++) curveTube(foot, [[-.05, .025, 0], [.04, .012, (j - 1) * .045], [.11, -.005, (j - 1) * .056]], .014, mat.orange, 8);
  legs.push({ side, thigh, shin, knee, foot });
}

// Fireflies are visible only in the moonlight setting.
const fireflyGeo = new THREE.BufferGeometry();
const fireflyPositions = new Float32Array(32 * 3);
for (let i = 0; i < 32; i++) { fireflyPositions[i * 3] = random() * 8 - 4; fireflyPositions[i * 3 + 1] = .3 + random() * 2.4; fireflyPositions[i * 3 + 2] = random() * 4 - 2; }
fireflyGeo.setAttribute('position', new THREE.BufferAttribute(fireflyPositions, 3));
const fireflies = new THREE.Points(fireflyGeo, new THREE.PointsMaterial({ color: '#f5dc8a', size: .045, transparent: true, opacity: .85, blending: THREE.AdditiveBlending, depthWrite: false })); fireflies.visible = false; scene.add(fireflies);

const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const state = { playing: !reducedMotion, speed: 12, distance: 0, angle: 0, time: 0, light: 'day', view: 'free', frames: 0 };
let viewTransition = null, toastTimer;
const defaultTarget = () => vec(0, innerWidth <= 760 ? 1.4 : 1.65, 0);
const defaultPosition = () => innerWidth <= 760 ? vec(9, 5.7, 12) : vec(7.3, 5.2, 10.5);
function setView(name, immediate = false) {
  state.view = name;
  orbit.autoRotate = false; $('#orbit').checked = false;
  const target = defaultTarget();
  const p = name === 'side' ? vec(0, 3.0, 11.8) : name === 'front' ? vec(11.8, 3.35, .25) : defaultPosition();
  if (immediate) { camera.position.copy(p); orbit.target.copy(target); orbit.update(); }
  else viewTransition = { position: p, target };
  document.querySelectorAll('[data-view]').forEach(b => { b.classList.toggle('active', b.dataset.view === name); b.setAttribute('aria-pressed', String(b.dataset.view === name)); });
}
function updateUI() {
  const moving = state.playing && state.speed > 0;
  $('#speed-value').textContent = state.playing ? state.speed : '0';
  $('#status').innerHTML = `<i style="background:${moving ? '#6d9463' : '#b0a883'}"></i>${moving ? '自在骑行中' : '停下来看看风景'}`;
  $('#speed-mode').textContent = state.speed === 0 ? '歇一小会' : state.speed <= 8 ? '慢慢散步' : state.speed <= 18 ? '悠闲兜风' : '追一阵风';
  $('#speed').style.background = `linear-gradient(to right,#507a5e ${state.speed / 30 * 100}%,#e7ebdf ${state.speed / 30 * 100}%)`;
  $('#play').setAttribute('aria-pressed', String(state.playing));
  $('#play span').textContent = state.playing ? '暂停一下' : '继续出发';
  $('#play-icon').innerHTML = state.playing ? '<path d="M7 4v12M13 4v12"/>' : '<path d="M6 3l10 7-10 7z" fill="currentColor" stroke="none"/>';
}
function toast(message) { $('#toast').textContent = message; $('#toast').classList.add('show'); clearTimeout(toastTimer); toastTimer = setTimeout(() => $('#toast').classList.remove('show'), 2400); }
const lighting = {
  day: { hemi: '#fff4d9', ground: '#81986b', intensity: 2.7, sun: '#fff0d4', power: 3.3, exposure: 1.2, position: [-3, 8, 5] },
  sunset: { hemi: '#ffe2b7', ground: '#9b7568', intensity: 1.9, sun: '#ffa562', power: 4.1, exposure: 1.08, position: [-6, 3, 3] },
  night: { hemi: '#a8c7ef', ground: '#74846f', intensity: 1.9, sun: '#b4d1ff', power: 2.2, exposure: 1.02, position: [-3, 6, 5] },
};
function setLight(name) {
  state.light = name; document.body.dataset.light = name;
  const l = lighting[name]; hemi.color.set(l.hemi); hemi.groundColor.set(l.ground); hemi.intensity = l.intensity;
  sun.color.set(l.sun); sun.intensity = l.power; sun.position.set(...l.position); renderer.toneMappingExposure = l.exposure;
  fill.intensity = name === 'night' ? .9 : 1.2;
  lampMat.emissiveIntensity = name === 'night' ? 3 : .15; headlight.intensity = name === 'night' ? 3 : 0;
  fireflies.visible = name === 'night'; moon.visible = name === 'night'; clouds.visible = name !== 'night';
  document.querySelectorAll('[data-light]').forEach(b => { b.classList.toggle('active', b.dataset.light === name); b.setAttribute('aria-pressed', String(b.dataset.light === name)); });
}
$('#play').addEventListener('click', () => { state.playing = !state.playing; updateUI(); });
$('#speed').addEventListener('input', e => { state.speed = Number(e.target.value); updateUI(); });
document.querySelectorAll('[data-view]').forEach(b => b.addEventListener('click', () => setView(b.dataset.view)));
document.querySelectorAll('[data-light]').forEach(b => b.addEventListener('click', () => setLight(b.dataset.light)));
$('#orbit').addEventListener('change', e => { viewTransition = null; orbit.autoRotate = e.target.checked; });
orbit.addEventListener('start', () => { viewTransition = null; state.view = 'free'; document.querySelectorAll('[data-view]').forEach(b => { b.classList.toggle('active', b.dataset.view === 'free'); b.setAttribute('aria-pressed', String(b.dataset.view === 'free')); }); });
$('#reset-view').addEventListener('click', () => setView('free'));
$('#reset').addEventListener('click', () => { state.playing = !reducedMotion; state.speed = 12; state.angle = 0; state.time = 0; state.distance = 0; $('#speed').value = 12; $('#distance').textContent = 0; setLight('day'); setView('free'); updateUI(); toast('又是一次新的小小出游'); });
$('#fullscreen').addEventListener('click', async () => { try { if (document.fullscreenElement) await document.exitFullscreen(); else if (stage.requestFullscreen) { await stage.requestFullscreen(); canvas.focus(); } else toast('此浏览器暂不支持全屏，可旋转手机横屏观看'); } catch { toast('此浏览器暂不支持全屏'); } });
$('#capture').addEventListener('click', () => {
  renderer.render(scene, camera);
  const photo = document.createElement('canvas'); photo.width = canvas.width; photo.height = canvas.height;
  const ctx = photo.getContext('2d'); ctx.fillStyle = getComputedStyle(document.body).backgroundColor; ctx.fillRect(0, 0, photo.width, photo.height); ctx.drawImage(canvas, 0, 0);
  ctx.fillStyle = state.light === 'night' ? '#d1dfcb' : '#4c6753'; ctx.font = `${Math.max(18, photo.width / 50)}px sans-serif`; ctx.fillText('鹧鸪出游 · A LITTLE RIDE', photo.width * .05, photo.height * .93);
  photo.toBlob(blob => { if (!blob) { toast('图片保存失败，请重试'); return; } const url = URL.createObjectURL(blob); const a = document.createElement('a'); a.href = url; a.download = '鹧鸪出游.png'; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); toast('已保存这一刻的风景'); }, 'image/png');
});
document.addEventListener('keydown', e => {
  if (['INPUT', 'BUTTON', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName) || e.ctrlKey || e.altKey || e.metaKey) return;
  if (e.code === 'Space') { e.preventDefault(); $('#play').click(); }
  if (e.code === 'KeyR') $('#reset').click();
  if (e.code === 'ArrowUp' || e.code === 'ArrowDown') { e.preventDefault(); state.speed = THREE.MathUtils.clamp(state.speed + (e.code === 'ArrowUp' ? 1 : -1), 0, 30); $('#speed').value = state.speed; updateUI(); }
});
let previousWidth = innerWidth;
function resize() { const w = stage.clientWidth, h = stage.clientHeight; renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); if ((previousWidth <= 760) !== (innerWidth <= 760)) setView('free', true); previousWidth = innerWidth; }
new ResizeObserver(resize).observe(stage);
setView('free', true); resize(); updateUI();

function pose() {
  crank.rotation.z = -state.angle;
  wheelGroups.forEach(w => w.rotation.z = -state.angle * 1.8);
  pedalPivots.forEach(p => p.rotation.z = state.angle);
  const bob = Math.sin(state.angle * 2) * .018;
  bird.position.y = 2.26 + bob;
  bird.rotation.x = Math.sin(state.angle) * .015;
  head.rotation.z = Math.sin(state.angle * 2 - .4) * .023;
  ribbon.rotation.z = Math.sin(state.time * 7) * .13 * Math.min(state.speed / 12, 1.5);
  for (const limb of wingTips) { setBar(limb.upper, [-.17, 2.32 + bob, limb.side * .4], [.49, 2.055, limb.side * .41], .12); limb.upper.scale.y *= .6; }
  for (const leg of legs) {
    const phase = -state.angle + (leg.side === 1 ? 0 : Math.PI);
    const foot = vec(-.12 + Math.cos(phase) * .26, .78 + Math.sin(phase) * .26 + .035, leg.side * .29);
    const hip = vec(-.39, 1.88 + bob, leg.side * .28);
    const delta = foot.clone().sub(hip), dist = delta.length();
    const l1 = .72, l2 = .69;
    const along = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist);
    const off = Math.sqrt(Math.max(0, l1 * l1 - along * along));
    const dir = delta.normalize(); const perpendicular = vec(-dir.y, dir.x, 0).normalize();
    const knee = hip.clone().addScaledVector(dir, along).addScaledVector(perpendicular, off);
    setBar(leg.thigh, hip, knee, .063); setBar(leg.shin, knee, foot, .029);
    leg.knee.position.copy(knee); leg.foot.position.copy(foot);
  }
  for (let i = 0; i < dashes.length; i++) dashes[i].position.x = THREE.MathUtils.euclideanModulo(i * .8 - state.angle * .6 * 1.8 + 4.8, 9.6) - 4.8;
}
let previous = performance.now(), lastReadout = 0;
function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min((now - previous) / 1000, .05); previous = now;
  if (document.hidden) return;
  if (state.playing && state.speed > 0) {
    const meters = state.speed / 3.6 * dt;
    state.distance += meters;
    state.angle += meters / (wheelRadius * 1.8);
    state.time += dt;
  }
  pose();
  if (viewTransition) { camera.position.lerp(viewTransition.position, 1 - Math.exp(-dt * 5)); orbit.target.lerp(viewTransition.target, 1 - Math.exp(-dt * 5)); if (camera.position.distanceTo(viewTransition.position) < .01) viewTransition = null; }
  if (fireflies.visible && state.playing) fireflies.rotation.y = Math.sin(state.time * .3) * .08;
  orbit.update(dt);
  renderer.render(scene, camera);
  state.frames++;
  if (now - lastReadout > 150) { $('#distance').textContent = Math.floor(state.distance).toLocaleString('zh-CN'); lastReadout = now; }
}
pose(); renderer.render(scene, camera); requestAnimationFrame(frame);
$('#loading').classList.add('hidden'); window.__rideReady = true;
// Read-only diagnostics for checking animation and pedal contact in the browser.
window.__ride = { snapshot: () => ({ ...state, camera: camera.position.toArray(), autoRotate: orbit.autoRotate, drawCalls: renderer.info.render.calls, triangles: renderer.info.render.triangles, pedalContactError: Math.max(...legs.map((leg, i) => { const p = pedalPivots[i].getWorldPosition(new THREE.Vector3()); const f = leg.foot.getWorldPosition(new THREE.Vector3()); return Math.hypot(p.x - f.x, p.y + .035 - f.y, p.z - f.z); })) }) };
canvas.addEventListener('webglcontextlost', e => { e.preventDefault(); state.playing = false; updateUI(); $('#loading').classList.remove('hidden'); $('#loading').textContent = '3D 场景暂时中断，请刷新页面恢复。'; });
