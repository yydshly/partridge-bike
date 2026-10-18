import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(fileURLToPath(import.meta.url));
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

const engines = ['src/engine.js', 'src/scene.js', 'src/app.js'].map(read).join('\n\n');
if (/<\/script/i.test(engines)) {
  throw new Error('Inline script contains a closing script tag');
}

let html = read('src/index.template.html');
html = html.replace('/*__STYLE__*/', () => read('src/style.css'));
html = html.replace('/*__SCRIPT__*/', () => engines);

const out = path.join(root, 'partridge-bike-3d.html');
fs.writeFileSync(out, html, 'utf8');
console.log(`built ${out} (${(html.length / 1024).toFixed(1)} kB)`);
