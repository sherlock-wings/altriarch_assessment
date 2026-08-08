use role candidate_callahan;
use schema callahan_db.marts;

update dim_facility tgt 
set tgt.net_funds_employed = src.facility_balance
from (
    select facility_sk
          ,facility_balance
    from fact_transaction
    qualify row_number() over (
           partition by facility_sk
           order by transaction_date desc
          ) = 1;
) src
where tgt.facility_sk = src.facility_sk
;

select * from dim_facility
order by facility_id;