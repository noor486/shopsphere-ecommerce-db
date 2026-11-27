// Administrator: manage products and stock, move orders through payment
// and shipping, and view sales reports.
//
// Every /api/admin request except /login needs an admin token:
//   1. POST /api/admin/login with an admin's email and password (Admin table)
//      answers with a token, a long random string.
//   2. The admin page sends it with every request in a header:
//      Authorization: Bearer <token>
//   3. The check below lets the request through only with a known, unexpired
//      token; otherwise it answers 401.
// Tokens are kept in the API's memory, so restarting the API logs admins out.
// (Passwords are not hashed: production-grade security is out of scope in the proposal.)
const crypto = require('crypto');
const express = require('express');
const { query } = require('../db');
const { HttpError, toId, toAmount, requireFields, found } = require('../helpers');

const router = express.Router();

// ===================== Logging in =====================

const sessions = new Map();          // token -> { admin, expires }
const SESSION_HOURS = 8;

// POST /api/admin/login   body: { email, password }
// The password must match exactly (case-sensitive), as for customers.
router.post('/login', async (req, res) => {
  requireFields(req.body, ['email', 'password']);
  const [admin] = await query(
    `SELECT AdminID, Name, Email FROM Admin
     WHERE Email = @email AND Password = @password COLLATE Latin1_General_CS_AS`,
    { email: req.body.email, password: req.body.password });
  if (!admin) throw new HttpError(401, 'Wrong email or password.');

  const token = crypto.randomBytes(32).toString('hex');   // 64 random hex characters
  sessions.set(token, { admin: admin, expires: Date.now() + SESSION_HOURS * 60 * 60 * 1000 });
  res.json({ token: token, admin: admin });
});

// The check: every route written below this line needs a valid token.
router.use((req, res, next) => {
  const match = /^Bearer ([0-9a-f]+)$/.exec(req.get('Authorization') || '');
  const session = match && sessions.get(match[1]);
  if (!session || session.expires < Date.now()) {
    if (session) sessions.delete(match[1]);                 // expired: forget it
    throw new HttpError(401, 'Log in as an admin first.');
  }
  req.admin = session.admin;
  req.token = match[1];
  next();
});

// GET /api/admin/me - who is logged in (the admin page asks after a refresh)
router.get('/me', (req, res) => res.json(req.admin));

// POST /api/admin/logout - forget this token
router.post('/logout', (req, res) => {
  sessions.delete(req.token);
  res.status(204).end();
});

// ===================== Products and stock =====================

// POST /api/admin/products
// body: { name, description, categoryId, sellerId, basePrice }
router.post('/products', async (req, res) => {
  requireFields(req.body, ['name', 'categoryId', 'sellerId', 'basePrice']);
  const { name, description, categoryId, sellerId, basePrice } = req.body;

  const [product] = await query(
    `INSERT INTO Product (Name, Description, CategoryID, SellerID, BasePrice)
     OUTPUT INSERTED.*
     VALUES (@name, @description, @categoryId, @sellerId, @basePrice)`,
    {
      name, description, basePrice: toAmount(basePrice, 'basePrice'),
      categoryId: toId(categoryId, 'categoryId'), sellerId: toId(sellerId, 'sellerId'),
    });

  res.status(201).json(product);
});

// POST /api/admin/products/:id/variants
// body: { sku, size, color, price, stockQty }
router.post('/products/:id/variants', async (req, res) => {
  requireFields(req.body, ['sku', 'price']);
  const { sku, size, color, price, stockQty } = req.body;

  const [variant] = await query(
    `INSERT INTO ProductVariant (ProductID, SKU, Size, Color, Price, StockQty)
     OUTPUT INSERTED.*
     VALUES (@productId, @sku, @size, @color, @price, @stockQty)`,
    {
      productId: toId(req.params.id), sku, size, color,
      price: toAmount(price, 'price'), stockQty: toAmount(stockQty || 0, 'stockQty'),
    });

  res.status(201).json(variant);
});

// Was this field sent in the request body? (Lets a field be cleared with null or "".)
const has = (body, field) => Object.prototype.hasOwnProperty.call(body, field);
const blankToNull = v => (v === '' || v === undefined ? null : v);

