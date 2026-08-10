use role candidate_callahan;
use schema callahan_db.marts;


-- Confirm task execution
select name
      ,state
      ,scheduled_time
      ,completed_time
      ,error_message
from table(information_schema.task_history(
       task_name => 'TSK_LOAD_TRANSACTIONS',
       result_limit => 20))
order by scheduled_time desc;

-- Confirm stream depletion
select system$stream_has_data('callahan_db.raw.stm_tenor_transactions') as stream_has_data;

-- show current row-counts for major pipeline objects
select (select count(*) from callahan_db.raw.tenor_transactions_export) as raw_rows
      ,(select count(*) from callahan_db.staging.int_transaction) as int_rows
      ,(select count(*) from fact_transaction) as fact_rows
      ,(select count(distinct transaction_id) from fact_transaction) as fact_distinct_ids
      ,(select count(*) from callahan_db.staging.audit_transaction) as audit_rows;

-- show disposition of every delta row
select f.transaction_id
      ,f.transaction_date
      ,f.facility_id
      ,f.fund_description
      ,f.amount
      ,f.known_facility_ind
      ,f.record_inserted_ts
      ,f.record_updated_ts
from fact_transaction f
where f.transaction_id in ('INV-70001','INV-70002','INV-70003','INV-70004','INV-70005','INV-50100')
order by f.transaction_id;

-- show NFE movement against the pre-delta snapshot
select p.facility_id
      ,d.status
      ,p.net_funds_employed as nfe_before
      ,d.net_funds_employed as nfe_after
      ,d.net_funds_employed - p.net_funds_employed as nfe_change
from callahan_db.staging.pre_delta_nfe_snapshot p
join dim_facility d
  on d.facility_sk = p.facility_sk
 and d.is_current_ind
where equal_null(p.net_funds_employed, d.net_funds_employed) = false
order by p.facility_id;

select transaction_id
      ,record_number
      ,duplicate_ind
      ,conflict_ind
      ,parse_fail_ind
      ,parse_fail_fields
      ,batch_ts
from callahan_db.staging.audit_transaction
order by batch_ts, transaction_id, record_number;


-- every facility resolves to an organization, in the marts and in staging. Both must be 0.
select (
  select count(*)
  from callahan_db.marts.dim_facility f
  where f.is_current_ind
    and not exists (select 1 from callahan_db.marts.dim_organization o
                    where o.is_current_ind and o.organization_sk = f.organization_sk)
) as orphan_facilities_marts
,(
  select count(*)
  from callahan_db.staging.int_facility f
  where not exists (select 1 from callahan_db.staging.int_organization o
                    where o.organization_sk = f.organization_sk)
) as orphan_facilities_staging;

-- no fan-out: one row per surrogate key in both layers. Both must be 0.
select (
  select count(*) from (
    select organization_sk from callahan_db.marts.dim_organization
    where is_current_ind group by 1 having count(*) > 1)
) as duplicate_org_sk_marts
,(
  select count(*) from (
    select organization_sk from callahan_db.staging.int_organization
    group by 1 having count(*) > 1)
) as duplicate_org_sk_staging;

-- the join does not multiply facilities. Must equal the DIM_FACILITY current row count, 41.
select count(*) as joined_rows
from callahan_db.marts.dim_facility f
join callahan_db.marts.dim_organization o
  on o.organization_sk = f.organization_sk and o.is_current_ind
where f.is_current_ind;

-- provenance. Expect 31 AFFINITY and 2 FACTORVIEW.
select source_system, count(*) as n
from callahan_db.staging.int_organization
group by 1 order by 1;

-- name groups the match key collapses. Expect 4, all legal-suffix variants of one borrower;
-- a fifth means the heuristic reached a name it should not have and needs a human to look.
with src as (
select 'AFFINITY' as source_system
      ,trim(upper(organization_name), ' ') as name
from callahan_db.raw.affinity_organizations_export
union
select 'FACTORVIEW'
      ,trim(upper(client_name), ' ')
from callahan_db.raw.factorview_facilities_export
)

,keyed as (
select source_system
      ,name
      ,trim(regexp_replace(
            regexp_replace(upper(nvl(name, '~NULL~')), '[^A-Z0-9 ]', ''),
            ' (LLC|INC|CO|LP|LTD|CORP|COMPANY)$', '')) as match_key
from src
)

select match_key
      ,count(distinct name) as distinct_source_names
      ,listagg(distinct source_system || ': ' || name, ' | ')
       within group (order by source_system || ': ' || name) as collapsed_names
from keyed
group by 1
having count(distinct name) > 1
order by 1;
