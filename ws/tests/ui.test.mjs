import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
import * as ui from '../assets/ui.js';
import * as pure from '../assets/state.js';
const product={id:'sample_food',nameAr:'طعام القطط',nameEn:'Cat food',category:'cats',image:'',currency:'QAR',available:100,groups:[
 {id:'single',nameAr:'قطعة',nameEn:'Single',active:true,wholesaleEnabled:true,unitsPerGroup:1,priceMinor:205},
 {id:'case',nameAr:'كرتون',nameEn:'Case',active:true,wholesaleEnabled:true,unitsPerGroup:12,priceMinor:2250,defaultForWholesale:true}]};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function page(t,manager=false){
 const html=readFileSync(new URL(manager?'../manage.html':'../index.html',import.meta.url),'utf8');
 const dom=new JSDOM(html,{url:'https://test.invalid/ws/',runScripts:'outside-only',pretendToBeVisual:true});t.after(()=>dom.window.close());
 const w=dom.window;w.HTMLDialogElement.prototype.showModal=function(){this.setAttribute('open','')};w.HTMLDialogElement.prototype.close=function(){this.removeAttribute('open')};
 w.HTMLElement.prototype.scrollIntoView=function(){};w.HTMLElement.prototype.getClientRects=function(){return [{}]};w.confirm=()=>true;Object.assign(w,{...ui,...pure});
 let src=readFileSync(new URL(manager?'../assets/manage.js':'../assets/app.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'');
 src=manager?src.replace(/locale\(\);connect\(\)\.catch\(.*\);/,'locale();'):src.replace('\nloadCatalog(true);','');
 src+='\nwindow.testAPI={state,'+(manager?'lang,locale,paintRequests,reload,loadBranches':'renderCatalog,renderDrawer,openDrawer,closeDrawer,productDetails,applyLanguage,visibleProducts,persistBuyer,runIntent,submitOrder,loadCatalog')+'};';w.eval(src);
 return {w,d:w.document,api:w.testAPI};
}
function seed(api){Object.assign(api.state,{products:[structuredClone(product)],loadError:false,loading:false,branches:[{id:'branch-a',nameAr:'الفرع',nameEn:'Branch',active:true}]});api.renderCatalog();}
test('pack calculation keeps integer minor units and rejects invalid quantities',()=>{
 assert.deepEqual(ui.quantityQuote(product,'case',3),{units:36,minor:6750,currency:'QAR'});for(const value of [0,-1,1.5,10001,NaN])assert.equal(ui.quantityQuote(product,'case',value),null);
});
test('cart never combines currencies and marks unavailable pricing incomplete',()=>{
 const usd={...product,id:'usd',currency:'USD'};
 const result=ui.cartSummary([{productId:product.id,groupId:'case',quantity:2},{productId:'usd',groupId:'single',quantity:1},{productId:'missing',groupId:'case',quantity:1}],[product,usd]);
 assert.deepEqual(result,{totals:[{currency:'QAR',minor:4500},{currency:'USD',minor:205}],incomplete:true,packs:4});
});
test('guest pack intent survives sign-in with selected pack and quantity',t=>{
 const {api,d,w}=page(t);seed(api);api.productDetails(product.id);assert.equal(d.querySelector('#detailGroup').value,'case');
 d.querySelector('#detailQuantity').value='3';d.querySelector('#detailQuantity').dispatchEvent(new w.Event('input'));assert.match(d.querySelector('#detailQuote').textContent,/36/);
 d.querySelector('#detailAdd').click();assert.ok(d.querySelector('#authDialog').open);assert.equal(api.state.pending.groupId,'case');assert.equal(api.state.pending.quantity,3);assert.equal(api.state.user,null);
});
test('sold-out details cannot add; invalid quantity has accessible feedback',t=>{
 const {api,d,w}=page(t);seed(api);api.state.products[0].available=0;api.productDetails(product.id);assert.equal(d.querySelector('#detailAdd').disabled,true);
 d.querySelector('#detailQuantity').value='1.5';d.querySelector('#detailQuantity').dispatchEvent(new w.Event('input'));assert.equal(d.querySelector('#detailQuantity').getAttribute('aria-invalid'),'true');assert.equal(d.querySelector('#detailAdd').disabled,true);
});
test('bilingual search, reset, compact view and language change work',t=>{
 const {api,d}=page(t);seed(api);api.state.query='Cat food';api.renderCatalog();assert.equal(d.querySelectorAll('.product-card').length,1);
 api.state.query='no match';api.renderCatalog();d.querySelector('.empty-state button').click();assert.equal(api.state.query,'');
 d.querySelector('#listView').click();assert.ok(d.querySelector('#productGrid').classList.contains('list-view'));d.querySelector('#languageBtn').click();assert.equal(d.documentElement.dir,'ltr');assert.equal(d.querySelector('#searchInput').getAttribute('aria-label'),'Search products...');
});
test('sorting follows displayed default pack instead of first group',t=>{
 const {api}=page(t);seed(api);api.state.products.push({...product,id:'lower',groups:[{...product.groups[0],priceMinor:1000}]});api.state.sort='priceAsc';assert.equal(api.visibleProducts()[0].id,'lower');
});
test('drawer traps focus, restores trigger and hides background',async t=>{
 const {api,d,w}=page(t);seed(api);api.state.user={uid:'test'};d.querySelector('#cartBtn').focus();await api.openDrawer('cart');assert.equal(d.querySelector('main').inert,true);assert.equal(d.querySelector('#orderDock').inert,true);
 const last=d.querySelector('#buyerSignOut');last.focus();last.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Tab',bubbles:true,cancelable:true}));assert.equal(d.activeElement.id,'closeDrawer');
 d.querySelector('#closeDrawer').dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true,cancelable:true}));assert.equal(d.querySelector('#buyerDrawer').hidden,true);assert.equal(d.querySelector('main').inert,false);assert.equal(d.activeElement.id,'cartBtn');
});
test('buyer mutation prevents concurrent writes and recovers from save failure',async t=>{
 const {api}=page(t);seed(api);api.state.user={uid:'test'};let reject;api.state.backend={invoke:()=>new Promise((_,r)=>reject=r)};
 const first=api.persistBuyer([{productId:product.id,groupId:'case',quantity:1}],[]);assert.equal(api.state.buyerBusy,true);await assert.rejects(api.persistBuyer([],[]));reject(new Error('offline'));await assert.rejects(first);assert.equal(api.state.buyerBusy,false);assert.equal(api.state.cart.length,0);
});
test('acknowledged request stays successful if cart cleanup fails',async t=>{
 const {api,d}=page(t);seed(api);api.state.user={uid:'test'};api.state.cart=[{productId:product.id,groupId:'case',quantity:2}];let creates=0;
 api.state.backend={invoke:async(name,payload)=>{if(name==='createWholesaleOrderRequest'){creates++;assert.equal(payload.branchId,'branch-a');return {ok:true,requestId:'request-fixture'};}if(name==='saveWholesaleBuyerState')throw new Error('offline cleanup');return {items:[]};}};
 await api.openDrawer('cart');d.querySelector('#branchSelect').value='branch-a';await api.submitOrder();assert.equal(creates,1);assert.equal(api.state.cart.length,0);assert.equal(api.state.drawer,'orders');assert.equal(api.state.orderCommandId,null);assert.equal(api.state.submitting,false);
});
test('pagination failure retains catalog and offers retry',async t=>{
 const {api,d}=page(t);seed(api);api.state.cursor='page2';api.state.backend={invoke:async()=>{throw new Error('offline')}};await api.loadCatalog();assert.equal(d.querySelectorAll('.product-card').length,1);assert.ok(d.querySelector('#catalogStatus button'));assert.equal(api.state.cursor,'page2');
});
test('staff language includes credentials and translated statuses',t=>{
 const {api,d}=page(t,true);api.lang.current='en';api.state.requests=[{id:'sample-request',status:'pending_review',items:[],totalMinor:2250,currency:'QAR'}];api.locale();assert.equal(d.querySelector('#emailLabel').textContent,'Email address');assert.equal(d.querySelector('.status-tag').textContent,'Pending review');assert.equal(d.documentElement.dir,'ltr');
});
test('stale staff responses cannot replace selected branch queue',async t=>{
 const {api,d}=page(t,true);const pending=[];api.state.user={uid:'test'};api.state.branch='branch-a';api.state.api={call:()=>new Promise(resolve=>pending.push(resolve))};
 const first=api.reload();api.state.branch='branch-b';const second=api.reload();pending[1]({items:[{id:'b',status:'pending_review',items:[]}]});await second;pending[0]({items:[{id:'a',status:'pending_review',items:[]}]});await first;assert.equal(api.state.requests[0].id,'b');assert.equal(d.querySelector('#refreshManager').disabled,false);
});
test('staff rejection is explicit and retains error recovery in dialog',async t=>{
 const {api,d}=page(t,true);api.lang.current='en';api.state.user={uid:'staff'};api.state.requests=[{id:'sample',branchId:'branch-a',status:'pending_review',items:[],totalMinor:100}];api.locale();
 api.state.api={call:async(name,data)=>{assert.equal(name,'reviewWholesaleStaffRequest');assert.equal(data.decision,'reject');throw new Error('permission-denied')}};
 d.querySelector('[data-decision=reject]').click();assert.equal(d.querySelector('#confirmReview').textContent,'Confirm rejection');d.querySelector('#confirmReview').click();await tick();assert.ok(d.querySelector('#reviewDialog').open);assert.equal(d.querySelector('#reviewError').hidden,false);assert.equal(d.querySelector('#confirmReview').disabled,false);
});
