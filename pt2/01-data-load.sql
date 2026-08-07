use role candidate_callahan;
use schema callahan_db.raw;


create or replace file format filefmt_csv
type = filefmt_csv
field_delimiter = ','
field_optionally_enclosed_by = '"'
skip_header = 1;