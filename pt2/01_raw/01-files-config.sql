use role candidate_callahan;
use schema callahan_db.raw;

/*
The convention followed from here on: anything holding state is created IF NOT EXISTS so
re-running a script cannot destroy it, while anything that is purely a definition keeps
OR REPLACE so an edit actually deploys. A stage holds the staged files, so it is the
former; a file format is the latter. 00_teardown.sql is the way back to a clean build.
*/
create or replace file format filefmt_csv
type = CSV
field_delimiter = ','
field_optionally_enclosed_by = '"'
skip_header = 1;

create stage if not exists internal_stage_csv
file_format = filefmt_csv
directory = (enable = true);