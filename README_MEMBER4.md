# Member 4 — Gemini AI & Integration (Runbook)

Owns the AI layer and the human-in-the-loop delivery: turns ranked cells into readable warnings, answers officer questions, gates every warning on a human decision, and pushes approved alerts to the field.

## Deliverables (what the team gets from you)
1. **`dengue_ew.alert_messages`** (BigQuery) — per HIGH/Critical cell: a severity alert, executive summary, and recommendation. **Pre-generated ("quota-proof")** so the demo never depends on live Gemini quota.
2. **Ask Sentinel** — a grounded Q&A chatbot officers can ask about the data.
3. **Human-in-the-loop approval** → writes officer decisions to **Supabase `alert_decisions`** (identity + timestamp).
4. **Telegram notifications** — approved alerts delivered to field officers.

Consumers: Member 3 (Looker Page 3 reads `v_officer_queue` for pending + Supabase `alert_decisions` for the decision log).

## What it does
```
alert_queue (Critical/High)  →  Gemini: severity alert · exec summary · recommendation
                             →  Ask Sentinel chatbot (grounded Q&A)
                             →  Officer of the Day approves/rejects  →  Supabase alert_decisions
                             →  approved only  →  Telegram → field officers
```

## Runbook (`member4_gemini.ipynb`, Colab)
1. `pip install google-genai` · set the **Gemini API key** (AI Studio) via Colab secret / env — **never commit keys**.
2. Authenticate to BigQuery; read `inspection_priority_v2` / `alert_queue`.
3. Generate alert message + summary + recommendation for **HIGH/Critical rows only**.
4. Run the **Ask Sentinel** chatbot cell (grounded on the data).
5. Officer approve/reject → `INSERT` into Supabase `alert_decisions`.
6. Send **approved** alerts to Telegram (`BOT_TOKEN`, `CHAT_ID`).

## Gotchas
- **Gemini free-tier daily quota → `429 RESOURCE_EXHAUSTED`.** Mitigations shipped: pre-generate the 7 HIGH/Critical alerts into `alert_messages`; add exponential backoff + a template fallback; use `flash-lite`; only score HIGH/Critical rows. Regenerate live when quota resets — schema stays the same.
- **Stable `alert_id`.** `alert_queue` uses `TO_HEX(MD5(cell_id))`, not `GENERATE_UUID()`, so officer decisions survive notebook re-runs. Do **not** revert — random ids orphan every prior decision.
- **Supabase for decisions.** BigQuery sandbox blocks `UPDATE`, so approve/reject writes go to Supabase (writable). Looker connects via the **Session Pooler** (IPv4), not the direct `db.…` host.
- **Telegram:** send only after officer sign-off; the message names the town (e.g. "Tai Seng") and the action.
- **Keys:** keep `BOT_TOKEN` and the Gemini key out of the repo.

Attribution: AI outputs are grounded in NEA dengue + rainfall data (data.gov.sg / SGCharts archive).
