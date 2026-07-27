# Member 1 — Data & Pipeline (Runbook)

## Deliverables
| Table | What | Consumer |
|---|---|---|
| `dengue_ew.nea_clusters_raw` | One dated snapshot per day of NEA active clusters | risk layer |
| `dengue_ew.weather_daily_raw` | Daily rainfall per station, 78 stations | risk layer |
| `dengue_ew.source_registry` | Publisher, licence, coverage, cadence per source | attribution |
| `dengue_ew.inspection_priority_live` | Ranked current inspection list | M3 Looker, M4 Gemini |
| `dengue_ew.v_data_freshness` | Latest date + staleness per layer | everyone, before any demo |
| `dengue_ew.telemetry_daily` / `features` | 2015–2020 historical series | M2 ARIMA training only |

## Data sources
| Source | What | Real? |
|---|---|---|
| NEA Dengue Clusters (`d_dbfabf16158d1b0e1c420627c0819168`) | Today's active clusters, polygons + case counts | ✅ real, same-day |
| NEA / MSS Realtime Rainfall API | Per-station daily rainfall | ✅ real, 45 days loaded |
| outbreak.sgcharts.com archive | 2015–2020 cluster case history | ✅ real |
| Historical rainfall 2015–2020 | Rainfall in `telemetry_daily` | ⚠️ **modelled, not observed** — ARIMA training only, documented in README |

**The NEA cluster feed is snapshot-only — it has no history.** Depth accumulates one day at a time from the first run onward. That's a property of the source, and it's why the daily run matters.

## Daily run
```powershell
cd C:\Users\edmun\dengue-early-warning
python fix_rainfall.py        # rainfall: resumable, skips days already loaded
python m1_daily_ingest.py     # clusters + rainfall
```
Then rebuild the risk layer:
```sql
-- 03_live_risk_layer.sql  (idempotent, safe to re-run)
```

## Verify before any demo
```sql
SELECT * FROM `dengue-early-warning.dengue_ew.v_data_freshness` ORDER BY days_stale DESC;
```
Expect `nea_clusters_raw` at 0 days stale and `weather_daily_raw` at 1. The historical
tables will always read ~2,089 days stale — that is correct, they are training data.

Sanity-check rainfall against climatology, not just "did it run":
```sql
SELECT ROUND(AVG(rain_mm),2) AS mean_station_day_mm
FROM `dengue-early-warning.dengue_ew.weather_daily_raw`;
-- Singapore norm is ~6 mm/day. An order of magnitude below means the ingest is broken,
-- not that it stopped raining.
```

## Gotchas — all of these cost us real time on 27 Jul

**The rainfall API paginates.** One request returns the first page of 5-minute readings, not the day. Ignore `paginationToken` and you capture ~2 minutes of weather, get 0.086 mm/day, and conclude Singapore had 31 rainless days in June. Follow the token to the end — a full day is 288 intervals across ~12 pages.

**The rainfall API rate-limits.** Bursting 45 days straight returns HTTP 429 for most of them. Pace requests ~1s apart and back off from 15s on 429. Expect several minutes for a 45-day backfill; make it resumable so Ctrl+C costs nothing.

**Never use streaming inserts for idempotent loads.** `insert_rows_json` puts rows in a buffer that BigQuery refuses to `DELETE` from for up to 90 minutes — so any same-day re-run dies with *"would affect rows in the streaming buffer"*. Use a load job instead: no buffer, works immediately, and it's free where streaming isn't.

**`WRITE_TRUNCATE` on a partition decorator silently appended** rather than replacing, giving 154 stations per day instead of 77 and halving every average. Use an explicit `DELETE ... WHERE obs_date = X` then `WRITE_APPEND`, and always verify row counts per day afterwards.

**Log-scale skewed counts.** Cluster case counts run 2 → 193. Normalising linearly against the max collapses every other cluster toward zero, so a 2-case cluster outranked a 38-case one. Use `LOG(1+x)/LOG(1+max)`.

**Zero-fill matters.** Cells with no cases on a date must exist as 0 rows or rolling windows lie.

**Billing must be linked, not just redeemed.** Redeeming the coupon credits the billing *account*; BigQuery stays in sandbox — and blocks all DML — until that account is linked to the project. Test with a single `INSERT` before writing any other code.

## Current state (27 Jul 2026)
- 17 active clusters · 340 cases · snapshot same-day
- 45 days rainfall · 78 stations · 3,460 station-days · mean 5.71 mm/day
- Rainfall spatially resolved: nearest gauge per cluster, 0.1–1.8 km
- Top risk: Countryside Rd / Lentor Ave — 193 cases, score 83.8, Critical
- 1 Critical · 4 High · 6 Moderate · 6 Low
