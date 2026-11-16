/* =====================================================================
   NovaStore E-Ticaret Veri Yönetim Sistemi
   Veri Tabanı ve SQL Projesi

   Hazırlayan : Efe Uğur
   Program    : 19. Dönem Yazılım Mesleki Gelişim Programı
   Eğitmen    : Salih Tekin
   Ortam      : Microsoft SQL Server (T-SQL), SSMS

   İÇİNDEKİLER
     BÖLÜM 0  Hazırlık (veri tabanı, güvenlik kontrolü, temizlik)
     BÖLÜM 1  Veri tabanı tasarımı (DDL)            -> yönerge Bölüm 1
     BÖLÜM 2  Veri girişi (DML)                     -> yönerge Bölüm 2
     BÖLÜM 3  Sorgulama ve analiz (DQL)             -> yönerge Bölüm 3
     BÖLÜM 4.1  View                                -> yönerge Bölüm 4.1
     EK A     Ek analiz sorguları (subquery, HAVING, CASE ...)
     EK B     Kısıt (constraint) testleri
     EK C     Transaction ile sipariş prosedürü
     EK D     Veri tutarlılığı kontrolü
     BÖLÜM 4.2  Yedekleme (BACKUP)                  -> yönerge Bölüm 4.2

   NOT: Bu dosya baştan sona tekrar tekrar çalıştırılabilir. Her çalıştırmada
   nesneler silinip yeniden kurulur, bu yüzden veriler çoğalmaz.
   ===================================================================== */


/* =====================================================================
   BÖLÜM 0: HAZIRLIK
   ===================================================================== */

-- 0.1 Veri tabanı yoksa oluştur (yönerge Bölüm 1, madde 1)
USE master;
GO

IF DB_ID(N'NovaStoreDB') IS NULL
    CREATE DATABASE NovaStoreDB;
GO

USE NovaStoreDB;
GO

