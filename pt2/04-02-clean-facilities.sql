use role candidate_callahan;
use schema callahan_db.staging;

create or replace table int_facilities (
facility_id varchar,
client_name varchar,
fund varchar,
product_type varchar,
status varchar,
discount_rate number(5,4),
facility_fund_limit number(35,3),
net_funds_employed number(35,3),
funding_date date,
maturity_date date
);


insert into int_facilities 
select facility_id
      ,client_name
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
from callahan_db.raw.factorview_facilities_export;