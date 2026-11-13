// ShopSphere REST API (Node.js + Express + SQL Server)
// Start with:  npm start     then open http://localhost:3000/api/health
const express = require('express');
const db = require('./db');

const app = express();
app.use(express.json());

// Let the storefront page (index.html, opened from disk or another port)
// call this API from the browser.
app.use((req, res, next) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  res.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// GET / - opening http://localhost:3000 in a browser shows where to start.
app.get('/', (req, res) => {
  res.json({
    message: 'ShopSphere API is running. All endpoints start with /api (see backend/README.md).',
    tryThese: [
      '/api/health',
      '/api/categories',
      '/api/products?search=laptop',
      '/api/products/1',
      '/api/customers/1/orders',
      '/api/admin/reports/top-products',
    ],
  });
});

// GET /api/health - is the API running and can it reach the database?
app.get('/api/health', async (req, res) => {
  const [row] = await db.query('SELECT DB_NAME() AS DatabaseName, COUNT(*) AS Products FROM Product');
  res.json({ status: 'ok', ...row });
});

app.use('/api', require('./routes/catalog'));
app.use('/api', require('./routes/customers'));
app.use('/api', require('./routes/cart'));
app.use('/api', require('./routes/orders'));
app.use('/api/admin', require('./routes/admin'));

// Unknown URL
app.use((req, res) => {
  res.status(404).json({ error: `No endpoint for ${req.method} ${req.originalUrl}` });
});

// Turn any error into a JSON reply with a sensible status code.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  // Our own errors (HttpError) and bad JSON in the request body
  if (err.status && err.status < 500) {
    return res.status(err.status).json({ error: err.message });
  }

  // SQL Server error number (e.g. 2627 = duplicate key)
  const number = err.number ?? err.originalError?.code;
  const message = String(err.message || '').replace(/^\[.*?\]\s*/g, '');

  if (number >= 50000 && number < 51000) {
    // Raised on purpose with THROW inside sp_AddToCart / sp_PlaceOrder
    return res.status(400).json({ error: message });
  }
  if (number === 2627 || number === 2601) {
    return res.status(409).json({ error: 'That record already exists (a unique value is repeated).' });
  }
  if (number === 547) {
    return res.status(400).json({ error: 'The request breaks a database rule: an ID that does not exist, or a value out of range.' });
  }

  console.error(err);
  res.status(500).json({ error: 'Something went wrong on the server.' });
});

const PORT = process.env.PORT || 3000;

db.ready
  .then(() => {
    app.listen(PORT, () => {
      console.log(`ShopSphere API on http://localhost:${PORT}  (database ${db.database} on ${db.server})`);
    });
  })
  .catch(err => {
    console.error(`Could not connect to database ${db.database} on ${db.server}:`, err.message);
    process.exit(1);
  });
