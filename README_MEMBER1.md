# Member 1 — Data & Pipeline (Runbook)

## Your deliverables (what the team gets from you)
1. **`dengue_ew.telemetry_daily`** (BigQuery) — cell_id, lat, lon, date, case_count, rain_mm
2. **`dengue_ew.features`** (BigQuery) + `handoff/features_latest.csv` — adds case_density_14d, rain_lag_7to14d, recurrence
3. The **data contract** message posted in team chat (bottom of the notebook)

Member 2 builds risk scores on your `features` table. Nothing else in the project starts until table #1 exists — you are the critical path for Day 1.

## Real data sources (verified July 2026)
| Source | What | How |
|---|---|---|
| NEA Dengue Clusters (data.gov.sg, id `d_dbfabf16158d1b0e1c420627c0819168`) | TODAY's active clusters, polygons + case counts | poll-download API — coded in notebook §1 |
| outbreak.sgcharts.com/data | HISTORICAL cluster snapshots (CSV, lat/lon/cases/date, since 2013) | Manual download into `data/history/` — notebook §2 loads them |
| data.gov.sg rainfall API | Daily rainfall | notebook §3 (has retry + fallback; NEA has flagged station outages) |

**Key insight:** the official NEA feed is a snapshot with NO history. The SGCharts archive supplies the time series your 14-day rolling features need. Attribution line (already in the notebook) must appear in the deck.

## Day 1 runbook
1. Open `member1_data_pipeline.ipynb` in Colab (no GPU needed for your part)
2. Run ALL cells first on the built-in synthetic fallback — proves the pipeline before real data (10 min)
3. Download ~30 recent cluster CSVs from outbreak.sgcharts.com/data → upload to `data/history/` in Colab
4. Re-run §2 onward — verify row counts and the date range printed
5. Get the team GCP project id from whoever owns it → set `RUN_BQ=True`, `PROJECT=...` → run §6
6. Post the data contract table in team chat, tag Member 2: "features table is live"

## Gotchas
- SGCharts CSVs use YYMMDD dates — the loader handles it, but eyeball the printed date range
- The bounds filter drops anything outside Singapore (bad geocodes exist in scraped data)
- Zero-fill matters: cells with no cases on a date must exist as 0 rows or rolling windows lie
- If BigQuery auth fights you for >15 min, ship `features_latest.csv` to Member 2 directly and fix BQ after — the CSV is the same contract