-- 0.2 Güvenlik kontrolü: Yanlış veri tabanındaysak (örneğin master) devam etme.
--     SET NOEXEC ON açıkken sonraki komutlar derlenir ama ÇALIŞTIRILMAZ.
--     Böylece tablolar yanlışlıkla başka bir veri tabanına kurulmaz.
IF DB_NAME() <> N'NovaStoreDB'
BEGIN
    RAISERROR(N'Aktif veri tabanı NovaStoreDB değil. Script durduruldu.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- 0.3 Temizlik: Önce bağımlı nesneler, sonra ana tablolar silinir
--     (oluşturma sırasının tersi).
DROP VIEW IF EXISTS dbo.vw_SiparisOzet;
DROP VIEW IF EXISTS dbo.vw_KategoriSatis;
DROP PROCEDURE IF EXISTS dbo.usp_SiparisVer;
DROP TABLE IF EXISTS dbo.OrderDetails;
DROP TABLE IF EXISTS dbo.Orders;
DROP TABLE IF EXISTS dbo.Products;
DROP TABLE IF EXISTS dbo.Customers;
DROP TABLE IF EXISTS dbo.Categories;
GO


/* =====================================================================
   BÖLÜM 1: VERİ TABANI TASARIMI (DDL)
   Sıra: önce ana tablolar (Categories, Customers),
         sonra bağımlı tablolar (Products, Orders, OrderDetails).

   Yönergeye ek olarak yapılanlar:
     - Metin sütunlarında VARCHAR yerine NVARCHAR (ş, ğ, İ, ı gibi Türkçe
       harfler sunucu dil ayarından bağımsız olarak doğru saklansın diye).
       Uzunluklar yönergedekiyle aynıdır.
     - Tüm kısıtlara isim verildi (PK_, FK_, UQ_, CK_, DF_).
     - CHECK kısıtları: negatif fiyat/stok ve sıfır adet engellenir.
     - OrderDetails.UnitPrice: satış anındaki birim fiyat saklanır.
     - Yabancı anahtar sütunlarına index eklendi.
   ===================================================================== */

-- 1.A Categories (Kategoriler)
CREATE TABLE dbo.Categories
(
    CategoryID   INT IDENTITY(1,1) NOT NULL,
    CategoryName NVARCHAR(50)      NOT NULL,
    CONSTRAINT PK_Categories PRIMARY KEY (CategoryID),
    CONSTRAINT UQ_Categories_CategoryName UNIQUE (CategoryName)
);
GO

-- 1.C Customers (Müşteriler)
CREATE TABLE dbo.Customers
(
    CustomerID INT IDENTITY(1,1) NOT NULL,
    FullName   NVARCHAR(50)      NOT NULL,
    City       NVARCHAR(20)      NULL,
    Email      VARCHAR(100)      NOT NULL,
    CONSTRAINT PK_Customers PRIMARY KEY (CustomerID),
    CONSTRAINT UQ_Customers_Email UNIQUE (Email),
    CONSTRAINT CK_Customers_Email CHECK (Email LIKE '%_@_%._%')
);
GO

-- 1.B Products (Ürünler)
CREATE TABLE dbo.Products
(
    ProductID   INT IDENTITY(1,1) NOT NULL,
    ProductName NVARCHAR(100)     NOT NULL,
    Price       DECIMAL(10,2)     NOT NULL,
    Stock       INT               NOT NULL CONSTRAINT DF_Products_Stock DEFAULT (0),
    CategoryID  INT               NOT NULL,
    CONSTRAINT PK_Products PRIMARY KEY (ProductID),
    CONSTRAINT FK_Products_Categories FOREIGN KEY (CategoryID)
        REFERENCES dbo.Categories (CategoryID),
    CONSTRAINT CK_Products_Price CHECK (Price >= 0),
    CONSTRAINT CK_Products_Stock CHECK (Stock >= 0)
);
GO

-- 1.D Orders (Siparişler)
CREATE TABLE dbo.Orders
(
    OrderID     INT IDENTITY(1,1) NOT NULL,
    CustomerID  INT               NOT NULL,
    OrderDate   DATETIME          NOT NULL CONSTRAINT DF_Orders_OrderDate DEFAULT (GETDATE()),
    TotalAmount DECIMAL(10,2)     NOT NULL CONSTRAINT DF_Orders_TotalAmount DEFAULT (0),
    CONSTRAINT PK_Orders PRIMARY KEY (OrderID),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID)
        REFERENCES dbo.Customers (CustomerID),
    CONSTRAINT CK_Orders_TotalAmount CHECK (TotalAmount >= 0)
);
GO

-- 1.E OrderDetails (Sipariş Detayları - ara tablo)
--     Bir sipariş silinirse satırları da silinir (ON DELETE CASCADE).
--     Satılmış bir ürün ise silinemez (varsayılan davranış: NO ACTION).
CREATE TABLE dbo.OrderDetails
(
    DetailID  INT IDENTITY(1,1) NOT NULL,
    OrderID   INT               NOT NULL,
    ProductID INT               NOT NULL,
    Quantity  INT               NOT NULL,
    UnitPrice DECIMAL(10,2)     NOT NULL,
    CONSTRAINT PK_OrderDetails PRIMARY KEY (DetailID),
    CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (OrderID)
        REFERENCES dbo.Orders (OrderID) ON DELETE CASCADE,
    CONSTRAINT FK_OrderDetails_Products FOREIGN KEY (ProductID)
        REFERENCES dbo.Products (ProductID),
    CONSTRAINT UQ_OrderDetails_Order_Product UNIQUE (OrderID, ProductID),
    CONSTRAINT CK_OrderDetails_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_OrderDetails_UnitPrice CHECK (UnitPrice >= 0)
);
GO

-- 1.F Ek: Index'ler
--     SQL Server yabancı anahtar sütunlarına kendiliğinden index koymaz.
--     JOIN ve filtrelerde en çok kullanılan sütunlara non-clustered index eklendi.
--     (OrderDetails.OrderID için UQ_OrderDetails_Order_Product zaten index oluşturur.)
CREATE NONCLUSTERED INDEX IX_Products_CategoryID    ON dbo.Products (CategoryID);
CREATE NONCLUSTERED INDEX IX_Orders_CustomerID      ON dbo.Orders (CustomerID);
CREATE NONCLUSTERED INDEX IX_Orders_OrderDate       ON dbo.Orders (OrderDate);
CREATE NONCLUSTERED INDEX IX_OrderDetails_ProductID ON dbo.OrderDetails (ProductID);
GO


