// Catalog: categories, products (browse, search, details) and reviews.
const express = require('express');
const { query } = require('../db');
const { HttpError, toId, requireFields, found } = require('../helpers');

const router = express.Router();

// GET /api/categories
// All categories. Top-level ones have ParentCategoryID = null.
router.get('/categories', async (req, res) => {
  const rows = await query(
    'SELECT CategoryID, Name, ParentCategoryID FROM Category ORDER BY Name');
  res.json(rows);
});

// GET /api/products?search=laptop&categoryId=1
// Browse or search the catalog (uses the view vw_ProductCatalog).
// categoryId also matches that category's subcategories.
router.get('/products', async (req, res) => {
  let text = 'SELECT * FROM vw_ProductCatalog WHERE 1 = 1';
  const params = {};

  if (req.query.search) {
    text += ' AND (ProductName LIKE @search OR Description LIKE @search)';
    params.search = `%${req.query.search}%`;
  }
  if (req.query.categoryId) {
    text += ' AND (CategoryID = @categoryId OR ParentCategoryID = @categoryId)';
    params.categoryId = toId(req.query.categoryId, 'categoryId');
  }
  text += ' ORDER BY ProductName';

  res.json(await query(text, params));
});

// GET /api/products/:id
// One product with its variants (sizes/colours), images and reviews.
router.get('/products/:id', async (req, res) => {
  const id = toId(req.params.id);

  const [product] = await query('SELECT * FROM vw_ProductCatalog WHERE ProductID = @id', { id });
  found(product, 'Product');

  product.variants = await query(
    `SELECT VariantID, SKU, Size, Color, Price, StockQty
     FROM ProductVariant WHERE ProductID = @id ORDER BY Price, SKU`, { id });

  product.images = await query(
    `SELECT ImageID, URL, IsPrimary
     FROM ProductImage WHERE ProductID = @id ORDER BY IsPrimary DESC, ImageID`, { id });

  product.reviews = await query(
    `SELECT r.ReviewID, c.Name AS CustomerName, r.Rating, r.Comment, r.ReviewDate
     FROM Review r JOIN Customer c ON r.CustomerID = c.CustomerID
     WHERE r.ProductID = @id ORDER BY r.ReviewDate DESC`, { id });

  res.json(product);
});

// POST /api/products/:id/reviews   body: { customerId, rating, comment }
// A customer may review a product once, and only after an order
// containing it has been delivered.
router.post('/products/:id/reviews', async (req, res) => {
  const productId = toId(req.params.id);
  requireFields(req.body, ['customerId', 'rating']);
  const customerId = toId(req.body.customerId, 'customerId');

  const [bought] = await query(
    `SELECT TOP 1 o.OrderID
     FROM [Order] o
     JOIN OrderItem oi     ON oi.OrderID = o.OrderID
     JOIN ProductVariant v ON oi.VariantID = v.VariantID
     WHERE o.CustomerID = @customerId AND v.ProductID = @productId AND o.Status = 'Delivered'`,
    { customerId, productId });
  if (!bought) {
    throw new HttpError(400, 'You can only review a product after an order with it has been delivered.');
  }

  const [review] = await query(
    `INSERT INTO Review (ProductID, CustomerID, Rating, Comment)
     OUTPUT INSERTED.*
     VALUES (@productId, @customerId, @rating, @comment)`,
    { productId, customerId, rating: toId(req.body.rating, 'rating'), comment: req.body.comment });

  res.status(201).json(review);
});

module.exports = router;
