-- Recreate it from the updated YAML
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'HOSPITAL_OPS_INTELLIGENCE.ANALYTICS',
  $$
name: hospital_ops_semantic_model
description: >
  Semantic model for hospital operations and financial intelligence.
  Supports natural language questions about patient encounters, costs,
  length of stay, conditions, procedures, medications, and hospital
  performance benchmarked against real CMS Hospital Compare data.

tables:

  - name: patients
    description: >
      One row per patient who has had at least one encounter in the last
      3 years (July 2023 - July 2026). Patients with no recent activity
      are intentionally excluded.
    base_table:
      database: HOSPITAL_OPS_INTELLIGENCE
      schema: CLEAN
      table: PATIENTS
    primary_key:
      columns: [PATIENT_KEY]
    dimensions:
      - name: gender
        expr: GENDER
        data_type: TEXT
        description: Patient's gender.
      - name: race
        expr: RACE
        data_type: TEXT
        description: Patient's race.
      - name: ethnicity
        expr: ETHNICITY
        data_type: TEXT
        description: Patient's ethnicity.
      - name: marital_status
        expr: MARITAL
        data_type: TEXT
        description: Patient's marital status.
        synonyms: ["marital", "marriage status"]
      - name: city
        expr: CITY
        data_type: TEXT
        description: Patient's home city.
      - name: state
        expr: STATE
        data_type: TEXT
        description: Patient's home state.
    facts:
      - name: income
        expr: INCOME
        data_type: NUMBER
        description: Patient's annual income.
      - name: healthcare_expenses
        expr: HEALTHCARE_EXPENSES
        data_type: NUMBER
        description: Total lifetime healthcare expenses for the patient.
      - name: healthcare_coverage
        expr: HEALTHCARE_COVERAGE
        data_type: NUMBER
        description: Total lifetime amount covered by insurance for the patient.
    metrics:
      - name: patient_count
        expr: COUNT(DISTINCT patient_key)
        description: Number of distinct active patients.
        synonyms: ["number of patients", "patient volume", "headcount"]

  - name: organizations
    description: >
      Hospitals/facilities, blended with real CMS Hospital Compare
      readmission benchmarks, matched by state and hospital type.
      Benchmark fields are NULL for hospital types CMS does not score
      (Critical Access, Children's, Psychiatric, VA) — this is expected,
      not missing data.
    base_table:
      database: HOSPITAL_OPS_INTELLIGENCE
      schema: ANALYTICS
      table: VW_ORGANIZATIONS_BENCHMARKED
    primary_key:
      columns: [ORGANIZATION_KEY]
    dimensions:
      - name: organization_name
        expr: NAME
        data_type: TEXT
        description: Name of the hospital/organization.
        synonyms: ["hospital name", "facility name", "facility"]
      - name: hospital_type
        expr: HOSPITAL_TYPE
        data_type: TEXT
        description: >
          Category of hospital (Acute Care Hospitals, Critical Access
          Hospitals, Childrens, Psychiatric, Acute Care - Veterans
          Administration), derived from the organization's name.
      - name: organization_city
        expr: CITY
        data_type: TEXT
        description: City where the hospital is located.
      - name: organization_state
        expr: STATE
        data_type: TEXT
        description: State where the hospital is located.
    facts:
      - name: revenue
        expr: REVENUE
        data_type: NUMBER
        description: Hospital's total revenue.
      - name: utilization
        expr: UTILIZATION
        data_type: NUMBER
        description: Hospital's utilization measure.
      - name: avg_excess_readmission_ratio
        expr: AVG_EXCESS_READMISSION_RATIO
        data_type: NUMBER
        description: >
          Real CMS benchmark: average excess readmission ratio for real
          hospitals of this type in this state. Above 1.0 means
          readmitting more than expected; below 1.0 means less.
        synonyms: ["readmission benchmark", "CMS readmission ratio"]
      - name: avg_predicted_readmission_rate
        expr: AVG_PREDICTED_READMISSION_RATE
        data_type: NUMBER
        description: Real CMS benchmark predicted readmission rate for this state/hospital type.
      - name: benchmark_hospital_count
        expr: BENCHMARK_HOSPITAL_COUNT
        data_type: NUMBER
        description: Number of real CMS hospitals used to compute this benchmark.

  - name: providers
    description: Clinicians who deliver care, each linked to one organization.
    base_table:
      database: HOSPITAL_OPS_INTELLIGENCE
      schema: CLEAN
      table: PROVIDERS
    primary_key:
      columns: [PROVIDER_KEY]
    dimensions:
      - name: provider_name
        expr: NAME
        data_type: TEXT
        description: Name of the provider/clinician.
        synonyms: ["doctor", "clinician", "physician"]
      - name: provider_gender
        expr: GENDER
        data_type: TEXT
        description: Provider's gender.
      - name: speciality
        expr: SPECIALITY
        data_type: TEXT
        description: Provider's medical speciality.
        synonyms: ["specialty", "department"]

  - name: payers
    description: Insurance payers/companies covering patient care.
    base_table:
      database: HOSPITAL_OPS_INTELLIGENCE
      schema: CLEAN
      table: PAYERS
    primary_key:
      columns: [PAYER_KEY]
    dimensions:
      - name: payer_name
        expr: NAME
        data_type: TEXT
        description: Name of the insurance payer.
        synonyms: ["insurer", "insurance company", "insurance"]
      - name: ownership
        expr: OWNERSHIP
        data_type: TEXT
        description: Payer ownership type (e.g. GOVERNMENT, PRIVATE).

  - name: encounters
    description: >
      One row per patient encounter/visit in the last 3 years. This is
      the core fact table for cost, length-of-stay, and operational
      analysis.
    base_table:
      database: HOSPITAL_OPS_INTELLIGENCE
      schema: CLEAN
      table: ENCOUNTERS
    primary_key:
      columns: [ENCOUNTER_KEY]
    dimensions:
      - name: encounter_class
        expr: ENCOUNTERCLASS
        data_type: TEXT
        description: Type of encounter (ambulatory, outpatient, wellness, emergency, inpatient, virtual, etc).
        synonyms: ["visit type", "encounter type"]
      - name: encounter_description
        expr: DESCRIPTION
        data_type: TEXT
        description: Description of what the encounter was for.
      - name: encounter_reason
        expr: REASONDESCRIPTION
        data_type: TEXT
        description: The diagnosis/condition that prompted this encounter, if any.
    time_dimensions:
      - name: encounter_start
        expr: START_TS
        data_type: TIMESTAMP
        description: When the encounter started.
        synonyms: ["visit date", "admission date", "encounter date"]
      - name: encounter_stop
        expr: STOP_TS
        data_type: TIMESTAMP
        description: When the encounter ended.
        synonyms: ["discharge date"]
    facts:
      - name: base_encounter_cost
        expr: BASE_ENCOUNTER_COST
        data_type: NUMBER
        description: Base cost of the encounter, excluding line items.
      - name: total_claim_cost
        expr: TOTAL_CLAIM_COST
        data_type: NUMBER
        description: Total cost of the encounter including all line items.
        synonyms: ["cost", "price", "charges", "claim amount", "bill amount"]
      - name: payer_coverage
        expr: PAYER_COVERAGE
        data_type: NUMBER
        description: Amount of the encounter cost covered by the payer/insurance.
      - name: length_of_stay_hours
        expr: DATEDIFF('hour', START_TS, STOP_TS)
        data_type: NUMBER
        description: Length of the encounter in hours.
        synonyms: ["LOS", "length of stay", "duration"]
      - name: patient_responsibility
        expr: TOTAL_CLAIM_COST - PAYER_COVERAGE
        data_type: NUMBER
        description: Portion of the encounter cost not covered by the payer (out-of-pocket).
        synonyms: ["out of pocket cost", "patient owes", "uncovered amount"]
    metrics:
      - name: encounter_count
        expr: COUNT(*)
        description: Number of encounters.
        synonyms: ["number of visits", "visit volume", "encounter volume"]
      - name: total_cost
        expr: SUM(total_claim_cost)
        description: Total cost across encounters.
      - name: avg_cost_per_encounter
        expr: AVG(total_claim_cost)
        description: Average cost per encounter.
      - name: avg_length_of_stay_hours
        expr: AVG(DATEDIFF('hour', START_TS, STOP_TS))
        description: Average length of stay in hours.
      - name: total_patient_responsibility
        expr: SUM(total_claim_cost - payer_coverage)
        description: Total out-of-pocket cost across encounters.

  - name: conditions
    description: Conditions/diagnoses recorded during an encounter.
    base_table:
      database: HOSPITAL_OPS_INTELLIGENCE
      schema: CLEAN
      table: CONDITIONS
    primary_key:
      columns: [CONDITION_KEY]
    dimensions:
      - name: condition_description
        expr: DESCRIPTION
        data_type: TEXT
        description: Name/description of the condition or diagnosis.
        synonyms: ["diagnosis", "disease", "illness", "disorder"]
        cortex_search_service:
          service: condition_description_search
          literal_column: description
          database: HOSPITAL_OPS_INTELLIGENCE
          schema: ANALYTICS
    time_dimensions:
      - name: condition_start
        expr: START_TS
        data_type: TIMESTAMP
        description: Date the condition was recorded/onset.
    metrics:
      - name: condition_count
        expr: COUNT(*)
        description: Number of condition records.
        synonyms: ["number of diagnoses", "diagnosis count"]

  - name: procedures
    description: Procedures performed during an encounter.
    base_table:
      database: HOSPITAL_OPS_INTELLIGENCE
      schema: CLEAN
      table: PROCEDURES
    primary_key:
      columns: [PROCEDURE_KEY]
    dimensions:
      - name: procedure_description
        expr: DESCRIPTION
        data_type: TEXT
        description: Name/description of the procedure performed.
        synonyms: ["surgery", "treatment", "operation"]
        cortex_search_service:
          service: procedure_description_search
          literal_column: description
          database: HOSPITAL_OPS_INTELLIGENCE
          schema: ANALYTICS
      - name: procedure_reason
        expr: REASONDESCRIPTION
        data_type: TEXT
        description: The condition that prompted this procedure, if any.
    time_dimensions:
      - name: procedure_date
        expr: START_TS
        data_type: TIMESTAMP
        description: Date the procedure was performed.
    facts:
      - name: procedure_base_cost
        expr: BASE_COST
        data_type: NUMBER
        description: Base cost of the procedure.
    metrics:
      - name: procedure_count
        expr: COUNT(*)
        description: Number of procedures performed.
      - name: total_procedure_cost
        expr: SUM(base_cost)
        description: Total cost of procedures.

  - name: medications
    description: Medications prescribed during an encounter.
    base_table:
      database: HOSPITAL_OPS_INTELLIGENCE
      schema: CLEAN
      table: MEDICATIONS
    primary_key:
      columns: [MEDICATION_KEY]
    dimensions:
      - name: medication_description
        expr: DESCRIPTION
        data_type: TEXT
        description: Name/description of the medication.
        synonyms: ["drug", "prescription", "medicine"]
        cortex_search_service:
          service: medication_description_search
          literal_column: description
          database: HOSPITAL_OPS_INTELLIGENCE
          schema: ANALYTICS
      - name: medication_reason
        expr: REASONDESCRIPTION
        data_type: TEXT
        description: The condition this medication was prescribed for.
    time_dimensions:
      - name: medication_start
        expr: START_TS
        data_type: TIMESTAMP
        description: Date the medication was prescribed/started.
      - name: medication_stop
        expr: STOP_TS
        data_type: TIMESTAMP
        description: Date the medication was stopped, if applicable.
    facts:
      - name: medication_base_cost
        expr: BASE_COST
        data_type: NUMBER
        description: Base cost of the medication.
      - name: medication_total_cost
        expr: TOTALCOST
        data_type: NUMBER
        description: Total cost of the medication including dispenses.
      - name: medication_payer_coverage
        expr: PAYER_COVERAGE
        data_type: NUMBER
        description: Amount of medication cost covered by the payer.
    metrics:
      - name: medication_count
        expr: COUNT(*)
        description: Number of medication records.
      - name: total_medication_cost
        expr: SUM(totalcost)
        description: Total medication cost.

relationships:
  - name: encounters_to_patients
    left_table: encounters
    right_table: patients
    relationship_columns:
      - left_column: PATIENT_KEY
        right_column: PATIENT_KEY

  - name: encounters_to_organizations
    left_table: encounters
    right_table: organizations
    relationship_columns:
      - left_column: ORGANIZATION_KEY
        right_column: ORGANIZATION_KEY

  - name: encounters_to_providers
    left_table: encounters
    right_table: providers
    relationship_columns:
      - left_column: PROVIDER_KEY
        right_column: PROVIDER_KEY

  - name: encounters_to_payers
    left_table: encounters
    right_table: payers
    relationship_columns:
      - left_column: PAYER_KEY
        right_column: PAYER_KEY

  - name: conditions_to_encounters
    left_table: conditions
    right_table: encounters
    relationship_columns:
      - left_column: ENCOUNTER_KEY
        right_column: ENCOUNTER_KEY

  - name: procedures_to_encounters
    left_table: procedures
    right_table: encounters
    relationship_columns:
      - left_column: ENCOUNTER_KEY
        right_column: ENCOUNTER_KEY

  - name: medications_to_encounters
    left_table: medications
    right_table: encounters
    relationship_columns:
      - left_column: ENCOUNTER_KEY
        right_column: ENCOUNTER_KEY
  $$
);
SHOW SEMANTIC VIEWS IN SCHEMA analytics;