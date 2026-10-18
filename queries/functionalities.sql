-- =====================================================================
-- ShopSphere: Phase 2 - Functionalities
-- Noor Fatima | 23L-0946

-- Parts 1-4 only read data. Part 5 (19-24) changes data, so it comes
-- last and the earlier results stay the same.
-- =====================================================================

USE shopsphere;
GO

-- =====================================================================
-- PART 1: Browsing and searching the catalog
-- =====================================================================

-- Functionality 1: Browse the catalog with each product's category and seller
-- Keywords: SELECT, JOIN, ORDER BY
SELECT p.Name AS Product, c.Name AS Category, s.StoreName AS Seller, p.BasePrice
FROM Product p
JOIN Category c ON p.CategoryID = c.CategoryID
JOIN Seller s ON p.SellerID = s.SellerID
ORDER BY c.Name, p.Name;

-- Functionality 2: Search products by keyword in the name or description
-- Keywords: SELECT, WHERE, LIKE
SELECT ProductID, Name, Description, BasePrice
FROM Product
WHERE Name LIKE '%Laptop%' OR Description LIKE '%laptop%';

-- Functionality 3: Low-stock alert for variants that need restocking
-- Keywords: SELECT, JOIN, WHERE, ORDER BY
SELECT p.Name AS Product, v.SKU, v.Size, v.Color, v.StockQty
FROM ProductVariant v
JOIN Product p ON v.ProductID = p.ProductID
WHERE v.StockQty < 10
ORDER BY v.StockQty ASC, p.Name;

-- =====================================================================
-- PART 2: Customers, orders and sales reports
-- =====================================================================

-- Functionality 4: View a customer's order history, newest first
-- Keywords: SELECT, JOIN, WHERE, ORDER BY
SELECT o.OrderID, o.OrderDate, o.Status, o.TotalAmount
FROM [Order] o
JOIN Customer c ON o.CustomerID = c.CustomerID
WHERE c.Email = 'ali.raza@example.com'
ORDER BY o.OrderDate DESC;

-- Functionality 5: Show the value of each customer's shopping cart
-- Keywords: SELECT, JOIN, GROUP BY, COUNT, SUM, ORDER BY
SELECT c.Name AS Customer, COUNT(ci.CartItemID) AS LinesInCart,
       SUM(ci.Quantity * v.Price) AS CartTotal
FROM Cart ct
JOIN Customer c ON ct.CustomerID = c.CustomerID
JOIN CartItem ci ON ci.CartID = ct.CartID
JOIN ProductVariant v ON ci.VariantID = v.VariantID
GROUP BY c.CustomerID, c.Name
ORDER BY CartTotal DESC;

-- Functionality 6: Rank products by units sold, ignoring cancelled orders
-- Keywords: SELECT, JOIN, WHERE, GROUP BY, SUM, ORDER BY
SELECT p.Name AS Product, SUM(oi.Quantity) AS UnitsSold
FROM OrderItem oi
JOIN [Order] o ON oi.OrderID = o.OrderID
JOIN ProductVariant v ON oi.VariantID = v.VariantID
JOIN Product p ON v.ProductID = p.ProductID
WHERE o.Status <> 'Cancelled'
GROUP BY p.ProductID, p.Name
ORDER BY UnitsSold DESC, p.Name;

-- Functionality 7: Find high-value customers who spent more than 50,000
-- Keywords: SELECT, JOIN, WHERE, GROUP BY, HAVING, COUNT, SUM, ORDER BY
SELECT c.Name AS Customer, COUNT(o.OrderID) AS Orders, SUM(o.TotalAmount) AS TotalSpent
FROM Customer c
JOIN [Order] o ON o.CustomerID = c.CustomerID
WHERE o.Status <> 'Cancelled'
GROUP BY c.CustomerID, c.Name
HAVING SUM(o.TotalAmount) > 50000
ORDER BY TotalSpent DESC;

