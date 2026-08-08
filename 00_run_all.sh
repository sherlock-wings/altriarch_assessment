#!/usr/bin/env bash
set -euo pipefail

find pt2/ -type f \( -name '*.sql' -o -name '*.sh' \) -print0 \
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
