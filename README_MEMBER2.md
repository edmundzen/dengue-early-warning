# Member 2 – Risk Model

## Overview

This notebook generates a dengue inspection priority list using engineered features created by Member 1. The model calculates a risk score for each geographic cell, ranks locations based on outbreak risk, and stores the results in Google BigQuery for downstream use.

---

## Input

BigQuery Dataset:
- dengue_ew

Input Table:
- features

Input Features:
- case_density_14d
- rain_lag_7to14d
- recurrence

---

## Processing Steps

1. Connect to Google BigQuery.
2. Load the engineered feature table.
3. Calculate a weighted dengue risk score.
4. Rank all locations by descending risk score.
5. Identify the dominant risk factor for each location.
6. Create an inspection priority table.
7. Upload the final results back to BigQuery.

---

## Output

BigQuery Table:
- inspection_priority

Columns:

- rank
- cell_id
- lat
- lon
- date
- risk_score
- top_factor

---

## Technologies Used

- Python
- RAPIDS cuDF
- Pandas
- Google BigQuery
- Google Colab
- NVIDIA T4 GPU

---

## Result

The notebook successfully generates inspection priorities and uploads the final ranked table to:

```
dengue_ew.inspection_priority
```

This table is ready for dashboard visualization and operational decision making.

---

## Author

Member 2
Risk Modeling
Gen AI Academy APAC
