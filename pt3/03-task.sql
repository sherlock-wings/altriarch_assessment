use role candidate_callahan;
use schema callahan_db.staging;

create or replace task tsk_load_transactions
warehouse = callahan_wh
when system$stream_has_data('callahan_db.raw.stm_tenor_transactions')
as
call callahan_db.staging.sp_load_transactions();

alter task tsk_load_transactions resume;

show tasks like 'tsk_load_transactions';
