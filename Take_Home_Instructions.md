**Data Engineer Take-Home Assessment**

*Private Credit Data Platform — Snowflake Build Exercise*

# **Scenario**

You have joined a specialty private credit firm as its first data engineer. The firm runs factoring, asset-based lending, and lender finance strategies across two funds. Its core systems operate in silos: Factorview (the loan servicing platform), Affinity (the CRM), and Tenor (the fund/portfolio accounting system). Reporting is manual, reconciliation is painful, and leadership lacks a unified view of portfolio risk.

You will build a small but production-minded analytics platform in Snowflake: load the data the Snowflake-native way, model it in layers, automate incremental processing, secure it with role-based access, answer real portfolio questions in SQL, and expose the result through a REST API you build yourself.

## **Your Environment**

We have provisioned a dedicated Snowflake account workspace for you. You will receive by email: the account URL, your username, and a temporary password (you will be required to change it on first sign-in; you may also be prompted to enroll in MFA — this is normal). Your workspace contains a database that is yours alone and an XSMALL warehouse. Build everything inside this database. All Snowflake work MUST be done in this account — it is how we review your submission, including your query history. Working out your approach elsewhere and pasting in a single finished script will be obvious to us and will count against you; we expect to see normal iteration.

## **Provided Files**

| File | Description |
| :---- | :---- |
| factorview\_facilities\_export.csv | Export from Factorview, our loan servicing platform. One row per facility. Columns: facility\_id, client\_name, fund, product\_type, status, facility\_limit (approved facility size / credit limit), nfe (Net Funds Employed \= current outstanding balance), discount\_rate, funding\_date, maturity\_date. |
| affinity\_organizations\_export.csv | Export from Affinity, our CRM. Company records for borrowers and prospects. Columns: affinity\_org\_id, organization\_name, industry, state, relationship\_owner, date\_added. |
| tenor\_transactions\_export.csv | Export from Tenor, our fund/portfolio accounting system: fundings, remittances, and servicer fees by fund and share class. Columns: transaction\_id, transaction\_date, fund, share\_class, investment\_ref (links to a Factorview facility\_id), transaction\_type, amount (parentheses \= negative). |
| tenor\_transactions\_delta.csv | A SECOND batch of Tenor activity. Do NOT load this during initial build — it is used in Part 3 to prove your automation works. |

**Important:** the files contain deliberate data quality issues: duplicates, inconsistent name spellings, mixed date and currency formats, missing values, records that fail referential integrity across systems, and at least one case where two systems disagree about the same fact. Find them, decide how to handle them, and document your decisions. Do not silently drop data — every exclusion must be logged and explainable.

# **Deliverables**

## **Part 1 — Data Model & Layered Architecture**

1. Create three schemas in your database: RAW (data as landed), STAGING (cleaned and standardized), and MARTS (business-ready dimensional model). You may adjust naming, but the layered pattern is required.

2. Provide your MARTS design as Snowflake DDL plus a half-page rationale: grain of each table, keys, how you unified borrower identity across systems, and how the design extends when new source systems are added.

## **Part 2 — Snowflake-Native Ingestion & Transformation**

