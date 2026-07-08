# Hospital Operations & Financial Intelligence

A production-style portfolio project demonstrating **Text-to-SQL over structured healthcare data** using Snowflake Cortex Analyst, Cortex Search, and Streamlit — built on synthetic patient data blended with real CMS hospital quality benchmarks.

---

## Problem Statement

Hospital finance and operations leaders need fast answers to questions that change constantly — average cost per encounter by condition, length-of-stay trends by department, which payers reimburse worst, how readmission rates are trending. Traditional BI dashboards can't keep pace: every new question either waits on an analyst to write custom SQL, or gets bolted onto an already-cluttered dashboard nobody fully understands.

This project uses **Snowflake Cortex Analyst** to close that gap. A semantic model encodes business logic once — what "readmission" means, how cost is calculated, how tables relate — and any authorized stakeholder can then ask questions in plain English and get correct, transparent SQL back, with the query itself visible for trust and audit.

---

## Dataset

| Source | Type | Role |
|---|---|---|
| **[Synthea](https://synthetichealth.github.io/synthea/)** | Synthetic patient-level EHR data | Core relational data — patients, encounters, conditions, procedures, medications, providers, organizations, payers |
| **[CMS Hospital Compare](https://data.cms.gov/provider-data/topics/hospitals)** | Real, publicly published hospital quality data | Blended in as a benchmark layer — real readmission ratios joined to synthetic hospitals |

**Why synthetic + real, blended:** Synthea provides genuinely relational, patient-level data with zero privacy/compliance risk (no real PHI, no HIPAA concerns, no credentialing wait like MIMIC-III/IV requires). But synthetic data alone has no real-world grounding. Blending in real CMS benchmark numbers gives the project an honest "real + synthetic" data story without the weeks-long approval process a fully real clinical dataset would require.

**Population:** ~5,800 Massachusetts patients generated via Synthea, filtered to those with at least one encounter in the last 3 years (July 2023–July 2026) to reflect *current* hospital operations rather than a 100+ year lifetime history.

**Benchmark join:** Synthetic hospitals don't map 1:1 to real CMS-certified facilities, so rather than faking a false identity match, benchmarks are joined on `(state, hospital_type)` — a defensible statistical approximation, documented transparently. Hospital types statutorily exempt from CMS's Hospital Readmissions Reduction Program (Critical Access, Children's, Psychiatric, VA) correctly show no benchmark, matching real CMS policy.

---

## Architecture

```
Synthea (local generation)
        │
        ▼
  CSV files (patients, encounters, conditions,
  procedures, medications, organizations,
  providers, payers)
        │
        ▼
  Snowflake Internal Stage (synthea_stage)
        │  COPY INTO (match-by-column-name)
        ▼
  RAW schema  ── unmodified, mirrors source exactly
        │  surrogate keys, PII dropped,
        │  3-year recency filter, SDOH noise filtered
        ▼
  CLEAN schema  ── patients, organizations, providers,
                    payers, encounters, conditions,
                    procedures, medications
        │
        ├──► ANALYTICS schema
        │      • vw_encounters_enriched (joined view)
        │      • vw_organizations_benchmarked
        │        (real CMS data blended in)
        │      • 3x Cortex Search Services
        │        (fuzzy match: conditions, procedures,
        │         medications)
        │
        ▼
  Semantic View (HOSPITAL_OPS_SEMANTIC_MODEL)
        │  8 logical tables, relationships, metrics,
        │  dimensions, synonyms, Cortex Search links
        ▼
  Cortex Analyst  ◄── Streamlit in Snowflake (chat UI)
```

**Real CMS data pipeline (separate, additive):**
```
CMS Hospital Compare CSVs (Hospital General Info,
Readmissions Reduction Program)
        │
        ▼
  cms_stage → RAW.cms_hospital_general_info,
              RAW.cms_readmissions
        │  aggregate by (state, hospital_type)
        ▼
  CLEAN.hospital_benchmarks
        │  LEFT JOIN on (state, hospital_type)
        ▼
  ANALYTICS.vw_organizations_benchmarked
```
---

## Tech Stack

- **Snowflake**: Cortex Analyst, Cortex Search, Semantic Views, Streamlit in Snowflake, SQL Worksheets
- **Data generation**: Synthea (synthetic patient population simulator)
- **External data**: CMS Hospital Compare (Hospital General Information, Hospital Readmissions Reduction Program)
- **App**: Python, Streamlit, Snowpark

---

## Repository Structure

```
├── initial_setup.sql            # Database, schemas, warehouse, stages,
│                                 # RAW table loads, CLEAN transformations
├── Cortex_search.sql            # 3 Cortex Search service definitions
├── Create_semantic_view_v2.sql  # Semantic model YAML wrapped in
│                                 # SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML,
│                                 # with Cortex Search services linked in
├── streamlit_app.py             # Streamlit in Snowflake chat application
└── README.md
```

---

## Setup / Reproduction

1. Generate Synthea data: `java -jar synthea-with-dependencies.jar -p 5000 --exporter.csv.export=true Massachusetts`
2. Download real CMS data: [Hospital General Information](https://data.cms.gov/provider-data/dataset/xubh-q36u), [Hospital Readmissions Reduction Program](https://data.cms.gov/provider-data/dataset/9n3s-kdb3)
3. Run `initial_setup.sql` — creates database/schemas/warehouse, loads and transforms all data
4. Run `Cortex_search.sql` — builds the 3 fuzzy search services (must exist before step 5)
5. Run `Create_semantic_view_v2.sql` — builds the semantic view with Cortex Search linked in
6. Deploy `streamlit_app.py` as a Streamlit in Snowflake app

---

## Demo Questions

- "How many patients do we have?"
- "What's the average cost per encounter?"
- "What's the average length of stay by encounter class?"
- "Which conditions are most common?"
- "How many patients have high blood pressure?" *(tests Cortex Search)*
- "Which hospitals have the highest excess readmission ratio?" *(tests real CMS benchmark blend)*
