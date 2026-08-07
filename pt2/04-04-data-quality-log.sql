use role candidate_callahan;
use schema callahan_db.staging;

create or replace transient table data_quality_log (
log_id INT AUTOINCREMENT START 1 INCREMENT 1 PRIMARY KEY,
object_type varchar,
object_schema varchar,
object_name varchar,
field_name varchar,
issue_type varchar,
issue_description varchar,
issue_resolution varchar
);

select 
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_ORGANIZATION' as object_name,
null as field_name,
'DUPLICATES' as issue_type,
$$ The same customer is represented with two different records. In that
record pair, all values are the same except for Affinity_ID and 
Organization_Name. And the Org-name is only different in the letter 
casing.
$$ as issue_description,
$$
This looks like a classic case of the same customer getting added 
to the CRM more than once. So, to avoid duplication, we will 
standardize the names by imposing a uniform casing, and we will
use QUALIFY take only the *first* record in any series of records 
all representing the same customer.
$$ as issue_resolution

union all 

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_ORGANIZATION' as object_name,
'DATE_ADDED' as field_name,
'ENFORCE-TYPE' as issue_type,
$$ Dates are string-formatted like MM/DD/YY; they are not true date type
$$ as issue_description,
$$
Impose proper DATE data type via TO_DATE()
$$ as issue_resolution

union all 

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_ORGANIZATION' as object_name,
null as field_name,
'MISSING-SURROGATE-KEY' as issue_type,
$$ 
This table has no surrogate key. Key formatting becomes non-standard if 
this table holds data from multiple sources in the future.
$$ as issue_description,
$$
Impose key-standardization with MD5 hash on organization_name. Do not use
affinity_org_id because a unique value there does not guarantee a unique
customer.
$$ as issue_resolution

union all 

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
null as field_name,
'MISSING-SURROGATE-KEY' as issue_type,
$$ 
This table has no surrogate key. Key formatting becomes non-standard if 
this table holds data from multiple sources in the future.
$$ as issue_description,
$$
Impose key-standardization with MD5 hash on FACILITY_ID.
$$ as issue_resolution

union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
'STATUS' as field_name,
'INCONSISTENT-FORMATTING' as issue_type,
$$ 
The same status is represented with various casings and spacings-- e.g.
'WATCH LIST', 'Watchlist', 'Watch List', etc
$$ as issue_description,
$$
Use a CASE to catch and resolve all instances of inconsistent formatting
so that a single distinct status has a single, uniform format
$$ as issue_resolution

union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
'DISCOUNT_RATE' as field_name,
'ENFORCE-TYPE' as issue_type,
$$ 
The discount rate (a percentage) is sometimes represented as a decimal between
1 and 100, sometimes as a decimal between 0 and 1. In the former case, percentage
characters are included; in the latter case, they are not. 

This value should be number type, not varchar.
$$ as issue_description,
$$
Use a CASE to parse out the number in its various formats, cast to NUMBER(35,3)
$$ as issue_resolution



