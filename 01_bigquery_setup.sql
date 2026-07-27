-- ============================================================
-- Dengue Sentinel — BigQuery setup (idempotent, sandbox-safe)
-- Project: dengue-early-warning   Dataset: dengue_ew
-- Run top-to-bottom to reproduce the live analytics + officer layer.
-- No DML (INSERT/UPDATE) is used, so it runs on the BigQuery free sandbox.
--
-- Prerequisites (built by member1 / member2, already in the dataset):
--   telemetry_daily          (5.1M rows: date, cell_id, lat, lon, case_count, rain_mm)
--   features, forecast_14d, arima_plus_model
--   inspection_priority_v2   (2,616 cells with risk_score, forecast_value, etc.)
-- ============================================================

-- 1) Daily trend (cases vs rainfall) — feeds the Looker trend chart
CREATE OR REPLACE VIEW `dengue-early-warning.dengue_ew.v_daily_trend` AS
SELECT DATE(date) AS date,
       SUM(case_count) AS cases,
       AVG(rain_mm)    AS rain_mm
FROM `dengue-early-warning.dengue_ew.telemetry_daily`
GROUP BY date
ORDER BY date;

-- 2) Latest cells — feeds the risk map (current snapshot per cell)
CREATE OR REPLACE VIEW `dengue-early-warning.dengue_ew.v_latest_cells` AS
SELECT cell_id, lat, lon, date, case_count, case_density_14d, rain_lag_7to14d,
       recurrence, forecast_value, risk_score, rank, risk_level
FROM `dengue-early-warning.dengue_ew.inspection_priority_v2`
WHERE date = (SELECT MAX(date) FROM `dengue-early-warning.dengue_ew.inspection_priority_v2`);

-- 3) Top-20 inspection list (with Singapore town/zone names)
CREATE OR REPLACE VIEW `dengue-early-warning.dengue_ew.v_top20` AS
SELECT rank, cell_id,
  CASE cell_id
    WHEN '1.33425_103.8825'  THEN 'Tai Seng'
    WHEN '1.34775_103.95225' THEN 'Changi Business Park'
    WHEN '1.314_103.9275'    THEN 'Bedok'
    WHEN '1.314_103.85325'   THEN 'Rochor'
    WHEN '1.3815_103.9365'   THEN 'Pasir Ris'
    WHEN '1.395_103.869'     THEN 'Buangkok'
    WHEN '1.27575_103.8285'  THEN 'HarbourFront'
    ELSE '—' END AS zone,
  case_density_14d, rain_lag_7to14d, recurrence, risk_score, risk_level
FROM `dengue-early-warning.dengue_ew.inspection_priority_v2`
ORDER BY rank
LIMIT 20;

-- 4) Alert queue — HIGH/Critical cells awaiting officer decision.
--    alert_id is STABLE (derived from cell_id) so officer decisions survive re-runs.
CREATE OR REPLACE TABLE `dengue-early-warning.dengue_ew.alert_queue` AS
SELECT
  TO_HEX(MD5(cell_id)) AS alert_id,
  cell_id, lat, lon, risk_score, risk_level, forecast_value,
  case_density_14d, recurrence, rank,
  1 AS blocks,
  '14d' AS forecast_window,
  CASE
    WHEN case_density_14d*0.60 >= rain_lag_7to14d*0.25
     AND case_density_14d*0.60 >= recurrence*0.15 THEN 'case density'
    WHEN rain_lag_7to14d*0.25 >= recurrence*0.15   THEN 'rainfall lag'
    ELSE 'recurrence' END AS top_factor,
  CURRENT_TIMESTAMP() AS created_at
FROM `dengue-early-warning.dengue_ew.inspection_priority_v2`
WHERE risk_level IN ('Critical','High');

-- 5) Officer queue (pending) — feeds Page 3 "Officer of the Day" pending table.
--    Officer DECISIONS live in Supabase (writable); BigQuery sandbox blocks UPDATE.
CREATE OR REPLACE VIEW `dengue-early-warning.dengue_ew.v_officer_queue` AS
SELECT alert_id, cell_id, blocks, risk_score, risk_level,
       forecast_window, top_factor, created_at,
       'PENDING' AS status
FROM `dengue-early-warning.dengue_ew.alert_queue`
ORDER BY risk_score DESC;

