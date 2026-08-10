use role candidate_callahan;
use schema callahan_db.marts;
use warehouse callahan_wh;

/*
Guards on the expressions scripts 01-04 repeat. Every check reports PASS or FAIL in its
last column. Run this after any change to those four scripts.
*/


-- Validates question 4.1 against 4.4 by comparing facility counts and exposure totals
-- and confirming they match. 
with headline as (
select count(*) as facilities
      ,sum(net_funds_employed) as total
from dim_facility
where is_current_ind
  and facility_id <> 'NULL FACILITY'
)

,by_industry as (
select count(*) as facilities
      ,sum(f.net_funds_employed) as total
from dim_facility f
left join dim_organization o
       on o.organization_sk = f.organization_sk
      and o.is_current_ind
where f.is_current_ind
  and f.facility_id <> 'NULL FACILITY'
)

select h.facilities as headline_facilities
      ,i.facilities as industry_facilities
      ,h.total as headline_total
      ,i.total as industry_total
      ,iff(h.facilities = i.facilities and h.total = i.total, 'PASS', 'FAIL') as result
from headline h
cross join by_industry i;


-- Validates question 4 by re-running its industry CASE and counting the rows it fails to
-- label, which must be zero. Confirms no facility falls through to a null industry and that
-- the '~NULL~' fallback is caught by 'INDUSTRY NOT SET' rather than leaving the mart.
with labelled as (
select case
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

select count(*) as unlabelled_facilities
      ,iff(count(*) = 0, 'PASS', 'FAIL') as result
from labelled
where nvl(industry, '~NULL~') = '~NULL~';


-- Validates question 2 against question 1 by comparing the open-book total to the whole
-- portfolio total and confirming the first is contained in the second.
with open_book as (
select sum(net_funds_employed) as total
from dim_facility
where is_current_ind
  and facility_id <> 'NULL FACILITY'
  and status in ('ACTIVE', 'WATCH-LIST')
)

,portfolio as (
select sum(net_funds_employed) as total
from dim_facility
where is_current_ind
  and facility_id <> 'NULL FACILITY'
)

select o.total as open_book
      ,p.total as portfolio
      ,round(o.total / p.total * 100, 2) as open_pct_of_portfolio
      ,iff(o.total <= p.total, 'PASS', 'FAIL') as result
from open_book o
cross join portfolio p;


-- Validates question 1 against question 3 by counting the orphan transactions both treat as
-- a reconciling item and confirming none of them sits on a real facility. 
-- Expect 5 transactions worth 70,385.05.
select count(*) as orphan_transactions
      ,sum(amount) as orphan_amount
      ,count_if(facility_sk <> md5('NULL FACILITY')) as touching_a_real_facility
      ,iff(count_if(facility_sk <> md5('NULL FACILITY')) = 0, 'PASS', 'FAIL') as result
from fact_transaction
where not known_facility_ind;


-- Validates question 3 against itself by comparing its overall total from the monthly aggregations
-- with a direct sum of all transactions in 2025 and confirming they match. 
-- Expect 5,126,379.30 both ways.
with gridded as (
select nvl(sum(n.amount), 0) as total
from (select dateadd(month, seq, '2025-01-01'::date) as month_start
      from (select row_number() over (order by null) - 1 as seq
            from table(generator(rowcount => 12)))) m
cross join (select distinct fund_description
            from dim_facility
            where is_current_ind and facility_id <> 'NULL FACILITY') f
left join (select transaction_date
                 ,case fund_description
                    when 'ABL Fund' then 'Cardinal ABL & Factoring Fund'
                    when 'Fund I'   then 'Cardinal Lender Finance Fund I'
                    else fund_description
                  end as fund_description
                 ,amount
           from fact_transaction
           where transaction_type = 'Remittance'
             and year(transaction_date) = 2025) n
       on n.fund_description = f.fund_description
      and date_trunc('month', n.transaction_date) = m.month_start
)

,ungridded as (
select sum(amount) as total
from fact_transaction
where transaction_type = 'Remittance'
  and year(transaction_date) = 2025
)

select g.total as gridded_total
      ,u.total as ungridded_total
      ,iff(g.total = u.total, 'PASS', 'FAIL') as result
from gridded g
cross join ungridded u;


-- Context for question 3: lists the remittances its 2025 filter
-- excludes, showing the rows left out of that answer. The
-- API-prefixed 2026 row is one POST /remittances wrote during the Part 6 walkthrough.
select transaction_id
      ,transaction_date
      ,facility_id
      ,amount
from fact_transaction
where transaction_type = 'Remittance'
  and year(transaction_date) <> 2025
order by transaction_date desc, transaction_id
limit 10;
