use role candidate_callahan;
use schema callahan_db.staging;

create or replace transient table int_transaction (
transaction_sk varchar, 
transaction_id varchar,
transaction_date date,
fund_description varchar,
share_class varchar,
facility_id varchar,
facility_sk varchar,
transaction_type varchar,
amount number(35,3)
);


insert into int_transaction
with dupes as (
select transaction_id
from callahan_db.raw.tenor_transactions_export
group by all having count(*) > 1
)

,normal_records as ( 
select md5(nvl(a.transaction_id::varchar, 'NULL')) as transaction_sk
      ,a.transaction_id
      ,to_date(a.transaction_date, 'dd-mon-yy') as transaction_date
      ,a.fund as fund_description
      ,a.share_class
      ,nvl(a.investment_ref, 'NULL') as facility_id 
      ,md5(nvl(a.investment_ref::varchar, 'NULL')) as facility_sk
      ,a.transaction_type
      ,case 
         when regexp_like(a.amount, '^\\(.*\\)$')
         then regexp_replace(a.amount, ',|\\(|\\)', '')::number(35,3)*-1
         else regexp_replace(a.amount, ',|\\(|\\)', '')::number(35,3)
       end as amount
from callahan_db.raw.tenor_transactions_export a 
left join dupes b
       on a.transaction_id = b.transaction_id
where b.transaction_id is null
)

,weird_records as (
select distinct 
       md5(nvl(a.transaction_id::varchar, 'NULL')) as transaction_sk
      ,a.transaction_id
      ,to_date(a.transaction_date, 'dd-mon-yy') as transaction_date
      ,'NULL' as fund_description
      ,a.share_class
      ,nvl(a.investment_ref, 'NULL') as facility_id 
      ,md5(nvl(a.investment_ref::varchar, 'NULL')) as facility_sk
      ,a.transaction_type
      ,case 
         when regexp_like(a.amount, '^\\(.*\\)$')
         then regexp_replace(a.amount, ',|\\(|\\)', '')::number(35,3)*-1
         else regexp_replace(a.amount, ',|\\(|\\)', '')::number(35,3)
       end as amount
from callahan_db.raw.tenor_transactions_export a 
join dupes b
  on a.transaction_id = b.transaction_id
)

select * from normal_records
union all
select * from weird_records
;

create or replace transient table audit_transaction like callahan_db.raw.tenor_transactions_export;
alter table audit_transaction add column record_number number(38,0), duplicate_id varchar;

insert into audit_transaction
with numbered as (
select *
      ,row_number() over (
       partition by transaction_id
       order     by transaction_date
      ) as record_number
from callahan_db.raw.tenor_transactions_export
)

,dedup as (
select distinct transaction_id from numbered 
where record_number > 1
)

select a.*
      ,md5(nvl(a.transaction_id::varchar, 'NULL') 
           || '||' || 
           nvl(a.record_number::varchar, 'NULL') 
       ) as duplicate_id
from numbered a
join dedup b 
  on a.transaction_id = b.transaction_id
order by all;


select * from int_transaction;
select * from audit_transaction;