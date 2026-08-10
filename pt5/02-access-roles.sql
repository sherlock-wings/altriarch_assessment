-- =============================================================================
-- ACCESS ROLES
-- =============================================================================
-- Access roles (_AR) hold privileges. Functional roles (_FR, pt5/03) hold access
-- roles and are what a person or service logs in as. Nothing is ever granted
-- directly to a functional role.
--
-- Each access role covers exactly one schema at one access level, or one warehouse.
--
-- =============================================================================

-- use role securityadmin;  -- Note: Cannot run on Assessment Account
use role candidate_callahan;

-- -----------------------------------------------------------------------------
-- CALLAHAN_DB_RAW_R_AR: Read-Only on CALLAHAN_DB.RAW
-- -----------------------------------------------------------------------------
create role if not exists callahan_db_raw_r_ar;
grant usage on database callahan_db to role callahan_db_raw_r_ar;
grant usage on schema callahan_db.raw to role callahan_db_raw_r_ar;

grant select on all tables in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant select on future tables in schema callahan_db.raw to role callahan_db_raw_r_ar;

grant select on all views in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant select on future views in schema callahan_db.raw to role callahan_db_raw_r_ar;

grant usage on all sequences in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant usage on future sequences in schema callahan_db.raw to role callahan_db_raw_r_ar;

grant usage on all stages in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant read on all stages in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant usage on future stages in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant read on future stages in schema callahan_db.raw to role callahan_db_raw_r_ar;

grant usage on all file formats in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant usage on future file formats in schema callahan_db.raw to role callahan_db_raw_r_ar;

grant select on all streams in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant select on future streams in schema callahan_db.raw to role callahan_db_raw_r_ar;

grant usage on all functions in schema callahan_db.raw to role callahan_db_raw_r_ar;
grant usage on future functions in schema callahan_db.raw to role callahan_db_raw_r_ar;


-- -----------------------------------------------------------------------------
-- CALLAHAN_DB_STAGING_R_AR: Read-Only on CALLAHAN_DB.STAGING
-- -----------------------------------------------------------------------------
create role if not exists callahan_db_staging_r_ar;
grant usage on database callahan_db to role callahan_db_staging_r_ar;
grant usage on schema callahan_db.staging to role callahan_db_staging_r_ar;

grant select on all tables in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant select on future tables in schema callahan_db.staging to role callahan_db_staging_r_ar;

grant select on all views in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant select on future views in schema callahan_db.staging to role callahan_db_staging_r_ar;

grant usage on all sequences in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant usage on future sequences in schema callahan_db.staging to role callahan_db_staging_r_ar;

grant usage on all stages in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant read on all stages in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant usage on future stages in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant read on future stages in schema callahan_db.staging to role callahan_db_staging_r_ar;

grant usage on all file formats in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant usage on future file formats in schema callahan_db.staging to role callahan_db_staging_r_ar;

grant select on all streams in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant select on future streams in schema callahan_db.staging to role callahan_db_staging_r_ar;

grant usage on all functions in schema callahan_db.staging to role callahan_db_staging_r_ar;
grant usage on future functions in schema callahan_db.staging to role callahan_db_staging_r_ar;


-- -----------------------------------------------------------------------------
-- CALLAHAN_DB_MARTS_R_AR: Read-Only on CALLAHAN_DB.MARTS
-- -----------------------------------------------------------------------------
create role if not exists callahan_db_marts_r_ar;
grant usage on database callahan_db to role callahan_db_marts_r_ar;
grant usage on schema callahan_db.marts to role callahan_db_marts_r_ar;

grant select on all tables in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant select on future tables in schema callahan_db.marts to role callahan_db_marts_r_ar;

grant select on all views in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant select on future views in schema callahan_db.marts to role callahan_db_marts_r_ar;

grant usage on all sequences in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant usage on future sequences in schema callahan_db.marts to role callahan_db_marts_r_ar;

grant usage on all stages in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant read on all stages in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant usage on future stages in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant read on future stages in schema callahan_db.marts to role callahan_db_marts_r_ar;

grant usage on all file formats in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant usage on future file formats in schema callahan_db.marts to role callahan_db_marts_r_ar;

grant select on all streams in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant select on future streams in schema callahan_db.marts to role callahan_db_marts_r_ar;

grant usage on all functions in schema callahan_db.marts to role callahan_db_marts_r_ar;
grant usage on future functions in schema callahan_db.marts to role callahan_db_marts_r_ar;


-- -----------------------------------------------------------------------------
-- CALLAHAN_DB_MARTS_LP_SUMMARY_R_AR: Read-Only on one named view in MARTS
-- -----------------------------------------------------------------------------
-- Object-level, not schema-level, and no FUTURE grants: a view added to MARTS
-- tomorrow must not become LP-visible by default.
create role if not exists callahan_db_marts_lp_summary_r_ar;
grant usage on database callahan_db to role callahan_db_marts_lp_summary_r_ar;
grant usage on schema callahan_db.marts to role callahan_db_marts_lp_summary_r_ar;
grant select on view callahan_db.marts.v_lp_portfolio_summary
   to role callahan_db_marts_lp_summary_r_ar;


-- -----------------------------------------------------------------------------
-- CALLAHAN_WH_U_AR: Usage on CALLAHAN_WH
-- -----------------------------------------------------------------------------
-- Usage without operate. The warehouse auto-resumes, so a reader never needs to
-- start or resize it.
create role if not exists callahan_wh_u_ar;
grant usage on warehouse callahan_wh to role callahan_wh_u_ar;
