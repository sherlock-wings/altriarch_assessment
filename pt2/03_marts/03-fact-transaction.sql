use role candidate_callahan;
use schema callahan_db.marts;

create or replace table fact_transaction (
 TRANSACTION_SK varchar
,TRANSACTION_ID varchar
,TRANSACTION_DATE date
,FUND_DESCRIPTION varchar
,SHARE_CLASS varchar
,FACILITY_SK varchar
,FACILITY_ID varchar
,TRANSACTION_TYPE varchar
,AMOUNT number(35,3)
,FACILITY_BALANCE varchar
,KNOWN_FACILITY_IND boolean
,ADJUSTMENT_IND boolean
,RECORD_INSERTED_TS timestamp_ntz(9)
,RECORD_UPDATED_TS timestamp_ntz(9)
);


/*
DATA CONFLICT

On: FUND_DESCRIPTION

Between: FACTORVIEW system and TENOR system

Resolution: Defer to FACTORVIEW's FUND_DESCRIPTION unless the facility is not found in
            DIM_FACILITY.

Rationale: 
  - The fund descriptions between Tenor and Factorview differ only in a superficial sense,
    (e.g. 'Cardinal ABL & Factoring Fund' from Factorview and 'ABL Fund' from Tenor), so
    it seems likely that these systems are in fact referring to the same fund and just 
    using different verbiage
 
  - Which fund is tied to which facility should be most authoratatively determined by the 
    Loan Servicing platform, since that's where the source-of-truth for all loans (and 
    the funds they are tied to) lives. 

  - The fund descriptions from Factorview are also generally more detailed than the 
    ones from Tenor
*/
merge into fact_transaction fct 
using (
with init_fact as (
select tr.TRANSACTION_SK
      ,tr.TRANSACTION_ID
      ,tr.TRANSACTION_DATE
      ,nvl(fl.fund_description, tr.fund_description) as fund_description
      ,tr.SHARE_CLASS
      ,nvl(fl.FACILITY_SK, md5('NULL FACILITY')) as FACILITY_SK
      ,tr.facility_id
      ,tr.TRANSACTION_TYPE
      ,tr.AMOUNT
      ,case
         when fl.facility_id is not null
         then true
         else false
       end as known_facility_ind
      ,case
         when transaction_type = 'Remittance'
          and amount < 0 
         then true
         else false
       end as adjustment_ind
from callahan_db.staging.int_transaction tr
left join dim_facility fl
       on fl.facility_id = tr.facility_id
)

select * exclude(known_facility_ind, adjustment_ind)
      ,sum(amount) over (
       partition by facility_id 
       order     by transaction_date
      ) as facility_balance
     ,known_facility_ind
     ,adjustment_ind
     ,current_timestamp()::timestamp_ntz(9) as record_inserted_ts
     ,null as record_updated_ts
from init_fact
) intr 
on fct.transaction_id = intr.transaction_id
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
  ,FACILITY_BALANCE
  ,KNOWN_FACILITY_IND
  ,ADJUSTMENT_IND
  ,RECORD_INSERTED_TS
  ,RECORD_UPDATED_TS
) values (
   intr.TRANSACTION_SK
  ,intr.TRANSACTION_ID
  ,intr.TRANSACTION_DATE
  ,intr.FUND_DESCRIPTION
  ,intr.SHARE_CLASS
  ,intr.FACILITY_SK
  ,intr.FACILITY_ID
  ,intr.TRANSACTION_TYPE
  ,intr.AMOUNT
  ,intr.FACILITY_BALANCE
  ,intr.KNOWN_FACILITY_IND
  ,intr.ADJUSTMENT_IND
  ,intr.RECORD_INSERTED_TS
  ,intr.RECORD_UPDATED_TS
)
when matched 
then update set
   fct.TRANSACTION_DATE = intr.TRANSACTION_DATE
  ,fct.FUND_DESCRIPTION = intr.FUND_DESCRIPTION
  ,fct.SHARE_CLASS = intr.SHARE_CLASS
  ,fct.FACILITY_SK = intr.FACILITY_SK
  ,fct.FACILITY_ID = intr.FACILITY_ID
  ,fct.TRANSACTION_TYPE = intr.TRANSACTION_TYPE
  ,fct.AMOUNT = intr.AMOUNT
  ,fct.FACILITY_BALANCE = intr.FACILITY_BALANCE
  ,fct.KNOWN_FACILITY_IND = intr.KNOWN_FACILITY_IND
  ,fct.ADJUSTMENT_IND = intr.ADJUSTMENT_IND
  ,fct.RECORD_UPDATED_TS = current_timestamp();

-- Clear raw table to prepare for next load
truncate table callahan_db.raw.tenor_transactions_export;
select * from fact_transaction order by facility_sk, transaction_date, transaction_id;