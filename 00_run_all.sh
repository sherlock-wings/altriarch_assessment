#!/usr/bin/env bash
set -euo pipefail

# Full rebuild from zero: teardown, then pt1/ and pt2/ in filename order, then pt3/
# in an explicit sequence. Ends with the pipeline live and the delta loaded.
#
# Every `snow sql` call opens its own session, and the assessment account is password
# + Duo, so each call costs an MFA push. Files are streamed into two batches on stdin
# instead. Concatenation relies on each file's own terminator -- a bare ';' separator
# is rejected as an empty statement.

CONN="${SNOWFLAKE_CONNECTION:-assessment}"
STREAM='callahan_db.raw.stm_tenor_transactions'
TASK_SETTLE=45
DRAIN_TIMEOUT=300
POLL_INTERVAL=30

if [[ "${1:-}" != "-y" ]]; then
    echo "Target connection: ${CONN}"
    echo "This drops schemas RAW, STAGING and MARTS in CALLAHAN_DB, then rebuilds them"
    echo "including the Part 3 stream and task. Accumulated AUDIT_TRANSACTION rows and"
    echo "any manually loaded data are lost."
    read -rp "Rebuild from scratch? [y/N] " reply
    [[ "$reply" == [yY] ]] || { echo "Aborted."; exit 1; }
fi

# One session for the whole list. The marker before each file makes a mid-batch
# failure easy to place, and costs no warehouse.
run_batch() {
    local f
    for f in "$@"; do
        echo "==> ${f}" >&2
        printf "\nselect '==> %s' as step;\n" "$f"
        cat "$f"
        printf "\n"
    done | uv run snow sql -c "$CONN" -i
}

# TSK_LOAD_TRANSACTIONS is triggered rather than scheduled: it fires within ~30s of
# rows landing and the run itself takes ~8s. Sleeping first means the poll below
# normally confirms on its first pass, and the warehouse stays free to auto-suspend
# in the meantime.
wait_for_stream() {
    local waited=0 has_data
    echo "==> waiting for TSK_LOAD_TRANSACTIONS to drain the stream"
    sleep "$TASK_SETTLE"
    while true; do
        has_data=$(uv run snow sql -c "$CONN" --format json \
            -q "select system\$stream_has_data('${STREAM}') as has_data" \
            | grep -oE 'true|false' | head -1)
        if [[ "$has_data" == "false" ]]; then
            echo "    stream drained"
            return 0
        fi
        waited=$((waited + POLL_INTERVAL))
        if (( waited >= DRAIN_TIMEOUT )); then
            echo "    stream still has data after ${waited}s -- the task is not" >&2
            echo "    keeping up or is not running. Check it with:" >&2
            echo "      uv run snow sql -c ${CONN} -q \"show tasks like 'tsk_load_transactions'\"" >&2
            return 1
        fi
        sleep "$POLL_INTERVAL"
    done
}

# pt3 cannot be globbed. The stream has to be created after the initial load so its
# offset starts at the end of the table, the delta load is asynchronous, and the two
# demo scripts are deliberately left for the user to run by hand.
mapfile -t PT12 < <(find pt1/ pt2/ -type f -name '*.sql' | sort)

run_batch \
    00_teardown.sql \
    "${PT12[@]}" \
    pt3/01-stream.sql \
    pt3/02-sp-load-transactions.sql \
    pt3/03-task.sql \
    pt3/04-load-delta.sql

wait_for_stream

# pt4 is read-only and reproduces the Part 4 numbers quoted in the README. pt5 runs
# last so its ALL-object grants cover the pt6 views too; dropping a schema drops its
# grants, so a rebuild has to replay these. The roles themselves survive.
run_batch \
    pt3/05-verify.sql \
    pt4/01-total-outstanding.sql \
    pt4/02-top-borrowers.sql \
    pt4/03-monthly-remittances.sql \
    pt4/04-exposure-by-industry.sql \
    pt4/05-verify.sql \
    pt6/00-api-views.sql \
    pt5/01-lp-summary-view.sql \
    pt5/02-access-roles.sql \
    pt5/03-functional-roles.sql \
    pt5/05-verify.sql

cat <<'EOF'

================================================================================
Rebuild complete. The pipeline is live: RAW.STM_TENOR_TRANSACTIONS is attached to
TENOR_TRANSACTIONS_EXPORT and STAGING.TSK_LOAD_TRANSACTIONS is resumed, so anything
landing in the raw table from here on is processed automatically.

Two demo scripts are also included with this project. They respectively verify:

  1. Idempotency -- re-sends of data already ingested get blocked.

       uv run snow sql -f pt3/06-resend-delta.sql

  2. Quarantine -- Unparsable data is intercepted and routed to AUDIT_TRANSACTION.

       uv run snow sql -f pt3/07-quarantine-demo.sql

Either file can also be pasted into a Snowsight worksheet instead.
================================================================================
EOF
