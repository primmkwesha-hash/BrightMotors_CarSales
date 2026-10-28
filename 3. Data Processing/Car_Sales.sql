-- Databricks notebook source
SELECT * 
FROM `majambura`.`default`.`car_sales_dataset`;

--Find rows with a broken saledate
SELECT saledate,
       SIZE(SPLIT(saledate, ' ')) AS parts
FROM   `majambura`.`default`.`car_sales_dataset`
WHERE  saledate IS NULL
   OR  SIZE(SPLIT(saledate, ' ')) < 4
LIMIT  20;

--KPI 
WITH cleaned AS 
(SELECT CAST(sellingprice AS DOUBLE) AS sellingprice,
           CAST(mmr AS DOUBLE) AS mmr
FROM `majambura`.`default`.`car_sales_dataset`
WHERE sellingprice IS NOT NULL AND mmr IS NOT NULL)
SELECT
    COUNT(*) AS total_transactions,
    ROUND(SUM(sellingprice), 0) AS total_revenue,
    ROUND(AVG(sellingprice), 0) AS avg_selling_price,
    ROUND(AVG(sellingprice - mmr), 0) AS avg_profit_vs_mmr,
    ROUND(AVG((sellingprice - mmr) / NULLIF(mmr, 0)), 4) AS avg_profit_pct
FROM cleaned;

--TOP 10 MAKES
SELECT  TRIM(make) AS make,
        COUNT(*) AS units_sold,
        ROUND(SUM(sellingprice)) AS revenue,
        ROUND(AVG(sellingprice)) AS avg_price
FROM `majambura`.`default`.`car_sales_dataset`
WHERE sellingprice IS NOT NULL
GROUP BY TRIM(make)
ORDER BY revenue DESC
LIMIT 10;

--States Performance
SELECT  UPPER(TRIM(state)) AS state,
        COUNT(*) AS units_sold,
        ROUND(SUM(sellingprice)) AS revenue,
        ROUND(AVG(sellingprice)) AS avg_price
FROM `majambura`.`default`.`car_sales_dataset`
WHERE sellingprice IS NOT NULL AND state IS NOT NULL
GROUP BY UPPER(TRIM(state))
ORDER BY revenue DESC;

--BODY TYPE MIX
SELECT  LOWER(TRIM(body)) AS body,
        COUNT(*) AS units_sold,
        ROUND(AVG(sellingprice)) AS avg_price,
        ROUND(SUM(sellingprice)) AS revenue
FROM `majambura`.`default`.`car_sales_dataset`
WHERE sellingprice IS NOT NULL AND body IS NOT NULL
GROUP BY LOWER(TRIM(body))
ORDER BY revenue DESC;


--MONTHLY TREND
WITH dated AS 
(SELECT sellingprice,
TO_TIMESTAMP(
CONCAT(try_element_at(SPLIT(saledate,' '),4),'-',
CASE try_element_at(SPLIT(saledate,' '),2)
     WHEN 'Jan' THEN '01' WHEN 'Feb' THEN '02'
     WHEN 'Mar' THEN '03' WHEN 'Apr' THEN '04'
     WHEN 'May' THEN '05' WHEN 'Jun' THEN '06'
     WHEN 'Jul' THEN '07' WHEN 'Aug' THEN '08'
     WHEN 'Sep' THEN '09' WHEN 'Oct' THEN '10'
     WHEN 'Nov' THEN '11' WHEN 'Dec' THEN '12'
     END,'-',
     try_element_at(SPLIT(saledate,' '),3),' ',
     try_element_at(SPLIT(saledate,' '),5)),
    'yyyy-MM-dd HH:mm:ss') AS sale_ts
FROM `majambura`.`default`.`car_sales_dataset`
WHERE sellingprice IS NOT NULL
AND SIZE(SPLIT(saledate,' ')) >= 5)
SELECT  DATE_FORMAT(sale_ts,'yyyy-MM') AS sale_month,
        COUNT(*) AS units_sold,
        ROUND(SUM(sellingprice)) AS revenue,
        ROUND(AVG(sellingprice)) AS avg_price
