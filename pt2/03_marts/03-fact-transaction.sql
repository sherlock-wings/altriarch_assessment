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
,KNOWN_FACILITY_IND boolean
,ADJUSTMENT_IND boolean
,CHANGE_TRACKING_KEY varchar
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

/*
CHANGE_TRACKING_KEY is hashed after the DIM_FACILITY join, not carried down from
INT_TRANSACTION: FUND_DESCRIPTION, FACILITY_SK and KNOWN_FACILITY_IND are resolved against
the dimension, so a facility first appearing in Factorview changes the fact row without
changing anything in staging.
*/
create or replace view v_fact_transaction_src as
with resolved as (
select tr.TRANSACTION_SK
      ,tr.TRANSACTION_ID
      ,tr.TRANSACTION_DATE
      ,nvl(fl.fund_description, tr.fund_description) as FUND_DESCRIPTION
      ,tr.SHARE_CLASS
      ,nvl(fl.FACILITY_SK, md5('NULL FACILITY')) as FACILITY_SK
      ,tr.FACILITY_ID
      ,tr.TRANSACTION_TYPE
      ,tr.AMOUNT
      ,case
         when fl.facility_id is not null
         then true
         else false
       end as KNOWN_FACILITY_IND
      ,case
         when tr.transaction_type = 'Remittance'
          and tr.amount < 0
         then true
         else false
       end as ADJUSTMENT_IND
from callahan_db.staging.int_transaction tr
left join dim_facility fl
       on fl.facility_id = tr.facility_id
      and fl.is_current_ind
)

select r.*
      ,md5(
        nvl(r.TRANSACTION_SK::varchar, 'NULL')
        || '||' ||
        nvl(r.TRANSACTION_ID::varchar, 'NULL')
        || '||' ||
        nvl(r.TRANSACTION_DATE::varchar, 'NULL')
        || '||' ||
        nvl(r.FUND_DESCRIPTION::varchar, 'NULL')
        || '||' ||
        nvl(r.SHARE_CLASS::varchar, 'NULL')
        || '||' ||
        nvl(r.FACILITY_SK::varchar, 'NULL')
        || '||' ||
        nvl(r.FACILITY_ID::varchar, 'NULL')
        || '||' ||
        nvl(r.TRANSACTION_TYPE::varchar, 'NULL')
        || '||' ||
        nvl(r.AMOUNT::varchar, 'NULL')
        || '||' ||
        nvl(r.KNOWN_FACILITY_IND::varchar, 'NULL')
        || '||' ||
        nvl(r.ADJUSTMENT_IND::varchar, 'NULL')
       ) as CHANGE_TRACKING_KEY
from resolved r;


merge into fact_transaction fct
using v_fact_transaction_src intr
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
  ,KNOWN_FACILITY_IND
  ,ADJUSTMENT_IND
  ,CHANGE_TRACKING_KEY
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
  ,intr.KNOWN_FACILITY_IND
  ,intr.ADJUSTMENT_IND
  ,intr.CHANGE_TRACKING_KEY
  ,current_timestamp()::timestamp_ntz(9)
  ,null
)
when matched
 and fct.change_tracking_key <> intr.change_tracking_key
then update set
   fct.TRANSACTION_DATE = intr.TRANSACTION_DATE
  ,fct.FUND_DESCRIPTION = intr.FUND_DESCRIPTION
  ,fct.SHARE_CLASS = intr.SHARE_CLASS
  ,fct.FACILITY_SK = intr.FACILITY_SK
  ,fct.FACILITY_ID = intr.FACILITY_ID
  ,fct.TRANSACTION_TYPE = intr.TRANSACTION_TYPE
  ,fct.AMOUNT = intr.AMOUNT
  ,fct.KNOWN_FACILITY_IND = intr.KNOWN_FACILITY_IND
  ,fct.ADJUSTMENT_IND = intr.ADJUSTMENT_IND
  ,fct.CHANGE_TRACKING_KEY = intr.CHANGE_TRACKING_KEY
  ,fct.RECORD_UPDATED_TS = current_timestamp();


create or replace view v_fact_transaction as
select f.*
      ,sum(f.amount) over (
       partition by f.facility_id
       order     by f.transaction_date
      ) as facility_balance
from fact_transaction f;

select * from v_fact_transaction order by facility_sk, transaction_date, transaction_id;
