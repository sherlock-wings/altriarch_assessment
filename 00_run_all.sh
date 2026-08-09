#!/usr/bin/env bash
set -euo pipefail

# Full rebuild from zero: teardown, then pt1/ and pt2/ in filename order, then pt3/
# in an explicit sequence. Ends with the pipeline live and the delta loaded.

STREAM='callahan_db.raw.stm_tenor_transactions'
DRAIN_TIMEOUT=300

if [[ "${1:-}" != "-y" ]]; then
    echo "This drops schemas RAW, STAGING and MARTS in CALLAHAN_DB, then rebuilds them"
    echo "including the Part 3 stream and task. Accumulated AUDIT_TRANSACTION rows and"
    echo "any manually loaded data are lost."
    read -rp "Rebuild from scratch? [y/N] " reply
    [[ "$reply" == [yY] ]] || { echo "Aborted."; exit 1; }
fi

run_sql() {
    echo "==> snow sql -f $1"
    uv run snow sql -f "$1"
}

# Poll until TSK_LOAD_TRANSACTIONS has consumed everything the stream is holding. The
# task is triggered rather than scheduled: it fires within ~30s of rows landing and the
# run itself takes ~8s.
wait_for_stream() {
    local waited=0 has_data
    echo "==> waiting for TSK_LOAD_TRANSACTIONS to drain the stream"
    while true; do
        has_data=$(uv run snow sql --format json \
            -q "select system\$stream_has_data('${STREAM}') as has_data" \
            | grep -oE 'true|false' | head -1)
        if [[ "$has_data" == "false" ]]; then
            echo "    stream drained after ${waited}s"
            return 0
        fi
        if (( waited >= DRAIN_TIMEOUT )); then
            echo "    stream still has data after ${DRAIN_TIMEOUT}s -- the task is not" >&2
            echo "    keeping up or is not running. Check it with:" >&2
            echo "      uv run snow sql -q \"show tasks like 'tsk_load_transactions'\"" >&2
            return 1
        fi
        sleep 10
        waited=$((waited + 10))
    done
}

echo "==> snow sql -f 00_teardown.sql"
uv run snow sql -f 00_teardown.sql

find pt1/ pt2/ -type f \( -name '*.sql' -o -name '*.sh' \) -print0 \
| sort -z \
| while IFS= read -r -d '' file; do
    case "$file" in
        *.sql)
        echo "==> snow sql -f $file"
        uv run snow sql -f "$file"
        ;;
        *.sh)
        echo "==> bash $file"
        bash "$file"
        ;;
    esac
    done

# pt3 cannot be globbed. The stream has to be created after the initial load so its
# offset starts at the end of the table, the delta load is asynchronous, and the two
# demo scripts are deliberately left for the user to run by hand.
run_sql pt3/01-stream.sql
run_sql pt3/02-sp-load-transactions.sql
run_sql pt3/03-task.sql
run_sql pt3/04-load-delta.sql
wait_for_stream
run_sql pt3/05-verify.sql

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
