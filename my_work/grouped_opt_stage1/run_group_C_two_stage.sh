#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_DIR="$ROOT_DIR/my_work/grouped_opt_stage1"
RUN_GROUP="C"

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
BENCH_LIST="${BENCH_LIST:-$BASE_DIR/groups/group_C.txt}"

STAGE1_CASES="${STAGE1_CASES:-$BASE_DIR/configs/cases_C_stage1.txt}"
STAGE2_CASES="${STAGE2_CASES:-$BASE_DIR/configs/cases_C_stage2.txt}"

# Stage 1: fast pre-screen
RUN_TAG_S1="${RUN_TAG}_C_s1"
RESULT_S1="$BASE_DIR/results/$RUN_TAG_S1/$RUN_GROUP/summary.csv"

STRATEGY_NAME="C_stage1_fast_prescreen" \
RUN_GROUP="$RUN_GROUP" BENCH_LIST="$BENCH_LIST" CASE_LIST="$STAGE1_CASES" \
MAX_SECONDS="${MAX_SECONDS_STAGE1:-3600}" EARLY_STOP_FAILS="${EARLY_STOP_FAILS_STAGE1:-2}" EARLY_STOP_DELAY_REJECT_CASES="${EARLY_STOP_DELAY_REJECT_CASES_STAGE1:-2}" \
RUN_TAG="$RUN_TAG_S1" bash "$BASE_DIR/run_group_experiments.sh"

# Stage 2: quality refinement
RUN_TAG_S2="${RUN_TAG}_C_s2"
RESULT_S2="$BASE_DIR/results/$RUN_TAG_S2/$RUN_GROUP/summary.csv"

STRATEGY_NAME="C_stage2_quality_refine" \
RUN_GROUP="$RUN_GROUP" BENCH_LIST="$BENCH_LIST" CASE_LIST="$STAGE2_CASES" \
MAX_SECONDS="${MAX_SECONDS_STAGE2:-0}" EARLY_STOP_FAILS="${EARLY_STOP_FAILS_STAGE2:-2}" EARLY_STOP_DELAY_REJECT_CASES="${EARLY_STOP_DELAY_REJECT_CASES_STAGE2:-2}" \
RUN_TAG="$RUN_TAG_S2" bash "$BASE_DIR/run_group_experiments.sh"

MERGED_DIR="$BASE_DIR/results/${RUN_TAG}_C_two_stage"
mkdir -p "$MERGED_DIR"
MERGED="$MERGED_DIR/summary_C_two_stage.csv"

if [ ! -f "$RESULT_S1" ] || [ ! -f "$RESULT_S2" ]; then
  echo "[error] two-stage summaries missing." >&2
  exit 1
fi

cat "$RESULT_S1" > "$MERGED"
tail -n +2 "$RESULT_S2" >> "$MERGED"

echo "[done] stage1: $RESULT_S1" >&2
echo "[done] stage2: $RESULT_S2" >&2
echo "[done] merged: $MERGED" >&2
