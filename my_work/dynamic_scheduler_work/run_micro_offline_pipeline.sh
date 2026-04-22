#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DYN_DIR="$ROOT_DIR/my_work/dynamic_scheduler_work"
RUN_TS="${RUN_TS:-$(date +%Y%m%d_%H%M%S)}"

BENCH_DIR="${BENCH_DIR:-$ROOT_DIR/iwls26/results}"
TRAIN_BENCH_LIST="${TRAIN_BENCH_LIST:-}"
APPLY_BENCH_LIST="${APPLY_BENCH_LIST:-}"
TRAIN_PICK_EACH="${TRAIN_PICK_EACH:-6}"

TRAIN_RUN_TAG="${TRAIN_RUN_TAG:-run_micro_train_wide_${RUN_TS}}"
APPLY_RUN_TAG="${APPLY_RUN_TAG:-run_micro_apply_offline_${RUN_TS}}"

MODEL_FILE="${MODEL_FILE:-$DYN_DIR/micro_model_offline_wide.txt}"
ONLINE_MODEL_SNAPSHOT="${ONLINE_MODEL_SNAPSHOT:-$DYN_DIR/micro_model_train_online_tmp.txt}"
SAMPLE_CSV="${SAMPLE_CSV:-$DYN_DIR/micro_train_samples_wide.csv}"

ROUNDS="${ROUNDS:-3}"
TRAIN_L_T="${TRAIN_L_T:-0.40}"
TRAIN_H_T="${TRAIN_H_T:-0.80}"
APPLY_L_T="${APPLY_L_T:-0.25}"
APPLY_H_T="${APPLY_H_T:-0.90}"

TRAIN_EPOCHS="${TRAIN_EPOCHS:-30}"
TRAIN_LR="${TRAIN_LR:-0.05}"
TRAIN_L2="${TRAIN_L2:-0.001}"
TRAIN_BALANCE="${TRAIN_BALANCE:-1}"

TRAIN_TRY_TARGET_PCT="${TRAIN_TRY_TARGET_PCT:-80}"
TRAIN_KEEP_MIN_PCT="${TRAIN_KEEP_MIN_PCT:-80}"
TRAIN_KEEP_MAX_PCT="${TRAIN_KEEP_MAX_PCT:-100}"
TRAIN_KEEP_STEP_PCT="${TRAIN_KEEP_STEP_PCT:-10}"
TRAIN_EXPLORE_FLOOR="${TRAIN_EXPLORE_FLOOR:-0.35}"
TRAIN_BLEND_L0="${TRAIN_BLEND_L0:-0.10}"
TRAIN_BLEND_L1="${TRAIN_BLEND_L1:-0.05}"

APPLY_TRY_TARGET_PCT="${APPLY_TRY_TARGET_PCT:-30}"
APPLY_KEEP_MIN_PCT="${APPLY_KEEP_MIN_PCT:-40}"
APPLY_KEEP_MAX_PCT="${APPLY_KEEP_MAX_PCT:-95}"
APPLY_KEEP_STEP_PCT="${APPLY_KEEP_STEP_PCT:-6}"
APPLY_EXPLORE_FLOOR="${APPLY_EXPLORE_FLOOR:-0.18}"
APPLY_BLEND_L0="${APPLY_BLEND_L0:-0.45}"
APPLY_BLEND_L1="${APPLY_BLEND_L1:-0.30}"

PIPE_DIR="${PIPE_DIR:-$DYN_DIR/pipeline_${RUN_TS}}"
AUTO_TRAIN_LIST="$PIPE_DIR/train_benches_auto.txt"
TRAIN_LIST="$PIPE_DIR/train_benches.txt"
APPLY_LIST="$PIPE_DIR/apply_benches.txt"
REPORT_FILE="$PIPE_DIR/pipeline_report.txt"

mkdir -p "$PIPE_DIR"

die() {
  echo "[error] $*" >&2
  exit 1
}

