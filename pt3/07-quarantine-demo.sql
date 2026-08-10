use role candidate_callahan;
use schema callahan_db.raw;


-- Get initial count of auditable (i.e. somehow erroneous) transaction records
-- This number should increase by the end of the script's execution
select count(*) from callahan_db.staging.audit_transaction;

-- This script is meant to demonstrate how the pipeline quarantines unparseable records.
-- We insert a known-bad record into our raw tenor export table, and then show where it 
-- ends up.
insert into tenor_transactions_export
(transaction_id, transaction_date, fund, share_class, investment_ref,
 transaction_type, amount, file_name, file_row_number, file_last_modified)
select 'INV-70006', '32-Foo-99', 'Fund I', 'Class A', 'FV-1001',
       'Remittance', 'not-a-number', 'quarantine_demo', '1', current_timestamp()::varchar
union all
select null, '21-Feb-26', 'Fund I', 'Class A', 'FV-1001',
       'Remittance', '1,000.00', 'quarantine_demo', '2', current_timestamp()::varchar;

select system$stream_has_data('callahan_db.raw.stm_tenor_transactions') as stream_has_data;

select $$ ** Allow about 60 seconds to pass for these records to be routed to the audit layer** .
Once ready, run `uv run snow sql -q "select count(*) from callahan_db.staging.audit_transaction;"`
in your terminal
$$ as message

-- Confirm that this number is larger than the one initiall y shown from the query on line 7.
