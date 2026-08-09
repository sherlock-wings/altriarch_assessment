use role candidate_callahan;
use schema callahan_db.staging;

/*
Sole input to the cleansing views below: the initial load fills it from the whole RAW
table, the Part 3 task fills it from the stream. Scoping everything to a batch is what
keeps the two dedup rules apart -- copies that disagree *within* a batch null the field
they disagree on, while a later batch re-sending an id is a correction that overwrites.
*/
create or replace transient table transaction_batch
like callahan_db.raw.tenor_transactions_export;


-- For transactions, create a "parsing quality" view. it indicates for any given batch 
-- what data quality issues are present post-parse
create or replace view v_transaction_parsed as
with parsed as (
select transaction_id
      ,transaction_date as transaction_date_raw
      ,fund
      ,share_class
      ,investment_ref
      ,transaction_type
      ,amount as amount_raw
      ,file_name
      ,file_row_number
      ,file_last_modified
      ,md5(nvl(transaction_id::varchar, '~NULL~')) as transaction_sk
      ,try_to_date(transaction_date, 'dd-mon-yy') as transaction_date
      ,fund as fund_description
      ,nvl(investment_ref, '~NULL~') as facility_id
      ,case
         when regexp_like(amount, '^\\(.*\\)$')
         then try_to_number(regexp_replace(amount, ',|\\(|\\)', ''), 35, 3) * -1
         else try_to_number(regexp_replace(amount, ',|\\(|\\)', ''), 35, 3)
       end as amount
from transaction_batch
)

-- a flag table is added to flag various quality issues: Duplicates, data conflicts, parse failures
,flagged as (
select p.*
      ,row_number() over (
       partition by p.transaction_id
       order     by p.file_name, p.file_row_number
      ) as record_number
      -- is this record a duplicate? 
      ,count(*) over (partition by p.transaction_id) > 1 as duplicate_ind
      
      -- Does this dupe series (if present) contain conflicting dates?
      ,min(nvl(p.transaction_date::varchar, '~NULL~')) over (partition by p.transaction_id)
    <> max(nvl(p.transaction_date::varchar, '~NULL~')) over (partition by p.transaction_id)
       as transaction_date_conflict_ind
      
      -- Does this dupe series (if present) contain conflicting Fund Descriptions?
      ,min(nvl(p.fund_description, '~NULL~')) over (partition by p.transaction_id)
    <> max(nvl(p.fund_description, '~NULL~')) over (partition by p.transaction_id)
       as fund_description_conflict_ind
      
       -- conflicting share classes? 
      ,min(nvl(p.share_class, '~NULL~')) over (partition by p.transaction_id)
    <> max(nvl(p.share_class, '~NULL~')) over (partition by p.transaction_id)
       as share_class_conflict_ind
      
       -- conflicting facility IDs? 
      ,min(nvl(p.facility_id, '~NULL~')) over (partition by p.transaction_id)
    <> max(nvl(p.facility_id, '~NULL~')) over (partition by p.transaction_id)
       as facility_id_conflict_ind
      
       -- conflicting Transaction Types? 
      ,min(nvl(p.transaction_type, '~NULL~')) over (partition by p.transaction_id)
    <> max(nvl(p.transaction_type, '~NULL~')) over (partition by p.transaction_id)
       as transaction_type_conflict_ind
      
       -- conflicting Transaction Amounts?
      ,min(nvl(p.amount::varchar, '~NULL~')) over (partition by p.transaction_id)
    <> max(nvl(p.amount::varchar, '~NULL~')) over (partition by p.transaction_id)
       as amount_conflict_ind
      
       -- did any vals fail to parse? If so, which ones?
      ,array_to_string(array_construct_compact(
         case when nvl(trim(p.transaction_id), '') = ''
              then 'TRANSACTION_ID' end
        ,case when nvl(trim(p.transaction_date_raw), '') <> '' and p.transaction_date is null
              then 'TRANSACTION_DATE' end
        ,case when nvl(trim(p.amount_raw), '') <> '' and p.amount is null
              then 'AMOUNT' end
       ), ', ') as parse_fail_fields
from parsed p
)

