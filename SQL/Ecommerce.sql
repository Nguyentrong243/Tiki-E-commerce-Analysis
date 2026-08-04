-- TIKI E-COMMERCE ANALYSIS

-- ============================================================
-- 1. GROSS MERCHANDISE VALUE (GMV) ANALYSIS
-- Business question: Which product categories and brands generate 
-- the highest Gross Merchandise Value (GMV) on the Tiki marketplace?
-- ============================================================

-- 1a. GMV by category
SELECT
    category,
    COUNT(*) AS total_products,
    SUM(quantity_sold) AS total_units_sold,
    SUM(price * quantity_sold) AS estimated_gmv,
    ROUND(AVG(price)::numeric, 0) AS avg_price
FROM tiki_products
GROUP BY category
ORDER BY estimated_gmv DESC;

-- 1b. Top 10 brands by GMV (excluding generic OEM/Unknown)
SELECT
    brand,
    COUNT(*) AS total_products,
    SUM(quantity_sold) AS total_units_sold,
    SUM(price * quantity_sold) AS estimated_gmv,
    ROUND(AVG(price)::numeric, 0) AS avg_price
FROM tiki_products
WHERE brand NOT IN ('OEM', 'Unknown')
GROUP BY brand
ORDER BY estimated_gmv DESC
LIMIT 10;


-- ============================================================
-- 2. PRODUCT PERFORMANCE MATRIX
-- Business question: Which products are Star Products, Hidden Gems, 
-- High-Demand but Low-Satisfaction products, and Underperformers?
--
-- Uses MEDIAN (not average) as the split point, since GMV is 
-- right-skewed (a small number of bestsellers generate 
-- disproportionately high GMV) — the median better represents 
-- the "typical" product than the mean would. Only products with 
-- at least 1 review are included, since unreviewed products 
-- default to a rating of 0, which would distort the comparison.
-- ============================================================

WITH rated_products AS (
    SELECT
        id,
        name,
        category,
        brand,
        price * quantity_sold AS gmv,
        rating_average,
        review_count
    FROM tiki_products
    WHERE review_count > 0
),
medians AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gmv) AS median_gmv,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rating_average) AS median_rating
    FROM rated_products
)
SELECT
    rp.id,
    rp.name,
    rp.category,
    rp.brand,
    rp.gmv,
    rp.rating_average,
    rp.review_count,
    CASE
        WHEN rp.gmv >= m.median_gmv AND rp.rating_average >= m.median_rating THEN 'Star Product'
        WHEN rp.gmv >= m.median_gmv AND rp.rating_average <  m.median_rating THEN 'High Demand - Low Satisfaction'
        WHEN rp.gmv <  m.median_gmv AND rp.rating_average >= m.median_rating THEN 'Hidden Gem'
        ELSE 'Underperformer'
    END AS performance_quadrant
FROM rated_products rp
CROSS JOIN medians m
ORDER BY rp.gmv DESC;

-- 2b. Quadrant summary — how many products and how much GMV per quadrant
WITH rated_products AS (
    SELECT
        price * quantity_sold AS gmv,
        rating_average
    FROM tiki_products
    WHERE review_count > 0
),
medians AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gmv) AS median_gmv,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rating_average) AS median_rating
    FROM rated_products
),
classified AS (
    SELECT
        rp.gmv,
        CASE
            WHEN rp.gmv >= m.median_gmv AND rp.rating_average >= m.median_rating THEN 'Star Product'
            WHEN rp.gmv >= m.median_gmv AND rp.rating_average <  m.median_rating THEN 'High Demand - Low Satisfaction'
            WHEN rp.gmv <  m.median_gmv AND rp.rating_average >= m.median_rating THEN 'Hidden Gem'
            ELSE 'Underperformer'
        END AS performance_quadrant
    FROM rated_products rp
    CROSS JOIN medians m
)
SELECT
    performance_quadrant,
    COUNT(*) AS num_products,
    SUM(gmv) AS total_gmv,
    ROUND(AVG(gmv)::numeric, 0) AS avg_gmv_per_product
