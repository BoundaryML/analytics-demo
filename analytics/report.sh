#!/usr/bin/env bash
# Run every query in this directory against the most recent `baml run run_eval`.
set -euo pipefail
cd "$(dirname "$0")/.."
for query in analytics/*.sql; do
  echo
  echo "── $(basename "$query" .sql) ──"
  sed -n 's/^-- //p' "$query"          # the comment header explains the query
  echo
  baml query - < "$query" || true      # exit 1 just means some values weren't hydrated
done
