-- CALLAHAN_DB.MARTS — deployed DDL, pulled with get_ddl() on 2026-08-09

use schema callahan_db.marts;


create or replace table DIM_ORGANIZATION (
   ORGANIZATION_SK        varchar
  ,ORGANIZATION_ID        varchar
  ,ORGANIZATION_NAME      varchar
  ,INDUSTRY               varchar
  ,STATE                  varchar
  ,RELATIONSHIP_OWNER     varchar
  ,DATE_ADDED             date
  ,SOURCE_SYSTEM          varchar
  ,CHANGE_TRACKING_KEY    varchar
  ,RECORD_VERSION_NUMBER  number(38,0)
  ,IS_CURRENT_IND         boolean
  ,RECORD_VALID_FROM_TS   timestamp_ntz(9)
  ,RECORD_VALID_TO_TS     timestamp_ntz(9)
  ,SCD_ID                 varchar
);


-- Facility dimension, SCD2. Replaces CLIENT_NAME with ORGANIZATION_SK, allowing
-- for a many-to-one relationship between this dim and DIM_ORGANIZATION
create or replace table DIM_FACILITY (
   FACILITY_SK            varchar
  ,FACILITY_ID            varchar
  ,ORGANIZATION_SK        varchar
  ,FUND_DESCRIPTION       varchar
  ,PRODUCT_TYPE           varchar
  ,DISCOUNT_RATE          number(5,4)
  ,NET_FUNDS_EMPLOYED     number(35,3)
  ,FACILITY_FUNDING_LIMIT number(35,3)
  ,FUNDING_DATE           date
  ,MATURITY_DATE          date
  ,STATUS                 varchar
  ,CHANGE_TRACKING_KEY    varchar
  ,RECORD_VERSION_NUMBER  number(38,0)
  ,IS_CURRENT_IND         boolean
  ,RECORD_VALID_FROM_TS   timestamp_ntz(9)
  ,RECORD_VALID_TO_TS     timestamp_ntz(9)
  ,SCD_ID                 varchar
);


-- One row per Tenor transaction. Re-sends of existing transactions with new attributes 
-- update in-place 
-- KNOWN_FACILITY_IND is false for transactions citing a facility Factorview has never seen.
create or replace table FACT_TRANSACTION (
   TRANSACTION_SK         varchar
  ,TRANSACTION_ID         varchar
  ,TRANSACTION_DATE       date
  ,FUND_DESCRIPTION       varchar
  ,SHARE_CLASS            varchar
  ,FACILITY_SK            varchar
  ,FACILITY_ID            varchar
  ,TRANSACTION_TYPE       varchar
  ,AMOUNT                 number(35,3)
  ,KNOWN_FACILITY_IND     boolean
  ,ADJUSTMENT_IND         boolean
  ,CHANGE_TRACKING_KEY    varchar
  ,RECORD_INSERTED_TS     timestamp_ntz(9)
  ,RECORD_UPDATED_TS      timestamp_ntz(9)
);


-- Merge source for FACT_TRANSACTION. Resolves the facility SK, prefers Factorview's fund
-- description over Tenor's where the two disagree, and routes unknown facilities to the
-- NULL FACILITY guard row rather than dropping the transaction.
create or replace view V_FACT_TRANSACTION_SRC (
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
) as
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


-- Running balance per facility 
create or replace view V_FACT_TRANSACTION (
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
  ,FACILITY_BALANCE
) as
select f.*
      ,sum(f.amount) over (
       partition by f.facility_id
       order     by f.transaction_date
      ) as facility_balance
from fact_transaction f;


-- Corrected net funds employed: the latest running balance per facility, sign-flipped.
-- Transactions on the NULL FACILITY cannot move a real balance.
create or replace view V_FACILITY_NFE (
   FACILITY_SK
  ,NET_FUNDS_EMPLOYED
) as
select f.facility_sk
      ,f.facility_balance * -1 as net_funds_employed
from v_fact_transaction f
where f.facility_sk <> md5('NULL FACILITY')

qualify row_number() over (
        partition by f.facility_sk
        order     by f.transaction_date desc
      ) = 1;
