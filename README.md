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

### Known limitation

`SP_LOAD_TRANSACTIONS` inserts into `STAGING.AUDIT_TRANSACTION` without the `AUDIT_RECORD_SK`
anti-join the initial-load path uses, so re-sending a file whose rows carry audit-worthy
issues — as `pt3/07-quarantine-demo.sql` does — writes those audit rows a second time; the
facts themselves stay correct because the merge is keyed on `TRANSACTION_ID`.

## Part 6: REST API

### Known limitations

**`POST /remittances` must write dates in `DD-MON-YY`.** The endpoint accepts an ISO date and
inserts into `RAW.TENOR_TRANSACTIONS_EXPORT`, which the staging layer parses with
`try_to_date(transaction_date, 'dd-mon-yy')`. That parser recognizes one format, so the API
reformats the date on the way in. Writing the ISO string straight through would parse to NULL,
trip `PARSE_FAIL_IND`, and quarantine the row into `AUDIT_TRANSACTION` instead of loading it —
the endpoint would return 201 and the remittance would never reach the marts. The coupling is
real: the API has to know the staging date format, and a change to either side breaks the
other silently. The durable fix is to widen the staging parser to accept ISO alongside
`DD-MON-YY`, since a REST producer is a legitimate second source into that table and should
not have to imitate a CSV export's formatting.

**One Snowflake connection, opened at startup.** The assessment account permits password plus
Duo MFA only — no key pair. Connecting per request would fire a Duo push on every HTTP call,
so the API opens a single connection in a FastAPI `lifespan` handler and reuses it, with
`client_session_keep_alive=True`. One push, approved in the terminal running `uvicorn`.
Consequences: do not run with `--reload`, because every code change restarts the process and
re-prompts; and if the connection drops mid-session, the next query reconnects and prompts
again. Setting `ALLOW_CLIENT_MFA_CACHING = TRUE` at the account level plus
`authenticator="username_password_mfa"` caches the MFA token so restarts within the caching
window are silent. A single shared connection also means requests serialize on one Snowflake
session; that is fine for a local single-user service and would become a connection pool in
production.
