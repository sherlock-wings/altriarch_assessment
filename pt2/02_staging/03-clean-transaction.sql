use role candidate_callahan;
use schema callahan_db.staging;

create or replace transient table int_transaction (
transaction_sk varchar, 
transaction_id varchar,
transaction_date date,
fund_description varchar,
share_class varchar,
facility_id varchar,
transaction_type varchar,
amount number(35,3)
);


insert into int_transaction
with parsed as (
select md5(nvl(transaction_id::varchar, 'NULL')) as transaction_sk
      ,transaction_id
      ,to_date(transaction_date, 'dd-mon-yy') as transaction_date
      ,fund as fund_description
      ,share_class
      ,nvl(investment_ref, 'NULL') as facility_id
      ,transaction_type
      ,case
         when regexp_like(amount, '^\\(.*\\)$')
         then regexp_replace(amount, ',|\\(|\\)', '')::number(35,3)*-1
         else regexp_replace(amount, ',|\\(|\\)', '')::number(35,3)
       end as amount
from callahan_db.raw.tenor_transactions_export
)

select transaction_sk
      ,transaction_id
      ,case when count(distinct nvl(transaction_date::varchar, '~NULL~')) = 1
            then max(transaction_date) end as transaction_date
      ,case when count(distinct nvl(fund_description, '~NULL~')) = 1
            then max(fund_description) end as fund_description
      ,case when count(distinct nvl(share_class, '~NULL~')) = 1
            then max(share_class) end as share_class
      ,case when count(distinct nvl(facility_id, '~NULL~')) = 1
            then max(facility_id) end as facility_id
      ,case when count(distinct nvl(transaction_type, '~NULL~')) = 1
            then max(transaction_type) end as transaction_type
      ,case when count(distinct nvl(amount::varchar, '~NULL~')) = 1
            then max(amount) end as amount
from parsed
group by transaction_sk, transaction_id
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