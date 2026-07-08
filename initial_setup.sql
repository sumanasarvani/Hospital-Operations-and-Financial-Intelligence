--> Create a Warehouse
CREATE WAREHOUSE IF NOT EXISTS HOSPITAL_OPS_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

--> Create a Database
CREATE DATABASE IF NOT EXISTS HOSPITAL_OPS_INTELLIGENCE;
USE DATABASE HOSPITAL_OPS_INTELLIGENCE;

--> Create 3 schemas inside it
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS CLEAN;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;

--> Create a file format object (Parsing of Syntheas CSVs)
USE SCHEMA RAW;
CREATE OR REPLACE FILE FORMAT csv_ff
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL')
  EMPTY_FIELD_AS_NULL = TRUE;

--> Create an internal stage
CREATE OR REPLACE STAGE synthea_stage
FILE_FORMAT = csv_ff;

--> Verify your upload
LIST @synthea_stage;

--> Let us redefine the file format to header based
CREATE OR REPLACE FILE FORMAT csv_ff
  TYPE = 'CSV'
  PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL')
  EMPTY_FIELD_AS_NULL = TRUE;

--> Create 8 RAW tables
CREATE OR REPLACE TABLE raw.patients (
  ID STRING, BIRTHDATE DATE, DEATHDATE DATE, SSN STRING, DRIVERS STRING, PASSPORT STRING,
  PREFIX STRING, FIRST STRING, MIDDLE STRING, LAST STRING, SUFFIX STRING, MAIDEN STRING, MARITAL STRING,
  RACE STRING, ETHNICITY STRING, GENDER STRING, BIRTHPLACE STRING, ADDRESS STRING,
  CITY STRING, STATE STRING, COUNTY STRING, FIPS STRING, ZIP STRING,
  LAT FLOAT, LON FLOAT, HEALTHCARE_EXPENSES FLOAT, HEALTHCARE_COVERAGE FLOAT, INCOME FLOAT
);

CREATE OR REPLACE TABLE raw.organizations (
  ID STRING, NAME STRING, ADDRESS STRING, CITY STRING, STATE STRING, ZIP STRING,
  LAT FLOAT, LON FLOAT, PHONE STRING, REVENUE FLOAT, UTILIZATION FLOAT
);

CREATE OR REPLACE TABLE raw.providers (
  ID STRING, ORGANIZATION STRING, NAME STRING, GENDER STRING, SPECIALITY STRING,
  ADDRESS STRING, CITY STRING, STATE STRING, ZIP STRING, LAT FLOAT, LON FLOAT,
  ENCOUNTERS INTEGER, PROCEDURES INTEGER
);

CREATE OR REPLACE TABLE raw.payers (
  ID STRING, NAME STRING, OWNERSHIP STRING, ADDRESS STRING, CITY STRING, STATE_HEADQUARTERED STRING, ZIP STRING,
  PHONE STRING, AMOUNT_COVERED FLOAT, AMOUNT_UNCOVERED FLOAT, REVENUE FLOAT,
  COVERED_ENCOUNTERS INTEGER, UNCOVERED_ENCOUNTERS INTEGER,
  COVERED_MEDICATIONS INTEGER, UNCOVERED_MEDICATIONS INTEGER,
  COVERED_PROCEDURES INTEGER, UNCOVERED_PROCEDURES INTEGER,
  COVERED_IMMUNIZATIONS INTEGER, UNCOVERED_IMMUNIZATIONS INTEGER,
  UNIQUE_CUSTOMERS INTEGER, QOLS_AVG FLOAT, MEMBER_MONTHS INTEGER
);

CREATE OR REPLACE TABLE raw.encounters (
  ID STRING, "START" TIMESTAMP_NTZ, "STOP" TIMESTAMP_NTZ, PATIENT STRING, ORGANIZATION STRING,
  PROVIDER STRING, PAYER STRING, ENCOUNTERCLASS STRING, CODE STRING, DESCRIPTION STRING,
  BASE_ENCOUNTER_COST FLOAT, TOTAL_CLAIM_COST FLOAT, PAYER_COVERAGE FLOAT,
  REASONCODE STRING, REASONDESCRIPTION STRING
);

