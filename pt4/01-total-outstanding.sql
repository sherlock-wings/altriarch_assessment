use role candidate_callahan;
use schema callahan_db.marts;

/*
Total portfolio outstanding balance.
  - NET_FUNDS_EMPLOYED sourced from Tenor, not Factorview.
  - The NULL FACILITY guard row is excluded -- it holds no balance and is not a facility.
*/
select count(*) as total_facilities
      ,count(*) - count(net_funds_employed) as facilities_missing_balance
      ,sum(net_funds_employed) as total_outstanding
from dim_facility
where is_current_ind = true
  and facility_id <> 'NULL FACILITY';


-- By status. CLOSED and PAID-OFF facilities still carry balance because Tenor's history
-- never remits them to zero; the discrepancy is Factorview's, not the ledger's.
select nvl(status, 'UNKNOWN') as status
      ,count(*) as facilities
      ,sum(net_funds_employed) as outstanding
      ,round(sum(net_funds_employed)
             / sum(sum(net_funds_employed)) over () * 100, 2) as pct_of_total
from dim_facility
where is_current_ind = true
  and facility_id <> 'NULL FACILITY'
group by 1
order by outstanding desc;


-- Balances Factorview left blank. Tenor supplies a real number for both, so neither is
-- null, dropped, or assumed to be zero.
select r.facility_id
      ,r.nfe as factorview_nfe
      ,d.status
      ,d.net_funds_employed as current_nfe
from (select distinct facility_id, nfe
      from callahan_db.raw.factorview_facilities_export) r
join dim_facility d
  on d.facility_id = r.facility_id
 and d.is_current_ind = true
where try_cast(regexp_replace(nvl(r.nfe, ''), '\\$|,', '') as number(35,3)) is null
order by r.facility_id;


-- Reconciling item: transactions Tenor reports against facilities Factorview has never
-- seen. They sit on the NULL FACILITY guard and move no facility balance, so their value
-- is outstanding somewhere but falls outside the total above.
select count(*) as orphan_transactions
      ,count(distinct facility_id) as orphan_facility_ids
      ,sum(amount) as orphan_amount
      ,listagg(distinct facility_id, ', ')
       within group (order by facility_id) as facility_ids
from fact_transaction
where not known_facility_ind;
