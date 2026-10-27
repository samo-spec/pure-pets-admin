/** Pure, audited intent and cart validation shared with the UI. */
const permittedActions = new Set(['add', 'save', 'cart', 'checkout', 'orders', 'saved']);
export function protectedIntent(action, payload = {}) {
  if (!permittedActions.has(action)) throw new Error('Unsupported protected action');
  const result = {action};
  if (action === 'add' || action === 'save') {
    if (typeof payload.productId !== 'string' || !/^[a-zA-Z0-9_-]{1,160}$/.test(payload.productId)) throw new Error('Invalid product');
    result.productId = payload.productId;
    if (action === 'add') {
      if (typeof payload.groupId !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(payload.groupId)) throw new Error('Invalid unit');
      if (!Number.isSafeInteger(payload.quantity) || payload.quantity < 1 || payload.quantity > 10000) throw new Error('Invalid quantity');
      result.groupId = payload.groupId;
      result.quantity = payload.quantity;
    }
  }
  return result;
}
export function validBuyerLine(line) {
  return Boolean(line && typeof line.productId === 'string' && /^[a-zA-Z0-9_-]{1,160}$/.test(line.productId)
    && typeof line.groupId === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(line.groupId)
    && Number.isSafeInteger(line.quantity) && line.quantity >= 1 && line.quantity <= 10000);
}
export function mergeCart(cart, incoming) {
  if (!validBuyerLine(incoming)) throw new Error('Invalid cart line');
  const clean = Array.isArray(cart) ? cart.filter(validBuyerLine).map(x => ({productId:x.productId, groupId:x.groupId, quantity:x.quantity})) : [];
  const found = clean.find(x => x.productId === incoming.productId && x.groupId === incoming.groupId);
  if (found) {
    const next = found.quantity + incoming.quantity;
    if (!Number.isSafeInteger(next) || next > 10000) throw new Error('Quantity limit exceeded');
    found.quantity = next;
  } else {
    if (clean.length >= 60) throw new Error('Cart item limit exceeded');
    clean.push({productId:incoming.productId, groupId:incoming.groupId, quantity:incoming.quantity});
  }
  return clean;
}
export function safeImageUrl(value) {
  if (typeof value !== 'string') return '';
  try {
    const url = new URL(value);
    return url.protocol === 'https:' ? url.toString() : '';
  } catch { return ''; }
}
export function normalizePhoneNumber(raw) {
  if (typeof raw !== 'string') throw new Error('Invalid phone number');
  let cleaned = raw.trim().replace(/[\s\-()]/g, '');
  if (!cleaned) throw new Error('Phone number is required');
  if (cleaned.startsWith('00')) cleaned = '+' + cleaned.slice(2);
  if (!cleaned.startsWith('+')) {
    if (/^\d{8}$/.test(cleaned)) cleaned = '+974' + cleaned;
    else if (/^974\d{8}$/.test(cleaned)) cleaned = '+' + cleaned;
    else cleaned = '+' + cleaned;
  }
  if (!/^\+[1-9]\d{6,14}$/.test(cleaned)) throw new Error('Invalid phone format');
  return cleaned;
}
export function normalizeCatalogItem(item) {
  if (!item || typeof item !== 'object' || typeof item.id !== 'string') return null;
  const groups = Array.isArray(item.groups) ? item.groups.filter(x =>
    x && typeof x.id === 'string' && x.active === true && x.wholesaleEnabled === true &&
    Number.isSafeInteger(x.unitsPerGroup) && x.unitsPerGroup > 1 &&
    x.id !== 'single' && x.nameAr !== 'حبة' && x.nameAr !== 'حبة مفرقة' &&
    x.nameEn?.toLowerCase() !== 'piece' && x.nameEn?.toLowerCase() !== 'single' &&
    Number.isSafeInteger(x.priceMinor) && x.priceMinor >= 0
  ) : [];
  if (!groups.length) return null;
  return {
    id:item.id,
    nameAr:typeof item.nameAr === 'string' ? item.nameAr : (item.name || ''),
    nameEn:typeof item.nameEn === 'string' ? item.nameEn : (item.name || ''),
    category:typeof item.category === 'string' ? item.category : 'other',
    image:safeImageUrl(item.image),
    currency:typeof item.currency === 'string' ? item.currency : 'QAR',
    available:Math.max(0, Number.isFinite(item.available) ? Math.floor(item.available) : 0),
    groups
  };
}
