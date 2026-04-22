#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_DIR="$ROOT_DIR/my_work/grouped_opt_stage1"

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
RUN_GROUP_LIST="${RUN_GROUP_LIST:-A B C D}"
OUT_DIR="$BASE_DIR/results/$RUN_TAG"
mkdir -p "$OUT_DIR"

for g in $RUN_GROUP_LIST; do
  echo "[run] strategy group=$g" >&2
  RUN_GROUP="$g" RUN_TAG="$RUN_TAG" bash "$BASE_DIR/run_group_strategy.sh"
done

COMBINED="$OUT_DIR/summary_all.csv"
first=1
for g in $RUN_GROUP_LIST; do
  f1="$OUT_DIR/$g/summary.csv"
  f2="$BASE_DIR/results/${RUN_TAG}_C_two_stage/summary_C_two_stage.csv"
  if [ "$g" = "C" ] && [ -f "$f2" ]; then
    src="$f2"
  else
    src="$f1"
  fi
  [ -f "$src" ] || continue

  if [ $first -eq 1 ]; then
    cat "$src" > "$COMBINED"
    first=0
  else
    tail -n +2 "$src" >> "$COMBINED"
  fi
done

if [ ! -f "$COMBINED" ]; then
  echo "[error] no strategy summary generated." >&2
  exit 1
fi

echo "[done] combined strategy summary: $COMBINED" >&2
