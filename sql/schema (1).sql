-- ShopSphere: E-Commerce Shopping Store Database
-- Schema (DDL) -- SQL Server (T-SQL)
-- All 16 tables, normalized to BCNF, in dependency order.
-- Run on an empty database to recreate the whole schema.

CREATE DATABASE shopsphere;
GO

USE shopsphere;
GO

-- ===================== Independent tables =====================

CREATE TABLE Customer (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    Email NVARCHAR(150) NOT NULL UNIQUE,
    Password NVARCHAR(255) NOT NULL,
    Phone NVARCHAR(20),
    CreatedAt DATETIME2 DEFAULT GETDATE()
);

CREATE TABLE Seller (
    SellerID INT IDENTITY(1,1) PRIMARY KEY,
    StoreName NVARCHAR(150) NOT NULL,
    Email NVARCHAR(150) NOT NULL UNIQUE,
    Rating DECIMAL(3,2) DEFAULT 0
);

CREATE TABLE Category (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    ParentCategoryID INT NULL,
    CONSTRAINT FK_Category_Parent FOREIGN KEY (ParentCategoryID)
        REFERENCES Category(CategoryID)
);

CREATE TABLE Coupon (
    CouponID INT IDENTITY(1,1) PRIMARY KEY,
    Code NVARCHAR(30) NOT NULL UNIQUE,
    DiscountType NVARCHAR(20) NOT NULL,
    DiscountValue DECIMAL(10,2) NOT NULL CHECK (DiscountValue >= 0),
    ExpiryDate DATE NOT NULL
);

-- ===================== Depend on Customer =====================

CREATE TABLE Address (
    AddressID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    Line1 NVARCHAR(200) NOT NULL,
    City NVARCHAR(100) NOT NULL,
    PostalCode NVARCHAR(20),
    Country NVARCHAR(100) NOT NULL,
    AddressType NVARCHAR(20) DEFAULT 'Shipping',
    CONSTRAINT FK_Address_Customer FOREIGN KEY (CustomerID)
        REFERENCES Customer(CustomerID)
);

-- Each customer has exactly one persistent cart (true 1:1, enforced by UNIQUE).
CREATE TABLE Cart (
    CartID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL UNIQUE,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT FK_Cart_Customer FOREIGN KEY (CustomerID)
        REFERENCES Customer(CustomerID)
);

-- ===================== Depend on Category / Seller =====================

CREATE TABLE Product (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    CategoryID INT NOT NULL,
    SellerID INT NOT NULL,
    BasePrice DECIMAL(10,2) NOT NULL CHECK (BasePrice >= 0),
    CONSTRAINT FK_Product_Category FOREIGN KEY (CategoryID)
        REFERENCES Category(CategoryID),
    CONSTRAINT FK_Product_Seller FOREIGN KEY (SellerID)
        REFERENCES Seller(SellerID)
);

-- ===================== Depend on Product =====================

CREATE TABLE ProductVariant (
    VariantID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    SKU NVARCHAR(50) NOT NULL UNIQUE,
    Size NVARCHAR(20),
    Color NVARCHAR(30),
    Price DECIMAL(10,2) NOT NULL CHECK (Price >= 0),
    StockQty INT NOT NULL DEFAULT 0 CHECK (StockQty >= 0),
    CONSTRAINT FK_Variant_Product FOREIGN KEY (ProductID)
        REFERENCES Product(ProductID)
);

CREATE TABLE ProductImage (
    ImageID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    URL NVARCHAR(300) NOT NULL,
    IsPrimary BIT DEFAULT 0,
    CONSTRAINT FK_ProductImage_Product FOREIGN KEY (ProductID)
        REFERENCES Product(ProductID)
);

-- A customer reviews a given product at most once.
CREATE TABLE Review (
    ReviewID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    CustomerID INT NOT NULL,
    Rating INT NOT NULL CHECK (Rating BETWEEN 1 AND 5),
    Comment NVARCHAR(MAX),
    ReviewDate DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT FK_Review_Product FOREIGN KEY (ProductID)
        REFERENCES Product(ProductID),
    CONSTRAINT FK_Review_Customer FOREIGN KEY (CustomerID)
        REFERENCES Customer(CustomerID),
    CONSTRAINT UQ_Review_Customer_Product UNIQUE (CustomerID, ProductID)
);

