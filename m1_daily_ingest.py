#!/usr/bin/env python3
"""
M1 — Dengue Sentinel daily ingest
=================================
Pulls REAL NEA dengue clusters + NEA/MSS rainfall from data.gov.sg and lands them
in BigQuery with full source attribution.

Designed to be RE-RUNNABLE: running it twice on the same day produces the same
result (it replaces that day's partition rather than appending duplicates).

Run it:
  * locally / Colab:  python m1_daily_ingest.py
  * Cloud Run Job or Cloud Function, triggered daily by Cloud Scheduler.

Target tables (already created in BigQuery):
  dengue_ew.nea_clusters_raw   — one snapshot per day, partitioned by snapshot_date
  dengue_ew.weather_daily_raw  — daily rainfall per station, partitioned by obs_date
  dengue_ew.source_registry    — attribution (already populated)

WHY a daily snapshot: the NEA clusters dataset is snapshot-only. It tells you the
ACTIVE clusters right now and carries no history. History is therefore something
we accumulate — one row set per day, from the first run onward.
"""

import json
import sys
from datetime import datetime, timedelta, timezone

import requests
from google.cloud import bigquery

# ----------------------------------------------------------------------------
# CONFIG
# ----------------------------------------------------------------------------
PROJECT = "dengue-early-warning"
DATASET = "dengue_ew"

# Verified against member1_data_pipeline.ipynb in the repo.
# data.gov.sg dataset ID for "Dengue Clusters (GEOJSON)", NEA.
CLUSTERS_DATASET_ID = "d_dbfabf16158d1b0e1c420627c0819168"

# Rainfall backfill: how many days of REAL rainfall to pull on this run.
# The live inspection map needs at least 30 (14-day rolling window + 7-day lag).
# Re-runs skip dates already present, so this is safe to raise later.
RAINFALL_BACKFILL_DAYS = 45

SGT = timezone(timedelta(hours=8))
TODAY = datetime.now(SGT).date()

client = bigquery.Client(project=PROJECT)


# ----------------------------------------------------------------------------
# 1. NEA DENGUE CLUSTERS  (active clusters — today's snapshot)
# ----------------------------------------------------------------------------
def fetch_clusters():
    """Returns a list of cluster dicts. Polygon centroid is used as the point."""
    meta_url = (
        "https://api-open.data.gov.sg/v1/public/api/datasets/"
        f"{CLUSTERS_DATASET_ID}/poll-download"
    )
    meta = requests.get(meta_url, timeout=60).json()
    if meta.get("code") != 0:
        raise RuntimeError(f"data.gov.sg poll-download failed: {meta.get('errMsg')}")

    gj = requests.get(meta["data"]["url"], timeout=60).json()

    rows = []
    for feat in gj.get("features", []):
        props = feat.get("properties", {}) or {}
        geom = feat.get("geometry", {}) or {}
        coords = geom.get("coordinates", [])

        # centroid = mean of the polygon's ring vertices
        lat = lon = None
        if geom.get("type") == "Polygon" and coords:
            ring = coords[0]
            lon = sum(c[0] for c in ring) / len(ring)
            lat = sum(c[1] for c in ring) / len(ring)
        elif geom.get("type") == "MultiPolygon" and coords:
            ring = coords[0][0]
            lon = sum(c[0] for c in ring) / len(ring)
            lat = sum(c[1] for c in ring) / len(ring)

        # NEA's property names vary in case across releases — try the usual suspects
        def pick(*names):
            for n in names:
                if props.get(n) not in (None, ""):
                    return props[n]
            return None

        case_count = pick("CASE_SIZE", "case_size", "CASES", "cases")
        locality = pick("LOCALITY", "locality", "Description", "DESCRIPTION")
        cluster_id = pick("CLUSTER_ID", "cluster_id", "OBJECTID", "Name")

        try:
            case_count = int(float(case_count)) if case_count is not None else None
        except (TypeError, ValueError):
            case_count = None

        rows.append(
            {
                "snapshot_date": TODAY.isoformat(),
                "ingested_at": datetime.now(timezone.utc).isoformat(),
                "cluster_id": str(cluster_id) if cluster_id is not None else None,
                "locality": str(locality)[:1000] if locality else None,
                "case_count": case_count,
                "lat": lat,
                "lon": lon,
                "source_key": "nea_dengue_clusters",
            }
        )
    return rows


