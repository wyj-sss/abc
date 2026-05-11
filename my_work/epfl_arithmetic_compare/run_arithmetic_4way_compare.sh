#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH_DIR_DEFAULT="$ROOT_DIR/../EPFL_benchmarks/arithmetic"
BENCH_DIR="${BENCH_DIR:-$BENCH_DIR_DEFAULT}"
RESULT_ROOT_DEFAULT="$ROOT_DIR/my_work/epfl_arithmetic_compare/results"
RESULT_ROOT="${RESULT_ROOT:-$RESULT_ROOT_DEFAULT}"
RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
RESULT_DIR="$RESULT_ROOT/$RUN_TAG"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

LIB_FILE="${LIB_FILE:-$ROOT_DIR/NangateOpenCellLibrary_typical.lib}"
BUILD_JOBS="${BUILD_JOBS:-1}"
ROUNDS="${ROUNDS:-1}"
PART_SIZE="${PART_SIZE:-25}"
PHYREAD_ARGS="${PHYREAD_ARGS:--i 0.50 -p 0.40 -f 0.05 -g 0.05}"
PHYOPT_EXTRA_ARGS="${PHYOPT_EXTRA_ARGS:-}"
BENCHES_INPUT="${BENCHES_INPUT:-adder bar div hyp log2 max multiplier sin sqrt square}"
MODES_INPUT="${MODES_INPUT:- global}"
KEEP_LOGS="${KEEP_LOGS:-1}"

mkdir -p "$RESULT_DIR"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [bench ...]

Examples:
  $(basename "$0")
  BENCHES_INPUT="adder multiplier" $(basename "$0")
  ROUNDS=1 PART_SIZE=20 $(basename "$0") square

Environment:
  BENCH_DIR          EPFL arithmetic directory (default: $BENCH_DIR_DEFAULT)
  RESULT_ROOT        output root directory (default: $RESULT_ROOT_DEFAULT)
  LIB_FILE           liberty file used for mapping
  ROUNDS             phyopt -n
  PART_SIZE          phyopt -k
  PHYREAD_ARGS       extra args passed to phyread
  PHYOPT_EXTRA_ARGS  extra args passed to phyopt
  MODES_INPUT        acceptance modes to run: global window
  BENCHES_INPUT      default bench list when no args are given
  KEEP_LOGS          1 to keep logs, 0 to delete intermediate logs
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 0 ]; then
  BENCHES=("$@")
else
  # shellcheck disable=SC2206
  BENCHES=($BENCHES_INPUT)
fi

# shellcheck disable=SC2206
MODES=($MODES_INPUT)

sanitize() {
  echo "$1" | sed -E 's/[^A-Za-z0-9_\-]+/_/g'
}

now_ns() {
  date +%s%N
}

elapsed_sec() {
  awk -v s="$1" -v e="$2" 'BEGIN { printf "%.3f", (e - s) / 1000000000.0 }'
}

ensure_build() {
  if [ -x "$ROOT_DIR/abc" ]; then
    return 0
  fi
  echo "[build] make -j${BUILD_JOBS}"
  (cd "$ROOT_DIR" && make -j"$BUILD_JOBS")
}