CREATE OR REPLACE TABLE raw.conditions (
  "START" TIMESTAMP_NTZ, "STOP" TIMESTAMP_NTZ, PATIENT STRING, ENCOUNTER STRING,
  SYSTEM STRING, CODE STRING, DESCRIPTION STRING
);

CREATE OR REPLACE TABLE raw.procedures (
  "START" TIMESTAMP_NTZ, "STOP" TIMESTAMP_NTZ, PATIENT STRING, ENCOUNTER STRING,
  SYSTEM STRING, CODE STRING, DESCRIPTION STRING, BASE_COST FLOAT,
  REASONCODE STRING, REASONDESCRIPTION STRING
);

CREATE OR REPLACE TABLE raw.medications (
  "START" TIMESTAMP_NTZ, "STOP" TIMESTAMP_NTZ, PATIENT STRING, PAYER STRING, ENCOUNTER STRING,
  CODE STRING, DESCRIPTION STRING, BASE_COST FLOAT, PAYER_COVERAGE FLOAT,
  DISPENSES INTEGER, TOTALCOST FLOAT, REASONCODE STRING, REASONDESCRIPTION STRING
);

--> Load each file into the tables by match-by-column name
COPY INTO raw.patients FROM @synthea_stage/patients.csv
  FILE_FORMAT = csv_ff MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO raw.organizations FROM @synthea_stage/organizations.csv
  FILE_FORMAT = csv_ff MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO raw.providers FROM @synthea_stage/providers.csv
  FILE_FORMAT = csv_ff MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO raw.payers FROM @synthea_stage/payers.csv
  FILE_FORMAT = csv_ff MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO raw.encounters FROM @synthea_stage/encounters.csv
  FILE_FORMAT = csv_ff MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO raw.conditions FROM @synthea_stage/conditions.csv
  FILE_FORMAT = csv_ff MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO raw.procedures FROM @synthea_stage/procedures.csv
  FILE_FORMAT = csv_ff MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

COPY INTO raw.medications FROM @synthea_stage/medications.csv
  FILE_FORMAT = csv_ff MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;


SELECT 'organizations' AS table_name, COUNT(*) AS row_count FROM raw.organizations
UNION ALL
SELECT 'providers', COUNT(*) FROM raw.providers
UNION ALL
SELECT 'payers', COUNT(*) FROM raw.payers
UNION ALL
SELECT 'encounters', COUNT(*) FROM raw.encounters
UNION ALL
SELECT 'conditions', COUNT(*) FROM raw.conditions
UNION ALL
SELECT 'procedures', COUNT(*) FROM raw.procedures
UNION ALL
SELECT 'medications', COUNT(*) FROM raw.medications;

--> Creating a clean build, dimensional tables that do not need filtering
CREATE OR REPLACE TABLE clean.organizations AS
SELECT
    'ORG_' || LPAD(ROW_NUMBER() OVER (ORDER BY id), 4, '0') AS organization_key,
    id AS synthea_id,
    name, city, state, zip, lat, lon, revenue, utilization
FROM raw.organizations;

CREATE OR REPLACE TABLE clean.providers AS
SELECT
    'PROV_' || LPAD(ROW_NUMBER() OVER (ORDER BY p.id), 5, '0') AS provider_key,
    p.id AS synthea_id,
    o.organization_key,
    p.name, p.gender, p.speciality, p.city, p.state, p.encounters, p.procedures
FROM raw.providers p
JOIN clean.organizations o ON p.organization = o.synthea_id;

CREATE OR REPLACE TABLE clean.payers AS
SELECT
    'PAY_' || LPAD(ROW_NUMBER() OVER (ORDER BY id), 3, '0') AS payer_key,
    id AS synthea_id,
    name, ownership, amount_covered, amount_uncovered, revenue,
    covered_encounters, uncovered_encounters, unique_customers
