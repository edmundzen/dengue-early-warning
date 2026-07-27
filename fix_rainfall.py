import sys, time
from datetime import datetime, timedelta, timezone
import requests
from google.cloud import bigquery

PROJECT, DATASET = "dengue-early-warning", "dengue_ew"
TABLE = f"{PROJECT}.{DATASET}.weather_daily_raw"
DAYS = 45
SGT = timezone(timedelta(hours=8))
TODAY = datetime.now(SGT).date()
BASE = "https://api-open.data.gov.sg/v2/real-time/api/rainfall"

client = bigquery.Client(project=PROJECT)
session = requests.Session()
schema = client.get_table(TABLE).schema

have = {r.obs_date for r in client.query(
    f"SELECT DISTINCT obs_date FROM `{TABLE}`").result()}
print(f"{len(have)} days already loaded\n")


def get_with_retry(params, tries=7):
    """data.gov.sg throttles bursts. Back off and keep going."""
    delay = 15.0
    for _ in range(tries):
        r = session.get(BASE, params=params, timeout=60)
        if r.status_code == 429:
            wait = float(r.headers.get("Retry-After", delay))
            print(f"        429 - waiting {wait:.0f}s", flush=True)
            time.sleep(wait)
            delay = min(delay * 2, 60)
            continue
        r.raise_for_status()
        time.sleep(1.0)          # pace the next page
        return r
    raise RuntimeError("still rate limited after retries")


def fetch_day(day):
    meta, totals, stamps, token, pages = {}, {}, set(), None, 0
    while True:
        params = {"date": day.isoformat()}
        if token:
            params["paginationToken"] = token
        payload = get_with_retry(params).json()
        if payload.get("code") not in (0, None):
            raise RuntimeError(payload.get("errorMsg"))
        data = payload.get("data") or {}
        for s in data.get("stations") or []:
            loc = s.get("location") or {}
            sid = s.get("id") or s.get("deviceId")
            if sid:
                meta[sid] = (s.get("name"), loc.get("latitude"), loc.get("longitude"))
        for block in data.get("readings") or []:
            if block.get("timestamp"):
                stamps.add(block["timestamp"])
            for item in block.get("data") or []:
                sid, val = item.get("stationId"), item.get("value")
                if sid is not None and val is not None:
                    totals[sid] = totals.get(sid, 0.0) + float(val)
        pages += 1
        token = data.get("paginationToken")
        if not token or pages >= 60:
            break

    now = datetime.now(timezone.utc).isoformat()
    rows = [{"obs_date": day.isoformat(), "ingested_at": now, "station_id": sid,
             "station_name": meta.get(sid, (None, None, None))[0],
             "lat": meta.get(sid, (None, None, None))[1],
             "lon": meta.get(sid, (None, None, None))[2],
             "rain_mm": round(mm, 3), "source_key": "nea_rainfall"}
            for sid, mm in totals.items()]
    return rows, len(stamps), pages


means, failed = [], []
todo = [d for d in (TODAY - timedelta(days=n) for n in range(1, DAYS + 1))
        if d not in have]
print(f"{len(todo)} days to fetch\n")

for i, day in enumerate(todo, 1):
    try:
        rows, intervals, pages = fetch_day(day)
        if not rows:
            print(f"  [{i}/{len(todo)}] {day}  no readings")
            continue
        client.query(f"DELETE FROM `{TABLE}` WHERE obs_date = DATE('{day}')").result()
        cfg = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
            schema=schema,
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON)
        client.load_table_from_json(rows, TABLE, job_config=cfg).result()
        mean = sum(r["rain_mm"] for r in rows) / len(rows)
        means.append(mean)
        print(f"  [{i}/{len(todo)}] {day}  {len(rows):>3} stn · {intervals:>3} int · "
              f"mean {mean:6.2f} mm", flush=True)
    except KeyboardInterrupt:
        print("\nStopped. Re-run to resume.")
        sys.exit(0)
    except Exception as exc:
        failed.append(day)
        print(f"  [{i}/{len(todo)}] {day}  FAILED: {exc}")

if means:
    print(f"\nLoaded {len(means)} more days · mean {sum(means)/len(means):.2f} mm")
if failed:
    print(f"{len(failed)} still failed - just re-run, it resumes.")