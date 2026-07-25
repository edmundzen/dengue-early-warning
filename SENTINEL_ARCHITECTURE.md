# Dengue Sentinel — Architecture & Reproduce Guide

AI-powered dengue cluster early-warning for Singapore. Predicts high-risk 250m blocks, and routes **every** warning through a human before it reaches the field.

## The flow
```
NEA cases + rainfall (data.gov.sg + SGCharts)
        ↓  member1 — data pipeline
BigQuery: telemetry_daily (5.1M) · features · forecast_14d (ARIMA_PLUS)
        ↓  member2 — risk model + ranking
inspection_priority_v2  →  alert_queue (Critical/High)
        ↓  member4 — Gemini AI
alert_messages (severity alert · summary · recommendation) + Ask Sentinel chatbot
        ↓  Officer of the Day (HUMAN GATE)
alert_decisions (Supabase, writable — approve/reject, logged with identity + timestamp)
        ↓  approved only
Telegram → field officers
```
A live **Looker Studio** dashboard (member3) spans the whole flow: risk map · this-week inspection list · 14-day forecast · officer console.

## Reproduce (order matters)
1. **BigQuery** — run `sql/01_bigquery_setup.sql` (creates all views, `alert_queue`, `alert_messages`). Idempotent, runs on the free sandbox (no DML).
2. **Supabase** — run `sql/02_supabase_setup.sql` (creates + seeds `alert_decisions`).
3. **Looker** — 3 pages: Inspection Priority (`v_latest_cells`, `v_top20`, `v_daily_trend`), Forecast (`inspection_priority_v2` / `forecast_14d`), Officer of the Day (`v_officer_queue` for pending; Supabase `alert_decisions` for the decision log).
4. **Gemini / Telegram** — `member4_gemini.ipynb` (alerts, chatbot, Telegram send).

## Data dictionary (key objects)
| Object | Type | Purpose |
|---|---|---|
| `telemetry_daily` | table | 5.1M rows — daily cases + rainfall per cell |
| `inspection_priority_v2` | table | 2,616 cells with weighted `risk_score`, `forecast_value` |
| `forecast_14d` | table | BigQuery ML ARIMA_PLUS 14-day forecast (36,624 rows) |
| `v_daily_trend` | view | daily cases vs rainfall → trend chart |
| `v_latest_cells` | view | current snapshot per cell → risk map |
| `v_top20` | view | top-20 inspection list **with town names** (Tai Seng, Bedok…) |
| `alert_queue` | table | HIGH/Critical alerts; **stable `alert_id = MD5(cell_id)`** |
| `v_officer_queue` | view | pending alerts → Page 3 pending table |
| `alert_messages` | table | 7 pre-generated AI alerts (quota-proof) with zones |
| `alert_decisions` (Supabase) | table | officer approve/reject audit log (writable) |

## Design notes
- **Weighted risk score:** case density 60% · rainfall lag 25% · recurrence 15%.
- **Stable `alert_id`:** derived from `cell_id` (`MD5`) so officer decisions in Supabase survive notebook re-runs. (Do **not** revert to `GENERATE_UUID()` — it orphans decisions.)
- **Human-in-the-loop:** BigQuery holds the *pending* queue; Supabase holds the *decisions*. One store each, no overlap. No warning ships without an approval logged with identity + timestamp.
- **$0 / free-tier:** BigQuery sandbox (no DML → tables built via `CREATE TABLE AS SELECT`), Colab T4, Gemini AI Studio, Supabase free, Netlify, Telegram. AI alerts are pre-generated so the demo never depends on live Gemini quota.

## Live links
- Demo: https://dengue-sentinel-demo.netlify.app
- Dashboard: Looker Studio (public)
