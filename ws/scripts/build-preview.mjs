// Reproducible Workers.dev snapshot. Canonical production uses Wrangler assets.
import {readFileSync, readdirSync, statSync, writeFileSync} from 'node:fs';
import {resolve, relative} from 'node:path';

const root = resolve(import.meta.dirname, '..');
const dist = resolve(root, 'dist');
const files = {};

for (const page of ['index.html', 'manage.html', 'mng.html']) {
  files['/' + page] = {
    type: 'text/html; charset=utf-8',
    body: readFileSync(resolve(dist, page), 'utf8')
  };
}

function collectAssets(dir) {
  for (const item of readdirSync(dir)) {
    const full = resolve(dir, item);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      collectAssets(full);
    } else {
      const rel = '/' + relative(dist, full).replace(/\\/g, '/');
      const isPng = item.endsWith('.png');
      const isTtf = item.endsWith('.ttf');
      const isWoff2 = item.endsWith('.woff2');
      const isCss = item.endsWith('.css');
      const isHtml = item.endsWith('.html');
      const binary = isPng || isTtf || isWoff2;
      let type = 'text/javascript; charset=utf-8';
      if (isPng) type = 'image/png';
      else if (isTtf) type = 'font/ttf';
      else if (isWoff2) type = 'font/woff2';
      else if (isCss) type = 'text/css; charset=utf-8';
      else if (isHtml) type = 'text/html; charset=utf-8';

      files[rel] = {
        type,
        body: readFileSync(full, binary ? 'base64' : 'utf8'),
        binary
      };
    }
  }
}

collectAssets(resolve(dist, 'assets'));

const canonical = readFileSync(resolve(root, 'worker/index.js'), 'utf8');
const shim = `const snapshot=${JSON.stringify(files)};\nconst assets={async fetch(request){const path=new URL(request.url).pathname;const entry=snapshot[path==='/'?'/index.html':path];if(!entry)return new Response('Not found',{status:404});const body=entry.binary?Uint8Array.from(atob(entry.body),c=>c.charCodeAt(0)):entry.body;return new Response(body,{headers:{'content-type':entry.type,'cache-control':'no-store'}});}};\n`;
writeFileSync(resolve(dist, 'preview-worker.mjs'), shim + canonical.replace('async fetch(request, env) {', 'async fetch(request, env) {\n    env={...env,ASSETS:assets};'));
console.log('Preview snapshot built from canonical worker and dist assets');

