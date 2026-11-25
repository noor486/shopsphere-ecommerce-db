// ShopSphere: the one place where the web pages talk to the backend API.
// Both pages (index.html and admin.html) load this file first.
//
//   api.get('/products?search=laptop')            -> GET    /api/products?search=laptop
//   api.post('/customers/3/cart', { variantId: 5 }) -> POST   /api/customers/3/cart
//   api.put / api.patch / api.del work the same way.
//
// Every call returns the JSON the API sent back. If the API replies with an
// error (400, 404, 409 ...), the call throws an Error whose message is the
// API's { "error": "..." } text and whose .status is the HTTP status code.

// Normally the pages are opened from the API itself (http://localhost:3000),
// so '/api' is enough. If a page is opened straight from disk, it calls the
// API on localhost:3000 instead.
const API_BASE = location.protocol === 'file:' ? 'http://localhost:3000/api' : '/api';

async function request(method, path, body) {
  const options = { method: method, headers: {} };
  if (body !== undefined) {
    options.headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(body);
  }

  let res;
  try {
    res = await fetch(API_BASE + path, options);
  } catch (e) {
    const err = new Error('Cannot reach the ShopSphere API. Start it with "npm start" in the backend folder.');
    err.status = 0;
    throw err;
  }

  if (res.status === 204) return null;                  // success, nothing to read
  let data = null;
  try { data = await res.json(); } catch (e) { /* not JSON */ }

  if (!res.ok) {
    const err = new Error((data && data.error) || 'Request failed (' + res.status + ').');
    err.status = res.status;
    throw err;
  }
  return data;
}

const api = {
  get: path => request('GET', path),
  post: (path, body) => request('POST', path, body || {}),
  put: (path, body) => request('PUT', path, body || {}),
  patch: (path, body) => request('PATCH', path, body || {}),
  del: path => request('DELETE', path),
};

// ---------- small display helpers used by both pages ----------

// Escape text before putting it into HTML, so a product name or review
// containing < or & cannot break the page.
const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// 1999.5 -> "Rs 1,999.50", 2000 -> "Rs 2,000"
const money = n => {
  const r = Math.round(Number(n) * 100) / 100;
  return 'Rs ' + (r % 1 === 0 ? r.toLocaleString('en-US')
    : r.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
};

// "2026-09-05T09:45:00.000Z" -> "5 Sept 2026"
const fmtDate = d => (d ? new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '');
