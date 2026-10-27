import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../worker/index.js';
const request=(path,options)=>new Request('https://example.com'+path,options);
test('wholesale root redirects inside its own prefix',async()=>{
 const response=await worker.fetch(request('/ws'),{});
 assert.equal(response.status,308);assert.equal(response.headers.get('location'),'https://example.com/ws/');
});
test('worker cannot serve unrelated site routes',async()=>{
 assert.equal((await worker.fetch(request('/admin'),{})).status,404);
});
test('missing configuration fails closed and is not cacheable',async()=>{
 const response=await worker.fetch(request('/ws/api/config'),{});
 assert.equal(response.status,503);assert.equal(response.headers.get('cache-control'),'no-store');
});
test('runtime configuration rejects writes',async()=>{
 assert.equal((await worker.fetch(request('/ws/api/config',{method:'POST'}),{})).status,405);
});
test('asset proxy maps the prefix and applies security headers',async()=>{
 let path;
 const response=await worker.fetch(request('/ws/assets/style.css'),{ASSETS:{fetch:async r=>{path=new URL(r.url).pathname;return new Response('body{}',{headers:{'content-type':'text/css'}});}}});
 assert.equal(path,'/assets/style.css');assert.equal(response.headers.get('x-frame-options'),'DENY');assert.equal(response.headers.get('x-content-type-options'),'nosniff');assert.equal(await response.text(),'body{}');
});
test('staff workspace aliases resolve to the staff page',async()=>{
 const response=await worker.fetch(request('/ws/manage/'),{});
 assert.equal(response.status,308);assert.equal(response.headers.get('location'),'https://example.com/ws/manage.html');
});
