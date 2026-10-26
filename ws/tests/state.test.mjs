import test from 'node:test';
import assert from 'node:assert/strict';
import {protectedIntent, mergeCart, normalizeCatalogItem, safeImageUrl} from '../assets/state.js';
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
test('image URLs allow only HTTPS, not script or data schemes', () => {
  assert.equal(safeImageUrl('javascript:alert(1)'),'');
  assert.equal(safeImageUrl('https://example.com/cat.png'),'https://example.com/cat.png');
});
