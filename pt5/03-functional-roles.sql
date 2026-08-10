-- =============================================================================
-- FUNCTIONAL ROLES
-- =============================================================================
-- The three roles Part 5 asks for, composed from the access roles defined in 
-- the previous script
--
--   CALLAHAN_ANALYST_RO  -> read-only, MARTS only
--   CALLAHAN_FINANCE     -> read-only, RAW + STAGING + MARTS
--   CALLAHAN_LP_READONLY -> MARTS.V_LP_PORTFOLIO_SUMMARY and nothing else
--
-- Every one of them gets WH_CALLAHAN_U_AR
-- =============================================================================

-- use role securityadmin;  -- Note: Cannot run on Assessment Account
use role candidate_callahan;

create role if not exists callahan_analyst_ro;
create role if not exists callahan_finance;
create role if not exists callahan_lp_readonly;

-- Analyst — business-ready layer only
grant role callahan_db_marts_r_ar to role callahan_analyst_ro;
grant role wh_callahan_u_ar to role callahan_analyst_ro;

-- Finance — all three layers
grant role callahan_db_raw_r_ar to role callahan_finance;
grant role callahan_db_staging_r_ar to role callahan_finance;
grant role callahan_db_marts_r_ar to role callahan_finance;
grant role wh_callahan_u_ar to role callahan_finance;

-- LP — one view
grant role callahan_db_marts_lp_summary_r_ar to role callahan_lp_readonly;
grant role wh_callahan_u_ar to role callahan_lp_readonly;

-- User provisioning. In the reference project this lives in a separate script; here
-- the assessment account has one human, and the roles have to be assumable to be
-- demonstrated in pt5/05. callahan_user is the account username; swap it if the login differs.
grant role callahan_analyst_ro to user callahan_user;
grant role callahan_finance to user callahan_user;
grant role callahan_lp_readonly to user callahan_user;
