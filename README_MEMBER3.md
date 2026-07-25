## Overview

This component represents the Frontend Application tier of the Dengue Cluster Early-Warning System. It translates backend predictive analytics into an enterprise-grade, public-facing **Decision Intelligence Platform** via Google Looker Studio.

## Input

BigQuery Dataset:
dengue-early-warning.dengue_ew

Input Views:

1) v_latest_cells (Risk map)
2) v_top20 (Inspection table)


3) v_daily_trend (Trend chart)


4) v_officer_queue (Officer page)


5) forecast_14d

## Processing Steps

1. Connect Google Looker Studio directly to live BigQuery views.
2. Page 1 (Inspection Priority): Build a Singapore-locked bubble risk map (v_latest_cells), Top-20 inspection table (v_top20), cases vs. rainfall trend chart (v_daily_trend), and an active cells scorecard (COUNT DISTINCT).
3. Page 2 (Forecast): Configure 14-day outbreak trajectory maps, scorecards, and predictive comparison tables.
4. Page 3 (Officer of the Day): Implement real-time status tracking scorecards, pending alert queues, and decision audit logs (v_officer_queue).
5. Deployment: Configure general access permissions to public viewer mode (Anyone with the link) for final submission.

## Output
Dashboard Platform:
https://datastudio.google.com/reporting/6ef1583e-0b14-4367-a29d-51fd1298e839

Key Visualizations:
1) Geospatial Risk Heatmap
2) Top-20 Triage Table
3) Historical Rainfall & Case Trend Chart
4) Officer Approval & Decision Log Queues

## Technologies Used

1) Google Looker Studio
2) Google BigQuery
3) BigQuery ML
4) Python / Pandas
5) Supabase

## Result

The multi-page operational dashboard is fully wired, verified against live BigQuery data, and published publicly as the official working prototype for the project submission.

## Author

Member 3 (Nandani)
UI/UX & Dashboard Analytics
Gen AI Academy APAC
