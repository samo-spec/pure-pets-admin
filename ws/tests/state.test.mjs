import test from 'node:test';
import assert from 'node:assert/strict';
import {protectedIntent, mergeCart, normalizeCatalogItem, safeImageUrl, normalizePhoneNumber} from '../assets/state.js';
test('guest action stores product, group and quantity without losing context', () => {
  assert.deepEqual(protectedIntent('add',{productId:'food_1',groupId:'carton',quantity:2}),
    {action:'add',productId:'food_1',groupId:'carton',quantity:2});
});
test('unknown actions and unsafe quantities are rejected', () => {
  assert.throws(() => protectedIntent('admin'));
  assert.throws(() => protectedIntent('add',{productId:'x',groupId:'pack',quantity:0}));
  assert.throws(() => protectedIntent('add',{productId:'x',groupId:'pack',quantity:1.5}));
});
test('cart merges only same product and selling group', () => {
  const result = mergeCart([{productId:'p1',groupId:'single',quantity:3}],
    {productId:'p1',groupId:'carton',quantity:2});
  assert.equal(result.length,2);
  assert.equal(mergeCart(result,{productId:'p1',groupId:'single',quantity:2})[0].quantity,5);
});
test('catalog hides non-wholesale items', () => {
  assert.equal(normalizeCatalogItem({id:'p',groups:[{id:'g',active:true,wholesaleEnabled:false,unitsPerGroup:6,priceMinor:1200}]}),null);
});
test('catalog permits valid active quantity groups only', () => {
  const item=normalizeCatalogItem({id:'p',groups:[{id:'g',active:true,wholesaleEnabled:true,unitsPerGroup:6,priceMinor:1200},{id:'z',active:false,wholesaleEnabled:true,unitsPerGroup:1,priceMinor:100}]});
  assert.deepEqual(item.groups.map(x=>x.id),['g']);
});
test('catalog strictly rejects selling by single pieces (unitsPerGroup === 1 or single)', () => {
  assert.equal(normalizeCatalogItem({id:'p',groups:[{id:'single',nameAr:'حبة',active:true,wholesaleEnabled:true,unitsPerGroup:1,priceMinor:200}]}), null);
});
test('image URLs allow only HTTPS, not script or data schemes', () => {
  assert.equal(safeImageUrl('javascript:alert(1)'),'');
  assert.equal(safeImageUrl('https://example.com/cat.png'),'https://example.com/cat.png');
});

test('saved workspace is an authenticated continuation intent',()=>{
  assert.deepEqual(protectedIntent('saved'),{action:'saved'});
  assert.throws(()=>protectedIntent('admin'));
});

test('normalizePhoneNumber formats Qatar and international numbers', () => {
  assert.equal(normalizePhoneNumber('55551234'), '+97455551234');
  assert.equal(normalizePhoneNumber('+974 5555 1234'), '+97455551234');
  assert.equal(normalizePhoneNumber('00974 5555 1234'), '+97455551234');
  assert.equal(normalizePhoneNumber('+966 50 123 4567'), '+966501234567');
  assert.equal(normalizePhoneNumber('+201022363409'), '+201022363409');
  assert.equal(normalizePhoneNumber('01022363409'), '+201022363409');
  assert.equal(normalizePhoneNumber('+٢٠١٠٢٢٣٦٣٤٠٩'), '+201022363409');
  assert.equal(normalizePhoneNumber('٠١٠٢٢٣٦٣٤٠٩'), '+201022363409');
  assert.equal(normalizePhoneNumber('0512345678'), '+966512345678');
  assert.throws(() => normalizePhoneNumber('123'));
  assert.throws(() => normalizePhoneNumber('not-a-number'));
  assert.throws(() => normalizePhoneNumber(''));
});
