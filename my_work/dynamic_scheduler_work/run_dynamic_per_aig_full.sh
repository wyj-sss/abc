#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="$ROOT_DIR/my_work"
DYN_DIR="$WORK_DIR/dynamic_scheduler_work"
STAGEC_DIR="$WORK_DIR/stageC_full_validation"

RUN_TAG="${RUN_TAG:-run_dynamic_per_aig_$(date +%Y%m%d_%H%M%S)}"
RESULT_DIR="${RESULT_DIR:-$DYN_DIR/result/$RUN_TAG}"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

LIB_FILE="${LIB_FILE:-$WORK_DIR/c17_work/NangateOpenCellLibrary_typical.lib}"
ROUNDS="${ROUNDS:-3}"
BUILD_JOBS="${BUILD_JOBS:-1}"

# Keep parameters exactly aligned with Stage C cfg_winvpair_base.
CASE_NAME="${CASE_NAME:-cfg_winvpair_base}"
I_W="${I_W:-0.50}"
P_W="${P_W:-0.40}"
F_W="${F_W:-0.05}"
G_W="${G_W:-0.05}"
L_T="${L_T:-0.25}"
H_T="${H_T:-0.90}"
K_V="${K_V:-40}"
CASE_TIMEOUT_SEC="${CASE_TIMEOUT_SEC:-300}"
MODEL_DIR="${MODEL_DIR:-$WORK_DIR/model}"
GLOBAL_SAMPLE_CSV="${GLOBAL_SAMPLE_CSV:-$MODEL_DIR/phy_micro_samples_global.csv}"
PHY_FIT_ENABLE_ENV="${PHY_FIT_ENABLE_ENV:-1}"
FIT_FILE="${FIT_FILE:-}"

BENCH_DIR="${BENCH_DIR:-$WORK_DIR/xiaorong_aig}"
BENCH_LIST="${BENCH_LIST:-}"
BENCH_ALLOW_REGEX="${BENCH_ALLOW_REGEX:-}"
BENCH_LIMIT="${BENCH_LIMIT:-0}"

mkdir -p "$RESULT_DIR"
mkdir -p "$MODEL_DIR"

if [ ! -f "$LIB_FILE" ]; then
  echo "[error] liberty not found: $LIB_FILE" >&2
  exit 1
fi
if [ -z "$BENCH_LIST" ] && [ ! -d "$BENCH_DIR" ]; then
  echo "[error] bench dir not found: $BENCH_DIR" >&2
  exit 1
fi
if [ -n "$BENCH_LIST" ] && [ ! -f "$BENCH_LIST" ]; then
  echo "[error] bench list not found: $BENCH_LIST" >&2
  exit 1
fi
if [ ! -x "$ROOT_DIR/abc" ]; then
  echo "[build] make -j${BUILD_JOBS}" >&2
  if ! (cd "$ROOT_DIR" && make -j"$BUILD_JOBS"); then
    echo "[error] build failed" >&2
    exit 1
  fi
fi