CREATE TABLE WishlistItem (
    WishlistItemID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    ProductID INT NOT NULL,
    CONSTRAINT FK_Wishlist_Customer FOREIGN KEY (CustomerID)
        REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Wishlist_Product FOREIGN KEY (ProductID)
        REFERENCES Product(ProductID),
    CONSTRAINT UQ_Wishlist_Customer_Product UNIQUE (CustomerID, ProductID)
);

-- ===================== Depend on Cart / ProductVariant =====================

-- One line per variant per cart (composite candidate key).
CREATE TABLE CartItem (
    CartItemID INT IDENTITY(1,1) PRIMARY KEY,
    CartID INT NOT NULL,
    VariantID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    CONSTRAINT FK_CartItem_Cart FOREIGN KEY (CartID)
        REFERENCES Cart(CartID),
    CONSTRAINT FK_CartItem_Variant FOREIGN KEY (VariantID)
        REFERENCES ProductVariant(VariantID),
    CONSTRAINT UQ_CartItem_Cart_Variant UNIQUE (CartID, VariantID)
);

-- ===================== Order and its dependents =====================
-- The shipping destination is stored on Shipment, not Order. Storing both
-- CustomerID and AddressID on Order would create the dependency
-- AddressID -> CustomerID inside Order (an address belongs to one customer),
-- which violates 3NF/BCNF.
-- CouponID is nullable: an order carries at most one coupon, so Coupon-Order
-- is a plain 1:N relationship and needs no junction table.

CREATE TABLE [Order] (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    CouponID INT NULL,
    OrderDate DATETIME2 DEFAULT GETDATE(),
    Status NVARCHAR(30) DEFAULT 'Pending',
    TotalAmount DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (TotalAmount >= 0),
    CONSTRAINT FK_Order_Customer FOREIGN KEY (CustomerID)
        REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Order_Coupon FOREIGN KEY (CouponID)
        REFERENCES Coupon(CouponID)
);

-- One line per variant per order, composite candidate key.
-- UnitPrice is a deliberate snapshot of the price at purchase time.
CREATE TABLE OrderItem (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    VariantID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL CHECK (UnitPrice >= 0),
    CONSTRAINT FK_OrderItem_Order FOREIGN KEY (OrderID)
        REFERENCES [Order](OrderID),
    CONSTRAINT FK_OrderItem_Variant FOREIGN KEY (VariantID)
        REFERENCES ProductVariant(VariantID),
    CONSTRAINT UQ_OrderItem_Order_Variant UNIQUE (OrderID, VariantID)
);

-- An order may have several payment records over time e.g. a failed
-- attempt followed by a successful retry: plain 1:N, no uniqueness.
CREATE TABLE Payment (
    PaymentID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    Method NVARCHAR(30) NOT NULL,
    Amount DECIMAL(10,2) NOT NULL CHECK (Amount >= 0),
    Status NVARCHAR(30) DEFAULT 'Pending',
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT FK_Payment_Order FOREIGN KEY (OrderID)
        REFERENCES [Order](OrderID)
);

-- One shipment per order true 1:1, enforced by UNIQUE. The shipment is
-- created when the order is placed ,Status = 'Processing', so the
-- destination address is known from the start.
CREATE TABLE Shipment (
    ShipmentID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL UNIQUE,
    AddressID INT NOT NULL,
    Carrier NVARCHAR(50),
    TrackingNumber NVARCHAR(50),
    Status NVARCHAR(30) DEFAULT 'Processing',
    ShippedDate DATETIME2 NULL,
    DeliveredDate DATETIME2 NULL,
    CONSTRAINT FK_Shipment_Order FOREIGN KEY (OrderID)
        REFERENCES [Order](OrderID),
    CONSTRAINT FK_Shipment_Address FOREIGN KEY (AddressID)
        REFERENCES Address(AddressID)
);
GO

-- ===================== SAMPLE DATA =====================

