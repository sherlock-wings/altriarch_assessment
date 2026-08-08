use role candidate_callahan;
use schema callahan_db.marts;

create or replace table dim_organization 
like callahan_db.staging.int_organization;
alter table dim_organization
add column record_version_number number(38,0)
          ,is_current_ind boolean
          ,record_valid_from_ts timestamp_tz(9)
          ,record_valid_to_ts timestamp_tz(9)
          ,scd_id varchar
;

merge into dim_organization dim 
using (
with max_record_version_number as (
    select nvl(max(record_version_number), 0) as maxnum
    from dim_organization
)

,incoming_src as (
    select * from callahan_db.staging.int_organization
)

,existing_tgt as (
    select * from dim_organization
)

,insert_new_org_data as (
    select src.*
          ,m.maxnum + 1 as record_version_number
          ,true as is_current_ind
          ,current_timestamp()::timestamp_tz(9)  as record_valid_from_ts
          ,'9999-12-31 23:59:59 -0700'::timestamp_tz(9) as record_valid_to_ts
          ,md5(
            src.organization_sk::varchar
            || '||' ||
            current_timestamp()::varchar
          ) as scd_id
    from incoming_src src
    left join existing_tgt tgt
           on src.organization_sk = tgt.organization_sk
    cross join max_record_version_number m
    where tgt.organization_sk is null
)

,insert_updated_org_data as (
    select src.*
          ,m.maxnum + 1 as record_version_number
          ,true as is_current_ind
          ,current_timestamp()::timestamp_tz(9) as record_valid_from_ts
          ,'9999-12-31 23:59:59 -0700'::timestamp_tz(9) as record_valid_to_ts
          ,md5(
            src.organization_sk::varchar
            || '||' ||
            current_timestamp()::timestamp_tz(9)::varchar
          ) as scd_id
    from incoming_src src
    join existing_tgt tgt
      on tgt.organization_sk = src.organization_sk
    cross join max_record_version_number m
    where tgt.change_tracking_key <> src.change_tracking_key
)

,expire_existing_org_data as (
    select tgt.ORGANIZATION_SK
          ,tgt.ORGANIZATION_ID
          ,tgt.ORGANIZATION_NAME
          ,tgt.INDUSTRY
          ,tgt.STATE
          ,tgt.RELATIONSHIP_OWNER
          ,tgt.DATE_ADDED
          ,tgt.CHANGE_TRACKING_KEY
          ,tgt.RECORD_VERSION_NUMBER
          ,false as IS_CURRENT_IND
          ,tgt.RECORD_VALID_FROM_TS
          ,dateadd(millisecond, -1, current_timestamp()::timestamp_tz(9)) as RECORD_VALID_TO_TS
          ,tgt.SCD_ID
    from existing_tgt tgt
    left join incoming_src src 
           on tgt.organization_sk = src.organization_sk
    where tgt.organization_sk is not null
      and tgt.change_tracking_key <> src.change_tracking_key
)

select * from insert_new_org_data
union all
select * from insert_updated_org_data
union all 
select * from expire_existing_org_data
) intr 
on dim.organization_sk = intr.organization_sk
when not matched then insert (
   ORGANIZATION_SK
  ,ORGANIZATION_ID
  ,ORGANIZATION_NAME
  ,INDUSTRY
  ,STATE
  ,RELATIONSHIP_OWNER
  ,DATE_ADDED
  ,CHANGE_TRACKING_KEY
  ,RECORD_VERSION_NUMBER
  ,IS_CURRENT_IND
  ,RECORD_VALID_FROM_TS
  ,RECORD_VALID_TO_TS
  ,SCD_ID
) values (
   intr.ORGANIZATION_SK
  ,intr.ORGANIZATION_ID
  ,intr.ORGANIZATION_NAME
  ,intr.INDUSTRY
  ,intr.STATE
  ,intr.RELATIONSHIP_OWNER
  ,intr.DATE_ADDED
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
   dim.ORGANIZATION_NAME = intr.ORGANIZATION_NAME
  ,dim.INDUSTRY = intr.INDUSTRY
  ,dim.STATE = intr.STATE
  ,dim.RELATIONSHIP_OWNER = intr.RELATIONSHIP_OWNER
  ,dim.DATE_ADDED = intr.DATE_ADDED
  ,dim.CHANGE_TRACKING_KEY = intr.CHANGE_TRACKING_KEY
  ,dim.RECORD_VERSION_NUMBER = intr.RECORD_VERSION_NUMBER
  ,dim.IS_CURRENT_IND = intr.IS_CURRENT_IND
  ,dim.RECORD_VALID_FROM_TS = intr.RECORD_VALID_FROM_TS
  ,dim.RECORD_VALID_TO_TS = intr.RECORD_VALID_TO_TS
  ,dim.SCD_ID = intr.SCD_ID
;


insert into dim_organization
select md5('NULL ORGANIZATION') as ORGANIZATION_SK
      ,'NULL ORGANIZATION' as ORGANIZATION_ID
      ,'NULL ORGANIZATION' as ORGANIZATION_NAME
      ,'NULL ORGANIZATION' as INDUSTRY
      ,'NULL ORGANIZATION' as STATE
      ,'NULL ORGANIZATION' as RELATIONSHIP_OWNER
      ,null as DATE_ADDED
      ,md5('NULL ORGANIZATION') as CHANGE_TRACKING_KEY
      ,1 as RECORD_VERSION_NUMBER
      ,true as IS_CURRENT_IND
      ,current_timestamp()::timestamp_tz(9) as record_valid_from_ts
      ,'9999-12-31 23:59:59 -0700'::timestamp_tz(9) as record_valid_to_ts
      ,md5('NULL ORGANIZATION') as SCD_ID;
select * from dim_organization;