// PATCH /api/admin/products/:id
// body: any of { name, description, categoryId, sellerId, basePrice }
// Only the fields sent are changed. Old orders keep their prices (OrderItem.UnitPrice).
router.patch('/products/:id', async (req, res) => {
  const id = toId(req.params.id), b = req.body;
  if (!['name', 'description', 'categoryId', 'sellerId', 'basePrice'].some(f => has(b, f))) {
    throw new HttpError(400, 'Nothing to change.');
  }
  if (has(b, 'name') && !String(b.name || '').trim()) throw new HttpError(400, 'The name cannot be empty.');

  const [product] = await query(
    `UPDATE Product SET
       Name        = COALESCE(@name, Name),
       Description = CASE WHEN @setDescription = 1 THEN @description ELSE Description END,
       CategoryID  = COALESCE(@categoryId, CategoryID),
       SellerID    = COALESCE(@sellerId, SellerID),
       BasePrice   = COALESCE(@basePrice, BasePrice)
     OUTPUT INSERTED.*
     WHERE ProductID = @id`,
    {
      id,
      name: has(b, 'name') ? String(b.name).trim() : null,
      setDescription: has(b, 'description') ? 1 : 0, description: blankToNull(b.description),
      categoryId: has(b, 'categoryId') ? toId(b.categoryId, 'categoryId') : null,
      sellerId: has(b, 'sellerId') ? toId(b.sellerId, 'sellerId') : null,
      basePrice: has(b, 'basePrice') ? toAmount(b.basePrice, 'basePrice') : null,
    });
  res.json(found(product, 'Product'));
});

// PATCH /api/admin/variants/:id   body: any of { sku, size, color, price }
// Stock is changed separately (PATCH /variants/:id/stock). SKU is UNIQUE, so a
// code already used by another variant is refused with 409.
router.patch('/variants/:id', async (req, res) => {
  const id = toId(req.params.id), b = req.body;
  if (!['sku', 'size', 'color', 'price'].some(f => has(b, f))) throw new HttpError(400, 'Nothing to change.');
  if (has(b, 'sku') && !String(b.sku || '').trim()) throw new HttpError(400, 'The SKU cannot be empty.');

  const [variant] = await query(
    `UPDATE ProductVariant SET
       SKU   = COALESCE(@sku, SKU),
       Size  = CASE WHEN @setSize = 1 THEN @size ELSE Size END,
       Color = CASE WHEN @setColor = 1 THEN @color ELSE Color END,
       Price = COALESCE(@price, Price)
     OUTPUT INSERTED.VariantID, INSERTED.ProductID, INSERTED.SKU, INSERTED.Size, INSERTED.Color, INSERTED.Price, INSERTED.StockQty
     WHERE VariantID = @id`,
    {
      id,
      sku: has(b, 'sku') ? String(b.sku).trim() : null,
      setSize: has(b, 'size') ? 1 : 0, size: blankToNull(b.size),
      setColor: has(b, 'color') ? 1 : 0, color: blankToNull(b.color),
      price: has(b, 'price') ? toAmount(b.price, 'price') : null,
    });
  res.json(found(variant, 'Variant'));
});

// ===================== Categories =====================
// Categories form two levels: main categories (no parent) and their subcategories.
// The shop's menu shows exactly these two levels, so a subcategory can only be
// placed under a main category. Two categories in the same place cannot share a name.

async function nameTaken(name, parentId, exceptId) {
  const [row] = await query(
    `SELECT TOP 1 CategoryID FROM Category
     WHERE Name = @name
       AND (ParentCategoryID = @parentId OR (ParentCategoryID IS NULL AND @parentId IS NULL))
       AND CategoryID <> @exceptId`,
    { name, parentId, exceptId: exceptId || 0 });
  return !!row;
}

// POST /api/admin/categories   body: { name, parentCategoryId (optional) }
router.post('/categories', async (req, res) => {
  const name = String(req.body.name || '').trim();
  if (!name) throw new HttpError(400, 'The name cannot be empty.');
  const parentId = req.body.parentCategoryId ? toId(req.body.parentCategoryId, 'parentCategoryId') : null;

  if (parentId) {
    const [parent] = await query('SELECT ParentCategoryID FROM Category WHERE CategoryID = @parentId', { parentId });
    found(parent, 'Parent category');
    if (parent.ParentCategoryID !== null) {
      throw new HttpError(400, 'A subcategory can only be placed under a main category.');
    }
  }
  if (await nameTaken(name, parentId)) throw new HttpError(409, 'There is already a category with this name here.');

  const [category] = await query(
    'INSERT INTO Category (Name, ParentCategoryID) OUTPUT INSERTED.* VALUES (@name, @parentId)',
    { name, parentId });
  res.status(201).json(category);
});

