use role candidate_callahan;
use schema callahan_db.marts;

create or replace table dim_facility 
like callahan_db.staging.int_facility;
alter table dim_facility
add column record_version_number number(38,0)
          ,is_current_ind boolean
          ,record_valid_from_ts timestamp_tz(9)
          ,record_valid_to_ts timestamp_tz(9)
          ,scd_id varchar
;
