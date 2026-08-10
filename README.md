-- TODO: parts 2, 4, 5, 7

## Part 1: Data model

`RAW`, `STAGING` and `MARTS` are created in `pt1/01-schemas.sql`. The deployed MARTS DDL is in
[`docs/marts-ddl.sql`](docs/marts-ddl.sql): two SCD2 dimensions, one fact table, and three views.
[`docs/pipeline-dag.md`](docs/pipeline-dag.md) diagrams the end-to-end flow across all three
schemas, the star schema, and every object the pipeline builds.
The views are part of the design. 
  1. `V_FACT_TRANSACTION_SRC` resolves the facility key and prefers Factorview's fund description over 
      Tenor's where the two disagree
  2. `V_FACT_TRANSACTION` adds a running balance per facility
  3. `V_FACILITY_NFE` turns that balance into the corrected net funds employed.

**Grain.** `DIM_ORGANIZATION` is one row per borrower per version: 34 rows, 33 borrowers plus a
`NULL ORGANIZATION` guard. `DIM_FACILITY` is one row per facility per version, 41 rows, 40 plus a
`NULL FACILITY` guard. `FACT_TRANSACTION` is one row per Tenor transaction, 180 rows, not
versioned. This design treats transactions as events that already happened, allowing subsequent
corrections to supercede the original values. With dimensions, however, we should be able to 
perform point-in-time analysis and keep all history. For that reason, an SCD2 grain was used
for all Dims.

**Keys.** Every table joins on an MD5 surrogate key, with the natural key carried alongside but
never joined on. `FACILITY_SK` is `md5(facility_id)`, `TRANSACTION_SK` is `md5(transaction_id)`,
and `ORGANIZATION_SK` is `md5(match key)` (see below). `SCD_ID`is the unique row identifier and 
the key the merge matches on, and any join to a dimension has to filter `IS_CURRENT_IND` or it 
fans out once per historical version. `FACT_TRANSACTION.FACILITY_SK` → `DIM_FACILITY` and 
`DIM_FACILITY.ORGANIZATION_SK` → `DIM_ORGANIZATION` are both total, zero orphans. Orphans are 
handled with NULL-guard rows rather than null field values. `INV-70005` cites a facility Factorview 
has never heard of, so it points at the `NULL FACILITY` row with `KNOWN_FACILITY_IND = false`, 
countable and excluded from balances rather than dropped.

**Borrower identity.** Factorview and Affinity share no borrower key, only a name, and they use
different spellings/verbiage. 8 of 40 facilities fail an exact-name join, across 6 distinct 
client names. Both systems normalize the name the same way (upper-case, strip punctuation, strip one trailing legal
suffix `LLC|INC|CO|LP|LTD|CORP|COMPANY`), and `ORGANIZATION_SK` is `md5(match_key)` rather than a
hash of the raw name, so `COBALT WORKING CAPITAL LLC` and `COBALT WORKING CAPITAL` resolve to the
same key by construction. This normalization resolves 6 of 8. The other two, `KINGSFORD RECEIVABLES` and `DUNMORE FUNDING LLC`,
are borrowers Affinity has no record of at all, so `DIM_ORGANIZATION` is a conformed dimension fed
by both systems rather than an Affinity mirror: they get their own rows tagged
`SOURCE_SYSTEM = 'FACTORVIEW'` with null CRM attributes and a deterministic id. 

**Extensibility.** A third system's borrowers normalize through the same match key and hash to the
same `ORGANIZATION_SK`, so they either merge into an existing borrower or arrive as a new row
carrying their own `SOURCE_SYSTEM` tag. When a new Source System is added, nothing downstream changes.
This is because downstream joins on the surrogate key and never on a name. The three-layer approach 
helps support this: 
- RAW is per-source and append-only
- STAGING conforms each source to a shared shape
- MARTS is source-agnostic
This way, a new system adds a RAW table and a STAGING script and leaves the marts merge logic untouched. 

## Part 3: Incremental processing

`RAW.STM_TENOR_TRANSACTIONS` (append-only stream) feeds `TSK_LOAD_TRANSACTIONS`, a
triggered task calling `STAGING.SP_LOAD_TRANSACTIONS()`, which drains the stream and runs
the same cleansing views as the initial load, so the parsing, dedup and balance rules have
one definition. All three hops run in a single transaction.

### What the pipeline did with each row of the delta file

`INV-70001`, `INV-70002` and `INV-70003` were ordinary new remittances and were inserted,
lowering net funds employed on FV-1001, FV-1011 and FV-1023. `INV-70004` was also inserted
even though Factorview marks FV-1036 CLOSED, and the pipeline logged that discrepancy as a
soft observation in `CALLAHAN_DB.STAGING.DATA_QUALITY_LOG`. `INV-50100` was an identical
re-send of a row from the initial export, so the MERGE matched it on `TRANSACTION_ID`, found
`CHANGE_TRACKING_KEY` unchanged, and did nothing. `INV-70005` cites FV-9201, which does not
exist in Factorview, so the row was kept, pointed at the `NULL FACILITY` surrogate key, marked
`KNOWN_FACILITY_IND = false`, and excluded from the net-funds-employed refresh so it could not
corrupt a real facility's balance.

### Known limitation

`SP_LOAD_TRANSACTIONS` inserts into `STAGING.AUDIT_TRANSACTION` without the `AUDIT_RECORD_SK`
anti-join the initial-load path uses, so re-sending a file whose rows carry audit-worthy
issues, as `pt3/07-quarantine-demo.sql` does, writes those audit rows a second time. The
facts themselves stay correct because the merge is keyed on `TRANSACTION_ID`.

## Part 6: REST API

A local FastAPI service in `pt6/`, talking to `CALLAHAN_DB` through the Snowflake Python
connector. No BI tool, no wrapper.

