use role candidate_callahan;
use schema callahan_db.staging;

create or replace transient table int_transactions (
transaction_sk varchar, 
transaction_id varchar,
transaction_date date,
fund_description varchar,
share_class varchar,
facility_sk varchar,
transaction_type varchar,
amount number(35,3)
);

insert into int_transactions
select md5(nvl(transaction_id::varchar, 'NULL')) as transaction_sk
      ,transaction_id
      ,to_date(transaction_date, 'dd-mon-yy') as transaction_date
      ,fund as fund_description
      ,share_class
      ,md5(nvl(investment_ref::varchar, 'NULL')) as facility_sk
      ,transaction_type
      ,case 
         when regexp_like(amount, '^\\(.*\\)$')
         then regexp_replace(amount, ',|\\(|\\)', '')::number(35,3)*-1
         else regexp_replace(amount, ',|\\(|\\)', '')::number(35,3)
       end as amount
from callahan_db.raw.tenor_transactions_export
;
