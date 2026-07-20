# Hospital Operations & Financial Intelligence

A production-style portfolio project demonstrating **Text-to-SQL over structured healthcare data** using Snowflake Cortex Analyst, Cortex Search, and Streamlit — built on synthetic patient data blended with real CMS hospital quality benchmarks.

---

## Problem Statement

Hospital finance and operations leaders need fast answers to questions that change constantly — average cost per encounter by condition, length-of-stay trends by department, which payers reimburse worst, how readmission rates are trending. Traditional BI dashboards can't keep pace: every new question either waits on an analyst to write custom SQL, or gets bolted onto an already-cluttered dashboard nobody fully understands.

This project uses **Snowflake Cortex Analyst** to close that gap. A semantic model encodes business logic once — what "readmission" means, how cost is calculated, how tables relate — and any authorized stakeholder can then ask questions in plain English and get correct, transparent SQL back, with the query itself visible for trust and audit.

---

## Tech Stack

- **Snowflake**: Cortex Analyst, Cortex Search, Semantic Views, Streamlit in Snowflake, SQL Worksheets
- **Data generation**: Synthea (synthetic patient population simulator)
- **External data**: CMS Hospital Compare (Hospital General Information, Hospital Readmissions Reduction Program)
- **App**: Python, Streamlit, Snowpark

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
