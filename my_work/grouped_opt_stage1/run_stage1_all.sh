#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_DIR="$ROOT_DIR/my_work/grouped_opt_stage1"

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
RUN_GROUP_LIST="${RUN_GROUP_LIST:-A B C D}"
OUT_DIR="$BASE_DIR/results/$RUN_TAG"
mkdir -p "$OUT_DIR"

for g in $RUN_GROUP_LIST; do
  echo "[run] group=$g" >&2
  RUN_TAG="$RUN_TAG" GROUP="$g" bash "$BASE_DIR/run_group_experiments.sh"
done

COMBINED="$OUT_DIR/summary_all.csv"
first=1
for g in $RUN_GROUP_LIST; do
  f="$OUT_DIR/$g/summary.csv"
  [ -f "$f" ] || continue
  if [ $first -eq 1 ]; then
    cat "$f" > "$COMBINED"
    first=0
  else
    tail -n +2 "$f" >> "$COMBINED"
  fi
done

if [ ! -f "$COMBINED" ]; then
  echo "[error] no group summary generated." >&2
  exit 1
fi

echo "[done] combined summary: $COMBINED" >&2
