use role candidate_callahan;
use schema callahan_db.marts;

/*
The one object CALLAHAN_LP_READONLY is allowed to read. Aggregate only: no facility id, no
borrower name, no per-facility amount. Status collapses to OPEN / NOT OPEN so that no cell
resolves down to a single facility, and concentration is a top-5 total rather than a ranked
list, which would hand an LP the largest borrower's balance.
*/
create or replace view v_lp_portfolio_summary as
with facility as (
    select f.facility_sk
          ,f.organization_sk
          ,f.fund_description
          ,f.net_funds_employed
          ,case
             when f.status in ('ACTIVE', 'WATCH-LIST')
             then 'OPEN'
             else 'NOT OPEN'
           end as position_status
    from dim_facility f
    where f.is_current_ind
      and f.facility_id <> 'NULL FACILITY'
),

portfolio as (
    select sum(net_funds_employed) as total_outstanding
    from facility
),

top_borrower as (
    select organization_sk
          ,count(*)                as facility_count
          ,sum(net_funds_employed) as outstanding_balance
    from facility
    where position_status = 'OPEN'
    group by organization_sk
    order by outstanding_balance desc
    limit 5
)

select 1                                as display_order
      ,'PORTFOLIO'                      as metric_group
      ,'TOTAL'                          as metric_label
      ,count(*)                         as facility_count
      ,count(distinct organization_sk)  as borrower_count
      ,sum(net_funds_employed)          as outstanding_balance
      ,100.00                           as pct_of_portfolio
from facility

union all

select 2
      ,'FUND'
      ,fund_description
      ,count(*)
      ,count(distinct organization_sk)
      ,sum(net_funds_employed)
      ,round(100 * sum(net_funds_employed) / (select total_outstanding from portfolio), 2)
from facility
group by fund_description

union all

select 3
      ,'POSITION STATUS'
      ,position_status
      ,count(*)
      ,count(distinct organization_sk)
      ,sum(net_funds_employed)
      ,round(100 * sum(net_funds_employed) / (select total_outstanding from portfolio), 2)
from facility
group by position_status

union all

select 4
      ,'CONCENTRATION'
      ,'TOP 5 BORROWERS BY OPEN EXPOSURE'
      ,sum(facility_count)
      ,count(*)
      ,sum(outstanding_balance)
      ,round(100 * sum(outstanding_balance) / (select total_outstanding from portfolio), 2)
from top_borrower;


-- The view must reconcile to the mart it summarizes and must never expose a cell backed by
-- one facility.
select (select outstanding_balance
        from v_lp_portfolio_summary
        where metric_group = 'PORTFOLIO')            as summary_total
      ,(select sum(net_funds_employed)
        from dim_facility
        where is_current_ind
          and facility_id <> 'NULL FACILITY')        as mart_total
      ,(select min(facility_count)
        from v_lp_portfolio_summary
        where metric_group in ('FUND', 'POSITION STATUS')) as smallest_cell_facilities;