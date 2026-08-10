use role candidate_callahan;
use schema callahan_db.marts;
use warehouse callahan_wh;

/*
Outstanding exposure by industry.

To get exposure (from Tenor) by Industry (from Affinity), we must join the Factorview, Tenor,
and Affinity Dataets. The systems share no built-in key, so we must devise a join strategy. 

That strategy cannot use the client_name from Factorview directly, as shown below:
*/
with factorview as (
select distinct facility_id
      ,upper(trim(client_name)) as client_name
from callahan_db.raw.factorview_facilities_export
)

,affinity as (
select distinct upper(trim(organization_name)) as organization_name
from callahan_db.raw.affinity_organizations_export
)

select count(*) as facilities
      ,count(a.organization_name) as matched_on_raw_name
      ,count(*) - count(a.organization_name) as lost_to_the_join
from factorview f
left join affinity a
       on a.organization_name = f.client_name;


/*
Instead, we normalize these names into a robustly-joinable "Match Key", that then gets 
hashed to generate ORGANIZATION_SK, which is used for all analytic joins, .

Unmapped borrowers are mapped in two ways: 'NOT IN CRM' is a borrower Affinity has no record of and someone has to create
one; 'INDUSTRY NOT SET' is a CRM record whose industry field is blank and someone has to
fill it in.
*/
with labelled as (
select f.facility_id
      ,f.status
      ,f.net_funds_employed
      ,o.organization_sk
      ,case
         when o.organization_sk is null       then 'Unmapped borrower'
         when o.source_system = 'FACTORVIEW'  then 'NOT IN CRM'
         when nvl(o.industry, '~NULL~') = '~NULL~' then 'INDUSTRY NOT SET'
         else o.industry
       end as industry
from dim_facility f
left join dim_organization o
       on o.organization_sk = f.organization_sk
      and o.is_current_ind
where f.is_current_ind
  and f.facility_id <> 'NULL FACILITY'
)

select industry
      ,count(distinct organization_sk) as borrowers
      ,count(*) as facilities
      ,sum(net_funds_employed) as exposure
      ,sum(iff(status in ('ACTIVE', 'WATCH-LIST'), net_funds_employed, 0)) as open_exposure
      ,round(sum(net_funds_employed)
             / sum(sum(net_funds_employed)) over () * 100, 2) as pct_of_portfolio
from labelled
group by 1
order by exposure desc;


-- The borrowers behind the two unmapped labels
select o.organization_name
      ,o.source_system
      ,count(f.facility_id) as facilities
      ,sum(f.net_funds_employed) as exposure
from dim_organization o
join dim_facility f
  on f.organization_sk = o.organization_sk
 and f.is_current_ind
 and f.facility_id <> 'NULL FACILITY'
where o.is_current_ind
  and (o.source_system = 'FACTORVIEW' or nvl(o.industry, '~NULL~') = '~NULL~')
group by 1, 2
order by exposure desc;