/* =====================================================================
   BÖLÜM 2: VERİ GİRİŞİ (DML - INSERT)
   ===================================================================== */

-- Görev 1: 5 kategori
INSERT INTO dbo.Categories (CategoryName)
VALUES (N'Elektronik'),
       (N'Giyim'),
       (N'Kitap'),
       (N'Kozmetik'),
       (N'Ev ve Yaşam');
GO

-- Görev 2: 12 ürün (her kategoride en az 2 ürün)
INSERT INTO dbo.Products (ProductName, Price, Stock, CategoryID)
VALUES (N'Kablosuz Kulaklık',      1899.90, 35, 1),
       (N'Akıllı Saat',            4499.00, 12, 1),
       (N'Mekanik Klavye',         2750.00,  8, 1),
       (N'Erkek Kot Pantolon',      899.90, 40, 2),
       (N'Kadın Trençkot',         2199.00, 15, 2),
       (N'Spor Ayakkabı',          3250.00, 22, 2),
       (N'Dünya Klasikleri Seti',   185.00, 60, 3),
       (N'SQL Sorgulama Rehberi',   420.00, 18, 3),
       (N'Nemlendirici Krem',       349.90, 50, 4),
       (N'Güneş Kremi SPF 50',      459.00,  5, 4),
       (N'Filtre Kahve Makinesi',  2890.00,  9, 5),
       (N'Nevresim Takımı',        1250.00, 27, 5);
GO

-- Görev 3: 6 müşteri (6. müşterinin bilerek siparişi yok; LEFT JOIN örnekleri için)
INSERT INTO dbo.Customers (FullName, City, Email)
VALUES (N'Ahmet Yılmaz', N'İstanbul',  'ahmet.yilmaz@example.com'),
       (N'Zeynep Kaya',  N'Ankara',    'zeynep.kaya@example.com'),
       (N'Mehmet Demir', N'İzmir',     'mehmet.demir@example.com'),
       (N'Elif Şahin',   N'Bursa',     'elif.sahin@example.com'),
       (N'Can Öztürk',   N'Antalya',   'can.ozturk@example.com'),
       (N'Ayşe Arslan',  N'Eskişehir', 'ayse.arslan@example.com');
GO

-- Görev 4: Farklı tarihlerde 10 sipariş
--   TotalAmount burada yazılmıyor (varsayılan 0). Aşağıda sipariş
--   satırlarından hesaplanıp güncelleniyor; böylece elle hesap hatası olmaz.
INSERT INTO dbo.Orders (CustomerID, OrderDate)
VALUES (1, '2026-08-14T10:25:00'),
       (2, '2026-08-29T19:40:00'),
       (3, '2026-09-05T13:10:00'),
       (1, '2026-09-18T21:05:00'),
       (4, '2026-09-27T11:30:00'),
       (5, '2026-10-06T16:45:00'),
       (2, '2026-10-15T09:15:00'),
       (3, '2026-10-24T20:20:00'),
       (1, '2026-11-02T14:00:00'),
       (4, '2026-11-07T18:35:00');
GO

-- Görev 4 (devam): 20 sipariş satırı
--   Birim fiyat elle yazılmıyor, Products tablosundan o anki fiyat alınıyor.
INSERT INTO dbo.OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
SELECT v.OrderID, v.ProductID, v.Quantity, p.Price
FROM (VALUES ( 1,  1, 1), ( 1,  7, 2),
             ( 2,  5, 1), ( 2,  9, 2),
             ( 3,  3, 1),
             ( 4,  2, 1), ( 4,  4, 2),
             ( 5,  9, 1), ( 5, 10, 3),
             ( 6,  8, 1), ( 6, 11, 1),
             ( 7,  6, 1), ( 7,  7, 1),
             ( 8,  1, 2),
             ( 9,  8, 1), ( 9, 10, 1), ( 9, 11, 1),
             (10,  4, 1), (10,  5, 1), (10,  6, 1)
     ) AS v (OrderID, ProductID, Quantity)