### Running it

```bash
cp pt6/.env.example pt6/.env      # then fill it in; pt6/.env is gitignored
uv sync
uv run snow sql -f pt6/00-api-views.sql
uv run uvicorn app.main:app --app-dir pt6 --port 8000
```

Swagger UI at http://127.0.0.1:8000/docs. `--app-dir` keeps the repo from having to be an
installable package. Tests, which never write to Snowflake, are `uv run pytest pt6/test_api.py`.

### How it connects

Everything comes from the environment — there is no account, user or secret anywhere in the
source, and the service never learns which account it is pointed at:

| Variable | Notes |
|---|---|
| `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER` | |
| `SNOWFLAKE_ROLE` | `CANDIDATE_CALLAHAN` |
| `SNOWFLAKE_WAREHOUSE`, `SNOWFLAKE_DATABASE` | `CALLAHAN_WH`, `CALLAHAN_DB` |
| `SNOWFLAKE_AUTHENTICATOR` | `snowflake_jwt` or `username_password_mfa` |
| `SNOWFLAKE_PRIVATE_KEY_FILE`, `SNOWFLAKE_PRIVATE_KEY_FILE_PWD` | key pair only |
| `SNOWFLAKE_PASSWORD` | password + MFA only |

`db.py` requires the five common variables plus whichever pair the chosen authenticator needs,
and fails at startup naming any that are missing rather than erroring on the first request.
`~/.snowflake/connections.toml` is deliberately not used: it is key-pair-only and machine-local,
where env vars work the same way on either account.

### The read surface

`pt6/00-api-views.sql` creates `MARTS.V_API_LOAN` and `MARTS.V_API_BORROWER`, and every handler
reads only those. The views own three things that are easy to get wrong once per endpoint
instead of once per project: the `IS_CURRENT_IND` filter on both SCD2 dimensions, the exclusion
of the `NULL FACILITY` / `NULL ORGANIZATION` guard rows, and nulling the `~NULL~` sentinel so a
client never receives it as a string. `V_API_LOAN` left-joins the borrower rather than
inner-joining, so a facility could never vanish from `GET /loans` by pointing at a guard row.

Because Part 2 resolves borrower identity upstream, `DIM_FACILITY.ORGANIZATION_SK` is a real
foreign key and the join here is plain. All 40 current facilities reach a borrower, including
`KINGSFORD RECEIVABLES` and `DUNMORE FUNDING LLC`, which Affinity has no record of.

### Design decisions

**`POST /remittances` writes to `RAW`, and `201` means "accepted", not "recorded".** Writing
straight to `MARTS.FACT_TRANSACTION` would make the response contract stronger, but it would
bypass every parse, dedup and quarantine rule Parts 2 and 3 exist to enforce and open a second
unvalidated path into the mart. Routing through RAW makes the API an ordinary producer into the
existing stream and inherits that behaviour for free. The cost is an eventually-consistent
response, which the `201` body states outright. Measured end to end, a posted remittance reached
`FACT_TRANSACTION` and moved `DIM_FACILITY.NET_FUNDS_EMPLOYED` within about thirty seconds.

**`{id}` in `/borrowers/{id}/loans` is an `ORGANIZATION_ID`.** Keying on a borrower name would
give consumers no stable identifier and make the 404 case incoherent. A borrower that exists
with no facilities returns `200` with an empty array; only an unknown id is a `404`.

**Money serializes as JSON numbers.** String decimals would be more defensible for a ledger.
This is a read-mostly reporting API and numbers are simpler to consume.

**Schema violations are `422`, business-rule violations are `400`.** `amount` deliberately
carries no Pydantic `gt=0` constraint — that would return `422` where the brief asks for `400`,
so the rule is enforced in the handler. Every failure, including FastAPI's own validation
errors and unmatched routes, comes back in one envelope:

```json
{ "error": { "code": "FACILITY_NOT_FOUND", "message": "No facility with id 'FV-9999'.",
             "detail": null } }
```

**`share_class` is an enum, not free text.** Staging passes the column through unnormalized, so
accepting `A` instead of `Class A` would put a third spelling into `FACT_TRANSACTION` on the
first request.

### Known limitations

**`POST /remittances` must write dates in `DD-MON-YY`.** The endpoint accepts an ISO date and
inserts into `RAW.TENOR_TRANSACTIONS_EXPORT`, which the staging layer parses with
`try_to_date(transaction_date, 'dd-mon-yy')`. An ISO date written there parses to null, trips
`parse_fail_ind` and is quarantined, so the endpoint would return `201` for a remittance that
never arrives. The API formats the date on the way in, which couples it to a CSV export's
conventions in both directions. The durable fix is widening the staging parser to accept ISO
too — a REST producer should not have to imitate a file format.

**One Snowflake connection, opened at startup.** The assessment account permits password plus
Duo MFA only, with no key pair. Connecting per request would fire a Duo push on every HTTP call,
so the API opens a single connection in a FastAPI `lifespan` handler and reuses it, with
`client_session_keep_alive=True`. One push, approved in the terminal running `uvicorn`. Setting
`ALLOW_CLIENT_MFA_CACHING = TRUE` at the account level plus
`authenticator="username_password_mfa"` caches the MFA token so restarts within the caching
window are silent; `--reload` must stay off, since every code change would re-prompt. A single
shared connection also means simultaneous requests queue within one Snowflake session. That is
acceptable for a local single-user service; in production this becomes a connection pool.

**One role for reads and writes.** The service connects as `CANDIDATE_CALLAHAN` because the
Part 5 roles are read-only by design and none of them could serve `POST /remittances`. A
production deployment would split the read endpoints onto a read-only role and leave only the
insert path with write access.
