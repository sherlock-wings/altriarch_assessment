use role candidate_callahan;
use schema callahan_db.marts;

create table if not exists dim_organization as
select o.*
      ,null::number(38,0) as record_version_number
      ,null::boolean as is_current_ind
      ,null::timestamp_ntz(9) as record_valid_from_ts
      ,null::timestamp_ntz(9) as record_valid_to_ts
      ,null::varchar as scd_id
from callahan_db.staging.int_organization o
where false;

merge into dim_organization dim
using (
with incoming_src as (
    select * from callahan_db.staging.int_organization
)

,existing_tgt as (
    -- current versions only; history rows would fan out every join below
    select * from dim_organization
    where is_current_ind
)

,insert_new_org_data as (
    select src.*
          ,nvl(tgt.record_version_number, 0) + 1 as record_version_number
          ,true as is_current_ind
          ,current_timestamp()::timestamp_ntz(9)  as record_valid_from_ts
          ,'9999-12-31 23:59:59'::timestamp_ntz(9) as record_valid_to_ts
          ,md5(
            src.organization_sk::varchar
            || '||' ||
            (nvl(tgt.record_version_number, 0) + 1)::varchar
          ) as scd_id
    from incoming_src src
    left join existing_tgt tgt
           on src.organization_sk = tgt.organization_sk
    where tgt.organization_sk is null
)

,insert_updated_org_data as (
    select src.*
          ,nvl(tgt.record_version_number, 0) + 1 as record_version_number
          ,true as is_current_ind
          ,current_timestamp()::timestamp_ntz(9) as record_valid_from_ts
          ,'9999-12-31 23:59:59'::timestamp_ntz(9) as record_valid_to_ts
          ,md5(
            src.organization_sk::varchar
            || '||' ||
            (nvl(tgt.record_version_number, 0) + 1)::varchar
          ) as scd_id
    from incoming_src src
    join existing_tgt tgt
      on tgt.organization_sk = src.organization_sk
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
          ,dateadd(millisecond, -1, current_timestamp()::timestamp_ntz(9)) as RECORD_VALID_TO_TS
          ,tgt.SCD_ID
    from existing_tgt tgt
    -- absence from the export is not a deletion; only changed organizations expire
    join incoming_src src
      on tgt.organization_sk = src.organization_sk
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
-- only expire_existing_org_data rows can match, and they close the version they came from
when matched then update set
   dim.IS_CURRENT_IND = intr.IS_CURRENT_IND
  ,dim.RECORD_VALID_TO_TS = intr.RECORD_VALID_TO_TS
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
      ,current_timestamp()::timestamp_ntz(9) as record_valid_from_ts
      ,'9999-12-31 23:59:59'::timestamp_ntz(9) as record_valid_to_ts
      ,md5('NULL ORGANIZATION') as SCD_ID
-- the MERGE above is re-runnable on its own; this single row is not, so guard it
where not exists (
      select 1 from dim_organization
      where organization_sk = md5('NULL ORGANIZATION')
);

select * from dim_organization;