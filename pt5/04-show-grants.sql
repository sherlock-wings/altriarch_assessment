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
show grants to role callahan_wh_u_ar;

show future grants in schema callahan_db.raw;
show future grants in schema callahan_db.staging;
show future grants in schema callahan_db.marts;

show grants of role callahan_analyst_ro;
show grants of role callahan_finance;
show grants of role callahan_lp_readonly;