FROM raw.payers;

CREATE OR REPLACE TABLE clean.encounters AS
SELECT
    'ENC_' || LPAD(ROW_NUMBER() OVER (ORDER BY e."START"), 7, '0') AS encounter_key,
    e.id AS synthea_id,
    e.patient AS synthea_patient_id,       -- resolved to patient_key in step 3
    org.organization_key,
    prov.provider_key,
    pay.payer_key,
    e."START" AS start_ts,
    e."STOP"  AS stop_ts,
    e.encounterclass,
    e.description,
    e.base_encounter_cost,
    e.total_claim_cost,
    e.payer_coverage,
    e.reasondescription
FROM raw.encounters e
JOIN clean.organizations org ON e.organization = org.synthea_id
JOIN clean.providers     prov ON e.provider     = prov.synthea_id
JOIN clean.payers        pay  ON e.payer        = pay.synthea_id
WHERE e."START" >= '2023-07-01';

CREATE OR REPLACE TABLE clean.patients AS
SELECT
    'PAT_' || LPAD(ROW_NUMBER() OVER (ORDER BY p.id), 6, '0') AS patient_key,
    p.id AS synthea_id,
    p.birthdate, p.deathdate, p.gender, p.race, p.ethnicity, p.marital,
    p.city, p.state, p.zip, p.income, p.healthcare_expenses, p.healthcare_coverage
FROM raw.patients p
WHERE p.id IN (SELECT DISTINCT synthea_patient_id FROM clean.encounters);

CREATE OR REPLACE TABLE clean.encounters AS
SELECT
    e.encounter_key, e.synthea_id,
    pt.patient_key,
    e.organization_key, e.provider_key, e.payer_key,
    e.start_ts, e.stop_ts, e.encounterclass, e.description,
    e.base_encounter_cost, e.total_claim_cost, e.payer_coverage, e.reasondescription
FROM clean.encounters e
JOIN clean.patients pt ON e.synthea_patient_id = pt.synthea_id

CREATE OR REPLACE TABLE clean.conditions AS
SELECT
    pt.patient_key,
    enc.encounter_key,
    c."START" AS start_ts,
    c."STOP"  AS stop_ts,
    c.description
FROM raw.conditions c
JOIN clean.encounters enc ON c.encounter = enc.synthea_id
JOIN clean.patients   pt  ON c.patient   = pt.synthea_id;

CREATE OR REPLACE TABLE clean.procedures AS
SELECT
    pt.patient_key,
    enc.encounter_key,
    p."START" AS start_ts,
    p.description,
    p.base_cost,
    p.reasondescription
FROM raw.procedures p
JOIN clean.encounters enc ON p.encounter = enc.synthea_id
JOIN clean.patients   pt  ON p.patient   = pt.synthea_id;

CREATE OR REPLACE TABLE clean.medications AS
SELECT
    pt.patient_key,
    enc.encounter_key,
    m."START" AS start_ts,
    m."STOP"  AS stop_ts,
    m.description,
    m.base_cost,
    m.payer_coverage,
    m.totalcost,
    m.reasondescription
FROM raw.medications m
JOIN clean.encounters enc ON m.encounter = enc.synthea_id
JOIN clean.patients   pt  ON m.patient   = pt.synthea_id;

--> Verify your 3-year filter
SELECT 'patients' AS table_name, COUNT(*) AS row_count FROM clean.patients
UNION ALL
SELECT 'encounters', COUNT(*) FROM clean.encounters
UNION ALL
SELECT 'conditions', COUNT(*) FROM clean.conditions
UNION ALL
SELECT 'procedures', COUNT(*) FROM clean.procedures
UNION ALL
SELECT 'medications', COUNT(*) FROM clean.medications;

