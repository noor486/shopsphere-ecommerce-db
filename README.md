# ShopSphere: E-Commerce Shopping Store Database

A relational database for an online shopping store, built in SQL Server for a database systems course project. It covers the whole life of an order: browsing the catalog, cart and wishlist, checkout, payment, shipping, cancellation and reviews. A REST API and a web front end show the database at work.

**Noor Fatima, 23L-0946**

## What's in the repo

The three folders `frontend/`, `backend/` and `sql/` are the proposal's three tiers: presentation, application and data.

| Path | What it is |
|---|---|
| [`docs/`](docs) | Project proposal, the [final report](docs/ShopSphere_Final_Report.docx) and the normalized schema diagram |
| [`sql/schema.sql`](sql/schema.sql) | Builds the whole database: 17 tables (normalized to BCNF), indexes, sample data, plus the 2 views and 2 stored procedures |
| [`queries/functionalities.sql`](queries/functionalities.sql) | 26 functionalities (queries) that run on the database |
| [`backend/`](backend) | REST API in Node.js and Express that connects to the database ([endpoints and details](backend/README.md)) |
| [`frontend/`](frontend) | The web pages, served by the API: the shop (`index.html`) and the admin pages (`admin.html`) |

## Database

**Tables (17):** Customer, Seller, Admin, Category, Coupon, Address, Cart, Product, ProductVariant, ProductImage, Review, WishlistItem, CartItem, Order, OrderItem, Payment, Shipment.

- Products come in variants (size and colour). Each variant has its own SKU, price and stock.
- Categories nest: a category can have a parent category (e.g. Electronics > Laptops).
- Each order item stores the price at the time of purchase, so later price changes don't alter old orders.
- An order can have several payments (e.g. a failed attempt, then a retry) and exactly one shipment.
- Admins are a separate table from customers: they don't shop, and nobody can sign up as one.
- CHECK, UNIQUE and FOREIGN KEY constraints enforce the rules. For example, stock can't go negative, a rating must be from 1 to 5, an email can be registered only once, and a customer can review a product only once.
- 16 indexes on foreign key and searched columns speed up joins and lookups.

**Sample data:** 79 products, 115 variants, 16 customers, 1 admin, 14 orders (at least one in every status: Pending, Processing, Shipped, Delivered, Cancelled), and their payments, shipments and 13 reviews. Every review is by a customer whose order with that product was delivered.

## Functionalities

`queries/functionalities.sql` has 26 numbered functionalities in five parts:

1. Browsing and searching the catalog
2. Customers, orders and sales reports
3. Finding gaps and comparing data (outer joins and set operations)
4. Nested queries
5. Changing data (insert, update, delete). Cancelling an order runs in a transaction and puts its items back in stock.

## Views and stored procedures

These are at the end of `sql/schema.sql`, each with a description and example calls.

| Object | What it does |
|---|---|
| `vw_ProductCatalog` | One row per product with what a shopper sees: category, seller, price range, total stock and average rating |
| `vw_OrderSummary` | One row per order: customer, item count, subtotal, coupon discount, total, and the latest payment and the shipment status |
| `sp_AddToCart` | Adds a product variant to a customer's cart. It creates the cart if needed, merges repeated items and checks stock. |
| `sp_PlaceOrder` | Checkout. Turns the cart into an order in a single transaction: creates the order, copies the items, reduces stock, records the payment, creates the shipment and empties the cart. If any step fails, the whole checkout is undone. |

## API

The backend exposes the database as a REST API: catalog and search, customer accounts and addresses, cart and wishlist, checkout, order history and cancelling, reviews, and the admin side (orders, payments, shipping, adding and editing products and categories, stock, sales reports). Requests that change several tables at once run in transactions.

The admin endpoints need an admin login: `POST /api/admin/login` returns a token, and every other `/api/admin` request without a valid token is refused with 401.

Details: [backend/README.md](backend/README.md).

## Frontend

Both pages read from and save to the database through the API.

**The shop** (<http://localhost:3000>): home page with best sellers and top-rated products, category menu, search and sorting, product details with variants, stock and reviews, log in and sign up, wishlist, cart with coupon codes, checkout (`sp_PlaceOrder`), order history with cancelling, and writing reviews (only after a delivered order).

**The admin pages** (<http://localhost:3000/admin.html>, or the **Admin** link in the shop's header), after logging in as an admin:

- **Orders:** every order with its payment and shipment; mark a payment paid or failed, ship (carrier and tracking number; only once paid, except cash on delivery), mark delivered, cancel.
- **Products and stock:** search the products; add or edit a product (name, description, category, seller, price); add or edit a variant (SKU, size, colour, price); restock or correct stock.
- **Categories:** add a main category or a subcategory, and rename categories. The shop's menu shows the changes straight away.
- **Reports:** revenue, orders, average order and units sold; revenue by month; top products; sales by category; customer spending; low stock.

## Running it

You need SQL Server (Express is enough), SSMS and Node.js.

1. Open `sql/schema.sql` in SSMS and run it. This creates the `shopsphere` database with all its data. If the API is running, stop it first (Ctrl+C), because the script recreates the database.
2. Optional: run `queries/functionalities.sql` to see the 26 functionalities. Its last part changes data; run `schema.sql` again to start fresh.
3. Start the API:
   ```
   cd backend
   npm install
   npm start
   ```
4. Open <http://localhost:3000>.

**Sample logins:**

| Who | Email | Password |
|---|---|---|
| Customer | `ali.raza@example.com` | `hashed_pw_001` (customer 2 uses `hashed_pw_002`, and so on) |
| Admin | `admin@example.com` | `admin_pw_001` |

## Out of scope

Following the proposal: real payment gateways, production-grade security (password hashing, signed tokens; passwords are stored as plain text and admin tokens live in the API's memory) and large-scale performance tuning. Product pictures are also left out: the database stores each product's image URLs (`ProductImage`), but the shop shows a coloured tile with the product's initials instead of a photo.
