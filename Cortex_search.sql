USE DATABASE HOSPITAL_OPS_INTELLIGENCE;
USE SCHEMA ANALYTICS;

--> CREATE CORTEX SEARCH
CREATE OR REPLACE CORTEX SEARCH SERVICE condition_description_search
  ON description
  WAREHOUSE = HOSPITAL_OPS_WH
  TARGET_LAG = '1 hour'
  AS (
    SELECT DISTINCT description FROM clean.conditions
  );

CREATE OR REPLACE CORTEX SEARCH SERVICE procedure_description_search
  ON description
  WAREHOUSE = HOSPITAL_OPS_WH
  TARGET_LAG = '1 hour'
  AS (
    SELECT DISTINCT description FROM clean.procedures
  );

CREATE OR REPLACE CORTEX SEARCH SERVICE medication_description_search
  ON description
  WAREHOUSE = HOSPITAL_OPS_WH
  TARGET_LAG = '1 hour'
  AS (
    SELECT DISTINCT description FROM clean.medications
  );