# ----------------------------------------------------------------------------
# 2. RAINFALL  (per station, aggregated to a daily total)
# ----------------------------------------------------------------------------
def fetch_rainfall(day):
    """Daily rainfall per station for `day`. 5-min readings summed to mm/day."""
    endpoints = [
        f"https://api-open.data.gov.sg/v2/real-time/api/rainfall?date={day.isoformat()}",
        f"https://api.data.gov.sg/v1/environment/rainfall?date={day.isoformat()}",
    ]
    payload = None
    for url in endpoints:
        try:
            r = requests.get(url, timeout=60)
            if r.ok:
                payload = r.json()
                break
        except requests.RequestException:
            continue
    if payload is None:
        raise RuntimeError("rainfall API unreachable on both v2 and v1 endpoints")

    data = payload.get("data", payload)
    stations = data.get("stations", data.get("metadata", {}).get("stations", []))
    readings = data.get("readings", [])

    meta = {}
    for s in stations:
        loc = s.get("location", s.get("labelLocation", {})) or {}
        meta[s.get("id") or s.get("stationId")] = (
            s.get("name"),
            loc.get("latitude"),
            loc.get("longitude"),
        )

    totals = {}
    for block in readings:
        items = block.get("data", block.get("readings", []))
        for item in items:
            sid = item.get("stationId") or item.get("station_id")
            val = item.get("value")
            if sid is None or val is None:
                continue
            totals[sid] = totals.get(sid, 0.0) + float(val)

    now = datetime.now(timezone.utc).isoformat()
    rows = []
    for sid, mm in totals.items():
        name, lat, lon = meta.get(sid, (None, None, None))
        rows.append(
            {
                "obs_date": day.isoformat(),
                "ingested_at": now,
                "station_id": sid,
                "station_name": name,
                "lat": lat,
                "lon": lon,
                "rain_mm": round(mm, 3),
                "source_key": "nea_rainfall",
            }
        )
    return rows


# ----------------------------------------------------------------------------
# 3. IDEMPOTENT LOAD — replace the day's partition, never append blindly
# ----------------------------------------------------------------------------
def load(table, rows, date_col, day):
    if not rows:
        print(f"  ⚠️  {table}: no rows returned — skipping (partition left untouched)")
        return 0

    full = f"{PROJECT}.{DATASET}.{table}"
    client.query(
        f"DELETE FROM `{full}` WHERE {date_col} = DATE('{day.isoformat()}')"
    ).result()

    errors = client.insert_rows_json(full, rows)
    if errors:
        raise RuntimeError(f"{table} insert errors: {errors[:3]}")

    print(f"  ✅ {table}: {len(rows)} rows for {day}")
    return len(rows)


def main():
    print(f"M1 daily ingest · {datetime.now(SGT):%Y-%m-%d %H:%M} SGT")

    print("\n[1/2] NEA dengue clusters")
    clusters = fetch_clusters()
    load("nea_clusters_raw", clusters, "snapshot_date", TODAY)
    if clusters:
        total = sum(c["case_count"] or 0 for c in clusters)
        print(f"      {len(clusters)} active clusters · {total} cases")

    # Rainfall. Ingests the actual station-level rainfall from NEA.
    # Rainfall carries 25% of the risk score, so this utilizes observed measurements
    # rather than historical seasonal averages.
    # Backfills RAINFALL_BACKFILL_DAYS and skips dates already loaded,
    # so re-running costs nothing and you can raise the window any time.
    # ------------------------------------------------------------------
    print(f"\n[2/2] Rainfall — backfilling up to {RAINFALL_BACKFILL_DAYS} days")

    have = {
        r.obs_date
        for r in client.query(
            f"SELECT DISTINCT obs_date FROM `{PROJECT}.{DATASET}.weather_daily_raw`"
        ).result()
    }

    # yesterday backwards: today's readings are still accumulating
    wanted = [TODAY - timedelta(days=n) for n in range(1, RAINFALL_BACKFILL_DAYS + 1)]
    todo = [d for d in wanted if d not in have]
    print(f"      {len(have)} days already loaded · {len(todo)} to fetch")

    loaded = failed = 0
    for day in todo:
        try:
            rows = fetch_rainfall(day)
            if rows:
                load("weather_daily_raw", rows, "obs_date", day)
                loaded += 1
            else:
                print(f"  ⚠️  {day}: no readings returned")
                failed += 1
        except Exception as exc:
            print(f"  ⚠️  {day}: {exc}")
            failed += 1

    print(f"      rainfall: {loaded} days loaded, {failed} unavailable")

    print("\nFreshness after load:")
    q = f"SELECT * FROM `{PROJECT}.{DATASET}.v_data_freshness` ORDER BY days_stale DESC"
    for r in client.query(q).result():
        stale = "—" if r.days_stale is None else f"{r.days_stale}d stale"
        print(f"  {r.table_name:<24} {str(r.latest_data):<12} {stale:<12} {r.row_count:>9,} rows")

    print("\nDone.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"\n❌ FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