INNER JOIN dbo.Products AS p ON p.ProductID = v.ProductID
ORDER BY v.OrderID, v.ProductID;
GO

-- Görev 4 (devam): Sipariş toplamlarını satırlardan hesapla (alt sorgu ile UPDATE)
UPDATE o
SET    o.TotalAmount = ISNULL((SELECT SUM(od.Quantity * od.UnitPrice)
                               FROM   dbo.OrderDetails AS od
                               WHERE  od.OrderID = o.OrderID), 0)
FROM   dbo.Orders AS o;
GO

-- Kontrol: Tabloların içeriği
SELECT * FROM dbo.Categories;
SELECT * FROM dbo.Products;
SELECT * FROM dbo.Customers;
SELECT * FROM dbo.Orders;
SELECT * FROM dbo.OrderDetails;
GO


/* =====================================================================
   BÖLÜM 3: SORGULAMA VE ANALİZ (DQL)
   ===================================================================== */

-- Soru 1 - Temel Listeleme:
-- Stok miktarı 20'den az olan ürünler, stok miktarına göre AZALAN sırada.
SELECT   ProductName AS UrunAdi,
         Stock       AS StokMiktari
FROM     dbo.Products
WHERE    Stock < 20
ORDER BY Stock DESC;
GO

-- Soru 2 - Veri Birleştirme (INNER JOIN):
-- Hangi müşteri, hangi tarihte sipariş vermiş?
SELECT     c.FullName    AS MusteriAdi,
           c.City        AS Sehir,
           o.OrderDate   AS SiparisTarihi,
           o.TotalAmount AS ToplamTutar
FROM       dbo.Customers AS c
INNER JOIN dbo.Orders    AS o ON o.CustomerID = c.CustomerID
ORDER BY   o.OrderDate;
GO

-- Soru 3 - Çoklu Birleştirme ve Detay Raporu:
-- "Ahmet Yılmaz" isimli müşterinin aldığı ürünler, fiyatları ve kategorileri.
-- (5 tablo zincirleme bağlanır. DISTINCT: aynı ürünü iki siparişte almışsa tek satır gelsin.)
SELECT DISTINCT
           p.ProductName  AS UrunAdi,
           p.Price        AS Fiyat,
           cat.CategoryName AS Kategori
FROM       dbo.Customers    AS c
INNER JOIN dbo.Orders       AS o   ON o.CustomerID  = c.CustomerID
INNER JOIN dbo.OrderDetails AS od  ON od.OrderID    = o.OrderID
INNER JOIN dbo.Products     AS p   ON p.ProductID   = od.ProductID
INNER JOIN dbo.Categories   AS cat ON cat.CategoryID = p.CategoryID
WHERE      c.FullName = N'Ahmet Yılmaz'
ORDER BY   Kategori, UrunAdi;
GO

-- Soru 4 - Gruplama ve Aggregate Fonksiyonlar:
-- Hangi kategoride toplam kaç ürün var?
-- (LEFT JOIN: ürünü olmayan bir kategori olsaydı o da 0 ile listelenirdi.)
SELECT    cat.CategoryName   AS Kategori,
          COUNT(p.ProductID) AS UrunSayisi
FROM      dbo.Categories AS cat
LEFT JOIN dbo.Products   AS p ON p.CategoryID = cat.CategoryID
GROUP BY  cat.CategoryName
ORDER BY  UrunSayisi DESC, Kategori;
GO

-- Soru 5 - Ciro Analizi:
-- Her müşterinin kazandırdığı toplam ciro, en çok harcayandan en aza.
-- (LEFT JOIN + ISNULL: hiç siparişi olmayan müşteri de 0 ciro ile görünür.)
SELECT    c.FullName                    AS MusteriAdi,
          COUNT(o.OrderID)              AS SiparisSayisi,
          ISNULL(SUM(o.TotalAmount), 0) AS ToplamCiro
FROM      dbo.Customers AS c
LEFT JOIN dbo.Orders    AS o ON o.CustomerID = c.CustomerID
GROUP BY  c.CustomerID, c.FullName
ORDER BY  ToplamCiro DESC;
GO

