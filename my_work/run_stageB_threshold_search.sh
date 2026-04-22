#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/my_work"
RESULT_DIR="$WORK_DIR/ablation_results_stageB"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

LIB_FILE="${LIB_FILE:-$WORK_DIR/c17_work/NangateOpenCellLibrary_typical.lib}"
ROUNDS="${ROUNDS:-1}"
PART_SIZE="${PART_SIZE:-30}"
BUILD_JOBS="${BUILD_JOBS:-1}"

BENCH_LIST="${BENCH_LIST:-$WORK_DIR/stageB_benches.txt}"
THRESH_LIST="${THRESH_LIST:-$WORK_DIR/stageB_thresholds.txt}"

# --- Helper Functions ---

sanitize() {
  echo "$1" | sed -E 's/[^A-Za-z0-9_\-]+/_/g'
}

extract_area_delay() {
  local aig="$1"
  local tmp="/tmp/ablation_ps_$$.log"
  "$ROOT_DIR/abc" -q "read_liberty $LIB_FILE; read_aiger $aig; map; ps" > "$tmp" 2>&1
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

resolve_bench_path() {
  local name="$1"
  local p
  for p in "$WORK_DIR/c17_work/$name.aig" "$WORK_DIR/c499_work/$name.aig" "$WORK_DIR/c880_work/$name.aig" "$WORK_DIR/xiaorong_aig/$name.aig"; do
    if [ -f "$p" ]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

run_case() {
  local bench_path="$1"
  local case_name="$2"
  local phyopt_args="$3"

  local bench_base bench_key bench_dir out_aig out_csv out_log cmd_file
  bench_base="$(basename "$bench_path" .aig)"
  bench_key="$(sanitize "$bench_base")"
  bench_dir="$RESULT_DIR/$bench_key"
  mkdir -p "$bench_dir"

  out_aig="$bench_dir/${bench_key}_${case_name}.aig"
  out_csv="$bench_dir/${bench_key}_${case_name}.csv"
  out_log="$bench_dir/${bench_key}_${case_name}.log"
  cmd_file="/tmp/ablation_${bench_key}_${case_name}_$$.scr"

  cat > "$cmd_file" <<EOF
read_liberty $LIB_FILE
read_aiger $bench_path
map_oto
mapper_extract -o $out_csv
phyread $out_csv
phyopt -n $ROUNDS -k $PART_SIZE $phyopt_args
strash
write_aiger $out_aig
cec -n $bench_path $out_aig
quit
EOF

  "$ROOT_DIR/abc" -f "$cmd_file" > "$out_log" 2>&1
  local rc=$?
  rm -f "$cmd_file"

  if [ $rc -ne 0 ]; then
      echo "[error] ABC execution failed for $bench_base with case $case_name. RC=$rc. See log: $out_log" >&2
      # Optionally output a failed CSV line
      echo "$bench_base,$case_name,FAIL_ABC,$rc,,,,,,,,,,,,,$phyopt_args,$out_log"
      return 0
  fi

  local status="PASS"
  if ! grep -q "Networks are equivalent" "$out_log"; then
    status="FAIL_CEC"
  fi

  local after_stats
  after_stats=$(extract_area_delay "$out_aig")

  local before_stats
  before_stats=$(extract_area_delay "$bench_path")

  local log_line
  log_line=$(grep -E "phyopt:.*acc=" "$out_log" | tail -n 1)
  local accepted rejected topk_hit_high topk_hit_low topk_hit_mid reject_runtime reject_delay reject_area
  accepted=$(echo "$log_line" | sed -E 's/.*acc=([0-9]+).*/\1/')
  rejected=$(echo "$log_line" | sed -E 's/.*rej=([0-9]+).*/\1/')
  topk_hit_high=$(echo "$log_line" | sed -E 's/.*H=([0-9]+).*/\1/')
  topk_hit_low=$(echo "$log_line" | sed -E 's/.*L=([0-9]+).*/\1/')
  topk_hit_mid=$(echo "$log_line" | sed -E 's/.*M=([0-9]+).*/\1/')
  reject_runtime=$(echo "$log_line" | sed -E 's/.*rR=([0-9]+).*/\1/')
  reject_delay=$(echo "$log_line" | sed -E 's/.*rD=([0-9]+).*/\1/')
  reject_area=$(echo "$log_line" | sed -E 's/.*rA=([0-9]+).*/\1/')

  echo "$bench_base,$case_name,$status,$before_stats,$after_stats,$accepted,$rejected,$topk_hit_high,$topk_hit_low,$topk_hit_mid,$reject_runtime,$reject_delay,$reject_area,N/A,$phyopt_args,$out_log"
}

main() {
  local bench_name bench_path
  while IFS= read -r bench_name || [ -n "$bench_name" ]; do
    bench_name=$(echo "$bench_name" | tr -d '\r')
    bench_path=$(resolve_bench_path "$bench_name")
    if [ -z "$bench_path" ]; then
      echo "[warn] bench not found: $bench_name" >&2
      continue
    fi

    local l_thresh h_thresh case_name phyopt_args line
    while IFS= read -r line || [ -n "$line" ]; do
      line=$(echo "$line" | tr -d '\r')
      l_thresh=$(echo "$line" | cut -d' ' -f1)
      h_thresh=$(echo "$line" | cut -d' ' -f2)
      case_name="L${l_thresh}_H${h_thresh}"
      phyopt_args="-L $l_thresh -H $h_thresh"
      echo "--- Running case: bench=$bench_name, case=$case_name ---" >&2
      run_case "$bench_path" "$case_name" "$phyopt_args"
    done < "$THRESH_LIST"
  done < "$BENCH_LIST"
}

# --- Main Execution ---

mkdir -p "$RESULT_DIR"

if [ ! -f "$LIB_FILE" ]; then
  echo "[error] liberty not found: $LIB_FILE" >&2
  exit 1
fi

if [ ! -x "$ROOT_DIR/abc" ]; then
  echo "[build] make -j${BUILD_JOBS}" >&2
  if ! (cd "$ROOT_DIR" && make -j"$BUILD_JOBS"); then
    echo "[error] build failed" >&2
    exit 1
  fi
fi

if [ ! -f "$BENCH_LIST" ]; then
  echo "[error] bench list not found: $BENCH_LIST" >&2
  exit 1
fi

if [ ! -f "$THRESH_LIST" ]; then
  echo "[error] threshold list not found: $THRESH_LIST" >&2
  exit 1
fi

total_cases=$(($(wc -l < "$BENCH_LIST") * $(wc -l < "$THRESH_LIST")))
echo "[info] total cases: $total_cases" >&2

header="bench,case,status,before_area,before_delay,after_area,after_delay,accepted,rejected,topk_hit_high,topk_hit_low,topk_hit_mid,reject_runtime,reject_delay,reject_area,phyread_args,phyopt_args,log_file"
echo "$header" > "$SUMMARY_CSV"

main_log="/tmp/main_run.log"
set +e
main "$@" > "$main_log" 2>&1
main_rc=$?
set -e
cat "$main_log" | tee -a "$SUMMARY_CSV"
rm -f "$main_log"

if [ "$main_rc" -ne 0 ]; then
  echo "[warn] stageB finished with non-zero status: $main_rc (some cases may have failed; check logs in $RESULT_DIR)" >&2
fi

echo "[done] summary: $SUMMARY_CSV" >&2
