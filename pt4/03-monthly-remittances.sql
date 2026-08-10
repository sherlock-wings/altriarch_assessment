use role candidate_callahan;
use schema callahan_db.marts;
use warehouse callahan_wh; 

/*
Monthly remittance totals for 2025, by fund.

FACT_TRANSACTION carries Factorview's fund name wherever the facility is known, which is
where Tenor's 'ABL Fund' and 'Fund I' spellings are normalized. The five transactions
citing a Factorview-unknown facility do not get normmalized and keep Tenor's spelling,
so we use a CASE statement to recreate that normalization in-line.
*/
with normalized as (
select transaction_date
      ,case fund_description
         when 'ABL Fund' then 'Cardinal ABL & Factoring Fund'
         when 'Fund I'   then 'Cardinal Lender Finance Fund I'
         else fund_description
       end as fund_description
      ,amount
from fact_transaction
where transaction_type = 'Remittance'
  and year(transaction_date) = 2025
)

,month_spine as (
select dateadd(month, seq, '2025-01-01'::date) as month_start
from (select row_number() over (order by null) - 1 as seq
      from table(generator(rowcount => 12)))
)

,fund as (
select distinct fund_description
from dim_facility
where is_current_ind = true
  and facility_id <> 'NULL FACILITY'
)

select m.month_start
      ,f.fund_description
      ,count(n.amount) as remittances
      ,nvl(sum(n.amount), 0) as remittance_total
from month_spine m
cross join fund f
left join normalized n
       on n.fund_description = f.fund_description
      and date_trunc('month', n.transaction_date) = m.month_start
group by 1, 2
order by 1, 2;


-- 2025 totals per fund.
select case fund_description
         when 'ABL Fund' then 'Cardinal ABL & Factoring Fund'
         when 'Fund I'   then 'Cardinal Lender Finance Fund I'
         else fund_description
       end as fund_description
      ,count(*) as remittances
      ,sum(amount) as remittance_total
from fact_transaction
where transaction_type = 'Remittance'
  and year(transaction_date) = 2025
group by 1
order by remittance_total desc;


-- Listing of all Remittances in 2025 for Unknown Facilities
select transaction_id
      ,transaction_date
      ,facility_id
      ,fund_description as tenor_fund_name
      ,amount
from fact_transaction
where transaction_type = 'Remittance'
  and year(transaction_date) = 2025
  and not known_facility_ind
order by transaction_id;
