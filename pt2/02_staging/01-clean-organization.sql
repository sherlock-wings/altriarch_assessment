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
select md5(nvl(trim(upper(organization_name), ' ')::varchar, '~NULL~')) as organization_sk
      ,affinity_org_id as organization_id
      ,trim(upper(organization_name), ' ') as organization_name
      ,nvl(industry, '~NULL~') as industry
      ,state
      ,relationship_owner
      ,to_date(date_added, 'mm/dd/yy') as date_added
      ,md5(
       nvl(industry::varchar, '~NULL~') 
       || '||' ||
       nvl(state::varchar, '~NULL~')
       || '||' ||
       nvl(relationship_owner::varchar, '~NULL~')
       || '||' ||
       to_date(date_added, 'mm/dd/yy')::varchar
      ) as change_tracking_key
from callahan_db.raw.affinity_organizations_export
qualify row_number() over (partition by upper(organization_name), 
                                        industry, 
                                        state, 
                                        relationship_owner, 
                                        date_added 
                           order     by affinity_org_id
        ) = 1
;


create transient table if not exists audit_organization as
select r.*
      ,null::number(38,0) as record_number
      ,null::varchar as duplicate_id
from callahan_db.raw.affinity_organizations_export r
where false;

truncate table audit_organization;

insert into audit_organization
with numbered as (
select *
      ,row_number() over (
       partition by upper(organization_name), 
                    industry, 
                    state, 
                    relationship_owner, 
                    date_added 
       order     by affinity_org_id
      ) as record_number
from callahan_db.raw.affinity_organizations_export
)


,dupe_ls as (
  select distinct * exclude (affinity_org_id, record_number) 
  from numbered
  where record_number > 1
)

select a.*
      ,md5(nvl(a.affinity_org_id::varchar, '~NULL~') 
           || '||' || 
           nvl(a.record_number::varchar, '~NULL~')
      ) as duplicate_id
from numbered a 
join dupe_ls b 
  on trim(upper(a.organization_name), ' ') = trim(upper(b.organization_name), ' ')
;

select * from int_organization;
select * from audit_organization;