-- Functionality 8: Monthly sales summary
-- Keywords: SELECT, WHERE, GROUP BY, COUNT, SUM, AVG, MIN, MAX, ORDER BY
SELECT YEAR(OrderDate) AS OrderYear, MONTH(OrderDate) AS OrderMonth,
       COUNT(*) AS Orders, SUM(TotalAmount) AS Revenue,
       AVG(TotalAmount) AS AvgOrderValue,
       MIN(TotalAmount) AS SmallestOrder, MAX(TotalAmount) AS LargestOrder
FROM [Order]
WHERE Status <> 'Cancelled'
GROUP BY YEAR(OrderDate), MONTH(OrderDate)
ORDER BY OrderYear, OrderMonth;

-- Functionality 9: Average rating of products that have at least 2 reviews
-- Keywords: SELECT, JOIN, GROUP BY, HAVING, COUNT, AVG, ORDER BY
SELECT p.Name AS Product, COUNT(r.ReviewID) AS Reviews,
       AVG(CAST(r.Rating AS DECIMAL(3,2))) AS AvgRating
FROM Product p
JOIN Review r ON r.ProductID = p.ProductID
GROUP BY p.ProductID, p.Name
HAVING COUNT(r.ReviewID) >= 2
ORDER BY AvgRating DESC, p.Name;

-- =====================================================================
-- PART 3: Finding gaps and comparing data (outer joins and set operations)
-- =====================================================================

-- Functionality 10: List customers who have never placed an order
-- Keywords: SELECT, LEFT JOIN, WHERE, ORDER BY
SELECT c.CustomerID, c.Name, c.Email
FROM Customer c
LEFT JOIN [Order] o ON o.CustomerID = c.CustomerID
WHERE o.OrderID IS NULL
ORDER BY c.Name;

-- Functionality 11: List product variants that have never been ordered
-- Keywords: SELECT, LEFT JOIN, JOIN, WHERE, ORDER BY
SELECT p.Name AS Product, v.SKU, v.StockQty
FROM ProductVariant v
JOIN Product p ON v.ProductID = p.ProductID
LEFT JOIN OrderItem oi ON oi.VariantID = v.VariantID
WHERE oi.OrderItemID IS NULL
ORDER BY p.Name, v.SKU;

-- Functionality 12: Show how often each coupon was used, including unused coupons
-- Keywords: SELECT, RIGHT JOIN, GROUP BY, COUNT, ORDER BY
SELECT cp.Code, cp.DiscountType, cp.DiscountValue, cp.ExpiryDate,
       COUNT(o.OrderID) AS TimesUsed
FROM [Order] o
RIGHT JOIN Coupon cp ON o.CouponID = cp.CouponID
GROUP BY cp.Code, cp.DiscountType, cp.DiscountValue, cp.ExpiryDate
ORDER BY TimesUsed DESC, cp.Code;

-- Functionality 13: Compare customers who have a cart with customers who have ordered
-- Keywords: SELECT, FULL OUTER JOIN (outer join), JOIN, ORDER BY
SELECT COALESCE(cc.Name, oc.Name) AS Customer,
       CASE WHEN cc.CustomerID IS NOT NULL THEN 'Yes' ELSE 'No' END AS HasCart,
       CASE WHEN oc.CustomerID IS NOT NULL THEN 'Yes' ELSE 'No' END AS HasOrders
FROM (SELECT DISTINCT c.CustomerID, c.Name
      FROM Customer c
      JOIN Cart ct ON ct.CustomerID = c.CustomerID) cc
FULL OUTER JOIN
     (SELECT DISTINCT c.CustomerID, c.Name
      FROM Customer c
      JOIN [Order] o ON o.CustomerID = c.CustomerID) oc
     ON cc.CustomerID = oc.CustomerID
ORDER BY Customer;

-- Functionality 14: Find customers who have both placed an order and written a review
-- Keywords: SELECT, WHERE, INTERSECT, nested query
SELECT Name
FROM Customer
WHERE CustomerID IN (SELECT CustomerID FROM [Order]
                     INTERSECT
                     SELECT CustomerID FROM Review)
