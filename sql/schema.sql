-- ShopSphere: E-Commerce Shopping Store Database
-- Schema (DDL) -- SQL Server (T-SQL)
-- All 16 tables (normalized to BCNF, in dependency order), their indexes,
-- sample data, and the Phase 3 views and stored procedures.
-- Running this file drops and recreates the whole shopsphere database.

-- Switch away from shopsphere first, so the database can be dropped on a re-run.
USE master;
GO

IF DB_ID('shopsphere') IS NOT NULL
BEGIN
    ALTER DATABASE shopsphere SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE shopsphere;
END
GO

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
    CONSTRAINT FK_Category_Parent FOREIGN KEY (ParentCategoryID) REFERENCES Category(CategoryID)
);

CREATE TABLE Coupon (
    CouponID INT IDENTITY(1,1) PRIMARY KEY,
    Code NVARCHAR(30) NOT NULL UNIQUE,
    DiscountType NVARCHAR(20) NOT NULL
        CONSTRAINT CK_Coupon_Type CHECK (DiscountType IN ('Percentage','Fixed')),
    DiscountValue DECIMAL(10,2) NOT NULL CHECK (DiscountValue >= 0),
    ExpiryDate DATE NOT NULL,
    -- Table-level check (it reads two columns), so it needs the comma above.
    CONSTRAINT CK_Coupon_Pct CHECK (DiscountType <> 'Percentage' OR DiscountValue <= 100)
);

-- ===================== Depend on Customer =====================

CREATE TABLE Address (
    AddressID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    Line1 NVARCHAR(200) NOT NULL,
    City NVARCHAR(100) NOT NULL,
    PostalCode NVARCHAR(20),
    Country NVARCHAR(100) NOT NULL,
    AddressType NVARCHAR(20) DEFAULT 'Shipping'
    CONSTRAINT CK_Address_Type CHECK (AddressType IN ('Shipping','Billing')),    
    CONSTRAINT FK_Address_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID)
);

-- Each customer has exactly one persistent cart (true 1:1, enforced by UNIQUE).
CREATE TABLE Cart (
    CartID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL UNIQUE,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT FK_Cart_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID)
);

-- ===================== Depend on Category / Seller =====================

CREATE TABLE Product (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(200) NOT NULL,
    Description NVARCHAR(MAX),
    CategoryID INT NOT NULL,
    SellerID INT NOT NULL,
    BasePrice DECIMAL(10,2) NOT NULL CHECK (BasePrice >= 0),
    CONSTRAINT FK_Product_Category FOREIGN KEY (CategoryID) REFERENCES Category(CategoryID),
    CONSTRAINT FK_Product_Seller FOREIGN KEY (SellerID) REFERENCES Seller(SellerID)
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
    CONSTRAINT FK_Variant_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

CREATE TABLE ProductImage (
    ImageID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    URL NVARCHAR(300) NOT NULL,
    IsPrimary BIT DEFAULT 0,
    CONSTRAINT FK_ProductImage_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID)
);

-- A customer reviews a given product at most once.
CREATE TABLE Review (
    ReviewID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT NOT NULL,
    CustomerID INT NOT NULL,
    Rating INT NOT NULL CHECK (Rating BETWEEN 1 AND 5),
    Comment NVARCHAR(MAX),
    ReviewDate DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT FK_Review_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    CONSTRAINT FK_Review_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    CONSTRAINT UQ_Review_Customer_Product UNIQUE (CustomerID, ProductID)
);

CREATE TABLE WishlistItem (
    WishlistItemID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    ProductID INT NOT NULL,
    CONSTRAINT FK_Wishlist_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Wishlist_Product FOREIGN KEY (ProductID) REFERENCES Product(ProductID),
    CONSTRAINT UQ_Wishlist_Customer_Product UNIQUE (CustomerID, ProductID)
);

-- ===================== Depend on Cart / ProductVariant =====================

-- One line per variant per cart (composite candidate key).
CREATE TABLE CartItem (
    CartItemID INT IDENTITY(1,1) PRIMARY KEY,
    CartID INT NOT NULL,
    VariantID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    CONSTRAINT FK_CartItem_Cart FOREIGN KEY (CartID) REFERENCES Cart(CartID),
    CONSTRAINT FK_CartItem_Variant FOREIGN KEY (VariantID) REFERENCES ProductVariant(VariantID),
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
    CONSTRAINT CK_Order_Status CHECK (Status IN ('Pending','Processing','Shipped','Delivered','Cancelled')),
    TotalAmount DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (TotalAmount >= 0),
    CONSTRAINT FK_Order_Customer FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Order_Coupon FOREIGN KEY (CouponID) REFERENCES Coupon(CouponID)
);

-- One line per variant per order, composite candidate key.
-- UnitPrice is a deliberate snapshot of the price at purchase time.
CREATE TABLE OrderItem (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    VariantID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL CHECK (UnitPrice >= 0),
    CONSTRAINT FK_OrderItem_Order FOREIGN KEY (OrderID) REFERENCES [Order](OrderID),
    CONSTRAINT FK_OrderItem_Variant FOREIGN KEY (VariantID) REFERENCES ProductVariant(VariantID),
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
    CONSTRAINT CK_Payment_Status CHECK (Status IN ('Pending','Completed','Failed','Refunded','Cancelled')),
    TransactionDate DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT FK_Payment_Order FOREIGN KEY (OrderID) REFERENCES [Order](OrderID)
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
    CONSTRAINT CK_Shipment_Status CHECK (Status IN ('Processing','Shipped','Delivered','Cancelled')),
    ShippedDate DATETIME2 NULL,
    DeliveredDate DATETIME2 NULL,
    CONSTRAINT FK_Shipment_Order FOREIGN KEY (OrderID) REFERENCES [Order](OrderID),
    CONSTRAINT FK_Shipment_Address FOREIGN KEY (AddressID) REFERENCES Address(AddressID)
);
GO

