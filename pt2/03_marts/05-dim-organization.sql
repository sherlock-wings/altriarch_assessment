use role candidate_callahan;
use schema callahan_db.marts;

create or replace table dim_organization like callahan_db.staging.int_organization;
alter table dim_organization add column load_number number(38,0)
                                       ,is_current_ind boolean
                                       ,record_valid_from_ts timestamp_ntz(9)
                                       ,record_valid_to_ts timestamp_ntz(9)
                                       ,scd_id varchar;

/*
Credit to this Medium article for the "inspiration" for the below MERGE SQL:
https://medium.com/@evgeniy.pintus/how-to-build-scd-type-2-in-one-merge-4da7f155a8a3
*/


with max_load_number as (
    select nvl(max(load_number), 0) as maxnum
    from dim_organization
)

incoming_src as (
    select * from callahan_db.staging.int_organization
)

,existing_tgt as (
    select * from dim_organization
)

,insert_new_org_data as (
    select src.*
          ,m.maxnum+1 as load_number
          ,true as is_current_ind
          ,current_timestamp() as record_valid_from_ts
          ,'9999-12-31 23:59:59'::timestamp_ntz(9) as record_valid_to_ts
          ,
    from incoming_src src
    left join existing_tgt 
           on tgt.organization_sk = src.organization_sk
    cross join max_load_number m
    where tgt.organization_sk is null
)

,insert_updated_org_data as (
    select src.*
          ,m.maxnum+1 as load_number
          ,true as is_current_ind
          ,current_timestamp() as record_valid_from
          ,'9999-12-31 23:59:59'::timestamp_ntz(9)
    from incoming_src src
    left join existing_tgt 
           on tgt.organization_sk = src.organization_sk
    cross join max_load_number m
    where tgt.organization_sk is not null
      and tgt.change_tracking_key <> src.change_tracking_key
)

,expire_existing_org_data as (
    select tgt.*, false as is_current_ind
    from existing_tgt tgt
    left join existing_tgt 
           on tgt.organization_sk = src.organization_sk
    cross join max_load_number m
    where tgt.organization_sk is not null
      and tgt.change_tracking_key <> src.change_tracking_key
)