1. Load the three initial CSVs into RAW using a named FILE FORMAT, an internal STAGE, and COPY INTO. (Loading files to a stage can be done via Snowsight's UI or SnowSQL — your choice — but the table loads must be SQL COPY INTO statements, not the table-load wizard.)

2. Build your STAGING and MARTS layers entirely in Snowflake SQL (views, CTAS, and/or stored procedures): parse the mixed formats, normalize statuses and fund names, resolve duplicates and cross-system conflicts, and quarantine bad records.

3. Create a DATA\_QUALITY\_LOG table in your database itemizing every issue found and the action taken: duplicate counts, quarantined records with reasons, conflicts and how you resolved them, and unreconcilable records.

**Hint:** when two systems disagree about the same fact, consider which system would be authoritative for that fact in a real firm — and whether other data you hold can break the tie.

## **Part 3 — Automation: Streams & Tasks**

1. Create a STREAM on your raw Tenor transactions table and a TASK (or small task tree) that automatically processes newly landed rows through staging into your marts — including your dedup/quarantine logic, so bad rows in new data are caught too.

2. Prove it works: load tenor\_transactions\_delta.csv into RAW via your stage and COPY INTO, let your task run (you may trigger it manually with EXECUTE TASK), and confirm your marts updated correctly. Leave the stream, task, and task history in place — we will inspect them.

3. In your README, state in one short paragraph what your pipeline did with each row of the delta file and why.

## **Part 4 — SQL Analytics**

Include the SQL and results (run in Snowflake) for:

* Total portfolio outstanding balance, and your treatment of missing/invalid balances.

* Top 5 borrowers by outstanding exposure (open facilities only), each with share of total portfolio exposure.

* Monthly remittance totals for 2025, by fund (after fund-name normalization).

* Outstanding exposure by industry — industry lives in a different system than balances; your join strategy matters, and unmapped borrowers must not silently disappear.

## **Part 5 — Role-Based Access Control**

1. Create three roles. Because roles are account-global in Snowflake, prefix each role name with your database name to avoid collisions (e.g. if your database is NGUYEN\_DB, name them NGUYEN\_ANALYST\_RO, NGUYEN\_FINANCE, NGUYEN\_LP\_READONLY). The three roles are: an ANALYST role (read-only on MARTS only), a FINANCE role (read-only on all three layers), and an LP\_READONLY role (access to exactly one summary view that exposes portfolio-level metrics but NO borrower names or loan-level detail).

2. Grant warehouse usage appropriately, and include the SHOW GRANTS output for each role in your submission. If a specific grant fails due to trial-account permissions, include the SQL you would run and note the error.

## **Part 6 — Build a REST API**

Build a small REST API (FastAPI, Flask, or equivalent) that runs locally on your machine and connects to YOUR Snowflake workspace using the Snowflake Python connector (or Snowpark). This must be your own service, not a BI tool wrapper. Endpoints:

| Method & Path | Purpose | Requirements |
| :---- | :---- | :---- |
| GET /loans | List loans | Filtering by status and fund via query parameters; pagination (limit/offset or page/size); clean typed JSON. |
| GET /borrowers/{id}/loans | All loans for one borrower | 404 with a clear error body if the borrower does not exist. |
| GET /portfolio/summary | Portfolio rollup | Total outstanding, loan counts by status, top 5 borrower exposures — computed live by querying your Snowflake marts. |
| POST /remittances | Record a new remittance | Validate: loan must exist, amount positive, date valid and not in the future. Insert into Snowflake on success (201); 400/404 with informative errors on failure. |

Requirements: input validation, correct HTTP status codes, structured error responses, OpenAPI/Swagger docs, and credentials kept out of source code (environment variables or a config file excluded from the repo). Automated tests are a bonus, not required.

## **Part 7 — README & Design Questions**

README must cover: how to run everything from a fresh clone (including how the API connects to Snowflake), an architecture overview with rationale, your delta-file explanation from Part 3, your AI usage disclosure, and what you would tackle next with one more week.

Also answer these four design questions (a focused paragraph each — no code required):

1. Production ingestion: one of our source systems offers no file exports — only a REST API returning 100 records per page with a 60 requests/minute rate limit. Describe your ingestion design: auth handling, pagination, rate limiting, retries/failure recovery, and how data lands in Snowflake (e.g., the role an external stage on S3 might play).

2. Scheduling: how would you schedule this pipeline to run daily in production using Snowflake-native features, and how would you monitor for failures without a third-party orchestrator?

3. Idempotency: the fund administrator re-sends a file that includes last month's transactions again. What does your current pipeline do, and what guarantees would you add?

4. Serving users: our users range from Excel power-users to SQL analysts, and leadership wants AI-assisted querying eventually. How would you expose the MARTS layer to each audience?

# **AI Policy**

You may use AI tools (Claude, ChatGPT, Copilot, etc.) — we use them here too. Two conditions:

1. Your README must include a disclosure: where you used AI, and at least two places where you rejected, corrected, or materially changed its output, and why.

2. Be prepared to defend every line. After submission there is a 20-minute walkthrough call where you will explain and modify parts of your solution live. We also review your full Snowflake query history. Work you cannot explain is treated as work you did not do.

# **Logistics & Priorities**

* Budget \~6–8 hours. We value sound judgment over polish. If you run short on time, the priority order is: Part 2, Part 3, Part 6, Part 4, Part 5, then the design questions — and write down what you skipped.

* Due within 5 calendar days of receiving your Snowflake credentials.

* Submit a Git repository (link or zip) containing: all SQL scripts in run order, API code, README. Leave all objects in your Snowflake workspace intact — your database, streams, tasks, roles, and query history ARE part of the submission.

* Questions about ambiguous requirements are welcome and viewed positively — email them. Reasonable documented assumptions are also fine.

* Your warehouse auto-suspends when idle and your account has a generous compute cap; normal work will not come close to it.