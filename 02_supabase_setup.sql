-- ============================================================
-- Dengue Sentinel — Supabase (Postgres) setup
-- Holds Officer-of-the-Day decisions. Supabase is WRITABLE (unlike the
-- BigQuery sandbox, which blocks UPDATE), so live approve/reject writes here.
-- Run in Supabase → SQL Editor.
-- ============================================================

create table if not exists public.alert_decisions (
  id          bigint generated always as identity primary key,
  cell_id     text,
  alert_id    text,
  decision    text check (decision in ('Approved','Rejected')),
  officer     text,
  reason      text,
  decided_at  timestamptz not null default now()
);

comment on table public.alert_decisions is
  'Officer of the Day approve/reject decisions — the writable audit log for Sentinel.';

-- Demo seed (2 Approved / 1 Rejected). Remove for a clean production start.
insert into public.alert_decisions (cell_id, decision, officer, reason) values
 ('1.33425_103.8825','Approved','Officer Tan','Tai Seng — highest case density (86), deploy team'),
 ('1.34775_103.95225','Approved','Officer Tan','Changi Business Park — critical cluster, dispatch <48h'),
 ('1.314_103.9275','Rejected','Officer Tan','Bedok — borderline, re-check next cycle')
on conflict do nothing;

-- The demo/notebook writes a live decision like this (Python, supabase-py):
--   sb.table("alert_decisions").insert({
--     "cell_id": cell_id, "decision": "Approved",
--     "officer": "Officer Tan", "reason": "Inspection required"
--   }).execute()
