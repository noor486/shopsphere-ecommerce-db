USE shopsphere;
GO

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

CREATE TABLE Coupon (
    CouponID INT IDENTITY(1,1) PRIMARY KEY,
    Code NVARCHAR(30) NOT NULL UNIQUE,
    DiscountType NVARCHAR(20) NOT NULL,
    DiscountValue DECIMAL(10,2) NOT NULL CHECK (DiscountValue >= 0),
    ExpiryDate DATE NOT NULL
);

CREATE TABLE OrderCoupon (
    OrderID INT NOT NULL,
    CouponID INT NOT NULL,
    PRIMARY KEY (OrderID, CouponID),
    CONSTRAINT FK_OrderCoupon_Order FOREIGN KEY (OrderID)
        REFERENCES [Order](OrderID),
    CONSTRAINT FK_OrderCoupon_Coupon FOREIGN KEY (CouponID)
        REFERENCES Coupon(CouponID)
);