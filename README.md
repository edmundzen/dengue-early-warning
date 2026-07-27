# 🦟 Dengue Sentinel — Cluster Early-Warning System

**AI-powered decision intelligence for dengue prevention in Singapore.**
Predicts high-risk 250m blocks *before* outbreaks escalate — and routes **every** warning through a human before it reaches the field.

> *Gen AI Academy APAC · Team Shehacks · built end-to-end on free-tier cloud ($0 spend).*

**Live:** [Interactive demo](https://dengue-sentinel-demo.netlify.app) · Looker dashboard (public) · [Architecture](SENTINEL_ARCHITECTURE.md)

---

## The problem
Dengue is fought reactively — teams respond *after* cases spike, and manually scanning millions of rows delays inspection and wastes scarce crews. A missed cluster costs lives; a false alarm erodes trust.

## What Sentinel does

Turns **5.1M rows of real NEA dengue cluster data (2015–2020)** and **live NEA rainfall readings** into a **14-day risk forecast per 250m cell** (BigQuery ML ARIMA_PLUS), scores and ranks every block by 
case density, lagged rainfall and recurrence, then routes thehighest-risk clusters through an **Officer-of-the-Day approval gate** — each decision logged with identity and timestamp — before approved alerts reach field teams via**Telegram**.

## Workflow
```
NEA cases + rainfall  →  BigQuery pipeline (5.1M rows)  →  ARIMA_PLUS forecast + weighted risk score
   →  alert queue (Critical/High)  →  Gemini severity alerts + "Ask Sentinel" chatbot
   →  OFFICER OF THE DAY approves/rejects (logged)  →  Telegram  →  field officers
```
A live **Looker Studio** dashboard spans the flow: risk map · this-week inspection list (with town names: Tai Seng, Bedok, Rochor…) · 14-day forecast · officer console.

## Key features
- **14-day forecast** per 250m cell (BigQuery ML ARIMA_PLUS)
- **Weighted risk score** — case density 60% · rainfall lag 25% · recurrence 15%
- **Gemini AI briefs** — severity alerts, executive summaries, recommendations
- **"Ask Sentinel" chatbot** — grounded Q&A over the data
- **Human-in-the-loop gate** — no warning ships without a logged officer decision
- **Telegram delivery** of approved alerts to field teams

## Tech stack (all free-tier)
Google Cloud — **BigQuery**, **BigQuery ML (ARIMA_PLUS)**, Cloud Storage, **Gemini** · **NVIDIA T4 + RAPIDS cuDF** (Colab) · **Looker Studio** · **Supabase** (writable officer decisions) · **Telegram Bot API**.

## Reproduce
1. **BigQuery:** run [`sql/01_bigquery_setup.sql`](sql/01_bigquery_setup.sql) — views, alert queue, AI alerts (idempotent, sandbox-safe).
2. **Supabase:** run [`sql/02_supabase_setup.sql`](sql/02_supabase_setup.sql) — officer decision log.
3. **Notebooks:** `member1_data_pipeline.ipynb` (data) · `member2_risk_model.ipynb` (risk + forecast) · `member4_gemini.ipynb` (Gemini, chatbot, Telegram).
4. **Dashboard:** Looker Studio, 3 pages (see [SENTINEL_ARCHITECTURE.md](SENTINEL_ARCHITECTURE.md)).

## Team
| | Member | Owns |
|---|---|---|
| M1 | Edmund Anthony | Data pipeline (`member1_data_pipeline.ipynb`) |
| M2 | Aadi Gupta | Risk model + forecast (`member2_risk_model.ipynb`) |
| M3 | Nandani Chauhan | Looker dashboard |
| M4 | Shraddha Pal | Gemini AI, chatbot, Telegram (`member4_gemini.ipynb`) |

## Data & attribution

| Source | Publisher | Used for | Licence |
|---|---|---|---|
| Dengue Clusters (GEOJSON) | National Environment Agency | Active cluster locations + case counts | [Singapore Open Data Licence v1.0](https://data.gov.sg/open-data-licence) |
| Historical cluster snapshots | NEA, via the `outbreak.sgcharts.com` archive | 2015–2020 case time series (1,954 days) | Singapore Open Data Licence v1.0 |
| Realtime Rainfall Readings | NEA / Meteorological Service Singapore | Per-station daily rainfall, the lagged rainfall risk driver | Singapore Open Data Licence v1.0 |

> Contains information from the National Environment Agency, the Meteorological Service
> Singapore, and the Housing & Development Board, accessed via data.gov.sg and used under
> the Singapore Open Data Licence version 1.0.

All sources are registered in BigQuery at `dengue_ew.source_registry` with publisher,
licence, coverage and update cadence. Every ingested row carries a `source_key` back to
that table, so any figure on the dashboard is traceable to its origin.

**Rainfall — a documented modelling choice.** Rainfall for the live inspection window is
real per-station data from the NEA rainfall API, ingested daily by `m1_daily_ingest.py`.
Historical rainfall for 2015–2020 is **modelled, not observed** — the archive does not
provide per-cell rainfall history at this resolution, so a seasonally-shaped series is
used for ARIMA training only. It is never presented as measured weather.

**Freshness.** `dengue_ew.v_data_freshness` reports the latest data date and staleness in
days for every layer. Run it before any demo:

```sql
SELECT * FROM `dengue-early-warning.dengue_ew.v_data_freshness` ORDER BY days_stale DESC;
```
---
*"No warning reaches the field without a human decision — logged, timestamped, accountable."*