FROM dated
GROUP BY DATE_FORMAT(sale_ts,'yyyy-MM')
ORDER BY sale_month;


--MAIN LONG QUERY 
WITH cleaned AS 
(SELECT
-- identifiers
    TRIM(make) AS make,
    TRIM(model) AS model,
    TRIM(trim) AS trim,
    LOWER(TRIM(body)) AS body,
    LOWER(TRIM(color)) AS color,
    LOWER(TRIM(interior)) AS interior,
    UPPER(TRIM(state)) AS state,
    TRIM(seller) AS seller,
    TRIM(vin) AS vin,

-- numerics
    CAST(year AS INT) AS model_year,
    CAST(condition AS DOUBLE) AS condition,
    CAST(odometer AS DOUBLE) AS odometer,
    CAST(mmr AS DOUBLE) AS mmr,
    CAST(sellingprice AS DOUBLE) AS sellingprice,

-- date parsing
TO_TIMESTAMP(CONCAT(
    try_element_at(SPLIT(saledate, ' '), 4), '-',
    CASE try_element_at(SPLIT(saledate, ' '), 2)
    WHEN 'Jan' THEN '01' WHEN 'Feb' THEN '02'
    WHEN 'Mar' THEN '03' WHEN 'Apr' THEN '04'
    WHEN 'May' THEN '05' WHEN 'Jun' THEN '06'
    WHEN 'Jul' THEN '07' WHEN 'Aug' THEN '08'
    WHEN 'Sep' THEN '09' WHEN 'Oct' THEN '10'
    WHEN 'Nov' THEN '11' WHEN 'Dec' THEN '12'
END, '-',
                try_element_at(SPLIT(saledate, ' '), 3),
                ' ',
                try_element_at(SPLIT(saledate, ' '), 5)),
            'yyyy-MM-dd HH:mm:ss') AS sale_ts,

 -- profitability
(CAST(sellingprice AS DOUBLE) - CAST(mmr AS DOUBLE)) AS profit,
(CAST(sellingprice AS DOUBLE) - CAST(mmr AS DOUBLE))
 / NULLIF(CAST(mmr AS DOUBLE), 0) AS profit_pct

FROM `majambura`.`default`.`car_sales_dataset`
WHERE sellingprice IS NOT NULL
      AND mmr IS NOT NULL
      AND saledate IS NOT NULL
     AND SIZE(SPLIT(saledate, ' ')) >= 5),

enriched AS 
(SELECT
        c.*,
        YEAR(sale_ts) AS sale_year,
        MONTH(sale_ts) AS sale_month_num,
        DATE_FORMAT(sale_ts, 'yyyy-MM') AS sale_month,
        sale_year - model_year AS vehicle_age_yrs,
CASE
    WHEN sellingprice < 5000 THEN '01. < 5k'
    WHEN sellingprice < 10000 THEN '02. 5k–10k'
    WHEN sellingprice < 20000 THEN '03. 10k–20k'
    WHEN sellingprice < 40000 THEN '04. 20k–40k'
    ELSE '05. 40k+'
END AS price_band
FROM cleaned c)

SELECT
    body,
    make,
    model,
    color,
    state,
    sale_month,
    COUNT(*) AS total_sales,
    AVG(sellingprice) AS avg_price,
    SUM(sellingprice) AS total_revenue,
    AVG(mmr) AS avg_mmr,
    AVG(profit) AS avg_profit,
    AVG(profit_pct) AS avg_profit_pct,
    AVG(odometer) AS avg_odometer,
    AVG(vehicle_age_yrs) AS avg_vehicle_age
FROM enriched
GROUP BY body, make, model, color, state, sale_month
ORDER BY avg_price DESC;