extract_area_delay() {
  local aig="$1"
  local tmp="/tmp/dyn_ps_$$.log"
  "$ROOT_DIR/abc" -q "read_lib $LIB_FILE; read_aiger $aig; map; ps" > "$tmp" 2>&1
  local line
  line=$(grep -E "area =" "$tmp" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')
  rm -f "$tmp"
  if [ -z "$line" ]; then
    echo ","
    return
  fi
  local area delay
  area=$(echo "$line" | sed -E 's/.*area = *([0-9.]+).*/\1/')
  delay=$(echo "$line" | sed -E 's/.*delay = *([0-9.]+).*/\1/')
  echo "$area,$delay"
}

collect_benches() {
  local out_list="$1"
  if [ -n "$BENCH_LIST" ]; then
    : > "$out_list"
    while IFS= read -r raw || [ -n "$raw" ]; do
      local entry candidate
      entry="$(echo "$raw" | sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -z "$entry" ] && continue

      candidate=""
      if [ -f "$entry" ]; then
        candidate="$entry"
      elif [ -f "$BENCH_DIR/$entry" ]; then
        candidate="$BENCH_DIR/$entry"
      elif [ -f "$BENCH_DIR/$entry.aig" ]; then
        candidate="$BENCH_DIR/$entry.aig"
      fi

      if [ -n "$candidate" ]; then
        echo "$candidate" >> "$out_list"
      else
        echo "[warn] bench entry not found, skip: $entry" >&2
      fi
    done < "$BENCH_LIST"
    awk '!seen[$0]++' "$out_list" > "${out_list}.uniq"
    mv "${out_list}.uniq" "$out_list"
  else
    find "$BENCH_DIR" -maxdepth 1 -type f -name "*.aig" | sort > "$out_list"
  fi
  if [ -n "$BENCH_ALLOW_REGEX" ]; then
    awk -v re="$BENCH_ALLOW_REGEX" '{ b=$0; sub(/^.*\//,"",b); sub(/\.aig$/,"",b); if (b ~ re) print $0 }' "$out_list" > "${out_list}.flt"
    mv "${out_list}.flt" "$out_list"
  fi
  if [ "$BENCH_LIMIT" -gt 0 ]; then
    head -n "$BENCH_LIMIT" "$out_list" > "${out_list}.lim"
    mv "${out_list}.lim" "$out_list"
  fi
}

run_case() {
  local bench_path="$1"
  local bench_name
  local bench_dir
  local out_csv out_log cmd_file
  local before_stats after_stats
  local t_start t_end runtime_sec
  local status="PASS"

  bench_name="$(basename "$bench_path" .aig)"
  bench_dir="$RESULT_DIR/$bench_name"
  mkdir -p "$bench_dir"

  out_csv="$bench_dir/${bench_name}_${CASE_NAME}.csv"
  out_log="$bench_dir/${bench_name}_${CASE_NAME}.log"
  cmd_file="/tmp/dyn_${bench_name}_$$.scr"

  t_start=$(date +%s)

  before_stats=$(extract_area_delay "$bench_path")

  cat > "$cmd_file" <<EOF
read_lib $LIB_FILE
read_aiger $bench_path
map_oto
mapper_extract -o $out_csv
phyread -i $I_W -p $P_W -f $F_W -g $G_W $out_csv
phyopt -d -n $ROUNDS -k $K_V -L $L_T -H $H_T -t $CASE_TIMEOUT_SEC
map
ps
quit
EOF

  PHY_MICRO_ENABLE=0 \
  PHY_FIT_ENABLE="$PHY_FIT_ENABLE_ENV" \
  PHY_FIT_COEF_FILE="$FIT_FILE" \
  PHY_MICRO_TRAIN_CSV="$GLOBAL_SAMPLE_CSV" \
  "$ROOT_DIR/abc" -f "$cmd_file" > "$out_log" 2>&1
  local rc=$?
  rm -f "$cmd_file"
  if [ $rc -ne 0 ]; then
    status="FAIL"
  fi

  local line
  line=$(grep -E "area =" "$out_log" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')
  if [ -z "$line" ]; then
    after_stats=","
    status="FAIL"
  else
    local area delay
    area=$(echo "$line" | sed -E 's/.*area = *([0-9.]+).*/\1/')
    delay=$(echo "$line" | sed -E 's/.*delay = *([0-9.]+).*/\1/')
    after_stats="$area,$delay"
  fi

  local accepted rejected timeout_hit top_high top_low top_mid rr_rt rr_delay rr_area
  accepted=$(grep -E "phyopt: done, accepted=" "$out_log" | tail -n1 | sed -E 's/.*accepted=([0-9]+).*/\1/')
  rejected=$(grep -E "phyopt: done, accepted=" "$out_log" | tail -n1 | sed -E 's/.*rejected=([0-9]+).*/\1/')
  timeout_hit=$(grep -E "phyopt: case timeout reached" "$out_log" | tail -n1)
  top_high=$(grep -E "^  high:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  top_low=$(grep -E "^  low:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  top_mid=$(grep -E "^  mid:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  rr_rt=$(grep -E "runtime_or_eval_fail" "$out_log" | tail -n1 | sed -E 's/.*: *([0-9]+).*/\1/')
  rr_delay=$(grep -E "delay_worse" "$out_log" | tail -n1 | sed -E 's/.*: *([0-9]+).*/\1/')
  rr_area=$(grep -E "area_worse" "$out_log" | head -n1 | sed -E 's/.*: *([0-9]+).*/\1/')

  [ -n "$accepted" ] || accepted=0
  [ -n "$rejected" ] || rejected=0
  if [ -n "$timeout_hit" ]; then
    timeout_hit=1
    [ "$status" = "PASS" ] && status="TIMEOUT"
  else
    timeout_hit=0
  fi
  [ -n "$top_high" ] || top_high=0
  [ -n "$top_low" ] || top_low=0
  [ -n "$top_mid" ] || top_mid=0
  [ -n "$rr_rt" ] || rr_rt=0
  [ -n "$rr_delay" ] || rr_delay=0
  [ -n "$rr_area" ] || rr_area=0

  t_end=$(date +%s)
  runtime_sec=$((t_end - t_start))
  [ "$runtime_sec" -ge 0 ] || runtime_sec=0

  echo "$bench_name,$CASE_NAME,$status,$before_stats,$after_stats,$accepted,$rejected,$timeout_hit,$runtime_sec,$top_high,$top_low,$top_mid,$rr_rt,$rr_delay,$rr_area,\"-i $I_W -p $P_W -f $F_W -g $G_W\",\"-d -k $K_V -L $L_T -H $H_T -t $CASE_TIMEOUT_SEC\",$out_log" >> "$SUMMARY_CSV"
}

BENCH_TMP_LIST="/tmp/dyn_per_aig_benches_$$.txt"
collect_benches "$BENCH_TMP_LIST"
bench_cnt=$(wc -l < "$BENCH_TMP_LIST")

echo "bench,case,status,before_area,before_delay,after_area,after_delay,accepted,rejected,timeout_hit,runtime_sec,topk_hit_high,topk_hit_low,topk_hit_mid,reject_runtime,reject_delay,reject_area,phyread_args,phyopt_args,log_file" > "$SUMMARY_CSV"
echo "[info] benches=$bench_cnt" >&2
echo "[info] result_dir=$RESULT_DIR" >&2
echo "[info] mode=per-aig-node-dynamic (no bench grouping)" >&2
echo "[info] case_timeout_sec=$CASE_TIMEOUT_SEC" >&2
echo "[info] global_sample_csv=$GLOBAL_SAMPLE_CSV" >&2
echo "[info] phy_fit_enable=$PHY_FIT_ENABLE_ENV" >&2
echo "[info] fit_file=${FIT_FILE:-<builtin/default>}" >&2

done_cases=0
while IFS= read -r bench; do
  [ -z "$bench" ] && continue
  done_cases=$((done_cases + 1))
  echo "[progress] $done_cases/$bench_cnt bench=$(basename "$bench" .aig)" >&2
  run_case "$bench"
done < "$BENCH_TMP_LIST"

rm -f "$BENCH_TMP_LIST"
echo "[done] summary: $SUMMARY_CSV" >&2
