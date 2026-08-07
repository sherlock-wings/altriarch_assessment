use role candidate_callahan;
use schema callahan_db.staging;

create or replace transient table int_organization (
organization_sk varchar,
organization_name varchar,
industry varchar,
state varchar,
relationship_owner varchar,
date_added date
);

/*
  - There are two records where the affinity_org_id is different,
    but all other values are the same.
    
  - Because this is a CRM, patterns like this are more likely to come 
    from the same customer being entered twice, or the same customer 
    changing names/other attributes over time. 

  - So rather than treating each unique affinity_org_id as a unique record,
    we deduplicate the dataset by the remaining attributes.
*/

insert into int_organization
select md5(nvl(upper(organization_name)::varchar, 'NULL') 
           || '||' ||
           nvl(industry::varchar, 'NULL') 
           || '||' ||
           nvl(state::varchar, 'NULL') 
           || '||' ||
           nvl(relationship_owner::varchar, 'NULL') 
           || '||' ||
           nvl(to_date(date_added, 'mm/dd/yy')::varchar, 'NULL') 
       ) as organization_sk
      ,upper(organization_name) as organization_name
      ,industry
      ,state
      ,relationship_owner
      ,to_date(date_added, 'mm/dd/yy') as date_added
from callahan_db.raw.affinity_organizations_export
qualify row_number() over (partition by upper(organization_name), 
                                        industry, 
                                        state, 
                                        relationship_owner, 
                                        date_added 
                           order     by affinity_org_id desc
        ) = 1
;