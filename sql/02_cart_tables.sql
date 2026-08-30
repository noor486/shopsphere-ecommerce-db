USE shopsphere;
GO

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

CREATE TABLE Cart (
    CartID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    CreatedAt DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT FK_Cart_Customer FOREIGN KEY (CustomerID)
        REFERENCES Customer(CustomerID)
);

CREATE TABLE CartItem (
    CartItemID INT IDENTITY(1,1) PRIMARY KEY,
    CartID INT NOT NULL,
    VariantID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    CONSTRAINT FK_CartItem_Cart FOREIGN KEY (CartID)
        REFERENCES Cart(CartID),
    CONSTRAINT FK_CartItem_Variant FOREIGN KEY (VariantID)
        REFERENCES ProductVariant(VariantID)
);