-- ===== Customers =====
INSERT INTO Customer (Name, Email, Password, Phone) VALUES
('Ali Raza', 'ali.raza@example.com', 'hashed_pw_001', '03001234567'),
('Sara Khan', 'sara.khan@example.com', 'hashed_pw_002', '03007654321'),
('Bilal Ahmed', 'bilal.ahmed@example.com', 'hashed_pw_003', '03211234567'),
('Ayesha Malik', 'ayesha.malik@example.com', 'hashed_pw_004', '03331234567'),
('Usman Tariq', 'usman.tariq@example.com', 'hashed_pw_005', '03451234567'),
('Hira Fatima', 'hira.fatima@example.com', 'hashed_pw_006', '03011234567'),
('Zain Abbas', 'zain.abbas@example.com', 'hashed_pw_007', '03211239876'),
('Mahnoor Iqbal', 'mahnoor.iqbal@example.com', 'hashed_pw_008', '03339876543'),
('Hamza Sheikh', 'hamza.sheikh@example.com', 'hashed_pw_009', '03451239876'),
('Fatima Noor', 'fatima.noor@example.com', 'hashed_pw_010', '03219876543'),
('Danish Aslam', 'danish.aslam@example.com', 'hashed_pw_011', '03001239876'),
('Kinza Yousaf', 'kinza.yousaf@example.com', 'hashed_pw_012', '03071234567'),
('Rehan Qureshi', 'rehan.qureshi@example.com', 'hashed_pw_013', '03349876543'),
('Sana Riaz', 'sana.riaz@example.com', 'hashed_pw_014', '03121234567'),
('Omar Farooq', 'omar.farooq@example.com', 'hashed_pw_015', '03429876543');

-- ===== Sellers =====
INSERT INTO Seller (StoreName, Email, Rating) VALUES
('TechHub Electronics', 'contact@techhub.example.com', 4.30),
('StyleNest Fashion', 'contact@stylenest.example.com', 4.10),
('HomeEase Essentials', 'contact@homeease.example.com', 4.50);

-- ===== Categories (top-level first, then subcategories) =====
INSERT INTO Category (Name, ParentCategoryID) VALUES
('Electronics', NULL),
('Fashion', NULL),
('Home & Kitchen', NULL),
('Books', NULL),
('Sports & Outdoors', NULL);

INSERT INTO Category (Name, ParentCategoryID)
VALUES ('Mobiles', (SELECT CategoryID FROM Category WHERE Name = 'Electronics'));

INSERT INTO Category (Name, ParentCategoryID)
VALUES ('Laptops', (SELECT CategoryID FROM Category WHERE Name = 'Electronics'));

INSERT INTO Category (Name, ParentCategoryID)
VALUES ('Men''s Clothing', (SELECT CategoryID FROM Category WHERE Name = 'Fashion'));

INSERT INTO Category (Name, ParentCategoryID)
VALUES ('Women''s Clothing', (SELECT CategoryID FROM Category WHERE Name = 'Fashion'));

-- ===== Addresses (one per customer) =====
INSERT INTO Address (CustomerID, Line1, City, PostalCode, Country, AddressType)
VALUES
((SELECT CustomerID FROM Customer WHERE Email = 'ali.raza@example.com'), 'House 12, Street 5, Gulberg', 'Lahore', '54000', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'sara.khan@example.com'), 'Flat 3B, DHA Phase 5', 'Lahore', '54792', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'bilal.ahmed@example.com'), 'House 45, F-10', 'Islamabad', '44000', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'ayesha.malik@example.com'), 'House 8, North Nazimabad', 'Karachi', '74700', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'usman.tariq@example.com'), 'House 22, Model Town', 'Lahore', '54700', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'hira.fatima@example.com'), 'Flat 12, Clifton Block 2', 'Karachi', '75600', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'zain.abbas@example.com'), 'House 3, G-11', 'Islamabad', '44000', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'mahnoor.iqbal@example.com'), 'House 19, Johar Town', 'Lahore', '54782', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'hamza.sheikh@example.com'), 'House 6, Bahria Town', 'Rawalpindi', '46000', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'fatima.noor@example.com'), 'Flat 2A, PECHS', 'Karachi', '75400', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'danish.aslam@example.com'), 'House 14, Wapda Town', 'Lahore', '54770', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'kinza.yousaf@example.com'), 'House 9, Satellite Town', 'Rawalpindi', '46300', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'rehan.qureshi@example.com'), 'House 27, Faisal Town', 'Lahore', '54600', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'sana.riaz@example.com'), 'Flat 5C, Gulshan-e-Iqbal', 'Karachi', '75300', 'Pakistan', 'Shipping'),
((SELECT CustomerID FROM Customer WHERE Email = 'omar.farooq@example.com'), 'House 31, E-11', 'Islamabad', '44000', 'Pakistan', 'Shipping');

