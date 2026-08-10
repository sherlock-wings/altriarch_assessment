-- Proves each role reaches what it should. Requires USE SECONDARY ROLES NONE.

use secondary roles none;
use warehouse wh_callahan;

-- Analyst: MARTS reachable.
use role callahan_analyst_ro;
select 'CALLAHAN_ANALYST_RO'                            as role_tested
      ,(select count(*) from callahan_db.marts.dim_facility)     as marts_facilities
      ,(select count(*) from callahan_db.marts.fact_transaction) as marts_transactions;

-- Finance: all three layers reachable.
use role callahan_finance;
select 'CALLAHAN_FINANCE'                                                as role_tested
      ,(select count(*) from callahan_db.raw.tenor_transactions_export)  as raw_rows
      ,(select count(*) from callahan_db.staging.int_facility)           as staging_rows
      ,(select count(*) from callahan_db.marts.dim_facility)             as marts_rows;

-- LP: the summary view only
use role callahan_lp_readonly;
select *
from callahan_db.marts.v_lp_portfolio_summary
order by display_order, metric_label;



-- Negative checks, run one at a time because each aborts the script. Errors below are the
-- actual responses, captured 2026-08-10.
/*
use role callahan_lp_readonly;
select count(*) from callahan_db.marts.dim_facility;
  -- 002003 (42S02): SQL compilation error:
  -- Object 'CALLAHAN_DB.MARTS.DIM_FACILITY' does not exist or not authorized.

use role callahan_lp_readonly;
select count(*) from callahan_db.marts.v_api_loan;
  -- 002003 (42S02): SQL compilation error:
  -- Object 'CALLAHAN_DB.MARTS.V_API_LOAN' does not exist or not authorized.

use role callahan_analyst_ro;
select count(*) from callahan_db.staging.int_facility;
  -- 002003 (02000): SQL compilation error:
  -- Schema 'CALLAHAN_DB.STAGING' does not exist or not authorized.

use role callahan_analyst_ro;
select count(*) from callahan_db.raw.tenor_transactions_export;
  -- 002003 (02000): SQL compilation error:
  -- Schema 'CALLAHAN_DB.RAW' does not exist or not authorized.

use role callahan_analyst_ro;
delete from callahan_db.marts.fact_transaction where 1 = 0;
  -- 003001 (42501): SQL access control error: Insufficient privileges to operate on table
  -- 'FACT_TRANSACTION' -- role CALLAHAN_ANALYST_RO must have DELETE granted on TABLE
  -- CALLAHAN_DB.MARTS.FACT_TRANSACTION.

use role callahan_finance;
call callahan_db.staging.sp_load_transactions();
  -- 002141 (42601): SQL compilation error:
  -- Unknown user-defined function CALLAHAN_DB.STAGING.SP_LOAD_TRANSACTIONS.
  -- read-only access roles are granted no USAGE on procedures, so a role that can read
  -- every row in STAGING still cannot run the loader that writes MARTS.
*/
