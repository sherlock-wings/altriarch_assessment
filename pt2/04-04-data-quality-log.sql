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

insert into data_quality_log 
(object_type, object_schema, object_name, field_name, issue_type, issue_description, issue_resolution)
select 
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_ORGANIZATION' as object_name,
null as field_name,
'DUPLICATES - SIMPLE' as issue_type,
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

union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
'NET_FUNDS_EMPLOYED' as field_name,
'ENFORCE-TYPE' as issue_type,
$$ 
The value uses Excel-style string formatting to represent currency amounts. 
Should be formatted as number, not varchar. 
$$ as issue_description,
$$
Use regexp to parse out the number in its various formats, cast to NUMBER(35,3)
$$ as issue_resolution


union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
'FACILITY_FUNDING_LIMIT' as field_name,
'ENFORCE-TYPE' as issue_type,
$$ 
The value uses Excel-style string formatting to represent positive and negative
currency amounts. Should be formatted as number, not varchar. 
$$ as issue_description,
$$
Use regexp to parse out the number in its various formats, cast to NUMBER(35,3)
$$ as issue_resolution


union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
'FUNDING_DATE' as field_name,
'ENFORCE-TYPE' as issue_type,
$$ 
The column contains varying string representations of a date. Should be
DATE, Not varchar.
$$ as issue_description,
$$
Use CASE statements to enumerate and parse all the various string formatted
dates into true dates via TO_DATE()
$$ as issue_resolution

union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
'MATURITY_DATE' as field_name,
'ENFORCE-TYPE' as issue_type,
$$ 
The column contains varying string representations of a date. Should be
DATE, Not varchar.
$$ as issue_description,
$$
Use CASE statements to enumerate and parse all the various string formatted
dates into true dates via TO_DATE()
$$ as issue_resolution

select 

union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_TRANSACTIONS' as object_name,
null as field_name,
'MISSING-SURROGATE-KEY' as issue_type,
$$ 
This table has no surrogate key. Key formatting becomes non-standard if 
this table holds data from multiple sources in the future.
$$ as issue_description,
$$
Impose key-standardization with MD5 hash on TRANSACTION_ID.
$$ as issue_resolution

union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_TRANSACTIONS' as object_name,
'TRANSACTION_DATE' as field_name,
'ENFORCE-TYPE' as issue_type,
$$ 
The column contains a dd-mm-yy string-date. Should be true DATE
$$ as issue_description,
$$
Parse into true dates via TO_DATE()
$$ as issue_resolution

union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_TRANSACTIONS' as object_name,
null as field_name,
'MISSING-SURROGATE-FOREIGN-KEY' as issue_type,
$$ 
This table has a join-field that can connect to another 
table, (investment_ref), but that value is not standardized.
Could lead to poor performance if multiple ID formats present
themselves in the future.
$$ as issue_description,
$$
Impose key-standardization with MD5 hash on INVESTMENT_REF.
$$ as issue_resolution

union all

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_TRANSACTIONS' as object_name,
'AMOUNT' as field_name,
'ENFORCE-TYPE' as issue_type,
$$ 
The value uses Excel-style string formatting to represent a 
signed currency amount. Should be a signed number, not a 
varchar.
$$ as issue_description,
$$
Use a CASE + regexp to parse out the number and its sign into 
a consistent NUMBER(35,3) type.
$$ as issue_resolution

union all 

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
null as field_name,
'DUPLICATES - SIMPLE' as issue_type,
$$ 
There are many duplicate facilities where each cell value is identical
across the record. 
$$ as issue_description,
$$
Squish these with DISTINCT
$$ as issue_resolution

union all 

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
'STATUS' as field_name,
'DUPLICATES - COMPOUND' as issue_type,
$$ 
Facility ID 'FV-1004' has a pair of dupes where each has a different
STATUS value. 
$$ as issue_description,
$$
Convert status to a ARRAY column and collapse differing STATUS values 
into a single list. See pt2/04-03-clean-transactions.sql for details on
thought process.
$$ as issue_resolution

union all 

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_FACILITIES' as object_name,
'FACILITY_FUNDING_LIMIT' as field_name,
'DUPLICATES - COMPOUND' as issue_type,
$$ 
Facility ID 'FV-1017' has a pair of dupes where each has a different
FACILITY_FUNDING_LIMIT value. 
$$ as issue_description,
$$
Consider both values for FACILITY_FUNDING_LIMIT as invalid.
Collapse this into a single record where FACILITY_FUNDING_LIMIT
is NULL. Follow-up would be required to diagnose and resolve 
the upstream issue that causes this problem. Likely solution 
would require making records distinct with timing-based 
metadata.
$$ as issue_resolution


union all 

select
'TABLE' as object_type,
'STAGING' as object_schema,
'INT_TRANSACTIONS' as object_name,
'FUND_DESCRIPTION' as field_name,
'DUPLICATES - COMPOUND' as issue_type,
$$ 
Transaction ID 'INV-50041' has a pair of dupes where each has a different
FUND_DESCRIPTION value. 
$$ as issue_description,
$$
Consider both values for FUND_DESCRIPTION as invalid.
Collapse this into a single record where FUND_DESCRIPTION
is NULL. Follow-up would be required to diagnose and resolve 
the upstream issue that causes this problem. Likely solution 
would require making records distinct with timing-based 
metadata.
$$ as issue_resolution;


select * from data_quality_log order by 2,3,4,5,6;