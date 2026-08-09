use role candidate_callahan;
use schema callahan_db.staging;

create transient table if not exists int_facility (
facility_sk varchar,
facility_id varchar,
client_name varchar,
fund_description varchar,
product_type varchar,
discount_rate number(5,4),
net_funds_employed number(35,3),
FACILITY_FUNDING_LIMIT number(35,3),
funding_date date,
maturity_date date,
statuses array,
change_tracking_key varchar
);


truncate table int_facility;

insert into int_facility
/*
Table presents with many initial simple duplicates-- once varying formats are 
standardized (dclient_name, status, discount_rate, etc) each value in these 
dupe-pairs is the same between them.

Squish all at once with DISTINCT 
*/
with simple_dedup as (
select distinct 
       md5(nvl(facility_id::varchar,'~NULL~')) as facility_sk
      ,facility_id
      ,trim(upper(client_name), ' ') as client_name
      ,fund as fund_description
      ,product_type
      ,case 
         when replace(upper(status), ' ', '-') = 'WATCHLIST' 
         then 'WATCH-LIST'
         else replace(upper(status), ' ', '-')
       end as status
      ,case
         when contains(discount_rate, '%')
         then try_cast(replace(discount_rate, '%', '') as number(35,3))*0.01
         else try_cast(discount_rate as number(35,3))
       end as discount_rate
      ,try_cast(regexp_replace(nfe, '\\$|,', '') as number(35,3)) as net_funds_employed
      ,try_cast(regexp_replace(facility_limit, '\\$|,', '') as number(35,3)) as facility_funding_limit
      ,case
         when funding_date like '%-%'
         then to_date(funding_date, 'YYYY-MM-DD')
         when regexp_like(funding_date, '.*[A-Za-z].*')
         then to_date(funding_date, 'MON DD, YYYY')
         when funding_date like '%/%'
         then to_date(funding_date, 'MM/DD/YYYY')
       end as funding_date
      ,case
         when maturity_date like '%-%'
         then to_date(maturity_date, 'YYYY-MM-DD')
         when regexp_like(maturity_date, '.*[A-Za-z].*')
         then to_date(maturity_date, 'MON DD, YYYY')
         when maturity_date like '%/%'
         then to_date(maturity_date, 'MM/DD/YYYY')
       end as maturity_date
from callahan_db.raw.factorview_facilities_export
)


/*
Two duplicates remain. These are "compound" duplicates-- at least one cell value differs between 
the pairs.

Two fields are contributing to the compound duplicates-- STATUS and FACILITY_FUNDING_LIMIT

To resolve the dupes, our options are:

1) Pick one record over another
2) Collapse both records into one 
3) Keep one record with a NULL for the discrepant field
4) Throw out the record entirely. 


For both duplicate cases, (1) and (4) are not good options. (4) would cause silent data loss,
so that's out of the question.

(1) is normally a good option, but in this case we have no timing metadata. If we did, we could
remove older records and keep current ones only (as in a SCD I dimension), or we could make
the duplicates distinct by establishing "current" and "historical" records (as in a SCD II
dimension).

So for both duplicate cases, we must either do option (2) or option (3)

------------------------------------------------------------------------------------------------
ON STATUS
------------------------------------------------------------------------------------------------
With the STATUS column, this is a category. It is not a true "fact" in that it is not numeric.
For that reason, we can feasibly combine multiple differing statuses into an array object (option
2).

This does not give the record a single "authoratative" status, but it does let the viewer know
when multiple statuses are present, which helps give the record context. 
*/
,collapse_statuses as (
select * exclude(status)
      ,split(listagg(distinct status, ',') within group (order by status), ',') as statuses
from simple_dedup
group by all
)

,numbered as (
select *
      ,row_number() over (
       partition by facility_id
       order     by facility_funding_limit
      ) as rownum
from collapse_statuses
)

,agged as (
select * exclude(rownum, facility_funding_limit), max(rownum) as max_rownum
from numbered
group by all
)

/*
------------------------------------------------------------------------------------------------
ON FACILITY_FUNDING_LIMIT
------------------------------------------------------------------------------------------------
This field is a true "fact" because it is numeric. Because we have no timing metadata, each 
value is equally valid, which is to say that both values are invalid and cannot be trusted.

Yet we have no reason to be suspicious of the rest of the record's values, based just on the 
information I have. 

So the approach I take here is option (3): "If the facility has two distinct 
FACILITY_FUNDING_LIMIT values, no it doesn't. Consider this a single facility record where 
FACILITY_FUNDING_LIMIT is NULL".
*/

,normal_records as (
select * from agged where max_rownum = 1
)

,weird_records as (
select * from agged where max_rownum = 2
)

,stack as (
select a.FACILITY_SK
      ,a.FACILITY_ID
      ,a.CLIENT_NAME
      ,a.FUND_DESCRIPTION
      ,a.PRODUCT_TYPE
      ,a.DISCOUNT_RATE
      ,a.NET_FUNDS_EMPLOYED
      ,b.FACILITY_FUNDING_LIMIT
      ,a.FUNDING_DATE
      ,a.MATURITY_DATE
      ,a.STATUSES
from normal_records a 
left join collapse_statuses b 
       on a.facility_id = b.facility_id

union all 

select FACILITY_SK
      ,FACILITY_ID
      ,CLIENT_NAME
      ,FUND_DESCRIPTION
      ,PRODUCT_TYPE
      ,DISCOUNT_RATE
      ,NET_FUNDS_EMPLOYED
      ,try_cast(null as number(35,3)) as FACILITY_FUNDING_LIMIT
      ,FUNDING_DATE
      ,MATURITY_DATE
      ,STATUSES
from weird_records
)

select *
      ,md5(
       nvl(FACILITY_SK::varchar, '~NULL~')
       || '||' ||
       nvl(FACILITY_ID::varchar, '~NULL~')
       || '||' ||
       nvl(CLIENT_NAME::varchar, '~NULL~')
       || '||' ||
       nvl(FUND_DESCRIPTION::varchar, '~NULL~')
       || '||' ||
       nvl(PRODUCT_TYPE::varchar, '~NULL~')
       || '||' ||
       nvl(DISCOUNT_RATE::varchar, '~NULL~')
       || '||' ||
       nvl(NET_FUNDS_EMPLOYED::varchar, '~NULL~')
       || '||' ||
       nvl(try_cast(null as number(35,3))::varchar, '~NULL~') 
       || '||' ||
       nvl(FUNDING_DATE::varchar, '~NULL~')
       || '||' ||
       nvl(MATURITY_DATE::varchar, '~NULL~')
       || '||' ||
       nvl(STATUSES::varchar, '~NULL~')
       ) as change_tracking_key
from stack
;

create transient table if not exists audit_facility as
select r.*
      ,null::number(38,0) as record_number
      ,null::varchar as duplicate_id
from callahan_db.raw.factorview_facilities_export r
where false;

truncate table audit_facility;

insert into audit_facility
with numbered as (
select *
      ,row_number() over (
       partition by facility_id
       order     by status, nfe
      ) as record_number
from callahan_db.raw.factorview_facilities_export
)

,dedup as (
select distinct facility_id from numbered
where record_number > 1
)

select a.*
      ,md5(nvl(a.facility_id::varchar, '~NULL~') 
           || '||' || 
           nvl(a.record_number::varchar, '~NULL~') 
       ) as duplicate_id
from numbered a 
join dedup b 
  on a.facility_id = b.facility_id
order by all;

select * from int_facility;
select * from audit_facility;