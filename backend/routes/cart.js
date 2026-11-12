// Shopping cart and wishlist for one customer.
const express = require('express');
const { query, execute } = require('../db');
const { HttpError, toId, requireFields, found } = require('../helpers');

const router = express.Router();

// Read a customer's cart and add up the total.
async function cartOf(customerId) {
  const items = await query(
    `SELECT ci.VariantID, p.ProductID, p.Name AS ProductName, v.SKU, v.Size, v.Color,
            ci.Quantity, v.Price, ci.Quantity * v.Price AS LineTotal, v.StockQty
     FROM Cart c
     JOIN CartItem ci      ON ci.CartID = c.CartID
     JOIN ProductVariant v ON ci.VariantID = v.VariantID
     JOIN Product p        ON v.ProductID = p.ProductID
     WHERE c.CustomerID = @customerId
     ORDER BY p.Name`, { customerId });

  const total = items.reduce((sum, i) => sum + Number(i.LineTotal), 0);
  return { customerId, items, total };
}

// ===================== Cart =====================

// GET /api/customers/:id/cart
router.get('/customers/:id/cart', async (req, res) => {
  res.json(await cartOf(toId(req.params.id)));
});

// POST /api/customers/:id/cart   body: { variantId, quantity }
// Uses the stored procedure sp_AddToCart (creates the cart if needed,
// merges with an existing line, checks stock).
router.post('/customers/:id/cart', async (req, res) => {
  const customerId = toId(req.params.id);
  requireFields(req.body, ['variantId']);

  await execute('sp_AddToCart', {
    CustomerID: customerId,
    VariantID: toId(req.body.variantId, 'variantId'),
    Quantity: req.body.quantity === undefined ? 1 : toId(req.body.quantity, 'quantity'),
  });

  res.status(201).json(await cartOf(customerId));
});

// PUT /api/customers/:id/cart/:variantId   body: { quantity }
// Set the quantity of a line that is already in the cart.
router.put('/customers/:id/cart/:variantId', async (req, res) => {
  const customerId = toId(req.params.id);
  const variantId = toId(req.params.variantId, 'variantId');
  const quantity = toId(req.body.quantity, 'quantity');

  const [line] = await query(
    `SELECT ci.CartItemID, v.StockQty
     FROM Cart c
     JOIN CartItem ci      ON ci.CartID = c.CartID
     JOIN ProductVariant v ON ci.VariantID = v.VariantID
     WHERE c.CustomerID = @customerId AND ci.VariantID = @variantId`,
    { customerId, variantId });
  found(line, 'Cart item');
  if (quantity > line.StockQty) throw new HttpError(400, 'Not enough stock for this item.');

  await query('UPDATE CartItem SET Quantity = @quantity WHERE CartItemID = @id',
    { quantity, id: line.CartItemID });

  res.json(await cartOf(customerId));
});

// DELETE /api/customers/:id/cart/:variantId
router.delete('/customers/:id/cart/:variantId', async (req, res) => {
  const customerId = toId(req.params.id);
  await query(
    `DELETE ci FROM CartItem ci
     JOIN Cart c ON ci.CartID = c.CartID
     WHERE c.CustomerID = @customerId AND ci.VariantID = @variantId`,
    { customerId, variantId: toId(req.params.variantId, 'variantId') });

  res.json(await cartOf(customerId));
});

// ===================== Wishlist =====================

// GET /api/customers/:id/wishlist
router.get('/customers/:id/wishlist', async (req, res) => {
  const rows = await query(
    `SELECT pc.ProductID, pc.ProductName, pc.MinPrice, pc.TotalStock, pc.ImageURL
     FROM WishlistItem w
     JOIN vw_ProductCatalog pc ON w.ProductID = pc.ProductID
     WHERE w.CustomerID = @id
     ORDER BY pc.ProductName`,
    { id: toId(req.params.id) });
  res.json(rows);
});

// POST /api/customers/:id/wishlist   body: { productId }
router.post('/customers/:id/wishlist', async (req, res) => {
  requireFields(req.body, ['productId']);
  const [item] = await query(
    `INSERT INTO WishlistItem (CustomerID, ProductID)
     OUTPUT INSERTED.*
     VALUES (@customerId, @productId)`,
    { customerId: toId(req.params.id), productId: toId(req.body.productId, 'productId') });
  res.status(201).json(item);
});

// DELETE /api/customers/:id/wishlist/:productId
router.delete('/customers/:id/wishlist/:productId', async (req, res) => {
  await query(
    'DELETE FROM WishlistItem WHERE CustomerID = @customerId AND ProductID = @productId',
    { customerId: toId(req.params.id), productId: toId(req.params.productId, 'productId') });
  res.status(204).end();
});

module.exports = router;