trim_line() {
  echo "$1" | sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

prepare_named_list() {
  local src="$1"
  local dst="$2"
  : > "$dst"
  while IFS= read -r raw || [ -n "$raw" ]; do
    local item
    item="$(trim_line "$raw")"
    [ -z "$item" ] && continue
    echo "$item" >> "$dst"
  done < "$src"
  awk '!seen[$0]++' "$dst" > "${dst}.uniq"
  mv "${dst}.uniq" "$dst"
}

auto_pick_train_list_by_size() {
  local by_size="$PIPE_DIR/all_benches_by_size.tsv"
  local total pick mid_start mid_end

  find "$BENCH_DIR" -maxdepth 1 -type f -name "*.aig" -printf '%s\t%p\n' | sort -n > "$by_size"
  total=$(wc -l < "$by_size" | tr -d ' ')
  [ "$total" -gt 0 ] || die "no .aig benches found in $BENCH_DIR"

  pick="$TRAIN_PICK_EACH"
  [ "$pick" -ge 1 ] || pick=1

  : > "$AUTO_TRAIN_LIST"
  head -n "$pick" "$by_size" | awk -F'\t' '{print $2}' >> "$AUTO_TRAIN_LIST"

  mid_start=$(( total / 2 - pick / 2 + 1 ))
  if [ "$mid_start" -lt 1 ]; then
    mid_start=1
  fi
  mid_end=$(( mid_start + pick - 1 ))
  if [ "$mid_end" -gt "$total" ]; then
    mid_end="$total"
  fi
  sed -n "${mid_start},${mid_end}p" "$by_size" | awk -F'\t' '{print $2}' >> "$AUTO_TRAIN_LIST"

  tail -n "$pick" "$by_size" | awk -F'\t' '{print $2}' >> "$AUTO_TRAIN_LIST"

  awk '!seen[$0]++' "$AUTO_TRAIN_LIST" > "${AUTO_TRAIN_LIST}.uniq"
  mv "${AUTO_TRAIN_LIST}.uniq" "$AUTO_TRAIN_LIST"
}

resolve_python() {
  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    echo "python"
    return 0
  fi
  return 1
}

[ -d "$BENCH_DIR" ] || die "bench dir not found: $BENCH_DIR"
[ -f "$ROOT_DIR/my_work/c17_work/NangateOpenCellLibrary_typical.lib" ] || die "liberty not found"

if [ -n "$TRAIN_BENCH_LIST" ]; then
  [ -f "$TRAIN_BENCH_LIST" ] || die "train bench list not found: $TRAIN_BENCH_LIST"
  prepare_named_list "$TRAIN_BENCH_LIST" "$TRAIN_LIST"
else
  auto_pick_train_list_by_size
  cp "$AUTO_TRAIN_LIST" "$TRAIN_LIST"
fi

if [ -n "$APPLY_BENCH_LIST" ]; then
  [ -f "$APPLY_BENCH_LIST" ] || die "apply bench list not found: $APPLY_BENCH_LIST"
  prepare_named_list "$APPLY_BENCH_LIST" "$APPLY_LIST"
else
  cp "$TRAIN_LIST" "$APPLY_LIST"
fi

train_cnt=$(wc -l < "$TRAIN_LIST" | tr -d ' ')
apply_cnt=$(wc -l < "$APPLY_LIST" | tr -d ' ')
[ "$train_cnt" -gt 0 ] || die "train list is empty"
[ "$apply_cnt" -gt 0 ] || die "apply list is empty"

PY_BIN="$(resolve_python)" || die "python3/python not found"

echo "[info] train benches: $train_cnt"
echo "[info] apply benches: $apply_cnt"
echo "[info] train run tag: $TRAIN_RUN_TAG"
echo "[info] apply run tag: $APPLY_RUN_TAG"

echo "[stage-1] collect training samples with widened funnel"
rm -f "$SAMPLE_CSV"
RUN_TAG="$TRAIN_RUN_TAG" \
BENCH_DIR="$BENCH_DIR" \
BENCH_LIST="$TRAIN_LIST" \
ROUNDS="$ROUNDS" \
L_T="$TRAIN_L_T" \
H_T="$TRAIN_H_T" \
PHY_MICRO_ENABLE=1 \
PHY_MICRO_MODEL_FILE="$ONLINE_MODEL_SNAPSHOT" \
PHY_MICRO_TRAIN_CSV="$SAMPLE_CSV" \
PHY_MICRO_TRY_TARGET_PCT="$TRAIN_TRY_TARGET_PCT" \
PHY_MICRO_KEEP_MIN_PCT="$TRAIN_KEEP_MIN_PCT" \
PHY_MICRO_KEEP_MAX_PCT="$TRAIN_KEEP_MAX_PCT" \
PHY_MICRO_KEEP_STEP_PCT="$TRAIN_KEEP_STEP_PCT" \
PHY_MICRO_EXPLORE_FLOOR="$TRAIN_EXPLORE_FLOOR" \
PHY_MICRO_BLEND_L0="$TRAIN_BLEND_L0" \
PHY_MICRO_BLEND_L1="$TRAIN_BLEND_L1" \
PHY_DYN_TRAIN_WIDE=1 \
bash "$DYN_DIR/run_dynamic_per_aig_full.sh"

[ -f "$SAMPLE_CSV" ] || die "training samples not generated: $SAMPLE_CSV"

echo "[stage-2] train offline micro model"
TRAIN_ARGS=(
  --input "$SAMPLE_CSV"
  --output "$MODEL_FILE"
  --epochs "$TRAIN_EPOCHS"
  --lr "$TRAIN_LR"
  --l2 "$TRAIN_L2"
)
if [ "$TRAIN_BALANCE" = "1" ]; then
  TRAIN_ARGS+=(--balance)
fi
"$PY_BIN" "$DYN_DIR/train_micro_model.py" "${TRAIN_ARGS[@]}"

[ -f "$MODEL_FILE" ] || die "offline model not generated: $MODEL_FILE"

echo "[stage-3] apply offline model with normal optimization settings"
RUN_TAG="$APPLY_RUN_TAG" \
BENCH_DIR="$BENCH_DIR" \
BENCH_LIST="$APPLY_LIST" \
ROUNDS="$ROUNDS" \
L_T="$APPLY_L_T" \
H_T="$APPLY_H_T" \
PHY_MICRO_ENABLE=1 \
PHY_MICRO_MODEL_FILE="$MODEL_FILE" \
PHY_MICRO_TRAIN_CSV="" \
PHY_MICRO_TRY_TARGET_PCT="$APPLY_TRY_TARGET_PCT" \
PHY_MICRO_KEEP_MIN_PCT="$APPLY_KEEP_MIN_PCT" \
PHY_MICRO_KEEP_MAX_PCT="$APPLY_KEEP_MAX_PCT" \
PHY_MICRO_KEEP_STEP_PCT="$APPLY_KEEP_STEP_PCT" \
PHY_MICRO_EXPLORE_FLOOR="$APPLY_EXPLORE_FLOOR" \
PHY_MICRO_BLEND_L0="$APPLY_BLEND_L0" \
PHY_MICRO_BLEND_L1="$APPLY_BLEND_L1" \
PHY_DYN_TRAIN_WIDE=0 \
PHY_DYN_ENABLE_L0=1 \
PHY_DYN_ENABLE_L1=1 \
bash "$DYN_DIR/run_dynamic_per_aig_full.sh"

{
  echo "pipeline_dir=$PIPE_DIR"
  echo "train_list=$TRAIN_LIST"
  echo "apply_list=$APPLY_LIST"
  echo "sample_csv=$SAMPLE_CSV"
  echo "model_file=$MODEL_FILE"
  echo "train_summary=$DYN_DIR/result/$TRAIN_RUN_TAG/summary.csv"
  echo "apply_summary=$DYN_DIR/result/$APPLY_RUN_TAG/summary.csv"
} > "$REPORT_FILE"

echo "[done] report: $REPORT_FILE"
