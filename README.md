-- TODO: parts 1, 2, 4-7

## Part 3: Incremental processing

`RAW.STM_TENOR_TRANSACTIONS` (append-only stream) feeds `TSK_LOAD_TRANSACTIONS`, a
triggered task calling `STAGING.SP_LOAD_TRANSACTIONS()`, which drains the stream and runs
the same cleansing views as the initial load — one definition of the parsing, dedup and
balance rules — with all three hops in a single transaction.

### What the pipeline did with each row of the delta file

`INV-70001`, `INV-70002` and `INV-70003` were ordinary new remittances and were inserted,
lowering net funds employed on FV-1001, FV-1011 and FV-1023. `INV-70004` was also inserted
even though Factorview marks FV-1036 CLOSED. This discrepancy was logged as a soft-observation
in `CALLAHAN_DB.STAGING.DATA_QUALITY_LOG`. `INV-50100` was an identical re-send of a 
row from the initial export, so the MERGE matched it on `TRANSACTION_ID`, found `CHANGE_TRACKING_KEY`
unchanged, and did nothing. `INV-70005`cites FV-9201, which does not exist in Factorview. So, 
the row was kept, pointed at the `NULL FACILITY` surrogate key, marked `KNOWN_FACILITY_IND = false`,
and excluded from the net-funds-employed refresh so it could not corrupt a real facility's balance.
