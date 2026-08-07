#! /usr/bin/bash

uv run snow sql -q "put file:///source-data/*.csv @callahan_db.raw.interal_stage_csv;"