/** Presentational helpers only. Callable contracts remain in the page controllers. */
export const icon = (name, extra='') => `<svg class="icon ${extra}" aria-hidden="true"><use href="/ws/assets/icons.svg#${name}"></use></svg>`;
export function readPreference(key, fallback) {
  try { return localStorage.getItem('pp-ws-'+key) || fallback; } catch { return fallback; }
}
export function writePreference(key, value) {
  try { localStorage.setItem('pp-ws-'+key, value); } catch { /* Storage may be disabled. */ }
}
export const defaultGroup = product => product.groups.find(g => g.defaultForWholesale) || product.groups[0];
export function cartSummary(cart, products) {
  const totals = new Map(); let incomplete=false;
  for (const line of cart) {
    const product=products.find(p=>p.id===line.productId);
    const group=product?.groups.find(g=>g.id===line.groupId);
    if (!group) { incomplete=true; continue; }
    totals.set(product.currency,(totals.get(product.currency)||0)+group.priceMinor*line.quantity);
  }
  return {totals:[...totals].map(([currency,minor])=>({currency,minor})),incomplete,packs:cart.reduce((sum,line)=>sum+line.quantity,0)};
}
export function quantityQuote(product, groupId, quantity) {
  const group=product.groups.find(g=>g.id===groupId);
  if(!group || !Number.isSafeInteger(quantity) || quantity<1 || quantity>10000) return null;
  return {units:quantity*group.unitsPerGroup,minor:quantity*group.priceMinor,currency:product.currency};
}
