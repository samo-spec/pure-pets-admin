/**
 * Cloudflare Worker for an isolated /ws/ SPA.
 * The authenticated commerce API is implemented only in canonical Firebase Infra.
 * No Firebase admin credentials or pricing authorization live here.
 * Do not attach production routes without separate release approval.
 */
const prefix = '/ws/';
function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff'
    }
  });
}
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/ws') {
      url.pathname = prefix;
      return Response.redirect(url.toString(), 308);
    }
    if (!url.pathname.startsWith(prefix)) return new Response('Not found', {status: 404});
    if (url.pathname === '/ws/api/config') {
      if (request.method !== 'GET') return new Response('Method not allowed', {status: 405});
      let firebase;
      try { firebase = JSON.parse(env.FIREBASE_CLIENT_CONFIG || 'null'); }
      catch { return json({error: 'Invalid deployment configuration'}, 503); }
      if (!firebase || !firebase.apiKey || !firebase.authDomain || !firebase.projectId || !firebase.appId) {
        return json({error: 'Wholesale preview needs Firebase client configuration'}, 503);
      }
      return json({firebase, region: env.FUNCTIONS_REGION || 'us-central1',
        appCheckSiteKey: env.FIREBASE_APPCHECK_SITE_KEY || null});
    }
    if (url.pathname.startsWith('/ws/api/')) return json({error: 'Unknown endpoint'}, 404);
    // Path aliases for the staff operations workspace; authorization is server-side.
    if (url.pathname === '/ws/manage' || url.pathname === '/ws/manage/') {
      url.pathname = '/ws/manage.html';
      return Response.redirect(url.toString(), 308);
    }
    const originalPath = url.pathname;
    url.pathname = '/' + originalPath.slice(prefix.length);
    const assetRequest = new Request(url.toString(), request);
    let response = await env.ASSETS.fetch(assetRequest);
    if (response.status === 404 && !url.pathname.includes('.') && request.headers.get('accept')?.includes('text/html')) {
      url.pathname = '/index.html';
      response = await env.ASSETS.fetch(new Request(url.toString(), request));
    }
    const headers = new Headers(response.headers);
    headers.set('x-content-type-options', 'nosniff');
    headers.set('referrer-policy', 'strict-origin-when-cross-origin');
    headers.set('x-frame-options', 'DENY');
    headers.set('permissions-policy', 'camera=(), microphone=(), geolocation=()');
    // The HTML must never be cached across releases.
    if (url.pathname === '/' || url.pathname.endsWith('.html')) headers.set('cache-control', 'no-store');
    return new Response(response.body, {status: response.status, statusText: response.statusText, headers});
  }
};