select f.*
      ,f.parse_fail_fields <> '' as parse_fail_ind
      ,f.transaction_date_conflict_ind
    or f.fund_description_conflict_ind
    or f.share_class_conflict_ind
    or f.facility_id_conflict_ind
    or f.transaction_type_conflict_ind
    or f.amount_conflict_ind as conflict_ind
from flagged f;

-- View that resolves the known-good data into the staging layer
create or replace view v_transaction_src as
with collapsed as (
select transaction_sk
      ,transaction_id
      -- When it is known that a value has no conflicts, supply the value
      -- Else, yield a NULL
      ,case when not boolor_agg(transaction_date_conflict_ind)
            then max(transaction_date) end as transaction_date
      ,case when not boolor_agg(fund_description_conflict_ind)
            then max(fund_description) end as fund_description
      ,case when not boolor_agg(share_class_conflict_ind)
            then max(share_class) end as share_class
      ,case when not boolor_agg(facility_id_conflict_ind)
            then max(facility_id) end as facility_id
      ,case when not boolor_agg(transaction_type_conflict_ind)
            then max(transaction_type) end as transaction_type
      ,case when not boolor_agg(amount_conflict_ind)
            then max(amount) end as amount
from v_transaction_parsed
where not parse_fail_ind
group by transaction_sk, transaction_id
)

-- Create a change-tracking key for performant diff-checks when merging to MARTS layer
select c.*
      ,md5(
        nvl(c.TRANSACTION_SK::varchar, '~NULL~')
        || '||' ||
        nvl(c.TRANSACTION_ID::varchar, '~NULL~')
        || '||' ||
        nvl(c.TRANSACTION_DATE::varchar, '~NULL~')
        || '||' ||
        nvl(c.FUND_DESCRIPTION::varchar, '~NULL~')
        || '||' ||
        nvl(c.SHARE_CLASS::varchar, '~NULL~')
        || '||' ||
        nvl(c.FACILITY_ID::varchar, '~NULL~')
        || '||' ||
        nvl(c.TRANSACTION_TYPE::varchar, '~NULL~')
        || '||' ||
        nvl(c.AMOUNT::varchar, '~NULL~')
       ) as change_tracking_key
from collapsed c;


/*
Referential integrity is deliberately not checked here -- DIM_FACILITY is a marts object
and STAGING should not read downward. An unknown facility surfaces instead as
FACT_TRANSACTION.KNOWN_FACILITY_IND = false.
*/
create or replace view v_transaction_audit as
select transaction_id
      ,transaction_date_raw as transaction_date
      ,fund
      ,share_class
      ,investment_ref
      ,transaction_type
      ,amount_raw as amount
      ,file_name
      ,file_row_number
      ,file_last_modified
      ,record_number
      ,md5(
        nvl(file_name::varchar, '~NULL~')
        || '||' ||
        nvl(file_row_number::varchar, '~NULL~')
        || '||' ||
        nvl(transaction_id::varchar, '~NULL~')
       ) as audit_record_sk
      ,duplicate_ind
      ,conflict_ind
      ,parse_fail_ind
      ,parse_fail_fields
      ,current_timestamp()::timestamp_ntz(9) as batch_ts
from v_transaction_parsed
where duplicate_ind
   or conflict_ind
   or parse_fail_ind;


create or replace transient table int_transaction (
transaction_sk varchar,
transaction_id varchar,
transaction_date date,
fund_description varchar,
share_class varchar,
facility_id varchar,
transaction_type varchar,
amount number(35,3),
change_tracking_key varchar
);

create or replace transient table audit_transaction
like callahan_db.raw.tenor_transactions_export;
alter table audit_transaction add column
   record_number number(38,0)
  ,audit_record_sk varchar
  ,duplicate_ind boolean
  ,conflict_ind boolean
  ,parse_fail_ind boolean
  ,parse_fail_fields varchar
  ,batch_ts timestamp_ntz(9);


insert into transaction_batch
select * from callahan_db.raw.tenor_transactions_export;

insert into int_transaction
select * from v_transaction_src;

insert into audit_transaction
select * from v_transaction_audit;


select * from int_transaction;
select * from audit_transaction;
