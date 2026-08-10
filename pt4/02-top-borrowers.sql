use role candidate_callahan;
use schema callahan_db.marts;
use warehouse callahan_wh;
/*
Top 5 borrowers by outstanding exposure, open facilities only.

Open means ACTIVE or WATCH-LIST. Watch-list is a credit-risk flag rather than a lifecycle
state -- the facility is still funded and the money is still out. Exposure aggregates at
the borrower, not the facility.

I was not sure how to interpret "share of total portfolio exposure" so I showed different interpretations 
with different denominators. in the final output
*/
with open_facility as (
select organization_sk
      ,net_funds_employed
from dim_facility
where is_current_ind
  and facility_id <> 'NULL FACILITY'
  and status in ('ACTIVE', 'WATCH-LIST')
)

,denominator as (
select (select sum(net_funds_employed) from open_facility) as open_book
      ,(select sum(net_funds_employed)
        from dim_facility
        where is_current_ind and facility_id <> 'NULL FACILITY') as whole_portfolio
)

select o.organization_id
      ,o.organization_name
      ,count(*) as open_facilities
      ,sum(f.net_funds_employed) as exposure
      ,round(sum(f.net_funds_employed) / max(d.open_book) * 100, 2) as pct_of_open_book
      ,round(sum(f.net_funds_employed) / max(d.whole_portfolio) * 100, 2) as pct_of_portfolio
from open_facility f
join dim_organization o
  on o.organization_sk = f.organization_sk
 and o.is_current_ind
cross join denominator d
group by 1, 2
order by exposure desc
limit 5;


-- Listing of all Not-Open facilities, excluded by the open-only filter
select nvl(status, 'UNKNOWN') as status
      ,count(*) as facilities
      ,sum(net_funds_employed) as excluded_exposure
      ,listagg(facility_id, ', ') within group (order by facility_id) as facility_ids
from dim_facility
where is_current_ind
  and facility_id <> 'NULL FACILITY'
  and nvl(status, 'UNKNOWN') not in ('ACTIVE', 'WATCH-LIST')
group by 1
order by excluded_exposure desc;
