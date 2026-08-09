-- Drops everything so 00_run_all.sh can rebuild from zero. 

use role candidate_callahan;
use database callahan_db;

drop schema if exists callahan_db.marts cascade;
drop schema if exists callahan_db.staging cascade;
drop schema if exists callahan_db.raw cascade;