-- ===================== INDEXES =====================
-- Foreign key columns and searched columns, so joins and lookups do not
-- scan whole tables. Columns that already lead a PRIMARY KEY or UNIQUE
-- constraint (e.g. ProductVariant.SKU, Cart.CustomerID, CartItem.CartID,
-- OrderItem.OrderID, Review.CustomerID, Shipment.OrderID) are indexed
-- automatically and are not repeated here.
CREATE INDEX IX_Address_Customer     ON Address(CustomerID);
CREATE INDEX IX_Category_Parent      ON Category(ParentCategoryID);
CREATE INDEX IX_Product_Category     ON Product(CategoryID);
CREATE INDEX IX_Product_Seller       ON Product(SellerID);
CREATE INDEX IX_Product_Name         ON Product(Name);
CREATE INDEX IX_Variant_Product      ON ProductVariant(ProductID);
CREATE INDEX IX_Image_Product        ON ProductImage(ProductID);
CREATE INDEX IX_Review_Product       ON Review(ProductID);
CREATE INDEX IX_Wishlist_Product     ON WishlistItem(ProductID);
CREATE INDEX IX_CartItem_Variant     ON CartItem(VariantID);
CREATE INDEX IX_Order_Customer       ON [Order](CustomerID);
CREATE INDEX IX_Order_Coupon         ON [Order](CouponID);
CREATE INDEX IX_Order_Date           ON [Order](OrderDate);
CREATE INDEX IX_OrderItem_Variant    ON OrderItem(VariantID);
CREATE INDEX IX_Payment_Order        ON Payment(OrderID);
CREATE INDEX IX_Shipment_Address     ON Shipment(AddressID);
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
('HomeEase Essentials', 'contact@homeease.example.com', 4.50),
('GlowHouse Beauty', 'contact@glowhouse.example.com', 4.40);

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

-- More subcategories: a subcategory is a category whose parent is another category.
INSERT INTO Category (Name, ParentCategoryID) VALUES ('Beauty & Personal Care', NULL);

INSERT INTO Category (Name, ParentCategoryID) VALUES
('Men''s Footwear', (SELECT CategoryID FROM Category WHERE Name = 'Fashion')),
('Men''s Accessories', (SELECT CategoryID FROM Category WHERE Name = 'Fashion')),
('Women''s Footwear', (SELECT CategoryID FROM Category WHERE Name = 'Fashion')),
('Women''s Accessories', (SELECT CategoryID FROM Category WHERE Name = 'Fashion')),
('Kids'' Clothing', (SELECT CategoryID FROM Category WHERE Name = 'Fashion')),
('Skincare', (SELECT CategoryID FROM Category WHERE Name = 'Beauty & Personal Care')),
('Fragrances', (SELECT CategoryID FROM Category WHERE Name = 'Beauty & Personal Care')),
('Audio', (SELECT CategoryID FROM Category WHERE Name = 'Electronics')),
('Computer Accessories', (SELECT CategoryID FROM Category WHERE Name = 'Electronics'));

-- Bath and body section: one main category with four subcategories.
INSERT INTO Category (Name, ParentCategoryID) VALUES ('Bath & Body', NULL);

INSERT INTO Category (Name, ParentCategoryID) VALUES
('Towels & Bath Robes', (SELECT CategoryID FROM Category WHERE Name = 'Bath & Body')),
('Body Wash & Soap', (SELECT CategoryID FROM Category WHERE Name = 'Bath & Body')),
('Bath Accessories', (SELECT CategoryID FROM Category WHERE Name = 'Bath & Body')),
('Hair Care', (SELECT CategoryID FROM Category WHERE Name = 'Bath & Body'));

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
('Women''s Handbag', 'Faux leather shoulder bag', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 2799.00),
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