extract_area_delay() {
  local log_file="$1"
  local line area delay
  line=$(grep -E "area =" "$log_file" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')
  if [ -z "$line" ]; then
    echo ","
    return 0
  fi
  area=$(echo "$line" | sed -E 's/.*area = *([0-9.]+).*/\1/')
  delay=$(echo "$line" | sed -E 's/.*delay = *([0-9.]+).*/\1/')
  echo "$area,$delay"
}

run_abc_file() {
  local cmd_file="$1"
  local log_file="$2"
  "$ROOT_DIR/abc" -f "$cmd_file" > "$log_file" 2>&1
}

run_stats_flow() {
  local bench_path="$1"
  local flow_name="$2"
  local extra_cmds="$3"
  local work_dir="$4"

  local cmd_file log_file start_ns end_ns status area_delay area delay
  cmd_file="$work_dir/${flow_name}_stats.scr"
  log_file="$work_dir/${flow_name}_stats.log"

  cat > "$cmd_file" <<EOF
read_lib $LIB_FILE
read_aiger $bench_path
$extra_cmds
map
ps
quit
EOF

  start_ns=$(now_ns)
  if run_abc_file "$cmd_file" "$log_file"; then
    status=0
  else
    status=$?
  fi
  end_ns=$(now_ns)
  rm -f "$cmd_file"
  area_delay=$(extract_area_delay "$log_file")
  area=${area_delay%,*}
  delay=${area_delay#*,}
  echo "$status,$area,$delay,$(elapsed_sec "$start_ns" "$end_ns"),$log_file"
}

run_opt_flow() {
  local bench_path="$1"
  local mode="$2"
  local work_dir="$3"

  local csv_file opt_aig cmd_file log_file start_ns end_ns status
  csv_file="$work_dir/${mode}.csv"
  opt_aig="$work_dir/${mode}.aig"
  cmd_file="$work_dir/${mode}_opt.scr"
  log_file="$work_dir/${mode}_opt.log"

  cat > "$cmd_file" <<EOF
read_lib $LIB_FILE
read_aiger $bench_path
phymid -C "$csv_file" -n $ROUNDS -k $PART_SIZE -A $mode $PHYREAD_ARGS $PHYOPT_EXTRA_ARGS
strash
write_aiger "$opt_aig"
quit
EOF

  start_ns=$(now_ns)
  if run_abc_file "$cmd_file" "$log_file"; then
    status=0
  else
    status=$?
  fi
  end_ns=$(now_ns)
  rm -f "$cmd_file"

  echo "$status,$csv_file,$opt_aig,$(elapsed_sec "$start_ns" "$end_ns"),$log_file"
}

extract_baseline_map() {
  local bench_path="$1"
  local work_dir="$2"
  local base_map
  local base_resyn2_map

  base_map=$(run_stats_flow "$bench_path" "baseline_map" "" "$work_dir")
  base_resyn2_map=$(run_stats_flow "$bench_path" "baseline_resyn2_map" "resyn2" "$work_dir")

  echo "$base_map|$base_resyn2_map"
}

impr_pct() {
  local before="$1"
  local after="$2"
  awk -v b="$before" -v a="$after" 'BEGIN { if (b <= 0) { printf ""; exit } printf "%.4f", (b - a) * 100.0 / b }'
}

diff_delay() {
  local before="$1"
  local after="$2"
  awk -v b="$before" -v a="$after" 'BEGIN { printf "%.4f", a - b }'
}

extract_accept_stats() {
  local log_file="$1"
  local line accepted rejected tried rate
  line=$(grep -E "phyopt: done, accepted=[0-9]+ rejected=[0-9]+" "$log_file" | tail -n 1 || true)
  if [ -z "$line" ]; then
    echo ",,,"
    return 0
  fi
  accepted=$(echo "$line" | sed -E 's/.*accepted=([0-9]+).*/\1/')
  rejected=$(echo "$line" | sed -E 's/.*rejected=([0-9]+).*/\1/')
  tried=$(awk -v a="$accepted" -v r="$rejected" 'BEGIN { print a + r }')
  rate=$(awk -v t="$tried" -v a="$accepted" 'BEGIN { if (t <= 0) printf "0.00"; else printf "%.2f", (100.0 * a / t) }')
  echo "$accepted,$rejected,$tried,$rate"
}

bench_found=0
for b in "${BENCHES[@]}"; do
  if [ -f "$BENCH_DIR/$b.aig" ]; then
    bench_found=1
    break
  fi
done

if [ "$bench_found" -eq 0 ]; then
  echo "[error] no benchmark AIGs found under $BENCH_DIR"
  exit 1
fi

if [ ! -f "$LIB_FILE" ]; then
  echo "[error] liberty not found: $LIB_FILE"
  exit 1
fi

ensure_build

echo "bench,accept_mode,flow,status,area,delay,opt_runtime_sec,post_runtime_sec,total_runtime_sec,delta_area_vs_raw_map_pct,delta_delay_vs_raw_map,delta_area_vs_raw_resyn2_map_pct,delta_delay_vs_raw_resyn2_map,accepted_count,rejected_count,tried_count,accept_rate_pct,opt_log,post_log,opt_aig" > "$SUMMARY_CSV"
echo "[info] bench_dir=$BENCH_DIR"
echo "[info] result_dir=$RESULT_DIR"
echo "[info] liberty=$LIB_FILE"
echo "[info] rounds=$ROUNDS part_size=$PART_SIZE"
echo "[info] phyread_args=$PHYREAD_ARGS"
echo "[info] phyopt_extra_args=$PHYOPT_EXTRA_ARGS"
echo "[info] modes=${MODES[*]}"
echo "[info] benches=${BENCHES[*]}"

for bench in "${BENCHES[@]}"; do
  bench_path="$BENCH_DIR/$bench.aig"
  if [ ! -f "$bench_path" ]; then
    echo "[skip] missing benchmark: $bench_path"
    continue
  fi

  bench_key=$(sanitize "$bench")
  bench_dir="$RESULT_DIR/$bench_key"
  mkdir -p "$bench_dir"

  echo "[bench] $bench"
  base_map_log=$(run_stats_flow "$bench_path" "raw_map" "" "$bench_dir")
  base_resyn_log=$(run_stats_flow "$bench_path" "raw_resyn2_map" "resyn2" "$bench_dir")

  IFS=',' read -r base_map_status base_map_area base_map_delay base_map_rt base_map_logfile <<< "$base_map_log"
  IFS=',' read -r base_resyn_status base_resyn_area base_resyn_delay base_resyn_rt base_resyn_logfile <<< "$base_resyn_log"

  base_map_da_raw="0.0000"
  base_map_dd_raw="0.0000"
  base_map_da_resyn=$(impr_pct "$base_resyn_area" "$base_map_area")
  base_map_dd_resyn=$(diff_delay "$base_resyn_delay" "$base_map_delay")
  base_resyn_da_raw=$(impr_pct "$base_map_area" "$base_resyn_area")
  base_resyn_dd_raw=$(diff_delay "$base_map_delay" "$base_resyn_delay")
  base_resyn_da_resyn="0.0000"
  base_resyn_dd_resyn="0.0000"

  echo "$bench,baseline,raw_map,$([ "$base_map_status" = 0 ] && echo PASS || echo FAIL),$base_map_area,$base_map_delay,0.000,$base_map_rt,$base_map_rt,$base_map_da_raw,$base_map_dd_raw,$base_map_da_resyn,$base_map_dd_resyn,0,0,0,0.00,$base_map_logfile,$base_map_logfile,$bench_path" >> "$SUMMARY_CSV"
  echo "$bench,baseline,raw_resyn2_map,$([ "$base_resyn_status" = 0 ] && echo PASS || echo FAIL),$base_resyn_area,$base_resyn_delay,0.000,$base_resyn_rt,$base_resyn_rt,$base_resyn_da_raw,$base_resyn_dd_raw,$base_resyn_da_resyn,$base_resyn_dd_resyn,0,0,0,0.00,$base_resyn_logfile,$base_resyn_logfile,$bench_path" >> "$SUMMARY_CSV"

  for mode in "${MODES[@]}"; do
    if [ "$mode" != "global" ] && [ "$mode" != "window" ]; then
      echo "[warn] skip unsupported mode: $mode"
      continue
    fi

    mode_dir="$bench_dir/$mode"
    mkdir -p "$mode_dir"

    opt_pack=$(run_opt_flow "$bench_path" "$mode" "$mode_dir")
    IFS=',' read -r opt_status opt_csv opt_aig opt_rt opt_log <<< "$opt_pack"

    if [ "$opt_status" != "0" ] || [ ! -f "$opt_aig" ]; then
      echo "[fail] $bench/$mode optimization failed"
      continue
    fi

    map_flow=$(run_stats_flow "$opt_aig" "${mode}_map" "" "$mode_dir")
    IFS=',' read -r map_status map_area map_delay map_rt map_log <<< "$map_flow"

    map_total=$(awk -v a="$opt_rt" -v b="$map_rt" 'BEGIN { printf "%.3f", a + b }')

    map_da_raw=$(impr_pct "$base_map_area" "$map_area")
    map_dd_raw=$(diff_delay "$base_map_delay" "$map_delay")
    map_da_resyn=$(impr_pct "$base_resyn_area" "$map_area")
    map_dd_resyn=$(diff_delay "$base_resyn_delay" "$map_delay")

    IFS=',' read -r acc_count rej_count tried_count acc_rate <<< "$(extract_accept_stats "$opt_log")"
    echo "$bench,$mode,phymid_${mode}_map,$([ "$map_status" = 0 ] && echo PASS || echo FAIL),$map_area,$map_delay,$opt_rt,$map_rt,$map_total,$map_da_raw,$map_dd_raw,$map_da_resyn,$map_dd_resyn,$acc_count,$rej_count,$tried_count,$acc_rate,$opt_log,$map_log,$opt_aig" >> "$SUMMARY_CSV"

    if [ "$KEEP_LOGS" = "0" ]; then
      rm -f "$map_log" "$opt_log" "$opt_csv"
    fi
  done

  if [ "$KEEP_LOGS" = "0" ]; then
    rm -f "$bench_dir/raw_map_stats.log" "$bench_dir/raw_resyn2_map_stats.log"
  fi

done

echo "[done] summary: $SUMMARY_CSV"
