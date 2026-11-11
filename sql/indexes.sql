-- ===================== Indexes (foreign keys and search columns) =====================
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