FROM classified
GROUP BY performance_quadrant
ORDER BY total_gmv DESC;


-- ============================================================
-- 3. DISCOUNT EFFECTIVENESS
-- Business question: Do discounts actually increase sales 
-- performance, or do they simply reduce selling prices without 
-- generating meaningful sales growth?
-- ============================================================

SELECT
    CASE
        WHEN original_price = price THEN 'No Discount'
        WHEN (original_price - price) / original_price::numeric < 0.10 THEN 'Small Discount (<10%)'
        WHEN (original_price - price) / original_price::numeric < 0.30 THEN 'Medium Discount (10-30%)'
        ELSE 'Large Discount (30%+)'
    END AS discount_tier,
    COUNT(*) AS num_products,
    ROUND(AVG(quantity_sold)::numeric, 1) AS avg_quantity_sold,
    ROUND(AVG(rating_average)::numeric, 2) AS avg_rating,
    ROUND(AVG(review_count)::numeric, 1) AS avg_reviews,
    SUM(price * quantity_sold) AS estimated_gmv
FROM tiki_products
GROUP BY discount_tier
ORDER BY avg_quantity_sold DESC;


-- ============================================================
-- 4. SELLER PERFORMANCE ANALYSIS
-- Business question: Which sellers contribute the most to 
-- marketplace performance, and which large sellers are underperforming?
-- ============================================================

-- 4a. Top 15 sellers by GMV
SELECT
    current_seller,
    COUNT(*) AS total_products,
    SUM(quantity_sold) AS total_units_sold,
    SUM(price * quantity_sold) AS estimated_gmv,
    ROUND(AVG(rating_average)::numeric, 2) AS avg_rating
FROM tiki_products
GROUP BY current_seller
ORDER BY estimated_gmv DESC
LIMIT 15;

-- 4b. Underperforming sellers: many listings, but low sales conversion
SELECT
    current_seller,
    COUNT(*) AS total_products,
    SUM(quantity_sold) AS total_units_sold,
    ROUND(SUM(quantity_sold)::numeric / COUNT(*), 2) AS avg_units_sold_per_product,
    ROUND(AVG(rating_average)::numeric, 2) AS avg_rating
FROM tiki_products
GROUP BY current_seller
HAVING COUNT(*) >= 20   -- sellers with meaningful catalog size
ORDER BY avg_units_sold_per_product ASC
LIMIT 15;


-- ============================================================
-- 5. CUSTOMER ENGAGEMENT ANALYSIS
-- Business question: Where does customer engagement (reviews and 
-- ratings) fail to align with actual sales performance?
--
-- Uses the 75th/25th percentile as thresholds (rather than the 
-- average) to isolate genuinely extreme cases — review_count and 
-- quantity_sold are both right-skewed, so percentile-based 
-- thresholds better capture true outliers than a simple average split.
-- ============================================================

-- 5a. High engagement, but low sales (potential pricing/stock issue)
SELECT
    id,
    name,
    category,
    brand,
    price,
    review_count,
    rating_average,
    quantity_sold
FROM tiki_products
WHERE review_count > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY review_count) FROM tiki_products)
  AND quantity_sold <= (SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY quantity_sold) FROM tiki_products)
ORDER BY review_count DESC
LIMIT 20;

-- 5b. Low engagement, but high sales (hidden bestsellers worth more visibility/marketing)
SELECT
    id,
    name,
    category,
    brand,
    price,
    review_count,
    rating_average,
    quantity_sold
FROM tiki_products
WHERE review_count <= (SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY review_count) FROM tiki_products)
  AND quantity_sold > (SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY quantity_sold) FROM tiki_products)
ORDER BY quantity_sold DESC
LIMIT 20;


-- ============================================================
-- 6. PRODUCT CONTENT QUALITY
-- Business question: Does richer product content (videos, images, 
-- and Buy Now Pay Later availability) improve sales performance?
-- ============================================================

