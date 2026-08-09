use role candidate_callahan;
use schema callahan_db.raw;

create or replace stream stm_tenor_transactions
on table tenor_transactions_export
append_only = true;

show streams like 'stm_tenor_transactions';