-- ===== Products =====
INSERT INTO Product (Name, Description, CategoryID, SellerID, BasePrice)
VALUES
('Wireless Bluetooth Earbuds', 'Compact earbuds with 24-hour battery life', (SELECT CategoryID FROM Category WHERE Name = 'Mobiles'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 4999.00),
('Smartphone 128GB', 'Mid-range smartphone with 6.5-inch display', (SELECT CategoryID FROM Category WHERE Name = 'Mobiles'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 54999.00),
('Slim Laptop 14-inch', 'Lightweight laptop for everyday use', (SELECT CategoryID FROM Category WHERE Name = 'Laptops'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 89999.00),
('Gaming Laptop 15.6-inch', 'High-performance laptop with dedicated GPU', (SELECT CategoryID FROM Category WHERE Name = 'Laptops'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 189999.00),
('Wireless Mouse', 'Ergonomic wireless mouse', (SELECT CategoryID FROM Category WHERE Name = 'Electronics'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 1499.00),
('Men''s Casual Shirt', 'Cotton casual shirt, regular fit', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 2199.00),
('Men''s Denim Jeans', 'Slim-fit denim jeans', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 3299.00),
('Women''s Kurti', 'Printed cotton kurti', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1899.00),
('Women''s Handbag', 'Faux leather shoulder bag', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 2799.00),
('Non-Stick Cookware Set', '5-piece non-stick cookware set', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 6499.00),
('Electric Kettle 1.7L', 'Stainless steel electric kettle', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 2399.00),
('Bedsheet Set (King Size)', 'Cotton bedsheet set with 2 pillow covers', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 3199.00),
('Table Lamp', 'Modern LED table lamp', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1799.00),
('Self-Help Book: Atomic Habits', 'Bestselling book on building good habits', (SELECT CategoryID FROM Category WHERE Name = 'Books'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1299.00),
('Novel: The Silent Patient', 'Psychological thriller novel', (SELECT CategoryID FROM Category WHERE Name = 'Books'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 999.00),
('Yoga Mat', 'Non-slip yoga mat, 6mm thick', (SELECT CategoryID FROM Category WHERE Name = 'Sports & Outdoors'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1599.00),
('Running Shoes', 'Lightweight running shoes with cushioned sole', (SELECT CategoryID FROM Category WHERE Name = 'Sports & Outdoors'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 4599.00),
('Adjustable Dumbbell Set', 'Pair of adjustable dumbbells, 2-20kg', (SELECT CategoryID FROM Category WHERE Name = 'Sports & Outdoors'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 8999.00),
('Wireless Charging Pad', 'Fast wireless charger for smartphones', (SELECT CategoryID FROM Category WHERE Name = 'Mobiles'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 1999.00),
('Laptop Backpack', 'Water-resistant laptop backpack, 15.6-inch', (SELECT CategoryID FROM Category WHERE Name = 'Laptops'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 2599.00);

-- ===== Product variants (size / colour / SKU-level price and stock) =====
INSERT INTO ProductVariant (ProductID, SKU, Size, Color, Price, StockQty)
SELECT p.ProductID, x.SKU, x.Size, x.Color, x.Price, x.Stock
FROM (VALUES
    ('Wireless Bluetooth Earbuds', 'EAR-BLK', 'Standard', 'Black', 4999.00, 40),
    ('Wireless Bluetooth Earbuds', 'EAR-WHT', 'Standard', 'White', 4999.00, 25),
    ('Smartphone 128GB', 'PH-128-BLK', '128GB', 'Black', 54999.00, 12),
    ('Smartphone 128GB', 'PH-128-BLU', '128GB', 'Blue', 54999.00, 8),
    ('Slim Laptop 14-inch', 'LT-SLIM-SLV', '14-inch', 'Silver', 89999.00, 6),
    ('Gaming Laptop 15.6-inch', 'LT-GAME-BLK', '15.6-inch', 'Black', 189999.00, 3),
    ('Wireless Mouse', 'MS-WL-BLK', 'Standard', 'Black', 1499.00, 60),
    ('Wireless Mouse', 'MS-WL-GRY', 'Standard', 'Grey', 1499.00, 35),
    ('Men''s Casual Shirt', 'SH-M-BLU', 'M', 'Blue', 2199.00, 30),
    ('Men''s Casual Shirt', 'SH-L-BLU', 'L', 'Blue', 2199.00, 22),
    ('Men''s Casual Shirt', 'SH-L-WHT', 'L', 'White', 2199.00, 4),
    ('Men''s Denim Jeans', 'JN-32-BLU', '32', 'Blue', 3299.00, 18),
    ('Men''s Denim Jeans', 'JN-34-BLK', '34', 'Black', 3299.00, 9),
    ('Women''s Kurti', 'KU-M-RED', 'M', 'Red', 1899.00, 28),
    ('Women''s Kurti', 'KU-L-GRN', 'L', 'Green', 1899.00, 5),
    ('Women''s Handbag', 'HB-BRN', 'Standard', 'Brown', 2799.00, 14),
    ('Non-Stick Cookware Set', 'CK-5PC', '5-piece', 'Black', 6499.00, 10),
    ('Electric Kettle 1.7L', 'KT-17-SLV', '1.7L', 'Silver', 2399.00, 26),
    ('Bedsheet Set (King Size)', 'BS-KING-WHT', 'King', 'White', 3199.00, 15),
    ('Table Lamp', 'LP-LED-WHT', 'Standard', 'White', 1799.00, 2),
    ('Self-Help Book: Atomic Habits', 'BK-ATOM', 'Paperback', 'N/A', 1299.00, 50),
    ('Novel: The Silent Patient', 'BK-SILENT', 'Paperback', 'N/A', 999.00, 45),
    ('Yoga Mat', 'YM-6MM-PRP', '6mm', 'Purple', 1599.00, 32),
    ('Running Shoes', 'RS-42-BLK', '42', 'Black', 4599.00, 12),
    ('Running Shoes', 'RS-44-BLK', '44', 'Black', 4599.00, 7),
    ('Adjustable Dumbbell Set', 'DB-ADJ-20', '2-20kg', 'Black', 8999.00, 6),
    ('Wireless Charging Pad', 'WC-PAD-BLK', 'Standard', 'Black', 1999.00, 38),
    ('Laptop Backpack', 'BP-156-GRY', '15.6-inch', 'Grey', 2599.00, 20)
) AS x (ProductName, SKU, Size, Color, Price, Stock)
JOIN Product p ON p.Name = x.ProductName;

-- ===== Product images (one main image each, a second for pricier items) =====
INSERT INTO ProductImage (ProductID, URL, IsPrimary)
SELECT ProductID, 'https://images.shopsphere.example/p' + CAST(ProductID AS NVARCHAR(10)) + '-main.jpg', 1
FROM Product;

INSERT INTO ProductImage (ProductID, URL, IsPrimary)
SELECT ProductID, 'https://images.shopsphere.example/p' + CAST(ProductID AS NVARCHAR(10)) + '-alt.jpg', 0
FROM Product
WHERE BasePrice > 5000;

-- ===== Coupons (one expired but used, one expired and unused, one never used) =====
INSERT INTO Coupon (Code, DiscountType, DiscountValue, ExpiryDate) VALUES
('SAVE10', 'Percentage', 10.00, '2027-12-31'),
('WELCOME500', 'Fixed', 500.00, '2027-06-30'),
('EID20', 'Percentage', 20.00, '2026-04-30'),
('FLASH15', 'Percentage', 15.00, '2027-03-31'),
('OLD5', 'Percentage', 5.00, '2025-12-31');

-- ===== Carts (one per customer; Rehan's cart is empty) =====
INSERT INTO Cart (CustomerID)
SELECT CustomerID FROM Customer
WHERE Email IN ('ali.raza@example.com', 'sara.khan@example.com', 'bilal.ahmed@example.com',
                'ayesha.malik@example.com', 'usman.tariq@example.com', 'zain.abbas@example.com',
                'kinza.yousaf@example.com', 'rehan.qureshi@example.com');

INSERT INTO CartItem (CartID, VariantID, Quantity)
SELECT ct.CartID, v.VariantID, x.Qty
FROM (VALUES
    ('ali.raza@example.com', 'EAR-BLK', 1),
    ('ali.raza@example.com', 'MS-WL-BLK', 2),
    ('sara.khan@example.com', 'KU-M-RED', 2),
    ('sara.khan@example.com', 'HB-BRN', 1),
    ('bilal.ahmed@example.com', 'LT-SLIM-SLV', 1),
    ('ayesha.malik@example.com', 'CK-5PC', 1),
    ('ayesha.malik@example.com', 'KT-17-SLV', 1),
    ('usman.tariq@example.com', 'RS-42-BLK', 1),
    ('zain.abbas@example.com', 'YM-6MM-PRP', 1),
    ('zain.abbas@example.com', 'DB-ADJ-20', 1),
    ('kinza.yousaf@example.com', 'WC-PAD-BLK', 1),
    ('kinza.yousaf@example.com', 'BK-ATOM', 2)
) AS x (Email, SKU, Qty)
JOIN Customer c ON c.Email = x.Email
JOIN Cart ct ON ct.CustomerID = c.CustomerID
JOIN ProductVariant v ON v.SKU = x.SKU;

-- ===== Orders (each order has a distinct timestamp, used below to match its rows) =====
INSERT INTO [Order] (CustomerID, CouponID, OrderDate, Status)
SELECT c.CustomerID, cp.CouponID, x.OrderDate, x.Status
FROM (VALUES
    ('ali.raza@example.com', NULL, '2026-01-10T11:20:00', 'Delivered'),
    ('sara.khan@example.com', 'SAVE10', '2026-01-25T15:45:00', 'Delivered'),
    ('bilal.ahmed@example.com', NULL, '2026-02-14T09:10:00', 'Delivered'),
    ('ayesha.malik@example.com', 'WELCOME500', '2026-02-28T18:30:00', 'Delivered'),
    ('ali.raza@example.com', NULL, '2026-03-12T13:05:00', 'Delivered'),
    ('usman.tariq@example.com', 'SAVE10', '2026-04-03T10:00:00', 'Delivered'),
    ('hira.fatima@example.com', NULL, '2026-04-19T16:40:00', 'Cancelled'),
    ('zain.abbas@example.com', 'EID20', '2026-04-22T12:25:00', 'Delivered'),
    ('mahnoor.iqbal@example.com', NULL, '2026-05-30T14:15:00', 'Delivered'),
    ('sara.khan@example.com', NULL, '2026-06-18T19:50:00', 'Shipped'),
    ('hamza.sheikh@example.com', 'SAVE10', '2026-07-07T11:35:00', 'Shipped'),
    ('fatima.noor@example.com', NULL, '2026-08-02T10:55:00', 'Processing'),
    ('danish.aslam@example.com', 'WELCOME500', '2026-08-21T17:20:00', 'Pending'),
    ('ali.raza@example.com', NULL, '2026-09-05T09:45:00', 'Processing')
) AS x (Email, CouponCode, OrderDate, Status)
JOIN Customer c ON c.Email = x.Email
LEFT JOIN Coupon cp ON cp.Code = x.CouponCode;

-- ===== Order items (UnitPrice copies the variant price at purchase time) =====
INSERT INTO OrderItem (OrderID, VariantID, Quantity, UnitPrice)
SELECT o.OrderID, v.VariantID, x.Qty, v.Price
FROM (VALUES
    ('2026-01-10T11:20:00', 'EAR-BLK', 1),
    ('2026-01-10T11:20:00', 'MS-WL-BLK', 1),
    ('2026-01-25T15:45:00', 'SH-M-BLU', 2),
    ('2026-01-25T15:45:00', 'JN-32-BLU', 1),
    ('2026-02-14T09:10:00', 'LT-SLIM-SLV', 1),
    ('2026-02-28T18:30:00', 'CK-5PC', 1),
    ('2026-02-28T18:30:00', 'KT-17-SLV', 2),
    ('2026-03-12T13:05:00', 'PH-128-BLK', 1),
    ('2026-04-03T10:00:00', 'RS-42-BLK', 1),
    ('2026-04-03T10:00:00', 'YM-6MM-PRP', 2),
    ('2026-04-19T16:40:00', 'BK-ATOM', 2),
    ('2026-04-22T12:25:00', 'LT-GAME-BLK', 1),
    ('2026-05-30T14:15:00', 'KU-M-RED', 3),
    ('2026-06-18T19:50:00', 'BS-KING-WHT', 1),
    ('2026-07-07T11:35:00', 'DB-ADJ-20', 1),
    ('2026-07-07T11:35:00', 'RS-44-BLK', 1),
    ('2026-08-02T10:55:00', 'EAR-WHT', 2),
    ('2026-08-02T10:55:00', 'BP-156-GRY', 1),
    ('2026-08-21T17:20:00', 'SH-L-BLU', 1),
    ('2026-08-21T17:20:00', 'JN-34-BLK', 1),
    ('2026-08-21T17:20:00', 'MS-WL-GRY', 1),
    ('2026-09-05T09:45:00', 'PH-128-BLU', 1)
) AS x (OrderDate, SKU, Qty)
JOIN [Order] o ON o.OrderDate = CONVERT(DATETIME2, x.OrderDate, 126)
JOIN ProductVariant v ON v.SKU = x.SKU;

-- ===== Order totals: sum of the lines, then the coupon discount =====
UPDATE o
SET TotalAmount = (SELECT SUM(oi.Quantity * oi.UnitPrice) FROM OrderItem oi WHERE oi.OrderID = o.OrderID)
FROM [Order] o;

UPDATE o
SET TotalAmount = CASE WHEN cp.DiscountType = 'Percentage'
                       THEN o.TotalAmount * (1 - cp.DiscountValue / 100)
                       ELSE o.TotalAmount - cp.DiscountValue END
FROM [Order] o
JOIN Coupon cp ON cp.CouponID = o.CouponID;

-- ===== Payments (order 2 has a failed attempt followed by a successful retry) =====
INSERT INTO Payment (OrderID, Method, Amount, Status, TransactionDate)
SELECT o.OrderID, x.Method, o.TotalAmount, x.Status, DATEADD(MINUTE, x.MinutesAfter, o.OrderDate)
FROM (VALUES
    ('2026-01-10T11:20:00', 'Credit Card', 'Completed', 2),
    ('2026-01-25T15:45:00', 'Credit Card', 'Failed', 1),
    ('2026-01-25T15:45:00', 'JazzCash', 'Completed', 10),
    ('2026-02-14T09:10:00', 'Easypaisa', 'Completed', 3),
    ('2026-02-28T18:30:00', 'Credit Card', 'Completed', 2),
    ('2026-03-12T13:05:00', 'Cash on Delivery', 'Completed', 4320),
    ('2026-04-03T10:00:00', 'JazzCash', 'Completed', 5),
    ('2026-04-19T16:40:00', 'Credit Card', 'Refunded', 3),
    ('2026-04-22T12:25:00', 'Bank Transfer', 'Completed', 30),
    ('2026-05-30T14:15:00', 'Cash on Delivery', 'Completed', 5760),
    ('2026-06-18T19:50:00', 'Easypaisa', 'Completed', 4),
    ('2026-07-07T11:35:00', 'Credit Card', 'Completed', 2),
    ('2026-08-02T10:55:00', 'JazzCash', 'Completed', 6),
    ('2026-08-21T17:20:00', 'Cash on Delivery', 'Pending', 0),
    ('2026-09-05T09:45:00', 'Credit Card', 'Completed', 2)
) AS x (OrderDate, Method, Status, MinutesAfter)
JOIN [Order] o ON o.OrderDate = CONVERT(DATETIME2, x.OrderDate, 126);

-- ===== Shipments (one per order, sent to the customer's saved address) =====
INSERT INTO Shipment (OrderID, AddressID, Carrier, TrackingNumber, Status, ShippedDate, DeliveredDate)
SELECT o.OrderID, a.AddressID, x.Carrier, x.Tracking, x.Status,
       DATEADD(DAY, x.ShipDays, o.OrderDate), DATEADD(DAY, x.DeliverDays, o.OrderDate)
FROM (VALUES
    ('2026-01-10T11:20:00', 'TCS', 'TRK-1001', 'Delivered', 1, 3),
    ('2026-01-25T15:45:00', 'Leopards', 'TRK-1002', 'Delivered', 1, 4),
    ('2026-02-14T09:10:00', 'TCS', 'TRK-1003', 'Delivered', 1, 2),
    ('2026-02-28T18:30:00', 'M&P', 'TRK-1004', 'Delivered', 2, 5),
    ('2026-03-12T13:05:00', 'TCS', 'TRK-1005', 'Delivered', 1, 3),
    ('2026-04-03T10:00:00', 'Leopards', 'TRK-1006', 'Delivered', 1, 3),
    ('2026-04-19T16:40:00', NULL, NULL, 'Cancelled', NULL, NULL),
    ('2026-04-22T12:25:00', 'TCS', 'TRK-1008', 'Delivered', 1, 2),
    ('2026-05-30T14:15:00', 'Pakistan Post', 'TRK-1009', 'Delivered', 2, 6),
    ('2026-06-18T19:50:00', 'TCS', 'TRK-1010', 'Shipped', 1, NULL),
    ('2026-07-07T11:35:00', 'Leopards', 'TRK-1011', 'Shipped', 1, NULL),
    ('2026-08-02T10:55:00', NULL, NULL, 'Processing', NULL, NULL),
    ('2026-08-21T17:20:00', NULL, NULL, 'Processing', NULL, NULL),
    ('2026-09-05T09:45:00', NULL, NULL, 'Processing', NULL, NULL)
) AS x (OrderDate, Carrier, Tracking, Status, ShipDays, DeliverDays)
JOIN [Order] o ON o.OrderDate = CONVERT(DATETIME2, x.OrderDate, 126)
JOIN Address a ON a.CustomerID = o.CustomerID;

-- ===== Reviews =====
INSERT INTO Review (ProductID, CustomerID, Rating, Comment)
SELECT p.ProductID, c.CustomerID, x.Rating, x.Comment
FROM (VALUES
    ('ali.raza@example.com', 'Wireless Bluetooth Earbuds', 5, 'Great sound and battery life'),
    ('sara.khan@example.com', 'Men''s Casual Shirt', 4, 'Good fit, fabric is soft'),
    ('sara.khan@example.com', 'Women''s Kurti', 5, 'Lovely print and comfortable'),
    ('bilal.ahmed@example.com', 'Slim Laptop 14-inch', 4, 'Fast and light for daily work'),
    ('ayesha.malik@example.com', 'Non-Stick Cookware Set', 5, 'Cooks evenly and cleans easily'),
    ('ayesha.malik@example.com', 'Electric Kettle 1.7L', 3, 'Works fine but a bit noisy'),
    ('usman.tariq@example.com', 'Running Shoes', 4, 'Comfortable for long runs'),
    ('usman.tariq@example.com', 'Yoga Mat', 2, 'Too thin for my liking'),
    ('zain.abbas@example.com', 'Gaming Laptop 15.6-inch', 5, 'Excellent performance for the price'),
    ('mahnoor.iqbal@example.com', 'Women''s Kurti', 4, 'Good quality cotton'),
    ('hamza.sheikh@example.com', 'Adjustable Dumbbell Set', 3, 'Locking mechanism feels loose'),
    ('fatima.noor@example.com', 'Wireless Bluetooth Earbuds', 4, 'Nice, but the case is a little bulky'),
    ('ali.raza@example.com', 'Wireless Mouse', 5, 'Smooth and quiet clicks'),
    ('ali.raza@example.com', 'Smartphone 128GB', 4, 'Smooth display and a decent camera'),
    ('danish.aslam@example.com', 'Men''s Denim Jeans', 3, 'Runs slightly small')
) AS x (Email, ProductName, Rating, Comment)
JOIN Customer c ON c.Email = x.Email
JOIN Product p ON p.Name = x.ProductName;

-- ===== Wishlists =====
INSERT INTO WishlistItem (CustomerID, ProductID)
SELECT c.CustomerID, p.ProductID
FROM (VALUES
    ('kinza.yousaf@example.com', 'Gaming Laptop 15.6-inch'),
    ('kinza.yousaf@example.com', 'Wireless Charging Pad'),
    ('rehan.qureshi@example.com', 'Smartphone 128GB'),
    ('rehan.qureshi@example.com', 'Running Shoes'),
    ('sana.riaz@example.com', 'Women''s Handbag'),
    ('sana.riaz@example.com', 'Table Lamp'),
    ('omar.farooq@example.com', 'Slim Laptop 14-inch'),
    ('ali.raza@example.com', 'Gaming Laptop 15.6-inch'),
    ('sara.khan@example.com', 'Women''s Handbag'),
    ('bilal.ahmed@example.com', 'Wireless Mouse'),
    ('hira.fatima@example.com', 'Novel: The Silent Patient'),
    ('usman.tariq@example.com', 'Adjustable Dumbbell Set'),
    ('zain.abbas@example.com', 'Laptop Backpack')
) AS x (Email, ProductName)
JOIN Customer c ON c.Email = x.Email
JOIN Product p ON p.Name = x.ProductName;
GO