--> Create business views in ANALYTICS
CREATE OR REPLACE VIEW analytics.vw_encounters_enriched AS
SELECT
    e.encounter_key,
    e.start_ts,
    e.stop_ts,
    DATEDIFF('hour', e.start_ts, e.stop_ts)          AS length_of_stay_hours,
    e.encounterclass,
    e.description                                     AS encounter_description,
    e.base_encounter_cost,
    e.total_claim_cost,
    e.payer_coverage,
    e.total_claim_cost - e.payer_coverage             AS patient_responsibility,
    e.reasondescription                                AS encounter_reason,

    p.patient_key,
    DATEDIFF('year', p.birthdate, e.start_ts)          AS patient_age_at_encounter,
    p.gender, p.race, p.ethnicity, p.marital,
    p.city                                             AS patient_city,
    p.state                                            AS patient_state,
    p.income                                           AS patient_income,

    o.organization_key,
    o.name                                             AS organization_name,
    o.city                                             AS organization_city,
    o.state                                             AS organization_state,
    o.lat                                               AS organization_lat,
    o.lon                                               AS organization_lon,

    pr.provider_key,
    pr.name                                            AS provider_name,
    pr.speciality                                      AS provider_speciality,

    pay.payer_key,
    pay.name                                           AS payer_name,
    pay.ownership                                      AS payer_ownership

FROM clean.encounters e
JOIN clean.patients      p   ON e.patient_key       = p.patient_key
JOIN clean.organizations o   ON e.organization_key  = o.organization_key
JOIN clean.providers     pr  ON e.provider_key       = pr.provider_key
JOIN clean.payers        pay ON e.payer_key          = pay.payer_key;

--> Quick check
SELECT * FROM analytics.vw_encounters_enriched LIMIT 10;

--> Create a stage for the CMS data
USE DATABASE HOSPITAL_OPS_INTELLIGENCE;
USE SCHEMA RAW;

CREATE OR REPLACE STAGE cms_stage
  FILE_FORMAT = csv_ff;

--> Verify your upload
LIST @cms_stage;

--> Create 2 RAW tables with columns relevant to our benchmark
CREATE OR REPLACE TABLE raw.cms_hospital_general_info (
  facility_id STRING,
  facility_name STRING,
  state STRING,
  hospital_type STRING,
  hospital_ownership STRING,
  overall_rating STRING
);

CREATE OR REPLACE TABLE raw.cms_readmissions (
  facility_name STRING,
  facility_id STRING,
  state STRING,
  measure_name STRING,
  excess_readmission_ratio STRING,
  predicted_readmission_rate STRING,
  expected_readmission_rate STRING
);


COPY INTO raw.cms_hospital_general_info (facility_id, facility_name, state, hospital_type, hospital_ownership, overall_rating)
FROM (
  SELECT $1, $2, $5, $9, $10, $13
  FROM @cms_stage/Hospital_General_Information.csv
)
FILE_FORMAT = (TYPE='CSV', SKIP_HEADER=1, FIELD_OPTIONALLY_ENCLOSED_BY='"');

COPY INTO raw.cms_readmissions (facility_name, facility_id, state, measure_name, excess_readmission_ratio, predicted_readmission_rate, expected_readmission_rate)
FROM (
  SELECT $1, $2, $3, $4, $7, $8, $9
  FROM @cms_stage/FY_2026_Hospital_Readmissions_Reduction_Program_Hospital.csv
)
FILE_FORMAT = (TYPE='CSV', SKIP_HEADER=1, FIELD_OPTIONALLY_ENCLOSED_BY='"');

--> Verify
SELECT 'cms_hospital_general_info' AS t, COUNT(*) FROM raw.cms_hospital_general_info
UNION ALL
SELECT 'cms_readmissions', COUNT(*) FROM raw.cms_readmissions;

