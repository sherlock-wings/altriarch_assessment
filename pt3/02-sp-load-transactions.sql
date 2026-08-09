use role candidate_callahan;
use schema callahan_db.staging;

/*
Propagates a new delta from the Tenor system from RAW -> STAGING -> MARTS

The entire proc's execution is wrapped in a single transaction, allowing easy rollback 
in case of execution failure.
*/
create or replace procedure sp_load_transactions()
returns varchar
language sql
execute as caller
as
$$
declare
    batch_rows  integer default 0;
    audit_rows  integer default 0;
    staged_rows integer default 0;
    fact_rows   integer default 0;
begin
    begin transaction;

    delete from callahan_db.staging.transaction_batch;

    -- capture stream-delta in a truncate-reload table. This way we 
    -- can re-read the delta from the stream as many times as needed
    insert into callahan_db.staging.transaction_batch
    select transaction_id
          ,transaction_date
          ,fund
          ,share_class
          ,investment_ref
          ,transaction_type
          ,amount
          ,file_name
          ,file_row_number
          ,file_last_modified
    from callahan_db.raw.stm_tenor_transactions;

    batch_rows := sqlrowcount;

    if (batch_rows = 0) then
        commit;
        return 'stream empty - nothing to process';
    end if;

    -- Capture auditable data quality issues
    insert into callahan_db.staging.audit_transaction
    select * from callahan_db.staging.v_transaction_audit;

    audit_rows := sqlrowcount;

    -- INT_TRANSACTION is meant to be truncate-reload; clear at the start of 
    -- each run so the end of each run still holds an inspectable artifact of 
    -- what was parsed from tenor from the last batch
    delete from callahan_db.staging.int_transaction;

    insert into callahan_db.staging.int_transaction
    select * from callahan_db.staging.v_transaction_src;

    staged_rows := sqlrowcount;

    merge into callahan_db.marts.fact_transaction tgt
    using callahan_db.marts.v_fact_transaction_src src
       on tgt.transaction_id = src.transaction_id
    when not matched
    then insert (
       TRANSACTION_SK
      ,TRANSACTION_ID
      ,TRANSACTION_DATE
      ,FUND_DESCRIPTION
      ,SHARE_CLASS
      ,FACILITY_SK
      ,FACILITY_ID
      ,TRANSACTION_TYPE
      ,AMOUNT
      ,KNOWN_FACILITY_IND
      ,ADJUSTMENT_IND
      ,CHANGE_TRACKING_KEY
      ,RECORD_INSERTED_TS
      ,RECORD_UPDATED_TS
    ) values (
       src.TRANSACTION_SK
      ,src.TRANSACTION_ID
      ,src.TRANSACTION_DATE
      ,src.FUND_DESCRIPTION
      ,src.SHARE_CLASS
      ,src.FACILITY_SK
      ,src.FACILITY_ID
      ,src.TRANSACTION_TYPE
      ,src.AMOUNT
      ,src.KNOWN_FACILITY_IND
      ,src.ADJUSTMENT_IND
      ,src.CHANGE_TRACKING_KEY
      ,current_timestamp()::timestamp_ntz(9)
      ,null
    )
    when matched 
     and tgt.change_tracking_key <> src.change_tracking_key
     --  ^^^ ensure re-sends of the same data "bounce off" as a no-op
    then update set
       tgt.TRANSACTION_DATE = src.TRANSACTION_DATE
      ,tgt.FUND_DESCRIPTION = src.FUND_DESCRIPTION
      ,tgt.SHARE_CLASS = src.SHARE_CLASS
      ,tgt.FACILITY_SK = src.FACILITY_SK
      ,tgt.FACILITY_ID = src.FACILITY_ID
      ,tgt.TRANSACTION_TYPE = src.TRANSACTION_TYPE
      ,tgt.AMOUNT = src.AMOUNT
      ,tgt.KNOWN_FACILITY_IND = src.KNOWN_FACILITY_IND
      ,tgt.ADJUSTMENT_IND = src.ADJUSTMENT_IND
      ,tgt.CHANGE_TRACKING_KEY = src.CHANGE_TRACKING_KEY
      ,tgt.RECORD_UPDATED_TS = current_timestamp();

    fact_rows := sqlrowcount;

    update callahan_db.marts.dim_facility tgt
    set tgt.net_funds_employed = src.net_funds_employed
    from callahan_db.marts.v_facility_nfe src
    where tgt.facility_sk = src.facility_sk
      and tgt.is_current_ind
      and src.facility_sk in (
          select facility_sk
          from callahan_db.marts.fact_transaction
          where transaction_id in (
                select transaction_id from callahan_db.staging.int_transaction)
      );

    commit;

    return 'batch=' || batch_rows
        || ' audited=' || audit_rows
        || ' staged=' || staged_rows
        || ' fact=' || fact_rows;

exception
    when other then
        rollback;
        raise;
end;
$$;

describe procedure sp_load_transactions();