-- 6) AI alert messages (Gemini-generated baseline demo seeds).
--    Stores the generated severity alerts, executive summaries, and action recommendations.
CREATE OR REPLACE TABLE `dengue-early-warning.dengue_ew.alert_messages` AS
SELECT * FROM UNNEST([
STRUCT(1 AS rank, '1.33425_103.8825' AS cell_id, 'Critical' AS risk_level, 38.61 AS risk_score, 'Tai Seng' AS zone,
 'Severity: CRITICAL  ·  Tai Seng (1.33425, 103.8825)\nReason: Highest 14-day case density on the island (86 cases per cell) with a 4.1-case forecast; sustained transmission cluster.\nRecommended Actions: Deploy inspection team within 24 hours; source reduction and larviciding; issue resident advisory.' AS alert_message,
 'Tai Seng is the top-ranked dengue cluster (critical risk 38.6) — highest recorded case density (86 in 14 days) and a rising 4.1-case forecast. Immediate inspection and vector control warranted.' AS executive_summary,
 '1) Dispatch officers within 24h for door-to-door inspection. 2) Larvicide all stagnant water and drains. 3) Notify residents and schedule follow-up fogging.' AS recommendation),
STRUCT(2, '1.34775_103.95225', 'Critical', 34.49, 'Changi Business Park',
 'Severity: CRITICAL  ·  Changi Business Park\nReason: Second-highest cluster (76 cases, forecast 3.6) indicating active transmission.\nRecommended Actions: Inspect within 24-48 hours; remove breeding habitats; alert nearby clinics.',
 'Changi Business Park scores 34.5 from very high case density (76) and a 3.6-case forecast. Prioritise alongside the top cell.',
 '1) Schedule inspection within 48h. 2) Clear standing water and containers. 3) Brief local clinics on surge risk.'),
STRUCT(3, '1.314_103.9275', 'High', 24.2, 'Bedok',
 'Severity: HIGH  ·  Bedok\nReason: Elevated case density (51) with a 2.4-case forecast; emerging hotspot.\nRecommended Actions: Inspect this week; targeted source reduction; monitor for escalation.',
 'Bedok is a high-risk emerging hotspot (score 24.2) with 51 recent cases and a 2.4 forecast.',
 '1) Add to this week inspection route. 2) Remove breeding sites in common areas. 3) Re-check density next cycle.'),
STRUCT(4, '1.314_103.85325', 'High', 23.0, 'Rochor',
 'Severity: HIGH  ·  Rochor\nReason: 48 cases with a 2.3 forecast AND the highest recurrence in the queue (0.32) - a repeat hotspot.\nRecommended Actions: Inspect this week; investigate the persistent breeding source; schedule a follow-up visit.',
 'Rochor scores 23.0 and stands out for recurrence (0.32) - it keeps flaring up. Points to an unresolved breeding source needing a root-cause visit.',
 '1) Inspect and trace the recurring source. 2) Larvicide and seal identified habitats. 3) Schedule a mandatory follow-up visit.'),
STRUCT(5, '1.3815_103.9365', 'High', 21.72, 'Pasir Ris',
 'Severity: HIGH  ·  Pasir Ris\nReason: 45 cases, forecast 2.1; steady transmission.\nRecommended Actions: Inspect this week; routine source reduction; community advisory.',
 'Pasir Ris (score 21.7) shows steady transmission with 45 cases and a 2.1 forecast.',
 '1) Include in weekly inspection. 2) Clear stagnant water. 3) Distribute prevention advisory.'),
STRUCT(6, '1.395_103.869', 'High', 21.31, 'Buangkok',
 'Severity: HIGH  ·  Buangkok\nReason: 44 cases, forecast 2.1; active cluster.\nRecommended Actions: Inspect this week; source reduction; monitor trend.',
 'Buangkok (score 21.3) is an active high-risk cluster with 44 cases and a 2.1 forecast.',
 '1) Add to weekly route. 2) Remove breeding habitats. 3) Track density next cycle.'),
STRUCT(7, '1.27575_103.8285', 'High', 20.07, 'HarbourFront',
 'Severity: HIGH  ·  HarbourFront\nReason: 41 cases, forecast 1.9; lower bound of the high band.\nRecommended Actions: Inspect this week; standard source reduction; reassess next cycle.',
 'HarbourFront (score 20.1) sits at the lower edge of the high-risk band with 41 cases and a 1.9 forecast.',
 '1) Schedule inspection this week. 2) Source reduction on common breeding sites. 3) Reassess at next update.')
]);

-- Verify
SELECT 'v_daily_trend' o, COUNT(*) n FROM `dengue-early-warning.dengue_ew.v_daily_trend`
UNION ALL SELECT 'v_latest_cells', COUNT(*) FROM `dengue-early-warning.dengue_ew.v_latest_cells`
UNION ALL SELECT 'v_top20', COUNT(*) FROM `dengue-early-warning.dengue_ew.v_top20`
UNION ALL SELECT 'alert_queue', COUNT(*) FROM `dengue-early-warning.dengue_ew.alert_queue`
UNION ALL SELECT 'v_officer_queue', COUNT(*) FROM `dengue-early-warning.dengue_ew.v_officer_queue`
UNION ALL SELECT 'alert_messages', COUNT(*) FROM `dengue-early-warning.dengue_ew.alert_messages`;
