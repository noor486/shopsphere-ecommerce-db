USE shopsphere;
GO

CREATE TABLE [Order] (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT NOT NULL,
    AddressID INT NOT NULL,
    OrderDate DATETIME2 DEFAULT GETDATE(),
    Status NVARCHAR(30) DEFAULT 'Pending',
    TotalAmount DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (TotalAmount >= 0),
    CONSTRAINT FK_Order_Customer FOREIGN KEY (CustomerID)
        REFERENCES Customer(CustomerID),
    CONSTRAINT FK_Order_Address FOREIGN KEY (AddressID)
        REFERENCES Address(AddressID)
);

CREATE TABLE OrderItem (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    VariantID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10,2) NOT NULL CHECK (UnitPrice >= 0),
    CONSTRAINT FK_OrderItem_Order FOREIGN KEY (OrderID)
        REFERENCES [Order](OrderID),
    CONSTRAINT FK_OrderItem_Variant FOREIGN KEY (VariantID)
        REFERENCES ProductVariant(VariantID)
);

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

CREATE TABLE Shipment (
    ShipmentID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT NOT NULL,
    Carrier NVARCHAR(50),
    TrackingNumber NVARCHAR(50),
    Status NVARCHAR(30) DEFAULT 'Processing',
    ShippedDate DATETIME2 NULL,
    DeliveredDate DATETIME2 NULL,
    CONSTRAINT FK_Shipment_Order FOREIGN KEY (OrderID)
        REFERENCES [Order](OrderID)
);