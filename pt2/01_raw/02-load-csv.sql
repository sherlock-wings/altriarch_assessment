use role candidate_callahan;
use schema callahan_db.raw;

-- Paths are relative to the repo root, which is where 00_run_all.sh runs.
put file://pt2/01_raw/source_data/affinity_organizations_export.csv @callahan_db.raw.internal_stage_csv;
put file://pt2/01_raw/source_data/factorview_facilities_export.csv @callahan_db.raw.internal_stage_csv;
put file://pt2/01_raw/source_data/tenor_transactions_delta.csv @callahan_db.raw.internal_stage_csv;
put file://pt2/01_raw/source_data/tenor_transactions_export.csv @callahan_db.raw.internal_stage_csv;
