use role candidate_callahan;
use schema callahan_db.raw;

create or replace file format filefmt_csv
type = CSV
field_delimiter = ','
field_optionally_enclosed_by = '"'
skip_header = 1;

create stage if not exists internal_stage_csv
file_format = filefmt_csv
directory = (enable = true);