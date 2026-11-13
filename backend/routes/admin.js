// Administrator: manage products and stock, move orders through payment
// and shipping, and view sales reports. (No login check yet: auth is out
// of scope in the proposal.)
const express = require('express');
const { query } = require('../db');
const { HttpError, toId, toAmount, requireFields, found } = require('../helpers');

const router = express.Router();

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
router.patch('/orders/:id/shipment', async (req, res) => {
  const id = toId(req.params.id);
  const { status, carrier, trackingNumber } = req.body;
  if (!['Shipped', 'Delivered'].includes(status)) {
    throw new HttpError(400, "status must be 'Shipped' or 'Delivered'.");
  }

  const [order] = await query('SELECT Status FROM [Order] WHERE OrderID = @id', { id });
  found(order, 'Order');
  if (order.Status === 'Cancelled') throw new HttpError(400, 'This order was cancelled.');

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
