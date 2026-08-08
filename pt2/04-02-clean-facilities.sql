use role candidate_callahan;
use schema callahan_db.staging;

create or replace transient table int_facilities (
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
statuses array
);

insert into int_facilities 
/*
Table presents with many initial (simple) duplicates-- each value in these dupe-pairs
is the same between them.

Squish all at once with DISTINCT 
*/
with simple_dedup as (
select distinct md5(nvl(facility_id::varchar,'NULL')) as facility_sk
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

Here, we have to either collapse compound values into a single value, or we must remove the value
altogether if it can't be reconcilied

Two cells are contributing to the compound duplicates-- STATUS and FACILITY_FUNDING_LIMIT

------------------------------------------------------------------------------------------------
ON STATUS
------------------------------------------------------------------------------------------------
With the STATUS column, this is a category. It is not a true "fact" in that it is not numeric.
For that reason, we can feasibly combine multiple differing statuses into an array object.

This does not give the record a single "authoratative" status, but it does let the viewer know
when multiple statuses are present, which helps give the record context. 

We *could* pick a single STATUS value. I am choosing NOT to do that here because we have no
timing metadata. If I had something like FACTORVIEW_SYNCED_TIMESTAMP, then I would pick
the STATUS that is dated later in time. 
*/
,collapse_statuses as (
select * exclude(status), split(listagg(distinct status, ','), ',') as statuses
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
This field is a true "fact" because it is numeric. As before, we have no metadata timestamp that
tells us which value is later. So each value is equally valid, which is to say that both values
are invalid and cannot be trusted.

Yet we have no reason to be suspicious of the rest of the record's values, based just on the 
information I have. 

So the approach I take here is "If the facility has two distinct FACILITY_FUNDING_LIMIT values,
no it doesn't. Consider this a single facility record where FACILITY_FUNDING_LIMIT IS NULL".

In the real world, this would just be the beginning of the resolution. A realistic follow up
would be to include in the source a "time-of-load" metadata column that would feasibly 
distinguish similar records. Unless FACILITY_FUNDING_LIMIT never changes (unrealistic), that 
kind of metadata is generally required for a good pipeline. 
*/
,normal_records as (
select * from agged where max_rownum = 1
)

,weird_records as (
select * from agged where max_rownum = 2
)


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
from weird_records;