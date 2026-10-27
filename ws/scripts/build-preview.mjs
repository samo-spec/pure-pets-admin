// Reproducible Workers.dev snapshot. Canonical production uses Wrangler assets.
import {readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');
const files={};
for(const page of ['index.html','manage.html'])files['/'+page]={type:'text/html; charset=utf-8',body:readFileSync(resolve(root,'dist',page),'utf8')};
for(const file of readdirSync(resolve(root,'dist/assets'))){
 const type=file.endsWith('.png')?'image/png':file.endsWith('.css')?'text/css; charset=utf-8':'text/javascript; charset=utf-8';
 const binary=file.endsWith('.png');
 files['/assets/'+file]={type,body:readFileSync(resolve(root,'dist/assets',file),binary?'base64':'utf8'),binary};
}
const canonical=readFileSync(resolve(root,'worker/index.js'),'utf8');
const shim=`const snapshot=${JSON.stringify(files)};\nconst assets={async fetch(request){const path=new URL(request.url).pathname;const entry=snapshot[path==='/'?'/index.html':path];if(!entry)return new Response('Not found',{status:404});const body=entry.binary?Uint8Array.from(atob(entry.body),c=>c.charCodeAt(0)):entry.body;return new Response(body,{headers:{'content-type':entry.type,'cache-control':'no-store'}});}};\n`;
writeFileSync(resolve(root,'dist/preview-worker.mjs'),shim+canonical.replace('async fetch(request, env) {','async fetch(request, env) {\n    env={...env,ASSETS:assets};'));
console.log('Preview snapshot built from canonical worker and dist assets');
