// Customers: register, log in, profile and saved addresses.
const express = require('express');
const { query } = require('../db');
const { HttpError, toId, requireFields, found } = require('../helpers');

const router = express.Router();

// Columns safe to send back. The password is never returned.
const PUBLIC_COLUMNS = 'CustomerID, Name, Email, Phone, CreatedAt';

// POST /api/customers/register   body: { name, email, password, phone }
router.post('/customers/register', async (req, res) => {
  requireFields(req.body, ['name', 'email', 'password']);
  const { name, email, password, phone } = req.body;

  // Note: the password is stored as given. Proper hashing is listed as
  // out of scope (production-grade security) in the proposal.
  const [customer] = await query(
    `INSERT INTO Customer (Name, Email, Password, Phone)
     OUTPUT INSERTED.CustomerID, INSERTED.Name, INSERTED.Email, INSERTED.Phone, INSERTED.CreatedAt
     VALUES (@name, @email, @password, @phone)`,
    { name, email, password, phone });

  res.status(201).json(customer);
});

// POST /api/customers/login   body: { email, password }
router.post('/customers/login', async (req, res) => {
  requireFields(req.body, ['email', 'password']);

  const [customer] = await query(
    `SELECT ${PUBLIC_COLUMNS} FROM Customer WHERE Email = @email AND Password = @password`,
    { email: req.body.email, password: req.body.password });

  if (!customer) throw new HttpError(401, 'Wrong email or password.');
  res.json(customer);
});

// GET /api/customers/:id
router.get('/customers/:id', async (req, res) => {
  const [customer] = await query(
    `SELECT ${PUBLIC_COLUMNS} FROM Customer WHERE CustomerID = @id`,
    { id: toId(req.params.id) });
  res.json(found(customer, 'Customer'));
});

// GET /api/customers/:id/addresses
router.get('/customers/:id/addresses', async (req, res) => {
  const rows = await query(
    `SELECT AddressID, Line1, City, PostalCode, Country, AddressType
     FROM Address WHERE CustomerID = @id ORDER BY AddressID`,
    { id: toId(req.params.id) });
  res.json(rows);
});

// POST /api/customers/:id/addresses
// body: { line1, city, postalCode, country, addressType: 'Shipping' | 'Billing' }
router.post('/customers/:id/addresses', async (req, res) => {
  const customerId = toId(req.params.id);
  requireFields(req.body, ['line1', 'city', 'country']);

  const [customer] = await query('SELECT CustomerID FROM Customer WHERE CustomerID = @customerId', { customerId });
  found(customer, 'Customer');

  const { line1, city, postalCode, country, addressType } = req.body;
  const [address] = await query(
    `INSERT INTO Address (CustomerID, Line1, City, PostalCode, Country, AddressType)
     OUTPUT INSERTED.*
     VALUES (@customerId, @line1, @city, @postalCode, @country, @addressType)`,
    { customerId, line1, city, postalCode, country, addressType: addressType || 'Shipping' });

  res.status(201).json(address);
});

module.exports = router;