-- ===== More products (numbers 21 to 64) =====
INSERT INTO Product (Name, Description, CategoryID, SellerID, BasePrice)
VALUES
('Men''s Polo Shirt', 'Soft cotton polo shirt with a classic collar', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1799.00),
('Men''s Graphic T-Shirt', 'Round-neck cotton t-shirt with a printed design', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1299.00),
('Men''s Chino Trousers', 'Slim-fit cotton chino trousers for work or weekends', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 3499.00),
('Men''s Zip Hoodie', 'Warm fleece hoodie with a front zip and pockets', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 3999.00),
('Men''s Winter Jacket', 'Padded winter jacket with a water-resistant outer layer', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 7999.00),
('Men''s Cotton Shalwar Kameez', 'Two-piece cotton shalwar kameez for daily and festive wear', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 4599.00),
('Men''s Leather Loafers', 'Slip-on leather loafers with a cushioned insole', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Footwear'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 5499.00),
('Men''s Canvas Sneakers', 'Lightweight canvas sneakers for everyday wear', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Footwear'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 3299.00),
('Men''s Leather Wallet', 'Slim leather wallet with card slots and a coin pocket', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1499.00),
('Men''s Analog Wrist Watch', 'Stainless steel analog watch with a date window', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 6999.00),
('Polarized Sunglasses', 'UV-protection polarized sunglasses with a light frame', (SELECT CategoryID FROM Category WHERE Name = 'Men''s Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 2499.00),
('Women''s Floral Maxi Dress', 'Flowing maxi dress with a floral print', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 4299.00),
('Women''s Embroidered Lawn Suit', 'Three-piece lawn suit with an embroidered neckline', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 5499.00),
('Women''s Denim Jacket', 'Classic denim jacket with a button front', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 3999.00),
('Women''s Block Heels', 'Comfortable block heels with an ankle strap', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Footwear'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 4499.00),
('Women''s Embroidered Khussa', 'Traditional khussa with embroidery', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Footwear'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 2799.00),
('Women''s Cotton Shawl', 'Light cotton shawl in a solid colour', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1799.00),
('Pearl Drop Earrings', 'Pearl-style drop earrings with silver-tone hooks', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1599.00),
('Women''s Silk Scarf', 'Smooth printed scarf that works all year', (SELECT CategoryID FROM Category WHERE Name = 'Women''s Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1399.00),
('Kids Cotton T-Shirt Set', 'Set of three soft cotton t-shirts for kids', (SELECT CategoryID FROM Category WHERE Name = 'Kids'' Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1599.00),
('Kids Denim Dungarees', 'Soft denim dungarees with adjustable straps', (SELECT CategoryID FROM Category WHERE Name = 'Kids'' Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 2199.00),
('Kids Winter Sweater', 'Warm knitted sweater for cold days', (SELECT CategoryID FROM Category WHERE Name = 'Kids'' Clothing'), (SELECT SellerID FROM Seller WHERE StoreName = 'StyleNest Fashion'), 1899.00),
('Bluetooth Speaker', 'Portable speaker with deep bass and a 12-hour battery', (SELECT CategoryID FROM Category WHERE Name = 'Audio'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 5999.00),
('Over-Ear Headphones', 'Wireless over-ear headphones with soft ear cushions', (SELECT CategoryID FROM Category WHERE Name = 'Audio'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 8499.00),
('Mechanical Keyboard', 'Full-size mechanical keyboard with backlit keys', (SELECT CategoryID FROM Category WHERE Name = 'Computer Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 6499.00),
('USB-C Hub', 'Seven-port USB-C hub with HDMI and a card reader', (SELECT CategoryID FROM Category WHERE Name = 'Computer Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 3299.00),
('Fast Charger 33W', '33W fast charger with a USB-C cable', (SELECT CategoryID FROM Category WHERE Name = 'Mobiles'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 1799.00),
('Laptop Sleeve 14-inch', 'Padded sleeve that protects a 14-inch laptop', (SELECT CategoryID FROM Category WHERE Name = 'Laptops'), (SELECT SellerID FROM Seller WHERE StoreName = 'TechHub Electronics'), 1299.00),
('Air Fryer 4L', 'Air fryer for crisp food with very little oil', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 14999.00),
('Ceramic Dinner Set 24-piece', 'Ceramic dinner set for six people', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 7499.00),
('Memory Foam Pillow', 'Supportive memory foam pillow for side and back sleepers', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 2499.00),
('Stainless Steel Water Bottle', 'Insulated bottle that keeps drinks cold or hot for hours', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1399.00),
('Wall Clock', 'Silent round wall clock for any room', (SELECT CategoryID FROM Category WHERE Name = 'Home & Kitchen'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1999.00),
('Novel: The Alchemist', 'Story of a shepherd who follows his dream', (SELECT CategoryID FROM Category WHERE Name = 'Books'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1099.00),
('Book: Rich Dad Poor Dad', 'Book about money habits and building wealth', (SELECT CategoryID FROM Category WHERE Name = 'Books'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1199.00),
('Book: Deep Work', 'Book about focusing without distraction', (SELECT CategoryID FROM Category WHERE Name = 'Books'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1399.00),
('Football Size 5', 'Stitched football for grass and hard ground', (SELECT CategoryID FROM Category WHERE Name = 'Sports & Outdoors'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 2199.00),
('Badminton Racket Set', 'Set of two rackets with shuttlecocks and a bag', (SELECT CategoryID FROM Category WHERE Name = 'Sports & Outdoors'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 3499.00),
('Camping Backpack 40L', 'Water-resistant 40 litre backpack for trips', (SELECT CategoryID FROM Category WHERE Name = 'Sports & Outdoors'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 5999.00),
('Daily Face Wash', 'Gentle face wash for everyday use', (SELECT CategoryID FROM Category WHERE Name = 'Skincare'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 899.00),
('Vitamin C Serum', 'Brightening serum for fresher-looking skin', (SELECT CategoryID FROM Category WHERE Name = 'Skincare'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 2199.00),
('Sunscreen SPF 50', 'Lightweight sunscreen with high sun protection', (SELECT CategoryID FROM Category WHERE Name = 'Skincare'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 1599.00),
('Men''s Eau de Parfum 100ml', 'Woody long-lasting fragrance for men', (SELECT CategoryID FROM Category WHERE Name = 'Fragrances'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 4999.00),
('Women''s Eau de Parfum 100ml', 'Floral long-lasting fragrance for women', (SELECT CategoryID FROM Category WHERE Name = 'Fragrances'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 5499.00);

-- ===== Bath and body products (numbers 65 to 79) =====
INSERT INTO Product (Name, Description, CategoryID, SellerID, BasePrice)
VALUES
('Cotton Bath Towel', 'Soft absorbent cotton bath towel, large size', (SELECT CategoryID FROM Category WHERE Name = 'Towels & Bath Robes'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1299.00),
('Hand Towel Set of 4', 'Four quick-drying cotton hand towels', (SELECT CategoryID FROM Category WHERE Name = 'Towels & Bath Robes'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1499.00),
('Hooded Kids Bath Towel', 'Soft hooded towel sized for children', (SELECT CategoryID FROM Category WHERE Name = 'Towels & Bath Robes'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1099.00),
('Cotton Bath Robe', 'Thick cotton bath robe with a belt and two pockets', (SELECT CategoryID FROM Category WHERE Name = 'Towels & Bath Robes'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 3999.00),
('Microfiber Hair Towel Wrap', 'Quick-dry microfiber wrap for drying long hair', (SELECT CategoryID FROM Category WHERE Name = 'Towels & Bath Robes'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 899.00),
('Moisturizing Body Wash 500ml', 'Gentle body wash that leaves skin soft', (SELECT CategoryID FROM Category WHERE Name = 'Body Wash & Soap'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 1199.00),
('Shower Gel 250ml', 'Fresh-smelling shower gel for daily use', (SELECT CategoryID FROM Category WHERE Name = 'Body Wash & Soap'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 799.00),
('Natural Soap Bar Pack of 6', 'Six plant-based soap bars', (SELECT CategoryID FROM Category WHERE Name = 'Body Wash & Soap'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 999.00),
('Coffee Body Scrub 200g', 'Exfoliating body scrub with ground coffee', (SELECT CategoryID FROM Category WHERE Name = 'Body Wash & Soap'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 1399.00),
('Bath Loofah Sponge Set', 'Set of three loofah sponges for the shower', (SELECT CategoryID FROM Category WHERE Name = 'Bath Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 499.00),
('Anti-Slip Bath Mat', 'Soft bath mat with a non-slip back', (SELECT CategoryID FROM Category WHERE Name = 'Bath Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1299.00),
('Shower Caddy Organizer', 'Hanging organizer for shampoo and soap', (SELECT CategoryID FROM Category WHERE Name = 'Bath Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 1999.00),
('Soap Dispenser Bottle', 'Refillable pump bottle for liquid soap', (SELECT CategoryID FROM Category WHERE Name = 'Bath Accessories'), (SELECT SellerID FROM Seller WHERE StoreName = 'HomeEase Essentials'), 899.00),
('Daily Shampoo 400ml', 'Mild shampoo for everyday washing', (SELECT CategoryID FROM Category WHERE Name = 'Hair Care'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 1099.00),
('Conditioner 400ml', 'Smoothing conditioner for soft, manageable hair', (SELECT CategoryID FROM Category WHERE Name = 'Hair Care'), (SELECT SellerID FROM Seller WHERE StoreName = 'GlowHouse Beauty'), 1099.00);

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
    ('Laptop Backpack', 'BP-156-GRY', '15.6-inch', 'Grey', 2599.00, 20),
    ('Men''s Polo Shirt', 'PO-M-NVY', 'M', 'Navy', 1799.00, 24),
    ('Men''s Polo Shirt', 'PO-L-NVY', 'L', 'Navy', 1799.00, 18),
    ('Men''s Polo Shirt', 'PO-L-WHT', 'L', 'White', 1799.00, 6),
    ('Men''s Graphic T-Shirt', 'GT-M-BLK', 'M', 'Black', 1299.00, 30),
    ('Men''s Graphic T-Shirt', 'GT-L-BLK', 'L', 'Black', 1299.00, 26),
    ('Men''s Chino Trousers', 'CH-32-KHK', '32', 'Khaki', 3499.00, 14),
    ('Men''s Chino Trousers', 'CH-34-OLV', '34', 'Olive', 3499.00, 9),
    ('Men''s Zip Hoodie', 'HD-M-GRY', 'M', 'Grey', 3999.00, 12),
    ('Men''s Zip Hoodie', 'HD-L-NVY', 'L', 'Navy', 3999.00, 7),
    ('Men''s Winter Jacket', 'JK-L-BLK', 'L', 'Black', 7999.00, 8),
    ('Men''s Winter Jacket', 'JK-XL-BLK', 'XL', 'Black', 7999.00, 5),
    ('Men''s Cotton Shalwar Kameez', 'SK-M-WHT', 'M', 'White', 4599.00, 15),
    ('Men''s Cotton Shalwar Kameez', 'SK-L-CRM', 'L', 'Cream', 4599.00, 11),
    ('Men''s Leather Loafers', 'LF-42-BRN', '42', 'Brown', 5499.00, 9),
    ('Men''s Leather Loafers', 'LF-43-BLK', '43', 'Black', 5499.00, 12),
    ('Men''s Canvas Sneakers', 'SN-41-WHT', '41', 'White', 3299.00, 20),
    ('Men''s Canvas Sneakers', 'SN-43-WHT', '43', 'White', 3299.00, 16),
    ('Men''s Leather Wallet', 'WL-BLK', 'Standard', 'Black', 1499.00, 35),
    ('Men''s Leather Wallet', 'WL-BRN', 'Standard', 'Brown', 1499.00, 28),
    ('Men''s Analog Wrist Watch', 'MW-SLV', 'Standard', 'Silver', 6999.00, 7),
    ('Polarized Sunglasses', 'SG-BLK', 'Standard', 'Black', 2499.00, 22),
    ('Women''s Floral Maxi Dress', 'MD-S-FLR', 'S', 'Floral', 4299.00, 10),
    ('Women''s Floral Maxi Dress', 'MD-M-FLR', 'M', 'Floral', 4299.00, 13),
    ('Women''s Embroidered Lawn Suit', 'LS-M-TEL', 'M', 'Teal', 5499.00, 14),
    ('Women''s Embroidered Lawn Suit', 'LS-L-MRN', 'L', 'Maroon', 5499.00, 6),
    ('Women''s Denim Jacket', 'DJ-S-BLU', 'S', 'Blue', 3999.00, 9),
    ('Women''s Denim Jacket', 'DJ-M-BLU', 'M', 'Blue', 3999.00, 11),
    ('Women''s Block Heels', 'BH-37-BLK', '37', 'Black', 4499.00, 8),
    ('Women''s Block Heels', 'BH-38-NUD', '38', 'Nude', 4499.00, 10),
    ('Women''s Embroidered Khussa', 'KH-37-GLD', '37', 'Gold', 2799.00, 12),
    ('Women''s Embroidered Khussa', 'KH-39-RED', '39', 'Red', 2799.00, 4),
    ('Women''s Cotton Shawl', 'SW-GRY', 'Standard', 'Grey', 1799.00, 25),
    ('Women''s Cotton Shawl', 'SW-MRN', 'Standard', 'Maroon', 1799.00, 18),
    ('Pearl Drop Earrings', 'PE-WHT', 'Standard', 'White', 1599.00, 30),
    ('Women''s Silk Scarf', 'SC-RED', 'Standard', 'Red', 1399.00, 19),
    ('Women''s Silk Scarf', 'SC-BLU', 'Standard', 'Blue', 1399.00, 15),
    ('Kids Cotton T-Shirt Set', 'KT-4Y', '4Y', 'Mixed', 1599.00, 22),
    ('Kids Cotton T-Shirt Set', 'KT-6Y', '6Y', 'Mixed', 1599.00, 17),
    ('Kids Denim Dungarees', 'KD-4Y', '4Y', 'Blue', 2199.00, 13),
    ('Kids Denim Dungarees', 'KD-6Y', '6Y', 'Blue', 2199.00, 9),
    ('Kids Winter Sweater', 'KS-4Y', '4Y', 'Red', 1899.00, 15),
    ('Kids Winter Sweater', 'KS-6Y', '6Y', 'Green', 1899.00, 3),
    ('Bluetooth Speaker', 'BS-BLK', 'Standard', 'Black', 5999.00, 18),
    ('Bluetooth Speaker', 'BS-BLU', 'Standard', 'Blue', 5999.00, 6),
    ('Over-Ear Headphones', 'HP-BLK', 'Standard', 'Black', 8499.00, 11),
    ('Mechanical Keyboard', 'KB-MEC-BLK', 'Standard', 'Black', 6499.00, 9),
    ('USB-C Hub', 'HB-7IN1', '7-in-1', 'Grey', 3299.00, 27),
    ('Fast Charger 33W', 'FC-33W', '33W', 'White', 1799.00, 40),
    ('Laptop Sleeve 14-inch', 'LS-14-GRY', '14-inch', 'Grey', 1299.00, 33),
    ('Air Fryer 4L', 'AF-4L', '4L', 'Black', 14999.00, 5),
    ('Ceramic Dinner Set 24-piece', 'DS-24', '24-piece', 'White', 7499.00, 8),
    ('Memory Foam Pillow', 'PL-MF', 'Standard', 'White', 2499.00, 21),
    ('Stainless Steel Water Bottle', 'WB-750-STL', '750ml', 'Steel', 1399.00, 34),
    ('Stainless Steel Water Bottle', 'WB-750-BLK', '750ml', 'Black', 1399.00, 29),
    ('Wall Clock', 'WC-30', '30cm', 'Black', 1999.00, 16),
    ('Novel: The Alchemist', 'BK-ALC', 'Paperback', 'N/A', 1099.00, 38),
    ('Book: Rich Dad Poor Dad', 'BK-RDPD', 'Paperback', 'N/A', 1199.00, 31),
    ('Book: Deep Work', 'BK-DW', 'Paperback', 'N/A', 1399.00, 3),
    ('Football Size 5', 'FB-5', 'Size 5', 'White', 2199.00, 26),
    ('Badminton Racket Set', 'BD-SET', '2 players', 'Red', 3499.00, 14),
    ('Camping Backpack 40L', 'CB-40', '40L', 'Green', 5999.00, 6),
    ('Daily Face Wash', 'FW-150', '150ml', 'N/A', 899.00, 60),
    ('Vitamin C Serum', 'VS-30', '30ml', 'N/A', 2199.00, 24),
    ('Sunscreen SPF 50', 'SS-50', '50ml', 'N/A', 1599.00, 32),
    ('Men''s Eau de Parfum 100ml', 'EM-100', '100ml', 'N/A', 4999.00, 12),
    ('Women''s Eau de Parfum 100ml', 'EW-100', '100ml', 'N/A', 5499.00, 9),
    ('Cotton Bath Towel', 'BT-WHT', 'Large', 'White', 1299.00, 40),
    ('Cotton Bath Towel', 'BT-GRY', 'Large', 'Grey', 1299.00, 28),
    ('Hand Towel Set of 4', 'HT-4PC', '4-piece', 'Mixed', 1499.00, 22),
    ('Hooded Kids Bath Towel', 'KBT-BLU', 'Kids', 'Blue', 1099.00, 16),
    ('Hooded Kids Bath Towel', 'KBT-PNK', 'Kids', 'Pink', 1099.00, 14),
    ('Cotton Bath Robe', 'BR-M-WHT', 'M', 'White', 3999.00, 12),
    ('Cotton Bath Robe', 'BR-L-WHT', 'L', 'White', 3999.00, 9),
    ('Cotton Bath Robe', 'BR-L-GRY', 'L', 'Grey', 3999.00, 5),
    ('Microfiber Hair Towel Wrap', 'HW-PNK', 'Standard', 'Pink', 899.00, 30),
    ('Moisturizing Body Wash 500ml', 'BW-500-LAV', '500ml', 'Lavender', 1199.00, 36),
    ('Moisturizing Body Wash 500ml', 'BW-500-OCN', '500ml', 'Ocean', 1199.00, 29),
    ('Shower Gel 250ml', 'SGL-250', '250ml', 'Mint', 799.00, 44),
    ('Natural Soap Bar Pack of 6', 'SP-6PK', '6-pack', 'N/A', 999.00, 52),
    ('Coffee Body Scrub 200g', 'BSC-200', '200g', 'N/A', 1399.00, 18),
    ('Bath Loofah Sponge Set', 'LF-3PC', '3-piece', 'Mixed', 499.00, 60),
    ('Anti-Slip Bath Mat', 'BM-60-GRY', '60x40cm', 'Grey', 1299.00, 24),
    ('Anti-Slip Bath Mat', 'BM-60-BLU', '60x40cm', 'Blue', 1299.00, 8),
    ('Shower Caddy Organizer', 'SCD-STL', 'Standard', 'Steel', 1999.00, 14),
    ('Soap Dispenser Bottle', 'SD-300', '300ml', 'White', 899.00, 31),
    ('Daily Shampoo 400ml', 'SH-400', '400ml', 'N/A', 1099.00, 40),
    ('Conditioner 400ml', 'CN-400', '400ml', 'N/A', 1099.00, 33)
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
-- NOTE: each order has a UNIQUE OrderDate; later inserts rely on this to find the order
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
-- NOTE: assumes exactly one address per customer in the sample data
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

-- #####################################################################
-- PHASE 3: VIEWS AND STORED PROCEDURES
-- The backend API (backend/ folder) uses all four objects.
--   View 1: vw_ProductCatalog   - one row per product, ready for browsing
--   View 2: vw_OrderSummary     - one row per order, with payment and shipment
--   Proc 1: sp_AddToCart        - add an item to a customer's cart
--   Proc 2: sp_PlaceOrder       - turn a customer's cart into an order
-- #####################################################################

-- =====================================================================
-- VIEW 1: vw_ProductCatalog
-- ---------------------------------------------------------------------
-- Description:
--   One row per product with everything a shopper sees on a product
--   card: category (and its parent category), seller, the cheapest and
--   dearest variant price, total stock across all variants, average
--   rating, number of reviews, and the main image.
--   Without this view, every catalog page would repeat the same five
--   joins and two GROUP BYs. Products with no variants or no reviews
--   still appear (LEFT JOIN), with zero stock and zero reviews.
-- Used by: GET /api/products, GET /api/products/:id
-- =====================================================================
CREATE VIEW vw_ProductCatalog AS
SELECT p.ProductID,
       p.Name                        AS ProductName,
       p.Description,
       p.BasePrice,
       c.CategoryID,
       c.Name                        AS CategoryName,
       c.ParentCategoryID,
       pc.Name                       AS ParentCategoryName,
       s.SellerID,
       s.StoreName                   AS SellerName,
       v.MinPrice,
       v.MaxPrice,
       ISNULL(v.VariantCount, 0)     AS VariantCount,
       ISNULL(v.TotalStock, 0)       AS TotalStock,
       ISNULL(r.ReviewCount, 0)      AS ReviewCount,
       r.AvgRating,
       (SELECT TOP 1 i.URL
        FROM ProductImage i
        WHERE i.ProductID = p.ProductID
        ORDER BY i.IsPrimary DESC, i.ImageID) AS ImageURL
FROM Product p
JOIN Category c       ON p.CategoryID = c.CategoryID
LEFT JOIN Category pc ON c.ParentCategoryID = pc.CategoryID
JOIN Seller s         ON p.SellerID = s.SellerID
LEFT JOIN (SELECT ProductID,
                  MIN(Price)    AS MinPrice,
                  MAX(Price)    AS MaxPrice,
                  COUNT(*)      AS VariantCount,
                  SUM(StockQty) AS TotalStock
           FROM ProductVariant
           GROUP BY ProductID) v ON v.ProductID = p.ProductID
LEFT JOIN (SELECT ProductID,
                  COUNT(*) AS ReviewCount,
                  CAST(AVG(CAST(Rating AS DECIMAL(4,2))) AS DECIMAL(3,2)) AS AvgRating
           FROM Review
           GROUP BY ProductID) r ON r.ProductID = p.ProductID;
GO

-- =====================================================================
-- VIEW 2: vw_OrderSummary
-- ---------------------------------------------------------------------
-- Description:
--   One row per order joining the customer, the coupon used, the item
--   count and subtotal (from OrderItem), the discount, the latest
--   payment attempt, and the shipment status with its destination city.
--   This is the "My Orders" screen for a customer and the order list
--   for an administrator.
--   Discount is Subtotal - TotalAmount, so it is derived, not stored.
--   An order can have several payments (e.g. a failed attempt then a
--   retry); the view shows only the most recent one (highest PaymentID).
-- Used by: GET /api/customers/:id/orders, GET /api/orders/:id,
--          and the result of sp_PlaceOrder
-- =====================================================================
CREATE VIEW vw_OrderSummary AS
SELECT o.OrderID,
       o.OrderDate,
       o.Status                      AS OrderStatus,
       c.CustomerID,
       c.Name                        AS CustomerName,
       c.Email                       AS CustomerEmail,
       cp.Code                       AS CouponCode,
       ISNULL(i.ItemCount, 0)        AS ItemCount,
       ISNULL(i.Subtotal, 0)         AS Subtotal,
       ISNULL(i.Subtotal, 0) - o.TotalAmount AS Discount,
       o.TotalAmount,
       pay.Method                    AS PaymentMethod,
       pay.Status                    AS PaymentStatus,
       s.Status                      AS ShipmentStatus,
       s.Carrier,
       s.TrackingNumber,
       a.City                        AS ShipToCity
FROM [Order] o
JOIN Customer c      ON o.CustomerID = c.CustomerID
LEFT JOIN Coupon cp  ON o.CouponID = cp.CouponID
LEFT JOIN (SELECT OrderID,
                  SUM(Quantity)             AS ItemCount,
                  SUM(Quantity * UnitPrice) AS Subtotal
           FROM OrderItem
           GROUP BY OrderID) i ON i.OrderID = o.OrderID
LEFT JOIN Payment pay ON pay.PaymentID = (SELECT MAX(p2.PaymentID)
                                          FROM Payment p2
                                          WHERE p2.OrderID = o.OrderID)
LEFT JOIN Shipment s ON s.OrderID = o.OrderID
LEFT JOIN Address a  ON s.AddressID = a.AddressID;
GO

-- =====================================================================
-- PROCEDURE 1: sp_AddToCart
-- ---------------------------------------------------------------------
-- Description:
--   Adds @Quantity units of a product variant to a customer's cart.
--   - Creates the customer's cart if they do not have one yet
--     (Customer-Cart is 1:1, enforced by UNIQUE on Cart.CustomerID).
--   - If the variant is already in the cart, it increases the quantity
--     instead of adding a second line (UNIQUE on CartID, VariantID).
--   - Refuses to put more units in the cart than are in stock.
--   Returns the customer's cart lines after the change.
-- Parameters:
--   @CustomerID  the shopper
--   @VariantID   the size/colour (SKU) being added
--   @Quantity    how many to add, default 1
-- Errors (THROW, so the API can show the message):
--   50001 bad quantity, 50002 unknown customer,
--   50003 unknown variant, 50004 not enough stock
-- Used by: POST /api/customers/:id/cart
-- =====================================================================
CREATE PROCEDURE sp_AddToCart
    @CustomerID INT,
    @VariantID  INT,
    @Quantity   INT = 1
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Check the inputs
    IF @Quantity IS NULL OR @Quantity < 1
        THROW 50001, 'Quantity must be at least 1.', 1;

    IF NOT EXISTS (SELECT 1 FROM Customer WHERE CustomerID = @CustomerID)
        THROW 50002, 'Customer not found.', 1;

    DECLARE @Stock INT;
    SELECT @Stock = StockQty FROM ProductVariant WHERE VariantID = @VariantID;

    IF @Stock IS NULL
        THROW 50003, 'Product variant not found.', 1;

    -- 2. Make sure the customer has a cart
    IF NOT EXISTS (SELECT 1 FROM Cart WHERE CustomerID = @CustomerID)
        INSERT INTO Cart (CustomerID) VALUES (@CustomerID);

    DECLARE @CartID INT;
    SELECT @CartID = CartID FROM Cart WHERE CustomerID = @CustomerID;

    -- 3. How many of this variant are already in the cart?
    DECLARE @InCart INT;
    SELECT @InCart = Quantity FROM CartItem WHERE CartID = @CartID AND VariantID = @VariantID;
    SET @InCart = ISNULL(@InCart, 0);

    IF @InCart + @Quantity > @Stock
        THROW 50004, 'Not enough stock for this item.', 1;

    -- 4. Add a new line, or increase the existing one
    IF @InCart = 0
        INSERT INTO CartItem (CartID, VariantID, Quantity)
        VALUES (@CartID, @VariantID, @Quantity);
    ELSE
        UPDATE CartItem
        SET Quantity = Quantity + @Quantity
        WHERE CartID = @CartID AND VariantID = @VariantID;

    -- 5. Return the updated cart
    SELECT ci.VariantID, p.ProductID, p.Name AS ProductName, v.SKU, v.Size, v.Color,
           ci.Quantity, v.Price, ci.Quantity * v.Price AS LineTotal
    FROM CartItem ci
    JOIN ProductVariant v ON ci.VariantID = v.VariantID
    JOIN Product p        ON v.ProductID = p.ProductID
    WHERE ci.CartID = @CartID
    ORDER BY p.Name;
END
GO

-- =====================================================================
-- PROCEDURE 2: sp_PlaceOrder
-- ---------------------------------------------------------------------
-- Description:
--   Checkout. Turns everything in the customer's cart into a new order:
--     a. creates the Order row (Status 'Pending')
--     b. copies each cart line into OrderItem, saving today's price
--        as UnitPrice
--     c. takes the ordered quantities off ProductVariant.StockQty
--     d. records a 'Pending' Payment for the order total
--     e. creates the Shipment ('Processing') to the chosen address
--     f. empties the cart
--   If a coupon code is given it must exist and not be expired;
--   Percentage coupons take a percent off, Fixed coupons take an
--   amount off (never below zero).
--   Returns the new order's row from vw_OrderSummary.
--
--   Note: every check runs BEFORE anything is written, so a rejected
--   checkout (empty cart, wrong address, low stock, bad coupon) changes
--   nothing. Steps a-f are not yet wrapped in a transaction; the
--   proposal requires that and it will be added in a later phase.
-- Parameters:
--   @CustomerID     the shopper
--   @AddressID      one of the shopper's own saved addresses
--   @PaymentMethod  e.g. 'Credit Card', 'JazzCash', 'Cash on Delivery'
--   @CouponCode     optional
-- Errors (THROW):
--   50010 empty cart, 50011 address not the customer's,
--   50012 not enough stock, 50013 bad or expired coupon,
--   50014 missing payment method
-- Used by: POST /api/customers/:id/orders
-- =====================================================================
CREATE PROCEDURE sp_PlaceOrder
    @CustomerID    INT,
    @AddressID     INT,
    @PaymentMethod NVARCHAR(30),
    @CouponCode    NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- ---------- 1. Checks (nothing is changed yet) ----------
    DECLARE @CartID INT;
    SELECT @CartID = CartID FROM Cart WHERE CustomerID = @CustomerID;

    IF @CartID IS NULL OR NOT EXISTS (SELECT 1 FROM CartItem WHERE CartID = @CartID)
        THROW 50010, 'The cart is empty.', 1;

    IF NOT EXISTS (SELECT 1 FROM Address WHERE AddressID = @AddressID AND CustomerID = @CustomerID)
        THROW 50011, 'That address does not belong to this customer.', 1;

    IF EXISTS (SELECT 1
               FROM CartItem ci
               JOIN ProductVariant v ON ci.VariantID = v.VariantID
               WHERE ci.CartID = @CartID AND ci.Quantity > v.StockQty)
        THROW 50012, 'Some items in the cart do not have enough stock.', 1;

    IF @PaymentMethod IS NULL OR LTRIM(RTRIM(@PaymentMethod)) = ''
        THROW 50014, 'A payment method is required.', 1;

    DECLARE @CouponID INT = NULL,
            @DiscountType NVARCHAR(20),
            @DiscountValue DECIMAL(10,2);

    IF @CouponCode IS NOT NULL AND LTRIM(RTRIM(@CouponCode)) <> ''
    BEGIN
        SELECT @CouponID = CouponID, @DiscountType = DiscountType, @DiscountValue = DiscountValue
        FROM Coupon
        WHERE Code = @CouponCode AND ExpiryDate >= CAST(GETDATE() AS DATE);

        IF @CouponID IS NULL
            THROW 50013, 'The coupon code is invalid or has expired.', 1;
    END

    -- ---------- 2. Work out the total ----------
    DECLARE @Subtotal DECIMAL(10,2), @Total DECIMAL(10,2);

    SELECT @Subtotal = SUM(ci.Quantity * v.Price)
    FROM CartItem ci
    JOIN ProductVariant v ON ci.VariantID = v.VariantID
    WHERE ci.CartID = @CartID;

    SET @Total = CASE
                     WHEN @CouponID IS NULL             THEN @Subtotal
                     WHEN @DiscountType = 'Percentage'  THEN @Subtotal * (1 - @DiscountValue / 100)
                     ELSE @Subtotal - @DiscountValue
                 END;

    IF @Total < 0 SET @Total = 0;

    -- ---------- 3. a. Create the order ----------
    INSERT INTO [Order] (CustomerID, CouponID, Status, TotalAmount)
    VALUES (@CustomerID, @CouponID, 'Pending', @Total);

    DECLARE @OrderID INT = SCOPE_IDENTITY();

    -- b. Copy the cart lines, saving the current price
    INSERT INTO OrderItem (OrderID, VariantID, Quantity, UnitPrice)
    SELECT @OrderID, ci.VariantID, ci.Quantity, v.Price
    FROM CartItem ci
    JOIN ProductVariant v ON ci.VariantID = v.VariantID
    WHERE ci.CartID = @CartID;

    -- c. Take the items out of stock
    UPDATE v
    SET v.StockQty = v.StockQty - ci.Quantity
    FROM ProductVariant v
    JOIN CartItem ci ON ci.VariantID = v.VariantID
    WHERE ci.CartID = @CartID;

    -- d. Record the payment as pending
    INSERT INTO Payment (OrderID, Method, Amount, Status)
    VALUES (@OrderID, @PaymentMethod, @Total, 'Pending');

    -- e. Create the shipment to the chosen address
    INSERT INTO Shipment (OrderID, AddressID, Status)
    VALUES (@OrderID, @AddressID, 'Processing');

    -- f. Empty the cart
    DELETE FROM CartItem WHERE CartID = @CartID;

    -- ---------- 4. Return the new order ----------
    SELECT * FROM vw_OrderSummary WHERE OrderID = @OrderID;
END
GO

-- =====================================================================
-- EXAMPLES: using the views and procedures
-- Commented out so that rebuilding the database keeps the sample data
-- exactly as above. Select a block and run it on its own in SSMS.
-- =====================================================================

-- View 1: browse the catalog, best-rated first
-- SELECT ProductName, CategoryName, SellerName, MinPrice, MaxPrice, TotalStock, ReviewCount, AvgRating
-- FROM vw_ProductCatalog
-- ORDER BY AvgRating DESC, ProductName;

-- View 1: everything under the Electronics department (the category or its subcategories)
-- SELECT ProductName, CategoryName, MinPrice, TotalStock
-- FROM vw_ProductCatalog
-- WHERE CategoryName = 'Electronics' OR ParentCategoryName = 'Electronics'
-- ORDER BY CategoryName, ProductName;

-- View 2: all orders, newest first
-- SELECT OrderID, OrderDate, CustomerName, OrderStatus, Subtotal, CouponCode, Discount,
--        TotalAmount, PaymentStatus, ShipmentStatus, ShipToCity
-- FROM vw_OrderSummary
-- ORDER BY OrderDate DESC;

-- View 2: orders that are paid but not yet delivered
-- SELECT OrderID, CustomerName, TotalAmount, ShipmentStatus, Carrier, TrackingNumber
-- FROM vw_OrderSummary
-- WHERE PaymentStatus = 'Completed' AND ShipmentStatus IN ('Processing', 'Shipped');

-- Procedure 1: Rehan's cart is empty; add one Yoga Mat, then one more (quantity becomes 2)
-- DECLARE @Rehan INT = (SELECT CustomerID FROM Customer WHERE Email = 'rehan.qureshi@example.com');
-- DECLARE @YogaMat INT = (SELECT VariantID FROM ProductVariant WHERE SKU = 'YM-6MM-PRP');
-- EXEC sp_AddToCart @CustomerID = @Rehan, @VariantID = @YogaMat, @Quantity = 1;
-- EXEC sp_AddToCart @CustomerID = @Rehan, @VariantID = @YogaMat;

-- Procedure 2: Kinza checks out her cart (charging pad + 2 books) with SAVE10
-- DECLARE @Kinza INT = (SELECT CustomerID FROM Customer WHERE Email = 'kinza.yousaf@example.com');
-- DECLARE @KinzaAddress INT = (SELECT TOP 1 AddressID FROM Address WHERE CustomerID = @Kinza);
-- EXEC sp_PlaceOrder @CustomerID = @Kinza, @AddressID = @KinzaAddress,
--                    @PaymentMethod = 'JazzCash', @CouponCode = 'SAVE10';