ORDER BY Name;

-- Functionality 15: Find products that have never been ordered
-- Keywords: SELECT, WHERE, EXCEPT, nested query, JOIN
SELECT Name, BasePrice
FROM Product
WHERE ProductID IN (SELECT ProductID FROM Product
                    EXCEPT
                    SELECT v.ProductID
                    FROM OrderItem oi
                    JOIN ProductVariant v ON oi.VariantID = v.VariantID)
ORDER BY Name;

-- Functionality 16: List every customer showing interest, by ordering or by wishlisting
-- Keywords: SELECT, JOIN, UNION, ORDER BY
SELECT c.Name, 'Placed an order' AS Interest
FROM Customer c
JOIN [Order] o ON o.CustomerID = c.CustomerID
UNION
SELECT c.Name, 'Wishlisted a product' AS Interest
FROM Customer c
JOIN WishlistItem w ON w.CustomerID = c.CustomerID
ORDER BY Name, Interest;

-- =====================================================================
-- PART 4: Nested queries
-- =====================================================================

-- Functionality 17: List products priced above the catalog average
-- Keywords: SELECT, WHERE, nested query, AVG, ORDER BY
SELECT Name, BasePrice
FROM Product
WHERE BasePrice > (SELECT AVG(BasePrice) FROM Product)
ORDER BY BasePrice DESC;

-- Functionality 18: Find who bought the most expensive item ever sold
-- Keywords: SELECT, JOIN, WHERE, nested query, MAX
SELECT DISTINCT c.Name AS Customer, p.Name AS Product, oi.UnitPrice
FROM OrderItem oi
JOIN [Order] o ON oi.OrderID = o.OrderID
JOIN Customer c ON o.CustomerID = c.CustomerID
JOIN ProductVariant v ON oi.VariantID = v.VariantID
JOIN Product p ON v.ProductID = p.ProductID
WHERE oi.UnitPrice = (SELECT MAX(UnitPrice) FROM OrderItem);

-- =====================================================================
-- PART 5: Changing data (insert, update, delete) - run once
-- =====================================================================

-- Functionality 19: Register a new customer
-- Keywords: INSERT
INSERT INTO Customer (Name, Email, Password, Phone)
VALUES ('Maryam Aslam', 'maryam.aslam@example.com', 'hashed_pw_016', '03111234567');

-- Functionality 20: Save a shipping address for the new customer
-- Keywords: INSERT, nested query
INSERT INTO Address (CustomerID, Line1, City, PostalCode, Country, AddressType)
VALUES ((SELECT CustomerID FROM Customer WHERE Email = 'maryam.aslam@example.com'),
        'House 40, Garden Town', 'Lahore', '54000', 'Pakistan', 'Shipping');

-- Functionality 21: Restock a low-stock variant after a supplier delivery
-- Keywords: UPDATE, WHERE
UPDATE ProductVariant
SET StockQty = StockQty + 25
WHERE SKU = 'LP-LED-WHT';

-- Functionality 22: Cancel a customer's pending order
-- Keywords: UPDATE, WHERE, nested query
UPDATE [Order]
SET Status = 'Cancelled'
WHERE Status = 'Pending'
  AND CustomerID = (SELECT CustomerID FROM Customer WHERE Email = 'danish.aslam@example.com');

-- Functionality 23: Remove a product from a customer's wishlist
-- Keywords: DELETE, WHERE, nested query
DELETE FROM WishlistItem
WHERE CustomerID = (SELECT CustomerID FROM Customer WHERE Email = 'sana.riaz@example.com')
  AND ProductID = (SELECT ProductID FROM Product WHERE Name = 'Table Lamp');

-- Functionality 24: Delete expired coupons that were never used on an order
-- Keywords: DELETE, WHERE, nested query
DELETE FROM Coupon
WHERE ExpiryDate < CAST(GETDATE() AS DATE)
  AND CouponID NOT IN (SELECT CouponID FROM [Order] WHERE CouponID IS NOT NULL);
GO
