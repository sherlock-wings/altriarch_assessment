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


merge into dim_facility dim 
using (
with max_record_version_number as (
    select nvl(max(record_version_number), 0) as maxnum
    from dim_facility
)

,incoming_src as (
    select * from callahan_db.staging.int_facility
)

,existing_tgt as (
    select * from dim_facility
)

,insert_new_org_data as (
    select src.*
          ,m.maxnum + 1 as record_version_number
          ,true as is_current_ind
          ,current_timestamp()::timestamp_tz(9)  as record_valid_from_ts
          ,'9999-12-31 23:59:59 -0700'::timestamp_tz(9) as record_valid_to_ts
          ,md5(
            src.facility_sk::varchar
            || '||' ||
            current_timestamp()::varchar
          ) as scd_id
    from incoming_src src
    left join existing_tgt tgt
           on src.facility_sk = tgt.facility_sk
    cross join max_record_version_number m
    where tgt.facility_sk is null
)

,insert_updated_org_data as (
    select src.*
          ,m.maxnum + 1 as record_version_number
          ,true as is_current_ind
          ,current_timestamp()::timestamp_tz(9) as record_valid_from_ts
          ,'9999-12-31 23:59:59 -0700'::timestamp_tz(9) as record_valid_to_ts
          ,md5(
            src.facility_sk::varchar
            || '||' ||
            current_timestamp()::timestamp_tz(9)::varchar
          ) as scd_id
    from incoming_src src
    join existing_tgt tgt
      on tgt.facility_sk = src.facility_sk
    cross join max_record_version_number m
    where tgt.change_tracking_key <> src.change_tracking_key
)

,expire_existing_org_data as (
    select tgt.FACILITY_SK
          ,tgt.FACILITY_ID
          ,tgt.CLIENT_NAME
          ,tgt.FUND_DESCRIPTION
          ,tgt.PRODUCT_TYPE
          ,tgt.DISCOUNT_RATE
          ,tgt.NET_FUNDS_EMPLOYED
          ,tgt.FACILITY_FUNDING_LIMIT
          ,tgt.FUNDING_DATE
          ,tgt.MATURITY_DATE
          ,tgt.STATUSES
          ,tgt.CHANGE_TRACKING_KEY
          ,tgt.RECORD_VERSION_NUMBER
          ,false as IS_CURRENT_IND
          ,tgt.RECORD_VALID_FROM_TS
          ,dateadd(millisecond, -1, current_timestamp()::timestamp_tz(9)) as RECORD_VALID_TO_TS
          ,tgt.SCD_ID
    from existing_tgt tgt
    left join incoming_src src 
           on tgt.facility_sk = src.facility_sk
    where tgt.facility_sk is not null
      and tgt.change_tracking_key <> src.change_tracking_key
)

select * from insert_new_org_data
union all
select * from insert_updated_org_data
union all 
select * from expire_existing_org_data
) intr 
on dim.facility_sk = intr.facility_sk
when not matched then insert (
   FACILITY_SK
  ,FACILITY_ID
  ,CLIENT_NAME
  ,FUND_DESCRIPTION
  ,PRODUCT_TYPE
  ,DISCOUNT_RATE
  ,NET_FUNDS_EMPLOYED
  ,FACILITY_FUNDING_LIMIT
  ,FUNDING_DATE
  ,MATURITY_DATE
  ,STATUSES
  ,CHANGE_TRACKING_KEY
  ,RECORD_VERSION_NUMBER
  ,IS_CURRENT_IND
  ,RECORD_VALID_FROM_TS
  ,RECORD_VALID_TO_TS
  ,SCD_ID
) values (
   intr.FACILITY_SK
  ,intr.FACILITY_ID
  ,intr.CLIENT_NAME
  ,intr.FUND_DESCRIPTION
  ,intr.PRODUCT_TYPE
  ,intr.DISCOUNT_RATE
  ,intr.NET_FUNDS_EMPLOYED
  ,intr.FACILITY_FUNDING_LIMIT
  ,intr.FUNDING_DATE
  ,intr.MATURITY_DATE
  ,intr.STATUSES
  ,intr.CHANGE_TRACKING_KEY
  ,intr.RECORD_VERSION_NUMBER
  ,intr.IS_CURRENT_IND
  ,intr.RECORD_VALID_FROM_TS
  ,intr.RECORD_VALID_TO_TS
  ,intr.SCD_ID
)
when matched 
 and dim.change_tracking_key <> intr.change_tracking_key
then update set  
   dim.CLIENT_NAME = intr.CLIENT_NAME
  ,dim.FUND_DESCRIPTION = intr.FUND_DESCRIPTION
  ,dim.PRODUCT_TYPE = intr.PRODUCT_TYPE
  ,dim.DISCOUNT_RATE = intr.DISCOUNT_RATE
  ,dim.NET_FUNDS_EMPLOYED = intr.NET_FUNDS_EMPLOYED
  ,dim.FACILITY_FUNDING_LIMIT = intr.FACILITY_FUNDING_LIMIT
  ,dim.FUNDING_DATE = intr.FUNDING_DATE
  ,dim.MATURITY_DATE = intr.MATURITY_DATE
  ,dim.STATUSES = intr.STATUSES
  ,dim.CHANGE_TRACKING_KEY = intr.CHANGE_TRACKING_KEY
  ,dim.RECORD_VERSION_NUMBER = intr.RECORD_VERSION_NUMBER
  ,dim.IS_CURRENT_IND = intr.IS_CURRENT_IND
  ,dim.RECORD_VALID_FROM_TS = intr.RECORD_VALID_FROM_TS
  ,dim.RECORD_VALID_TO_TS = intr.RECORD_VALID_TO_TS
  ,dim.SCD_ID = intr.SCD_ID
;

insert into dim_facility
select md5('NULL FACILITY') as FACILITY_SK
      ,'NULL FACILITY' AS FACILITY_ID
      ,'NULL FACILITY' AS CLIENT_NAME
      ,'NULL FACILITY' AS FUND_DESCRIPTION
      ,'NULL FACILITY' AS PRODUCT_TYPE
      ,null AS DISCOUNT_RATE
      ,null AS NET_FUNDS_EMPLOYED
      ,null AS FACILITY_FUNDING_LIMIT
      ,null AS FUNDING_DATE
      ,null AS MATURITY_DATE
      ,null AS STATUSES
      ,md5('NULL FACILITY') as CHANGE_TRACKING_KEY
      ,1 as RECORD_VERSION_NUMBER
      ,true as IS_CURRENT_IND
      ,current_timestamp()::timestamp_tz(9) as record_valid_from_ts
      ,'9999-12-31 23:59:59 -0700'::timestamp_tz(9) as record_valid_to_ts
      ,md5('NULL FACILITY') as SCD_ID;

select * from dim_facility;