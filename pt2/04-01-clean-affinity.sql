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

insert into int_organization
select md5(upper(organization_name)::varchar 
           || '||' ||
           industry::varchar 
           || '||' ||
           state::varchar 
           || '||' ||
           relationship_owner::varchar 
           || '||' ||
           to_date(date_added, 'mm/dd/yy')::varchar 
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