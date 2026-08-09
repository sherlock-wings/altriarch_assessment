#!/usr/bin/env bash
set -euo pipefail

# Full rebuild from zero: teardown, then pt1/ and pt2/ in filename order.

if [[ "${1:-}" != "-y" ]]; then
    echo "This drops schemas RAW, STAGING and MARTS in CALLAHAN_DB, including the"
    echo "Part 3 stream, task and accumulated AUDIT_TRANSACTION rows."
    read -rp "Rebuild from scratch? [y/N] " reply
    [[ "$reply" == [yY] ]] || { echo "Aborted."; exit 1; }
fi

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