-- Soru 6 - Zaman Analizi:
-- Bugünün tarihine göre siparişlerin üzerinden kaç gün geçmiş?
SELECT     o.OrderID                              AS SiparisNo,
           c.FullName                             AS MusteriAdi,
           o.OrderDate                            AS SiparisTarihi,
           DATEDIFF(DAY, o.OrderDate, GETDATE())  AS GecenGun
FROM       dbo.Orders    AS o
INNER JOIN dbo.Customers AS c ON c.CustomerID = o.CustomerID
ORDER BY   GecenGun DESC;
GO


/* =====================================================================
   BÖLÜM 4.1: İLERİ SEVİYE NESNELER - VIEW
   ===================================================================== */

-- vw_SiparisOzet: Müşteri Adı, Sipariş Tarihi, Ürün Adı ve Adet
--     bilgilerini tek tablodaymış gibi getirir.
--     Ek: WITH SCHEMABINDING. View'ın kullandığı sütunlar silinemez veya
--     değiştirilemez; böylece view farkında olmadan bozulmaz.
CREATE VIEW dbo.vw_SiparisOzet
WITH SCHEMABINDING
AS
SELECT     o.OrderID     AS SiparisNo,
           c.FullName    AS MusteriAdi,
           o.OrderDate   AS SiparisTarihi,
           p.ProductName AS UrunAdi,
           od.Quantity   AS Adet
FROM       dbo.Orders       AS o
INNER JOIN dbo.Customers    AS c  ON c.CustomerID = o.CustomerID
INNER JOIN dbo.OrderDetails AS od ON od.OrderID   = o.OrderID
INNER JOIN dbo.Products     AS p  ON p.ProductID  = od.ProductID;
GO

-- View'ın kullanımı
SELECT   MusteriAdi, SiparisTarihi, UrunAdi, Adet
FROM     dbo.vw_SiparisOzet
ORDER BY SiparisTarihi, UrunAdi;
GO

-- View üzerinde filtre: uzun JOIN yazmadan tek müşterinin siparişleri
SELECT   MusteriAdi, SiparisTarihi, UrunAdi, Adet
FROM     dbo.vw_SiparisOzet
WHERE    MusteriAdi = N'Zeynep Kaya'
ORDER BY SiparisTarihi;
GO

-- SCHEMABINDING testi: View'ın kullandığı bir sütunu silmeyi dene.
-- Beklenen: SQL Server izin vermez, hata mesajı döner. (Transaction içinde,
-- beklenmedik bir durumda bile değişiklik geri alınır.)
BEGIN TRY
    BEGIN TRANSACTION;
    ALTER TABLE dbo.Products DROP COLUMN ProductName;
    ROLLBACK TRANSACTION;
    SELECT N'BEKLENMEYEN: sütun silinebildi (geri alındı).' AS Sonuc;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    SELECT N'Engellendi (beklenen)' AS Sonuc,
           ERROR_NUMBER()           AS HataNo,
           ERROR_MESSAGE()          AS HataMesaji;
END CATCH;
GO

-- Ek: vw_KategoriSatis - kategori bazında satış adedi ve ciro
CREATE VIEW dbo.vw_KategoriSatis
AS
SELECT     cat.CategoryName                              AS Kategori,
           ISNULL(SUM(od.Quantity), 0)                   AS SatilanAdet,
           ISNULL(SUM(od.Quantity * od.UnitPrice), 0)    AS Ciro
FROM       dbo.Categories   AS cat
LEFT JOIN  dbo.Products     AS p  ON p.CategoryID = cat.CategoryID
LEFT JOIN  dbo.OrderDetails AS od ON od.ProductID = p.ProductID
GROUP BY   cat.CategoryName;
GO

SELECT   Kategori, SatilanAdet, Ciro
FROM     dbo.vw_KategoriSatis
ORDER BY Ciro DESC;
GO


/* =====================================================================
   EK A: EK ANALİZ SORGULARI (yönergede istenenlerin üzerine)
   ===================================================================== */

-- A1 - Alt sorgu (Subquery): Fiyatı ortalama ürün fiyatının üzerinde olan ürünler
SELECT   ProductName AS UrunAdi,
         Price       AS Fiyat
