-- The Part 5 deliverable: SHOW GRANTS for every role created. Captured output is in
-- docs/pt5-show-grants.md.

-- use role securityadmin;  -- Note: Cannot run on Assessment Account
use role candidate_callahan;

show grants to role callahan_analyst_ro;
show grants to role callahan_finance;
show grants to role callahan_lp_readonly;

show grants to role callahan_db_marts_r_ar;
show grants to role callahan_db_staging_r_ar;
show grants to role callahan_db_raw_r_ar;
show grants to role callahan_db_marts_lp_summary_r_ar;
show grants to role wh_callahan_u_ar;

-- No future grants exist to show: they are commented out in pt5/02 because MANAGE GRANTS
-- is not available to the assessment execution user.
-- show future grants in schema callahan_db.raw;
-- show future grants in schema callahan_db.staging;
-- show future grants in schema callahan_db.marts;

show grants of role callahan_analyst_ro;
show grants of role callahan_finance;
show grants of role callahan_lp_readonly;
