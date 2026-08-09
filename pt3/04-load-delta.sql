use role candidate_callahan;
use schema callahan_db.raw;

put file://pt2/01_raw/source_data/tenor_transactions_delta.csv @internal_stage_csv
overwrite = true;

-- Capture pre-delta data. That way we can more robustly verify that the delta-ingestion
-- executed as expected later (see 05-verify.sql)
create or replace transient table callahan_db.staging.pre_delta_nfe_snapshot as
select facility_sk
      ,facility_id
      ,net_funds_employed
from callahan_db.marts.dim_facility
where is_current_ind;

copy into tenor_transactions_export
from (
select $1, $2, $3, $4, $5, $6, $7,
       metadata$filename as file_name, metadata$file_row_number as file_row_number,
       metadata$file_last_modified as file_last_modified
from @internal_stage_csv
  (file_format => filefmt_csv, pattern => '.*tenor_transactions_delta.*')
  )
  ;

select system$stream_has_data('callahan_db.raw.stm_tenor_transactions') as stream_has_data;
