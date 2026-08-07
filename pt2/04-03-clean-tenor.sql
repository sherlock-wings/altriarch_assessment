use role candidate_callahan;
use schema callahan_db.staging;

select md5(transaction_id::varchar, 'NULL') as transaction_sk
      ,transaction_id
      ,to_date(transaction_date, 'dd-mon-yy') as transaction_date
      ,fund
      ,share_class
      ,investment_ref
      ,transaction_type
      ,case 
         when regexp_like(amount, '^\\(.*\\)$')
         then regexp_replace(amount, ',|\\(|\\)', '')::number(35,3)*-1
         else regexp_replace(amount, ',|\\(|\\)', '')::number(35,3)
       end as amount
from callahan_db.raw.tenor_transactions_export
;