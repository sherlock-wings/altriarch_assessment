#! /usr/bin/bash
# at this directory, run chmod +x 02-load-csv.sh to make this file executable

cd "$(dirname "$0")"

uv run snow sql -q "put file://source_data/affinity_organizations_export.csv @callahan_db.raw.internal_stage_csv;"
uv run snow sql -q "put file://source_data/factorview_facilities_export.csv @callahan_db.raw.internal_stage_csv;"
uv run snow sql -q "put file://source_data/tenor_transactions_delta.csv @callahan_db.raw.internal_stage_csv;"
uv run snow sql -q "put file://source_data/tenor_transactions_export.csv @callahan_db.raw.internal_stage_csv;"