FROM     dbo.Products
WHERE    Price > (SELECT AVG(Price) FROM dbo.Products)
ORDER BY Price DESC;
GO

-- A2 - HAVING: Birden fazla sipariş vermiş (sadık) müşteriler
--      WHERE satırları, HAVING ise grupları filtreler.
SELECT     c.FullName         AS MusteriAdi,
           COUNT(o.OrderID)   AS SiparisSayisi,
           SUM(o.TotalAmount) AS ToplamCiro
FROM       dbo.Customers AS c
INNER JOIN dbo.Orders    AS o ON o.CustomerID = c.CustomerID
GROUP BY   c.CustomerID, c.FullName
HAVING     COUNT(o.OrderID) > 1
ORDER BY   SiparisSayisi DESC, ToplamCiro DESC;
GO

-- A3 - Hiç satılmamış ürünler (LEFT JOIN + IS NULL)
SELECT    p.ProductName AS UrunAdi,
          p.Stock       AS StokMiktari
FROM      dbo.Products     AS p
LEFT JOIN dbo.OrderDetails AS od ON od.ProductID = p.ProductID
WHERE     od.DetailID IS NULL;
GO

-- A4 - Hiç sipariş vermemiş müşteriler (NOT EXISTS)
SELECT c.FullName AS MusteriAdi,
       c.City     AS Sehir,
       c.Email    AS Eposta
FROM   dbo.Customers AS c
WHERE  NOT EXISTS (SELECT 1
                   FROM   dbo.Orders AS o
                   WHERE  o.CustomerID = c.CustomerID);
GO

-- A5 - En çok satan 3 ürün (adet bazında)
SELECT TOP (3)
           p.ProductName                   AS UrunAdi,
           SUM(od.Quantity)                AS SatilanAdet,
           SUM(od.Quantity * od.UnitPrice) AS Ciro
FROM       dbo.OrderDetails AS od
INNER JOIN dbo.Products     AS p ON p.ProductID = od.ProductID
GROUP BY   p.ProductID, p.ProductName
ORDER BY   SatilanAdet DESC, Ciro DESC;
GO

-- A6 - Aylık ciro ve sipariş sayısı
SELECT   YEAR(OrderDate)   AS Yil,
         MONTH(OrderDate)  AS Ay,
         COUNT(*)          AS SiparisSayisi,
         SUM(TotalAmount)  AS AylikCiro
FROM     dbo.Orders
GROUP BY YEAR(OrderDate), MONTH(OrderDate)
ORDER BY Yil, Ay;
GO

-- A7 - Stok durumu raporu (CASE)
SELECT   ProductName AS UrunAdi,
         Stock       AS StokMiktari,
         CASE
             WHEN Stock < 10 THEN N'Kritik'
             WHEN Stock < 20 THEN N'Azalıyor'
             ELSE N'Yeterli'
         END         AS StokDurumu
FROM     dbo.Products
ORDER BY Stock;
GO


/* =====================================================================
   EK B: KISIT (CONSTRAINT) TESTLERİ
   Hatalı veriler bilerek denenir. Her deneme TRY...CATCH içinde olduğu için
   script durmaz, hata mesajı sonuç olarak gösterilir ve tabloya hiçbir
   hatalı satır girmez.
   ===================================================================== */

-- B1 - CHECK: Negatif fiyatlı ürün eklenemez
BEGIN TRY
    INSERT INTO dbo.Products (ProductName, Price, Stock, CategoryID)
    VALUES (N'Hatalı Ürün', -50.00, 10, 1);
    SELECT N'BEKLENMEYEN: satır eklendi.' AS Sonuc;
END TRY
BEGIN CATCH
    SELECT N'B1 - Negatif fiyat engellendi' AS Test,
           ERROR_NUMBER()                  AS HataNo,
           ERROR_MESSAGE()                 AS HataMesaji;
END CATCH;
GO

-- B2 - UNIQUE: Aynı e-posta ile ikinci müşteri eklenemez
BEGIN TRY
    INSERT INTO dbo.Customers (FullName, City, Email)
    VALUES (N'Sahte Ahmet', N'Ankara', 'ahmet.yilmaz@example.com');
    SELECT N'BEKLENMEYEN: satır eklendi.' AS Sonuc;
