use role candidate_callahan;
use schema callahan_db.marts;

create table if not exists dim_facility as
select f.*
      ,null::number(38,0) as record_version_number
      ,null::boolean as is_current_ind
      ,null::timestamp_ntz(9) as record_valid_from_ts
      ,null::timestamp_ntz(9) as record_valid_to_ts
      ,null::varchar as scd_id
from callahan_db.staging.int_facility f
where false;


merge into dim_facility dim
using (
with incoming_src as (
    select * from callahan_db.staging.int_facility
)

,existing_tgt as (
    -- current versions only; history rows would fan out every join below
    select * from dim_facility
    where is_current_ind
)

,insert_new_org_data as (
    select src.*
          ,nvl(tgt.record_version_number, 0) + 1 as record_version_number
          ,true as is_current_ind
          ,current_timestamp()::timestamp_ntz(9)  as record_valid_from_ts
          ,'9999-12-31 23:59:59'::timestamp_ntz(9) as record_valid_to_ts
          ,md5(
            src.facility_sk::varchar
            || '||' ||
            (nvl(tgt.record_version_number, 0) + 1)::varchar
          ) as scd_id
    from incoming_src src
    left join existing_tgt tgt
           on src.facility_sk = tgt.facility_sk
    where tgt.facility_sk is null
)

,insert_updated_org_data as (
    select src.*
          ,nvl(tgt.record_version_number, 0) + 1 as record_version_number
          ,true as is_current_ind
          ,current_timestamp()::timestamp_ntz(9) as record_valid_from_ts
          ,'9999-12-31 23:59:59'::timestamp_ntz(9) as record_valid_to_ts
          ,md5(
            src.facility_sk::varchar
            || '||' ||
            (nvl(tgt.record_version_number, 0) + 1)::varchar
          ) as scd_id
    from incoming_src src
    join existing_tgt tgt
      on tgt.facility_sk = src.facility_sk
    where tgt.change_tracking_key <> src.change_tracking_key
)

,expire_existing_org_data as (
    select tgt.FACILITY_SK
          ,tgt.FACILITY_ID
          ,tgt.ORGANIZATION_SK
          ,tgt.FUND_DESCRIPTION
          ,tgt.PRODUCT_TYPE
          ,tgt.DISCOUNT_RATE
          ,tgt.NET_FUNDS_EMPLOYED
          ,tgt.FACILITY_FUNDING_LIMIT
          ,tgt.FUNDING_DATE
          ,tgt.MATURITY_DATE
          ,tgt.STATUS
          ,tgt.CHANGE_TRACKING_KEY
          ,tgt.RECORD_VERSION_NUMBER
          ,false as IS_CURRENT_IND
          ,tgt.RECORD_VALID_FROM_TS
          ,dateadd(millisecond, -1, current_timestamp()::timestamp_ntz(9)) as RECORD_VALID_TO_TS
          ,tgt.SCD_ID
    from existing_tgt tgt
    -- absence from the export is not a deletion; only changed facilities expire
    join incoming_src src
      on tgt.facility_sk = src.facility_sk
    where tgt.change_tracking_key <> src.change_tracking_key
)

select * from insert_new_org_data
union all
select * from insert_updated_org_data
union all 
select * from expire_existing_org_data
) intr
on dim.scd_id = intr.scd_id
when not matched then insert (
   FACILITY_SK
  ,FACILITY_ID
  ,ORGANIZATION_SK
  ,FUND_DESCRIPTION
  ,PRODUCT_TYPE
  ,DISCOUNT_RATE
  ,NET_FUNDS_EMPLOYED
  ,FACILITY_FUNDING_LIMIT
  ,FUNDING_DATE
  ,MATURITY_DATE
  ,STATUS
  ,CHANGE_TRACKING_KEY
  ,RECORD_VERSION_NUMBER
  ,IS_CURRENT_IND
  ,RECORD_VALID_FROM_TS
  ,RECORD_VALID_TO_TS
  ,SCD_ID
) values (
   intr.FACILITY_SK
  ,intr.FACILITY_ID
  ,intr.ORGANIZATION_SK
  ,intr.FUND_DESCRIPTION
  ,intr.PRODUCT_TYPE
  ,intr.DISCOUNT_RATE
  ,intr.NET_FUNDS_EMPLOYED
  ,intr.FACILITY_FUNDING_LIMIT
  ,intr.FUNDING_DATE
  ,intr.MATURITY_DATE
  ,intr.STATUS
  ,intr.CHANGE_TRACKING_KEY
  ,intr.RECORD_VERSION_NUMBER
  ,intr.IS_CURRENT_IND
  ,intr.RECORD_VALID_FROM_TS
  ,intr.RECORD_VALID_TO_TS
  ,intr.SCD_ID
)
-- only expire_existing_org_data rows can match, and they close the version they came from
when matched then update set
   dim.IS_CURRENT_IND = intr.IS_CURRENT_IND
  ,dim.RECORD_VALID_TO_TS = intr.RECORD_VALID_TO_TS
;

insert into dim_facility
select md5('NULL FACILITY') as FACILITY_SK
      ,'NULL FACILITY' AS FACILITY_ID
      -- even the guard facility resolves to a real organization, so the foreign key
      -- has no exceptions anywhere in the table
      ,md5('NULL ORGANIZATION') as ORGANIZATION_SK
      ,'NULL FACILITY' AS FUND_DESCRIPTION
      ,'NULL FACILITY' AS PRODUCT_TYPE
      ,null AS DISCOUNT_RATE
      ,null AS NET_FUNDS_EMPLOYED
      ,null AS FACILITY_FUNDING_LIMIT
      ,null AS FUNDING_DATE
      ,null AS MATURITY_DATE
      ,null AS STATUS
      ,md5('NULL FACILITY') as CHANGE_TRACKING_KEY
      ,1 as RECORD_VERSION_NUMBER
      ,true as IS_CURRENT_IND
      ,current_timestamp()::timestamp_ntz(9) as record_valid_from_ts
      ,'9999-12-31 23:59:59'::timestamp_ntz(9) as record_valid_to_ts
      ,md5('NULL FACILITY') as SCD_ID
where not exists (
      select 1 from dim_facility
      where facility_sk = md5('NULL FACILITY')
);

select * from dim_facility;