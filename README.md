# ShopSphere: E-Commerce Shopping Store Database

A relational database for an online shopping store, built in SQL Server for a database systems course project. It covers the whole life of an order: browsing the catalog, cart and wishlist, checkout, payment, shipping, cancellation and reviews.

**Noor Fatima, 23L-0946**

## What's in the repo

| Path | What it is |
|---|---|
| [`docs/`](docs) | Project proposal and the normalized schema diagram |
| [`sql/schema.sql`](sql/schema.sql) | Builds the whole database: 16 tables (normalized to BCNF), indexes, sample data, plus the 2 views and 2 stored procedures |
| [`queries/functionalities.sql`](queries/functionalities.sql) | 26 functionalities (queries) that run on the database |
| [`backend/`](backend) | REST API in Node.js and Express that connects to the database ([how to run it and the list of endpoints](backend/README.md)) |
| [`index.html`](index.html) | Storefront page (see [Frontend](#frontend)) |

## Database

**Tables (16):** Customer, Seller, Category, Coupon, Address, Cart, Product, ProductVariant, ProductImage, Review, WishlistItem, CartItem, Order, OrderItem, Payment, Shipment.

- Products come in variants (size and colour). Each variant has its own SKU, price and stock.
- Categories nest: a category can have a parent category (e.g. Electronics > Laptops).
- Each order item stores the price at the time of purchase, so later price changes don't alter old orders.
- CHECK, UNIQUE and FOREIGN KEY constraints enforce the rules. For example, stock can't go negative, a rating must be from 1 to 5, and an email can be registered only once.

**Sample data:** 79 products, 115 variants, 15 customers, 14 orders, and their payments, shipments and reviews.

## Functionalities

`queries/functionalities.sql` has 26 numbered functionalities in five parts:

1. Browsing and searching the catalog
2. Customers, orders and sales reports
3. Finding gaps and comparing data (outer joins and set operations)
4. Nested queries
5. Changing data (insert, update, delete). Cancelling an order runs in a transaction.

## Views and stored procedures

These are at the end of `sql/schema.sql`, each with a description and example calls.

| Object | What it does |
|---|---|
| `vw_ProductCatalog` | One row per product with what a shopper sees: category, seller, price range, total stock and average rating |
| `vw_OrderSummary` | One row per order: customer, item count, subtotal, coupon discount, total, and the payment and shipment status |
| `sp_AddToCart` | Adds a product variant to a customer's cart. It creates the cart if needed, merges repeated items and checks stock. |
| `sp_PlaceOrder` | Checkout. Turns the cart into an order in a single transaction: creates the order, copies the items, reduces stock, records the payment, creates the shipment and empties the cart. If any step fails, the whole checkout is undone. |

## API

The backend exposes the database as a REST API: catalog and search, customer accounts and addresses, cart and wishlist, checkout, order history and cancelling, and admin actions (products, stock, payments, shipping, sales reports). Steps that change several tables at once run in transactions.

Details: [backend/README.md](backend/README.md).

## Running it

You need SQL Server (Express is enough), SSMS and Node.js.

1. Open `sql/schema.sql` in SSMS and run it. This creates the `shopsphere` database with all its data.
2. Optional: run `queries/functionalities.sql` to see the 26 functionalities.
3. Start the API:
   ```
   cd backend
   npm install
   npm start
   ```
4. Open <http://localhost:3000>.

## Frontend

`index.html` is a storefront page you can open straight in a browser: home page, categories, search, product details, wishlist, cart, coupons, checkout, order history and reviews. For now it works from a copy of the sample data stored inside the page, not from the database. Changes made on the page are lost when it reloads.

**Next step:** connect the page to the API, so it shows live data and saves orders, carts and reviews to the database.

## Out of scope

Following the proposal: real payment gateways, production-grade login security (password hashing, tokens) and large-scale performance tuning.
