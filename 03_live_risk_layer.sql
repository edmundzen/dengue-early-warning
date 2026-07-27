-- Dengue Sentinel · live risk layer
-- Rebuilds inspection_priority_live from real data only:
--   cases      : today's NEA cluster snapshot (nea_clusters_raw)
--   rainfall   : real NEA station readings, nearest station per cluster (weather_daily_raw)
--   recurrence : genuine 2015-2020 history for that 250m cell (telemetry_daily)
-- Weights: case density 60% / rainfall lag 25% / recurrence 15%
-- Idempotent - safe to re-run daily.

CREATE OR REPLACE TABLE `dengue-early-warning.dengue_ew.inspection_priority_live` AS
WITH params AS (SELECT 0.00225 AS step, CURRENT_DATE('Asia/Singapore') AS asof),

clusters AS (
  SELECT c.cluster_id, c.locality, c.case_count, c.lat, c.lon,
         ROUND(FLOOR(c.lat / p.step) * p.step, 5) AS cell_lat,
         ROUND(FLOOR(c.lon / p.step) * p.step, 5) AS cell_lon,
         c.snapshot_date
  FROM `dengue-early-warning.dengue_ew.nea_clusters_raw` c, params p
  WHERE c.snapshot_date = (SELECT MAX(snapshot_date)
                           FROM `dengue-early-warning.dengue_ew.nea_clusters_raw`)
    AND c.lat IS NOT NULL AND c.lon IS NOT NULL
),

-- per-station rainfall: 14-day mean and the 7-14 day lagged window
stn AS (
  SELECT station_id, station_name, ANY_VALUE(lat) AS lat, ANY_VALUE(lon) AS lon,
         AVG(IF(obs_date >= DATE_SUB((SELECT asof FROM params), INTERVAL 14 DAY),
                rain_mm, NULL)) AS rain_14d,
         AVG(IF(obs_date BETWEEN DATE_SUB((SELECT asof FROM params), INTERVAL 14 DAY)
                             AND DATE_SUB((SELECT asof FROM params), INTERVAL 7 DAY),
                rain_mm, NULL)) AS rain_lag_7to14d,
         COUNT(DISTINCT obs_date) AS days_observed
  FROM `dengue-early-warning.dengue_ew.weather_daily_raw`
  WHERE lat IS NOT NULL AND lon IS NOT NULL
  GROUP BY station_id, station_name
),

-- nearest station per cluster: spatially resolved rainfall, not one island number
nearest AS (
  SELECT * EXCEPT(rn) FROM (
    SELECT c.*, s.station_id, s.station_name, s.rain_14d, s.rain_lag_7to14d,
           s.days_observed,
           ROUND(ST_DISTANCE(ST_GEOGPOINT(c.lon, c.lat),
                             ST_GEOGPOINT(s.lon, s.lat)) / 1000, 2) AS station_km,
           ROW_NUMBER() OVER (PARTITION BY c.cluster_id
                              ORDER BY ST_DISTANCE(ST_GEOGPOINT(c.lon, c.lat),
                                                   ST_GEOGPOINT(s.lon, s.lat))) AS rn
    FROM clusters c CROSS JOIN stn s
  ) WHERE rn = 1
),

recur AS (
  SELECT ROUND(lat,5) AS cell_lat, ROUND(lon,5) AS cell_lon,
         AVG(case_count) AS hist_mean_cases,
         SAFE_DIVIDE(COUNTIF(case_count > 0), COUNT(*)) AS hist_active_rate,
         SUM(case_count) AS hist_total_cases
  FROM `dengue-early-warning.dengue_ew.telemetry_daily`
  GROUP BY cell_lat, cell_lon
),

joined AS (
  SELECT n.*, IFNULL(r.hist_mean_cases,0) AS hist_mean_cases,
         IFNULL(r.hist_active_rate,0) AS hist_active_rate,
         IFNULL(r.hist_total_cases,0) AS hist_total_cases
  FROM nearest n LEFT JOIN recur r USING (cell_lat, cell_lon)
),

norm AS (
  SELECT *,
    -- log scale: case counts are heavily skewed (max 193, median 3), so linear
    -- normalisation against the outlier collapses every other cluster toward 0
    SAFE_DIVIDE(LOG(1 + case_count), LOG(1 + MAX(case_count) OVER ()))  AS c_case_log,
    SAFE_DIVIDE(case_count, MAX(case_count) OVER ())                    AS c_case_lin,
    SAFE_DIVIDE(rain_lag_7to14d, MAX(rain_lag_7to14d) OVER ())          AS c_rain,
    SAFE_DIVIDE(hist_active_rate, NULLIF(MAX(hist_active_rate) OVER (),0)) AS c_recur
  FROM joined
),

scored AS (
  SELECT *,
    ROUND(100*(0.60*IFNULL(c_case_log,0) + 0.25*IFNULL(c_rain,0) + 0.15*IFNULL(c_recur,0)),2) AS risk_score,
    ROUND(100*(0.60*IFNULL(c_case_lin,0) + 0.25*IFNULL(c_rain,0) + 0.15*IFNULL(c_recur,0)),2) AS risk_score_linear
  FROM norm
)

SELECT
  ROW_NUMBER() OVER (ORDER BY risk_score DESC) AS rank,
  cluster_id, locality AS zone, case_count, lat, lon, cell_lat, cell_lon,
  risk_score, risk_score_linear,
  CASE WHEN risk_score >= 70 THEN 'Critical'
       WHEN risk_score >= 50 THEN 'High'
       WHEN risk_score >= 30 THEN 'Moderate'
       ELSE 'Low' END AS risk_level,
  ROUND(rain_14d,2) AS rain_14d_mm,
  ROUND(rain_lag_7to14d,2) AS rain_lag_7to14d_mm,
  station_name AS nearest_station, station_km, days_observed AS rain_days_observed,
  ROUND(hist_active_rate,4) AS hist_active_rate, hist_total_cases,
  ROUND(100*0.60*IFNULL(c_case_log,0),1) AS pts_case_density,
  ROUND(100*0.25*IFNULL(c_rain,0),1)     AS pts_rainfall_lag,
  ROUND(100*0.15*IFNULL(c_recur,0),1)    AS pts_recurrence,
  snapshot_date, CURRENT_TIMESTAMP() AS generated_at
FROM scored ORDER BY rank;
