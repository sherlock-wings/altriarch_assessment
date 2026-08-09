use role candidate_callahan;
use schema callahan_db.raw;

-- This script is meant to confirm idempotency. By using FORCE to copy another load of the 
-- same set of already-ingested reocrds. These records should "bounce off" the pipeline. No 
-- new INT_TRANSACTION or FACT_TRANSACTION rows, no NFE movement, and no RECORD_UPDATED_TS 
-- set, because every CHANGE_TRACKING_KEY matches the existing records

copy into tenor_transactions_export
from (
select $1, $2, $3, $4, $5, $6, $7,
       metadata$filename as file_name, metadata$file_row_number as file_row_number,
       metadata$file_last_modified as file_last_modified
from @internal_stage_csv
  (file_format => filefmt_csv, pattern => '.*tenor_transactions_delta.*')
  )
force = true
  ;

select system$stream_has_data('callahan_db.raw.stm_tenor_transactions') as stream_has_data;