END TRY
BEGIN CATCH
    SELECT N'B2 - Tekrarlanan e-posta engellendi' AS Test,
           ERROR_NUMBER()                        AS HataNo,
           ERROR_MESSAGE()                       AS HataMesaji;
END CATCH;
GO

-- B3 - FOREIGN KEY: Olmayan bir kategoriye ürün eklenemez
BEGIN TRY
    INSERT INTO dbo.Products (ProductName, Price, Stock, CategoryID)
    VALUES (N'Kategorisiz Ürün', 100.00, 10, 999);
    SELECT N'BEKLENMEYEN: satır eklendi.' AS Sonuc;
END TRY
BEGIN CATCH
    SELECT N'B3 - Olmayan kategori engellendi' AS Test,
           ERROR_NUMBER()                     AS HataNo,
           ERROR_MESSAGE()                    AS HataMesaji;
END CATCH;
GO

-- B4 - DEFAULT: Stok yazılmadan eklenen ürünün stoğu 0 olur.
--      Test verisi kalıcı olmasın diye transaction geri alınır (ROLLBACK).
BEGIN TRANSACTION;
    INSERT INTO dbo.Products (ProductName, Price, CategoryID)
    VALUES (N'Test Ürünü (stok yazılmadı)', 10.00, 1);

    SELECT ProductName AS UrunAdi, Price AS Fiyat, Stock AS VarsayilanStok
    FROM   dbo.Products
    WHERE  ProductID = SCOPE_IDENTITY();
ROLLBACK TRANSACTION;
GO


/* =====================================================================
   EK C: TRANSACTION İLE SİPARİŞ PROSEDÜRÜ
   Bir sipariş üç adımdan oluşur: Orders'a kayıt, OrderDetails'e satır,
   Products'ta stok düşme. Üçü "ya hep ya hiç" olmalıdır. Stok yetersizse
   veya herhangi bir adım hata verirse hiçbir değişiklik kalmaz (ROLLBACK).
   ===================================================================== */
CREATE PROCEDURE dbo.usp_SiparisVer
    @CustomerID INT,
    @ProductID  INT,
    @Quantity   INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Price   DECIMAL(10,2),
            @Stock   INT,
            @OrderID INT,
            @Mesaj   NVARCHAR(200);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Girdi kontrolleri
        IF @Quantity IS NULL OR @Quantity <= 0
        BEGIN
            THROW 50001, N'Adet 0''dan büyük olmalıdır.', 1;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.Customers WHERE CustomerID = @CustomerID)
        BEGIN
            THROW 50002, N'Müşteri bulunamadı.', 1;
        END;

        -- Ürünün fiyatını ve stoğunu oku. UPDLOCK: aynı anda gelen ikinci bir
        -- sipariş, bu işlem bitene kadar aynı stoğu okuyup kullanamaz.
        SELECT @Price = Price,
               @Stock = Stock
        FROM   dbo.Products WITH (UPDLOCK, ROWLOCK)
        WHERE  ProductID = @ProductID;

        IF @Price IS NULL
        BEGIN
            THROW 50003, N'Ürün bulunamadı.', 1;
        END;

        IF @Stock < @Quantity
        BEGIN
            SET @Mesaj = CONCAT(N'Yetersiz stok. Mevcut: ', @Stock, N', istenen: ', @Quantity, N'.');
            THROW 50004, @Mesaj, 1;
        END;

        -- 1) Sipariş başlığı (OrderDate varsayılan olarak GETDATE() alır)
        INSERT INTO dbo.Orders (CustomerID, TotalAmount)
        VALUES (@CustomerID, @Price * @Quantity);

        SET @OrderID = SCOPE_IDENTITY();

        -- 2) Sipariş satırı
        INSERT INTO dbo.OrderDetails (OrderID, ProductID, Quantity, UnitPrice)
        VALUES (@OrderID, @ProductID, @Quantity, @Price);

        -- 3) Stoktan düş
        UPDATE dbo.Products
        SET    Stock = Stock - @Quantity
        WHERE  ProductID = @ProductID;

        COMMIT TRANSACTION;

        SELECT @OrderID           AS YeniSiparisNo,
               @Price * @Quantity AS ToplamTutar;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