// PATCH /api/admin/categories/:id   body: { name }
router.patch('/categories/:id', async (req, res) => {
  const id = toId(req.params.id);
  const name = String(req.body.name || '').trim();
  if (!name) throw new HttpError(400, 'The name cannot be empty.');

  const [current] = await query('SELECT ParentCategoryID FROM Category WHERE CategoryID = @id', { id });
  found(current, 'Category');
  if (await nameTaken(name, current.ParentCategoryID, id)) {
    throw new HttpError(409, 'There is already a category with this name here.');
  }

  const [category] = await query('UPDATE Category SET Name = @name OUTPUT INSERTED.* WHERE CategoryID = @id', { id, name });
  res.json(category);
});

// PATCH /api/admin/variants/:id/stock   body: { change }
// Add stock after a delivery (change: 25) or correct it (change: -3).
// Stock can never go below zero (CHECK constraint on StockQty).
router.patch('/variants/:id/stock', async (req, res) => {
  const change = Number(req.body.change);
  if (!Number.isInteger(change)) throw new HttpError(400, 'change must be a whole number.');

  const [variant] = await query(
    `UPDATE ProductVariant SET StockQty = StockQty + @change
     OUTPUT INSERTED.VariantID, INSERTED.SKU, INSERTED.StockQty
     WHERE VariantID = @id`,
    { id: toId(req.params.id), change });

  res.json(found(variant, 'Variant'));
});

// ===================== Payments and shipping =====================

// GET /api/admin/orders?status=Pending
// Every order, newest first (uses the view vw_OrderSummary), optionally
// only one status. PaymentID is the latest payment, the one the admin
// marks as paid or failed.
router.get('/orders', async (req, res) => {
  let text =
    `SELECT s.*, (SELECT MAX(p.PaymentID) FROM Payment p WHERE p.OrderID = s.OrderID) AS PaymentID
     FROM vw_OrderSummary s`;
  const params = {};
  if (req.query.status) {
    text += ' WHERE s.OrderStatus = @status';
    params.status = req.query.status;
  }
  text += ' ORDER BY s.OrderDate DESC, s.OrderID DESC';
  res.json(await query(text, params));
});

// Which payment status may follow which (the proposal's workflow).
const NEXT_PAYMENT_STATUS = {
  Pending: ['Completed', 'Failed'],
  Completed: ['Refunded'],
};

// PATCH /api/admin/payments/:id   body: { status }
// Pending -> Completed or Failed; Completed -> Refunded.
// When a payment completes, a Pending order moves to Processing.
// Both updates run in one transaction.
router.patch('/payments/:id', async (req, res) => {
  const id = toId(req.params.id);
  requireFields(req.body, ['status']);
  const { status } = req.body;

  const [payment] = await query('SELECT OrderID, Status FROM Payment WHERE PaymentID = @id', { id });
  found(payment, 'Payment');
  if (!(NEXT_PAYMENT_STATUS[payment.Status] || []).includes(status)) {
    throw new HttpError(400, `A ${payment.Status} payment cannot become ${status}.`);
  }

  await query(
    `BEGIN TRY
       BEGIN TRANSACTION;

       UPDATE Payment SET Status = @status WHERE PaymentID = @id;

       IF @status = 'Completed'
         UPDATE [Order] SET Status = 'Processing'
         WHERE OrderID = @orderId AND Status = 'Pending';

       COMMIT TRANSACTION;
     END TRY
     BEGIN CATCH
       IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
       THROW;
     END CATCH`,
    { id, status, orderId: payment.OrderID });

  const [updated] = await query('SELECT * FROM Payment WHERE PaymentID = @id', { id });
  res.json(updated);
});