CREATE OR REPLACE TABLE clean.organizations AS
SELECT
    organization_key,
    synthea_id,
    name,
    CASE
        WHEN name ILIKE '%psychiatric%' OR name ILIKE '%mental health%' THEN 'Psychiatric'
        WHEN name ILIKE '%children%' OR name ILIKE '%pediatric%' THEN 'Childrens'
        WHEN name ILIKE '%veterans%' OR name ILIKE '%VA %' THEN 'Acute Care - Veterans Administration'
        WHEN name ILIKE '%rehabilitation%' OR name ILIKE '%rehab%' THEN 'Critical Access Hospitals'
        ELSE 'Acute Care Hospitals'
    END AS hospital_type,
    city, state, zip, lat, lon, revenue, utilization
FROM clean.organizations;

--> Build the benchmark table
CREATE OR REPLACE TABLE clean.hospital_benchmarks AS
SELECT
    g.state,
    g.hospital_type,
    COUNT(DISTINCT g.facility_id)                          AS benchmark_hospital_count,
    AVG(TRY_TO_DOUBLE(r.excess_readmission_ratio))          AS avg_excess_readmission_ratio,
    AVG(TRY_TO_DOUBLE(r.predicted_readmission_rate))        AS avg_predicted_readmission_rate,
    AVG(TRY_TO_DOUBLE(r.expected_readmission_rate))         AS avg_expected_readmission_rate
FROM raw.cms_hospital_general_info g
JOIN raw.cms_readmissions r ON g.facility_id = r.facility_id
GROUP BY g.state, g.hospital_type;

--> verify
SELECT * FROM clean.hospital_benchmarks
WHERE state = 'MA'
ORDER BY hospital_type;

--> Joining the benchmark onto our organizations
CREATE OR REPLACE VIEW analytics.vw_organizations_benchmarked AS
SELECT
    o.*,
    b.benchmark_hospital_count,
    b.avg_excess_readmission_ratio,
    b.avg_predicted_readmission_rate,
    b.avg_expected_readmission_rate
FROM clean.organizations o
LEFT JOIN clean.hospital_benchmarks b
    ON o.state = b.state
   AND o.hospital_type = b.hospital_type;

   --> Check
   SELECT
    hospital_type,
    COUNT(*) AS synthetic_org_count,
    COUNT(avg_excess_readmission_ratio) AS orgs_with_benchmark
FROM analytics.vw_organizations_benchmarked
GROUP BY hospital_type;

--> Add surrogate keys to the three tables
CREATE OR REPLACE TABLE clean.conditions AS
SELECT
    'COND_' || LPAD(ROW_NUMBER() OVER (ORDER BY start_ts), 7, '0') AS condition_key,
    patient_key, encounter_key, start_ts, stop_ts, description
FROM clean.conditions;

CREATE OR REPLACE TABLE clean.procedures AS
SELECT
    'PROC_' || LPAD(ROW_NUMBER() OVER (ORDER BY start_ts), 7, '0') AS procedure_key,
    patient_key, encounter_key, start_ts, description, base_cost, reasondescription
FROM clean.procedures;

CREATE OR REPLACE TABLE clean.medications AS
SELECT
    'MED_' || LPAD(ROW_NUMBER() OVER (ORDER BY start_ts), 7, '0') AS medication_key,
    patient_key, encounter_key, start_ts, stop_ts, description, base_cost, payer_coverage, totalcost, reasondescription
FROM clean.medications;


--> Ajustments
USE SCHEMA CLEAN;
USE WAREHOUSE HOSPITAL_OPS_WH;

CREATE OR REPLACE TABLE clean.conditions AS
SELECT * FROM clean.conditions
WHERE NOT (
    description ILIKE '%employment%'
    OR description ILIKE '%unemployed%'
    OR description ILIKE '%labor force%'
    OR description ILIKE '%social isolation%'
    OR description ILIKE '%social contact%'
    OR description ILIKE '%medication review%'
    OR description ILIKE '%stress (finding)%'
    OR description ILIKE '%victim of%'
    OR description ILIKE '%violence%'
    OR description ILIKE '%abuse%'
);

--> Quick check
SELECT description, COUNT(*) AS condition_count
FROM clean.conditions
GROUP BY description
ORDER BY condition_count DESC
LIMIT 10;