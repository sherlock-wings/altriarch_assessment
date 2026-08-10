use role candidate_callahan;
use schema callahan_db.staging;

create transient table if not exists int_organization (
organization_sk varchar,
organization_id varchar,
organization_name varchar,
industry varchar,
state varchar,
relationship_owner varchar,
date_added date,
source_system varchar,
change_tracking_key varchar
);

/*
  - There are two records where the affinity_org_id is different,
    but all other values are the same.

  - Because this is a CRM, patterns like this are more likely to come
    from the same customer being entered twice, or the same customer
    changing names/other attributes over time.

  - So rather than treating each unique affinity_org_id as a unique
    record, we deduplicate the dataset by the remaining attributes.

  - We assign the *first* affinity_org_id as the official ID for
    a given partition. This way the first ID that is known for a
    customer is frozen, and future IDs that point to the same
    customer are blocked
*/

truncate table int_organization;

insert into int_organization
/*
Factorview and Affinity share no borrower key, only a name, and they spell it differently:
8 of 40 facilities fail an exact-name join. Punctuation and a trailing legal suffix are the
only differences observed, so both systems normalize through MATCH_KEY below and hash the
result into ORGANIZATION_SK. 02-clean-facility.sql repeats that expression verbatim rather
than reading this table; pt3/05-verify.sql fails if the two copies ever drift apart.
*/
with affinity_raw as (
select affinity_org_id
      ,trim(upper(organization_name), ' ') as organization_name
      ,industry
      ,state
      ,relationship_owner
      ,date_added
      ,trim(regexp_replace(
            regexp_replace(upper(nvl(organization_name, '~NULL~')), '[^A-Z0-9 ]', ''),
            ' (LLC|INC|CO|LP|LTD|CORP|COMPANY)$', '')) as match_key
from callahan_db.raw.affinity_organizations_export
)

,affinity as (
select md5(match_key) as organization_sk
      ,affinity_org_id as organization_id
      ,organization_name
      ,nvl(industry, '~NULL~') as industry
      ,state
      ,relationship_owner
      ,to_date(date_added, 'mm/dd/yy') as date_added
      ,'AFFINITY' as source_system
from affinity_raw
qualify row_number() over (partition by match_key,
                                        industry,
                                        state,
                                        relationship_owner,
                                        date_added
                           order     by affinity_org_id
        ) = 1
)


,affinity_deduped as (
select * from affinity
qualify row_number() over (partition by organization_sk order by organization_id) = 1
)

,factorview_raw as (
select trim(upper(client_name), ' ') as organization_name
      ,trim(regexp_replace(
            regexp_replace(upper(nvl(client_name, '~NULL~')), '[^A-Z0-9 ]', ''),
            ' (LLC|INC|CO|LP|LTD|CORP|COMPANY)$', '')) as match_key
from callahan_db.raw.factorview_facilities_export
)

,factorview_only as (
select md5(match_key) as organization_sk
      ,'FV-' || upper(left(md5(match_key), 8)) as organization_id
      ,organization_name
      ,'~NULL~' as industry
      ,null::varchar as state
      ,null::varchar as relationship_owner
      ,null::date as date_added
      ,'FACTORVIEW' as source_system
from factorview_raw
where md5(match_key) not in (select organization_sk from affinity_deduped)
qualify row_number() over (partition by organization_sk order by organization_name) = 1
)

,conformed as (
select * from affinity_deduped
union all
select * from factorview_only
)


select organization_sk
      ,organization_id
      ,organization_name
      ,industry
      ,state
      ,relationship_owner
      ,date_added
      ,source_system
      ,md5(
       nvl(organization_id::varchar, '~NULL~')
       || '||' ||
       nvl(organization_name::varchar, '~NULL~')
       || '||' ||
       nvl(industry::varchar, '~NULL~')
       || '||' ||
       nvl(state::varchar, '~NULL~')
       || '||' ||
       nvl(relationship_owner::varchar, '~NULL~')
       || '||' ||
       nvl(date_added::varchar, '~NULL~')
       || '||' ||
       nvl(source_system::varchar, '~NULL~')
      ) as change_tracking_key
from conformed
;


create transient table if not exists audit_organization as
select r.*
      ,null::number(38,0) as record_number
      ,null::varchar as duplicate_id
from callahan_db.raw.affinity_organizations_export r
where false;

truncate table audit_organization;

insert into audit_organization
-- This table collects the "losers" of the dedup operations above. A 
-- row that loses either QUALIFY lands here.
with keyed as (
select *
      ,trim(regexp_replace(
            regexp_replace(upper(nvl(organization_name, '~NULL~')), '[^A-Z0-9 ]', ''),
            ' (LLC|INC|CO|LP|LTD|CORP|COMPANY)$', '')) as match_key
from callahan_db.raw.affinity_organizations_export
)

,numbered as (
select *
      ,row_number() over (
       partition by match_key,
                    industry,
                    state,
                    relationship_owner,
                    date_added
       order     by affinity_org_id
      ) as record_number
from keyed
)

,dupe_ls as (
  select distinct match_key from numbered
  where record_number > 1
)

select a.* exclude (match_key)
      ,md5(nvl(a.affinity_org_id::varchar, '~NULL~')
           || '||' ||
           nvl(a.record_number::varchar, '~NULL~')
      ) as duplicate_id
from numbered a
join dupe_ls b
  on a.match_key = b.match_key
;

select * from int_organization;
select * from audit_organization;