-- C1 - Başarılı sipariş: Can Öztürk (5), 2 adet Nemlendirici Krem (9) alıyor.
--      Beklenen: yeni sipariş oluşur, stok 50'den 48'e düşer.
SELECT ProductName AS UrunAdi, Stock AS OncekiStok FROM dbo.Products WHERE ProductID = 9;

EXEC dbo.usp_SiparisVer @CustomerID = 5, @ProductID = 9, @Quantity = 2;

SELECT ProductName AS UrunAdi, Stock AS SonrakiStok FROM dbo.Products WHERE ProductID = 9;
GO

-- C2 - Başarısız sipariş: Stokta 5 adet olan Güneş Kremi'nden (10) 50 adet isteniyor.
--      Beklenen: hata mesajı döner; sipariş sayısı ve stok DEĞİŞMEZ (ROLLBACK).
DECLARE @OncekiSiparisSayisi INT = (SELECT COUNT(*) FROM dbo.Orders);

BEGIN TRY
    EXEC dbo.usp_SiparisVer @CustomerID = 1, @ProductID = 10, @Quantity = 50;
END TRY
BEGIN CATCH
    SELECT N'C2 - Sipariş reddedildi' AS Test,
           ERROR_NUMBER()            AS HataNo,
           ERROR_MESSAGE()           AS HataMesaji;
END CATCH;

SELECT @OncekiSiparisSayisi                           AS OncekiSiparisSayisi,
       (SELECT COUNT(*) FROM dbo.Orders)              AS SonrakiSiparisSayisi,
       (SELECT Stock FROM dbo.Products WHERE ProductID = 10) AS GunesKremiStok;
GO


/* =====================================================================
   EK D: VERİ TUTARLILIĞI KONTROLÜ
   Orders.TotalAmount ile sipariş satırlarının toplamı aynı mı?
   Beklenen: 0 satır (tutarsız sipariş yok).
   ===================================================================== */
SELECT    o.OrderID                                  AS SiparisNo,
          o.TotalAmount                              AS KayitliTutar,
          ISNULL(SUM(od.Quantity * od.UnitPrice), 0) AS HesaplananTutar
FROM      dbo.Orders       AS o
LEFT JOIN dbo.OrderDetails AS od ON od.OrderID = o.OrderID
GROUP BY  o.OrderID, o.TotalAmount
HAVING    o.TotalAmount <> ISNULL(SUM(od.Quantity * od.UnitPrice), 0);
GO


/* =====================================================================
   BÖLÜM 4.2: İLERİ SEVİYE NESNELER - YEDEKLEME (BACKUP)
   Proje tamamlandıktan sonra alındığı için dosyanın sonundadır.
   ===================================================================== */

-- Adım 1: C:\Yedek\ klasörü yoksa oluştur.
--     (Klasörü SQL Server'ın kendisi oluşturduğu için yazma izni sorunu çıkmaz.)
EXEC master.dbo.xp_create_subdir N'C:\Yedek\';
GO

-- Adım 2: Tam (full) yedek
--     INIT     : aynı dosyanın üzerine yazar, eski yedekler dosyada birikmez.
--     CHECKSUM : yedek alınırken sayfaların sağlaması kontrol edilir.
BACKUP DATABASE NovaStoreDB
TO DISK = N'C:\Yedek\NovaStoreDB.bak'
WITH INIT,
     CHECKSUM,
     NAME = N'NovaStoreDB - Tam Yedek';
GO

-- Adım 3 (ek): Alınan yedeğin okunabilir ve sağlam olduğunu doğrula
--     (yedeği geri yüklemeden kontrol eder).
RESTORE VERIFYONLY
FROM DISK = N'C:\Yedek\NovaStoreDB.bak'
WITH CHECKSUM;
GO

-- 0.2'deki güvenlik kontrolü devreye girdiyse normale dön
SET NOEXEC OFF;
GO

/* ============================ SCRIPT SONU ============================ */
