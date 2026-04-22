#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$ROOT_DIR/my_work"
RESULT_DIR="$WORK_DIR/ablation_results"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

LIB_FILE="${LIB_FILE:-$WORK_DIR/c17_work/NangateOpenCellLibrary_typical.lib}"
ROUNDS="${ROUNDS:-1}"
PART_SIZE="${PART_SIZE:-30}"
BUILD_JOBS="${BUILD_JOBS:-1}"
BENCH_LIMIT="${BENCH_LIMIT:-0}"
CASE_FILTER="${CASE_FILTER:-}"
BENCH_ALLOW_REGEX="${BENCH_ALLOW_REGEX:-}"
BENCH_DEDUP_BY_NAME="${BENCH_DEDUP_BY_NAME:-0}"

mkdir -p "$RESULT_DIR"

if [ ! -f "$LIB_FILE" ]; then
  echo "[error] liberty not found: $LIB_FILE"
  exit 1
fi

if [ ! -x "$ROOT_DIR/abc" ]; then
  echo "[build] make -j${BUILD_JOBS}"
  if ! (cd "$ROOT_DIR" && make -j"$BUILD_JOBS"); then
    echo "[error] build failed"
    exit 1
  fi
fi

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

collect_benches() {
  local list_file="$1"
  : > "$list_file"

  for fixed in "$WORK_DIR/c17_work/c17.aig" "$WORK_DIR/c499_work/c499.aig" "$WORK_DIR/c880_work/c880.aig"; do
    if [ -f "$fixed" ]; then
      echo "$fixed" >> "$list_file"
    fi
  done

  if [ -d "$WORK_DIR/xiaorong_aig" ]; then
    find "$WORK_DIR/xiaorong_aig" -maxdepth 1 -type f -name "*.aig" | sort >> "$list_file"
  fi

  awk '!seen[$0]++' "$list_file" > "${list_file}.dedup"
  mv "${list_file}.dedup" "$list_file"
}

run_case() {
  local bench_path="$1"
  local case_name="$2"
  local phyread_args="$3"
  local phyopt_args="$4"

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
phyread $phyread_args $out_csv
phyopt -n $ROUNDS -k $PART_SIZE $phyopt_args
strash
write_aiger $out_aig
cec -n $bench_path $out_aig
quit
EOF

  "$ROOT_DIR/abc" -f "$cmd_file" > "$out_log" 2>&1
  local rc=$?
  rm -f "$cmd_file"

  local status="PASS"
  if [ $rc -ne 0 ] || ! grep -q "Networks are equivalent" "$out_log"; then
    status="FAIL"
  fi

  local before after before_area before_delay after_area after_delay
  before="$(extract_area_delay "$bench_path")"
  after="$(extract_area_delay "$out_aig")"
  before_area="${before%,*}"; before_delay="${before#*,}"
  after_area="${after%,*}"; after_delay="${after#*,}"

  local accepted rejected top_high top_mid top_low rr_area rr_delay rr_rt
  accepted=$(grep -E "phyopt: done, accepted=" "$out_log" | tail -n1 | sed -E 's/.*accepted=([0-9]+).*/\1/')
  rejected=$(grep -E "phyopt: done, accepted=" "$out_log" | tail -n1 | sed -E 's/.*rejected=([0-9]+).*/\1/')
  top_high=$(grep -E "^  high:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  top_low=$(grep -E "^  low:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  top_mid=$(grep -E "^  mid:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  rr_rt=$(grep -E "runtime_or_eval_fail" "$out_log" | tail -n1 | sed -E 's/.*: *([0-9]+).*/\1/')
  rr_delay=$(grep -E "delay_worse" "$out_log" | tail -n1 | sed -E 's/.*: *([0-9]+).*/\1/')
  rr_area=$(grep -E "area_worse" "$out_log" | head -n1 | sed -E 's/.*: *([0-9]+).*/\1/')

  echo "${bench_base},${case_name},${status},${before_area},${before_delay},${after_area},${after_delay},${accepted},${rejected},${top_high},${top_low},${top_mid},${rr_rt},${rr_delay},${rr_area},\"${phyread_args}\",\"${phyopt_args}\",${out_log}" >> "$SUMMARY_CSV"
}

# case_name|phyread_args|phyopt_args
CASES=(
  "baseline||"
  "no_inv_chain|-i 0 -p 0.3 -f 0.2 -g 0.1|"
  "no_pair_collapse|-i 0.4 -p 0 -f 0.2 -g 0.1|"
  "no_fanout_ease|-i 0.4 -p 0.3 -f 0 -g 0.1|"
  "no_gate_score|-i 0.4 -p 0.3 -f 0.2 -g 0|"
  "thresh_tight||-L 0.20 -H 0.90"
  "thresh_loose||-L 0.40 -H 0.70"
  "alpha_slack_heavy|-L 0.50 -M 0.70 -H 0.90|"
  "alpha_struct_heavy|-L 0.10 -M 0.30 -H 0.50|"
)

BENCH_LIST="/tmp/ablation_bench_list_$$.txt"
collect_benches "$BENCH_LIST"

echo "bench,case,status,before_area,before_delay,after_area,after_delay,accepted,rejected,topk_hit_high,topk_hit_low,topk_hit_mid,reject_runtime,reject_delay,reject_area,phyread_args,phyopt_args,log_file" > "$SUMMARY_CSV"

n=0
declare -A seen_bench_names
while IFS= read -r bench; do
  [ -z "$bench" ] && continue
  bench_base="$(basename "$bench" .aig)"
  if [ -n "$BENCH_ALLOW_REGEX" ]; then
    echo "$bench_base" | grep -Eq "$BENCH_ALLOW_REGEX" || continue
  fi
  if [ "$BENCH_DEDUP_BY_NAME" = "1" ]; then
    if [ -n "${seen_bench_names[$bench_base]+x}" ]; then
      continue
    fi
    seen_bench_names[$bench_base]=1
  fi
  n=$((n+1))
  if [ "$BENCH_LIMIT" -gt 0 ] && [ "$n" -gt "$BENCH_LIMIT" ]; then
    break
  fi
  echo "[bench] $bench"
  for item in "${CASES[@]}"; do
    IFS='|' read -r case_name phyread_args phyopt_args <<< "$item"
    if [ -n "$CASE_FILTER" ]; then
      echo "$case_name" | grep -Eq "$CASE_FILTER" || continue
    fi
    echo "  [case] $case_name"
    run_case "$bench" "$case_name" "$phyread_args" "$phyopt_args"
  done
done < "$BENCH_LIST"

rm -f "$BENCH_LIST"

echo "[done] summary: $SUMMARY_CSV"