-- 6a. Video presence
SELECT
    has_video,
    COUNT(*) AS num_products,
    ROUND(AVG(quantity_sold)::numeric, 1) AS avg_quantity_sold,
    ROUND(AVG(rating_average)::numeric, 2) AS avg_rating,
    SUM(price * quantity_sold) AS estimated_gmv
FROM tiki_products
GROUP BY has_video;

-- 6b. Number of images (bucketed)
SELECT
    CASE
        WHEN number_of_images <= 3 THEN '1-3 images'
        WHEN number_of_images <= 6 THEN '4-6 images'
        WHEN number_of_images <= 10 THEN '7-10 images'
        ELSE '10+ images'
    END AS image_count_bucket,
    COUNT(*) AS num_products,
    ROUND(AVG(quantity_sold)::numeric, 1) AS avg_quantity_sold,
    ROUND(AVG(rating_average)::numeric, 2) AS avg_rating,
    SUM(price * quantity_sold) AS estimated_gmv
FROM tiki_products
GROUP BY image_count_bucket
ORDER BY avg_quantity_sold DESC;

-- 6c. Pay-later availability
SELECT
    pay_later,
    COUNT(*) AS num_products,
    ROUND(AVG(quantity_sold)::numeric, 1) AS avg_quantity_sold,
    ROUND(AVG(price)::numeric, 0) AS avg_price,
    SUM(price * quantity_sold) AS estimated_gmv
FROM tiki_products
GROUP BY pay_later;


-- ============================================================
-- 7. PRICING STRATEGY
-- Business question: Which price segments perform best within 
-- each product category?
-- ============================================================

WITH price_bands AS (
    SELECT
        category,
        quantity_sold,
        rating_average,
        price * quantity_sold AS gmv,
        CASE
            WHEN price < 100000 THEN 'Budget (<100k VND)'
            WHEN price < 300000 THEN 'Mid-range (100k-300k VND)'
            WHEN price < 700000 THEN 'Premium (300k-700k VND)'
            ELSE 'Luxury (700k+ VND)'
        END AS price_band
    FROM tiki_products
)
SELECT
    category,
    price_band,
    COUNT(*) AS num_products,
    ROUND(AVG(quantity_sold)::numeric, 1) AS avg_quantity_sold,
    ROUND(AVG(rating_average)::numeric, 2) AS avg_rating,
    SUM(gmv) AS estimated_gmv
FROM price_bands
GROUP BY category, price_band
ORDER BY category, avg_quantity_sold DESC;


-- ============================================================
-- 8. BRAND POSITIONING
-- Business question: How are brands positioned across the 
-- marketplace in terms of pricing, customer satisfaction, and 
-- sales performance?
--
-- Framework: classify brands (min. 5 products, excluding generic 
-- OEM/Unknown) by comparing average price and sales volume against 
-- the market-wide average across all qualifying brands.
-- ============================================================

WITH brand_stats AS (
    SELECT
        brand,
        COUNT(*) AS total_products,
        SUM(quantity_sold) AS total_units_sold,
        SUM(price * quantity_sold) AS estimated_gmv,
        ROUND(AVG(price)::numeric, 0) AS avg_price,
        ROUND(AVG(rating_average)::numeric, 2) AS avg_rating
    FROM tiki_products
    WHERE brand NOT IN ('OEM', 'Unknown')
    GROUP BY brand
    HAVING COUNT(*) >= 5
)
SELECT
    brand,
    total_products,
    total_units_sold,
    estimated_gmv,
    avg_price,
    avg_rating,
    CASE
        WHEN avg_price >= (SELECT AVG(avg_price) FROM brand_stats)
             AND avg_rating >= (SELECT AVG(avg_rating) FROM brand_stats) THEN 'Premium Brand'
        WHEN avg_price <  (SELECT AVG(avg_price) FROM brand_stats)
             AND total_units_sold >= (SELECT AVG(total_units_sold) FROM brand_stats) THEN 'Mass-Market Brand'
        ELSE 'Standard Brand'
    END AS brand_positioning
FROM brand_stats
ORDER BY estimated_gmv DESC;