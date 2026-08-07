use role candidate_callahan;
use schema callahan_db.raw;


create or replace file format filefmt_csv
type = csv
field_delimiter = ','
field_optionally_enclosed_by = '"'
skip_header = 1;

create or replace stage internal_stage_csv
file_format = filefmt_csv
directory = (enable = true);

create or replace table raw.affinity_organizations_export (
affinity_org_id varchar,
organization_name varchar,
industry varchar,
state varchar,
relationship_owner varchar,
date_added varchar,
file_name varchar,
file_row_number varchar,
file_last_modified varchar
);

copy into raw.affinity_organizations_export 
from (
select $1, $2, $3, $4, $5, $6, 
       metadata$filename as file_name, metadata$file_row_number as file_row_number,
       metadata$file_last_modified as file_last_modified
from @internal_stage_csv
(file_format => filefmt_csv, pattern => '.*affinity.*')
);

create or replace table raw.factorview_facilities_export (
facility_id varchar,
client_name varchar,
fund varchar,
product_type varchar,
status varchar,
facility_limit varchar,
nfe varchar,
discount_rate varchar,
funding_date varchar,
maturity_date varchar,
file_name varchar,
file_row_number varchar,
file_last_modified varchar
);


copy into raw.factorview_facilities_export 
from (
select $1, $2, $3, $4, $5, $6,
       $7, $8, $9, $10,
       metadata$filename as file_name, metadata$file_row_number as file_row_number,
       metadata$file_last_modified as file_last_modified
from @internal_stage_csv
(file_format => filefmt_csv, pattern => '.*factorview_facilities.*')
);


create or replace table raw.tenor_transactions_export (
transaction_id varchar,
transaction_date varchar,
fund varchar,
share_class varchar,
investment_ref varchar,
transaction_type varchar,
amount varchar,
file_name varchar,
file_row_number varchar,
file_last_modified varchar
);

copy into raw.factorview_facilities_export 
from (
select $1, $2, $3, $4, $5, $6,
       $7, $8, $9, $10,
       metadata$filename as file_name, metadata$file_row_number as file_row_number,
       metadata$file_last_modified as file_last_modified
from @internal_stage_csv
(file_format => filefmt_csv, pattern => '.*tenor_transactions_export.*')
);