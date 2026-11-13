// Orders: checkout, order history, order details, cancelling, coupons.
const express = require('express');
const { query, execute } = require('../db');
const { HttpError, toId, requireFields, found } = require('../helpers');

const router = express.Router();

// POST /api/customers/:id/orders
// body: { addressId, paymentMethod, couponCode (optional) }
// Checkout. Uses the stored procedure sp_PlaceOrder, which turns the cart
// into an order, takes the items out of stock, records a pending payment,
// creates the shipment and empties the cart.
router.post('/customers/:id/orders', async (req, res) => {
  requireFields(req.body, ['addressId', 'paymentMethod']);

  const [order] = await execute('sp_PlaceOrder', {
    CustomerID: toId(req.params.id),
    AddressID: toId(req.body.addressId, 'addressId'),
    PaymentMethod: req.body.paymentMethod,
    CouponCode: req.body.couponCode,
  });

  res.status(201).json(order);
});

// GET /api/customers/:id/orders
// A customer's order history, newest first (uses the view vw_OrderSummary).
router.get('/customers/:id/orders', async (req, res) => {
  const rows = await query(
    'SELECT * FROM vw_OrderSummary WHERE CustomerID = @id ORDER BY OrderDate DESC',
    { id: toId(req.params.id) });
  res.json(rows);
});

// GET /api/orders/:id
// One order: its summary row, its line items and every payment attempt.
router.get('/orders/:id', async (req, res) => {
  const id = toId(req.params.id);

  const [order] = await query('SELECT * FROM vw_OrderSummary WHERE OrderID = @id', { id });
  found(order, 'Order');

  order.items = await query(
    `SELECT oi.VariantID, p.ProductID, p.Name AS ProductName, v.SKU, v.Size, v.Color,
            oi.Quantity, oi.UnitPrice, oi.Quantity * oi.UnitPrice AS LineTotal
     FROM OrderItem oi
     JOIN ProductVariant v ON oi.VariantID = v.VariantID
     JOIN Product p        ON v.ProductID = p.ProductID
     WHERE oi.OrderID = @id
     ORDER BY p.Name`, { id });

  order.payments = await query(
    `SELECT PaymentID, Method, Amount, Status, TransactionDate
     FROM Payment WHERE OrderID = @id ORDER BY TransactionDate, PaymentID`, { id });

  res.json(order);
});

// POST /api/orders/:id/cancel
// Only orders that have not shipped yet (Pending or Processing) can be
// cancelled. Puts the items back in stock, refunds a completed payment
// (or cancels a pending one) and cancels the shipment.
// The four updates run in one transaction: all of them happen or none do.
router.post('/orders/:id/cancel', async (req, res) => {
  const id = toId(req.params.id);

  const [order] = await query('SELECT Status FROM [Order] WHERE OrderID = @id', { id });
  found(order, 'Order');
  if (!['Pending', 'Processing'].includes(order.Status)) {
    throw new HttpError(400, `A ${order.Status.toLowerCase()} order cannot be cancelled.`);
  }

  await query(
    `BEGIN TRY
       BEGIN TRANSACTION;

       UPDATE Payment
       SET Status = CASE WHEN Status = 'Completed' THEN 'Refunded' ELSE 'Cancelled' END
       WHERE OrderID = @id AND Status IN ('Pending', 'Completed');

       UPDATE Shipment SET Status = 'Cancelled' WHERE OrderID = @id;

       UPDATE v
       SET v.StockQty = v.StockQty + oi.Quantity
       FROM ProductVariant v
       JOIN OrderItem oi ON oi.VariantID = v.VariantID
       WHERE oi.OrderID = @id;

       UPDATE [Order] SET Status = 'Cancelled' WHERE OrderID = @id;

       COMMIT TRANSACTION;
     END TRY
     BEGIN CATCH
       IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
       THROW;
     END CATCH`,
    { id });

  const [updated] = await query('SELECT * FROM vw_OrderSummary WHERE OrderID = @id', { id });
  res.json(updated);
});

// GET /api/coupons/:code
// Check a coupon before checkout. IsValid is 1 if it has not expired.
router.get('/coupons/:code', async (req, res) => {
  const [coupon] = await query(
    `SELECT Code, DiscountType, DiscountValue, ExpiryDate,
            CASE WHEN ExpiryDate >= CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS IsValid
     FROM Coupon WHERE Code = @code`,
    { code: req.params.code });
  res.json(found(coupon, 'Coupon'));
});

module.exports = router;
