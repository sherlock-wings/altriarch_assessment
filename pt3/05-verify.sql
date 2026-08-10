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
