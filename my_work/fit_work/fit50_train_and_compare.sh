#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DYN_DIR="$ROOT_DIR/my_work/dynamic_scheduler_work"
MODEL_DIR="$ROOT_DIR/my_work/model"
FIT_DIR="$ROOT_DIR/my_work/fit_work"

RUN_TAG="${RUN_TAG:-run_iwls26_fit50_collect_20260420_155120}"
RESULT_DIR="${RESULT_DIR:-$DYN_DIR/result/$RUN_TAG}"
SUMMARY_CSV="${SUMMARY_CSV:-$RESULT_DIR/summary.csv}"
SAMPLES_CSV="${SAMPLES_CSV:-$MODEL_DIR/phy_fit_samples_50.csv}"
FIT_FILE="${FIT_FILE:-$MODEL_DIR/phy_fit_function_v1.txt}"
FIT_LOG="${FIT_LOG:-$RESULT_DIR/fit_train.log}"

MIN_CASES="${MIN_CASES:-50}"
DO_COMPARE="${DO_COMPARE:-1}"
COMPARE_TAG="${COMPARE_TAG:-run_iwls26_model_equiv_fit50_$(date +%Y%m%d_%H%M%S)}"

GOAL_MIN_AREA="${GOAL_MIN_AREA:-0.0}"
DELAY_EPS="${DELAY_EPS:-0.001}"
EPOCHS="${EPOCHS:-30}"
LR="${LR:-0.05}"
L2="${L2:-0.001}"
SEED="${SEED:-7}"
TRAIN_FRAC="${TRAIN_FRAC:-0.85}"

FAIL() {
  echo "[error] $*" >&2
  exit 1
}

if [ ! -f "$SUMMARY_CSV" ]; then
  FAIL "summary not found: $SUMMARY_CSV"
fi
if [ ! -f "$SAMPLES_CSV" ]; then
  FAIL "samples csv not found: $SAMPLES_CSV"
fi

summary_lines=$(wc -l < "$SUMMARY_CSV")
sample_lines=$(wc -l < "$SAMPLES_CSV")
# header + MIN_CASES rows expected in summary
if [ "$summary_lines" -lt $((MIN_CASES + 1)) ]; then
  FAIL "summary not complete yet (lines=$summary_lines, need >= $((MIN_CASES + 1)))"
fi
if [ "$sample_lines" -lt 2 ]; then
  FAIL "samples csv has no data rows"
fi

mkdir -p "$MODEL_DIR"
mkdir -p "$RESULT_DIR"

echo "[info] train fit from $SAMPLES_CSV" | tee "$FIT_LOG"
python3 "$FIT_DIR/train_fit_function.py" \
  --input "$SAMPLES_CSV" \
  --output "$FIT_FILE" \
  --goal-min-area-impr-pct "$GOAL_MIN_AREA" \
  --delay-eps "$DELAY_EPS" \
  --epochs "$EPOCHS" \
  --lr "$LR" \
  --l2 "$L2" \
  --seed "$SEED" \
  --train-frac "$TRAIN_FRAC" \
  --balance | tee -a "$FIT_LOG"

if [ "$DO_COMPARE" = "1" ]; then
  echo "[info] run compare with fitted function: $FIT_FILE" | tee -a "$FIT_LOG"
  RUN_TAG="$COMPARE_TAG" FIT_FILE="$FIT_FILE" "$DYN_DIR/run_model_opt_equiv_compare.sh" | tee -a "$FIT_LOG"
fi

echo "[done] fit file: $FIT_FILE" | tee -a "$FIT_LOG"
