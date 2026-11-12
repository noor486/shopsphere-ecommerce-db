# ShopSphere API

REST API for the ShopSphere database, built with Node.js, Express and SQL Server (the proposal's application tier).

## Run it

1. Build the database: open `sql/schema.sql` in SSMS and run it. This creates the tables, indexes, sample data, views and stored procedures.
2. Install and start the API:

   ```
   cd backend
   npm install
   npm start
   ```

3. Open <http://localhost:3000/api/health>. It should show the database name and the number of products.

The API logs in to SQL Server with your Windows account. The default server is `.\SQLEXPRESS` and the default database is `shopsphere`. To use different ones, set environment variables before `npm start` (PowerShell):

```
$env:DB_SERVER = "localhost\SQLEXPRESS"; $env:DB_NAME = "shopsphere"; $env:PORT = "3000"
```

It needs **ODBC Driver 18 for SQL Server**, which installs with SSMS. If you only have version 17, also set `$env:DB_DRIVER = "ODBC Driver 17 for SQL Server"`.

## Endpoints

Request and response bodies are JSON. Errors come back as `{ "error": "message" }`:

| Status | Meaning |
|---|---|
| 400 | Bad input, or a business rule was broken (e.g. not enough stock) |
| 401 | Wrong email or password |
| 404 | Not found |
| 409 | Duplicate (e.g. email already registered, product already reviewed) |

### Catalog

| Method | URL | Body | What it does |
|---|---|---|---|
| GET | `/api/categories` | | All categories (top-level ones have no parent) |
| GET | `/api/products?search=&categoryId=` | | Browse or search products (**vw_ProductCatalog**). `categoryId` includes its subcategories |
| GET | `/api/products/:id` | | One product with variants, images and reviews |
| POST | `/api/products/:id/reviews` | `customerId, rating, comment` | Review a product (only after a delivered order, once per customer) |

### Customers

| Method | URL | Body | What it does |
|---|---|---|---|
| POST | `/api/customers/register` | `name, email, password, phone` | Create an account |
| POST | `/api/customers/login` | `email, password` | Log in, returns the customer |
| GET | `/api/customers/:id` | | Profile (the password is never returned) |
| GET | `/api/customers/:id/addresses` | | Saved addresses |
| POST | `/api/customers/:id/addresses` | `line1, city, postalCode, country, addressType` | Add an address (`Shipping` or `Billing`) |

### Cart and wishlist

| Method | URL | Body | What it does |
|---|---|---|---|
| GET | `/api/customers/:id/cart` | | Cart lines and total |
| POST | `/api/customers/:id/cart` | `variantId, quantity` | Add to cart (**sp_AddToCart**) |
| PUT | `/api/customers/:id/cart/:variantId` | `quantity` | Change a line's quantity |
| DELETE | `/api/customers/:id/cart/:variantId` | | Remove a line |
| GET | `/api/customers/:id/wishlist` | | Wishlist products |
| POST | `/api/customers/:id/wishlist` | `productId` | Add to wishlist |
| DELETE | `/api/customers/:id/wishlist/:productId` | | Remove from wishlist |

### Orders

| Method | URL | Body | What it does |
|---|---|---|---|
| GET | `/api/coupons/:code` | | Check a coupon (`IsValid` is 1 if not expired) |
| POST | `/api/customers/:id/orders` | `addressId, paymentMethod, couponCode` | Checkout the cart (**sp_PlaceOrder**) |
| GET | `/api/customers/:id/orders` | | Order history (**vw_OrderSummary**) |
| GET | `/api/orders/:id` | | One order with its items and payments |
| POST | `/api/orders/:id/cancel` | | Cancel a Pending or Processing order; puts stock back, refunds or cancels the payment |

### Admin

| Method | URL | Body | What it does |
|---|---|---|---|
| POST | `/api/admin/products` | `name, description, categoryId, sellerId, basePrice` | Add a product |
| POST | `/api/admin/products/:id/variants` | `sku, size, color, price, stockQty` | Add a size/colour variant |
| PATCH | `/api/admin/variants/:id/stock` | `change` | Restock (`25`) or correct (`-3`) stock |
| PATCH | `/api/admin/payments/:id` | `status` | Pending → Completed or Failed; Completed → Refunded. Completing a payment moves a Pending order to Processing |
| PATCH | `/api/admin/orders/:id/shipment` | `status, carrier, trackingNumber` | Mark as `Shipped` or `Delivered`; the order status follows |
| GET | `/api/admin/reports/top-products` | | Units sold per product |
| GET | `/api/admin/reports/customer-spending` | | Total spent per customer |
| GET | `/api/admin/reports/low-stock?threshold=10` | | Variants below the threshold |
| GET | `/api/admin/reports/monthly-revenue` | | Revenue per month |
| GET | `/api/admin/reports/category-performance` | | Units and revenue per category |

## Example: a full purchase (PowerShell)

```powershell
$api = "http://localhost:3000/api"
# Rehan (customer 13) adds 2 yoga mats (variant 23) to the cart
Invoke-RestMethod -Method Post "$api/customers/13/cart" -ContentType "application/json" -Body '{"variantId":23,"quantity":2}'
# Check out to his saved address (13) with a coupon
Invoke-RestMethod -Method Post "$api/customers/13/orders" -ContentType "application/json" -Body '{"addressId":13,"paymentMethod":"JazzCash","couponCode":"SAVE10"}'
```

## Not done yet (on purpose)

- **No transactions.** Checkout and cancel are several statements that are not yet wrapped in a transaction. `sp_PlaceOrder` runs all its checks before it changes anything, so a rejected checkout leaves the data untouched. The proposal requires a transaction for checkout, and that is planned for a later phase.
- **No login tokens or password hashing.** Customer IDs come from the URL. The proposal lists production-grade auth as out of scope.