// PATCH /api/admin/orders/:id/shipment
// body: { status: 'Shipped' | 'Delivered', carrier, trackingNumber }
// Updates the shipment and keeps the order status in step with it.
// Both updates run in one transaction.
// The order must be in the right state:
//   Shipped   - only a Pending or Processing order, and only once it is paid
//               (latest payment Completed), except cash on delivery, which
//               ships first and is paid on arrival.
//   Delivered - only an order that has been Shipped.
router.patch('/orders/:id/shipment', async (req, res) => {
  const id = toId(req.params.id);
  const { status, carrier, trackingNumber } = req.body;
  if (!['Shipped', 'Delivered'].includes(status)) {
    throw new HttpError(400, "status must be 'Shipped' or 'Delivered'.");
  }

  // The order, with its latest payment (an order can have several attempts).
  const [order] = await query(
    `SELECT o.Status, p.Method AS PaymentMethod, p.Status AS PaymentStatus
     FROM [Order] o
     LEFT JOIN Payment p ON p.PaymentID = (SELECT MAX(PaymentID) FROM Payment WHERE OrderID = o.OrderID)
     WHERE o.OrderID = @id`, { id });
  found(order, 'Order');
  if (order.Status === 'Cancelled') throw new HttpError(400, 'This order was cancelled.');

  if (status === 'Shipped') {
    if (!['Pending', 'Processing'].includes(order.Status)) {
      throw new HttpError(400, `A ${order.Status.toLowerCase()} order cannot be shipped again.`);
    }
    const paid = order.PaymentStatus === 'Completed';
    const cashOnDelivery = order.PaymentMethod === 'Cash on Delivery' && order.PaymentStatus === 'Pending';
    if (!paid && !cashOnDelivery) {
      throw new HttpError(400, 'This order cannot ship until it is paid. Only cash-on-delivery orders ship before payment.');
    }
  }
  if (status === 'Delivered' && order.Status !== 'Shipped') {
    throw new HttpError(400, 'Only a shipped order can be marked as delivered.');
  }

  await query(
    `BEGIN TRY
       BEGIN TRANSACTION;

       UPDATE Shipment
       SET Status         = @status,
           Carrier        = ISNULL(@carrier, Carrier),
           TrackingNumber = ISNULL(@trackingNumber, TrackingNumber),
           ShippedDate    = ISNULL(ShippedDate, GETDATE()),
           DeliveredDate  = CASE WHEN @status = 'Delivered' THEN GETDATE() ELSE DeliveredDate END
       WHERE OrderID = @id;

       UPDATE [Order] SET Status = @status WHERE OrderID = @id;

       COMMIT TRANSACTION;
     END TRY
     BEGIN CATCH
       IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
       THROW;
     END CATCH`,
    { id, status, carrier, trackingNumber });

  const [updated] = await query('SELECT * FROM vw_OrderSummary WHERE OrderID = @id', { id });
  res.json(updated);
});

// ===================== Reports (the proposal's sample queries) =====================

// GET /api/admin/reports/top-products
router.get('/reports/top-products', async (req, res) => {
  res.json(await query(
    `SELECT p.ProductID, p.Name AS Product, SUM(oi.Quantity) AS UnitsSold
     FROM OrderItem oi
     JOIN [Order] o        ON oi.OrderID = o.OrderID
     JOIN ProductVariant v ON oi.VariantID = v.VariantID
     JOIN Product p        ON v.ProductID = p.ProductID
     WHERE o.Status <> 'Cancelled'
     GROUP BY p.ProductID, p.Name
     ORDER BY UnitsSold DESC, p.Name`));
});

// GET /api/admin/reports/customer-spending
router.get('/reports/customer-spending', async (req, res) => {
  res.json(await query(
    `SELECT c.CustomerID, c.Name AS Customer, COUNT(o.OrderID) AS Orders,
            SUM(o.TotalAmount) AS TotalSpent
     FROM Customer c
     JOIN [Order] o ON o.CustomerID = c.CustomerID
     WHERE o.Status <> 'Cancelled'
     GROUP BY c.CustomerID, c.Name
     ORDER BY TotalSpent DESC`));
});

// GET /api/admin/reports/low-stock?threshold=10
router.get('/reports/low-stock', async (req, res) => {
  const threshold = req.query.threshold === undefined ? 10 : toId(req.query.threshold, 'threshold');
  res.json(await query(
    `SELECT v.VariantID, p.Name AS Product, v.SKU, v.Size, v.Color, v.StockQty
     FROM ProductVariant v
     JOIN Product p ON v.ProductID = p.ProductID
     WHERE v.StockQty < @threshold
     ORDER BY v.StockQty, p.Name`, { threshold }));
});

// GET /api/admin/reports/monthly-revenue
router.get('/reports/monthly-revenue', async (req, res) => {
  res.json(await query(
    `SELECT YEAR(OrderDate) AS OrderYear, MONTH(OrderDate) AS OrderMonth,
            COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue
     FROM [Order]
     WHERE Status <> 'Cancelled'
     GROUP BY YEAR(OrderDate), MONTH(OrderDate)
     ORDER BY OrderYear, OrderMonth`));
});

// GET /api/admin/reports/category-performance
router.get('/reports/category-performance', async (req, res) => {
  res.json(await query(
    `SELECT cat.CategoryID, cat.Name AS Category,
            SUM(oi.Quantity) AS UnitsSold, SUM(oi.Quantity * oi.UnitPrice) AS Revenue
     FROM OrderItem oi
     JOIN [Order] o        ON oi.OrderID = o.OrderID
     JOIN ProductVariant v ON oi.VariantID = v.VariantID
     JOIN Product p        ON v.ProductID = p.ProductID
     JOIN Category cat     ON p.CategoryID = cat.CategoryID
     WHERE o.Status <> 'Cancelled'
     GROUP BY cat.CategoryID, cat.Name
     ORDER BY Revenue DESC`));
});

module.exports = router;
