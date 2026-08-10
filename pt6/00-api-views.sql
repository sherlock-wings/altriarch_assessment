use role candidate_callahan;
use schema callahan_db.marts;

/*
The read surface for the Part 6 API. Both views filter IS_CURRENT_IND and drop the NULL guard
rows so no handler can forget to, and both null the '~NULL~' sentinel: it is an internal
convention and a REST consumer should see JSON null, not a string that looks like data.
*/
create or replace view v_api_borrower as
select organization_id
      ,organization_name
      ,nullif(industry, '~NULL~') as industry
      ,state
      ,relationship_owner
from dim_organization
where is_current_ind
  and organization_id <> 'NULL ORGANIZATION';


-- Left join, not inner: a facility pointing at the NULL ORGANIZATION guard row must still
-- appear in GET /loans rather than disappear from the API entirely.
create or replace view v_api_loan as
select f.facility_id
      ,o.organization_id
      ,o.organization_name
      ,nullif(o.industry, '~NULL~') as industry
      ,f.fund_description
      ,f.product_type
      ,f.status
      ,f.net_funds_employed
      ,f.facility_funding_limit
      ,f.discount_rate
      ,f.funding_date
      ,f.maturity_date
from dim_facility f
left join dim_organization o
       on o.organization_sk = f.organization_sk
      and o.is_current_ind
      and o.organization_id <> 'NULL ORGANIZATION'
where f.is_current_ind
  and f.facility_id <> 'NULL FACILITY';


select 'v_api_loan'      as view_name
      ,count(*)          as row_count
      ,40                as expected_rows
      ,count(organization_id) as mapped_to_borrower
      ,40                as expected_mapped
from v_api_loan

union all

select 'v_api_borrower'
      ,count(*)
      ,33
      ,count(organization_id)
      ,33
from v_api_borrower;
