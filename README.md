# 🦟 Dengue Sentinel — Cluster Early-Warning System

**AI-powered decision intelligence for dengue prevention in Singapore.**
Predicts high-risk 250m blocks *before* outbreaks escalate — and routes **every** warning through a human before it reaches the field.

> *Gen AI Academy APAC · Team Shehacks · built end-to-end on free-tier cloud ($0 spend).*

**Live:** [Interactive demo](https://dengue-sentinel-demo.netlify.app) · Looker dashboard (public) · [Architecture](SENTINEL_ARCHITECTURE.md)

---

## The problem
Dengue is fought reactively — teams respond *after* cases spike, and manually scanning millions of rows delays inspection and wastes scarce crews. A missed cluster costs lives; a false alarm erodes trust.

## What Sentinel does
Turns **5.1M rows of real NEA case + rainfall data (2015–2020)** into a **14-day risk forecast per 250m cell** (BigQuery ML ARIMA_PLUS), ranks the highest-risk blocks, and routes the top clusters through an **Officer-of-the-Day approval gate** — every decision logged with identity and timestamp — before approved alerts go to field teams via **Telegram**.

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
Dengue cluster data © National Environment Agency, via data.gov.sg and the outbreak.sgcharts.com archive. Rainfall via data.gov.sg.

---
*"No warning reaches the field without a human decision — logged, timestamped, accountable."*
