#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="$ROOT_DIR/my_work"
STAGEC_DIR="$WORK_DIR/stageC_full_validation"

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
RESULT_DIR="${RESULT_DIR:-$STAGEC_DIR/results/$RUN_TAG}"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

LIB_FILE="${LIB_FILE:-$WORK_DIR/c17_work/NangateOpenCellLibrary_typical.lib}"
ROUNDS="${ROUNDS:-1}"
BUILD_JOBS="${BUILD_JOBS:-1}"

CASE_LIST="${CASE_LIST:-$STAGEC_DIR/cases_stageC.txt}"
BENCH_ALLOW_REGEX="${BENCH_ALLOW_REGEX:-}"
BENCH_LIMIT="${BENCH_LIMIT:-0}"

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

if [ ! -f "$CASE_LIST" ]; then
  echo "[error] case list not found: $CASE_LIST" >&2
  exit 1
fi

sanitize() {
  echo "$1" | sed -E 's/[^A-Za-z0-9_\-]+/_/g'
}

extract_area_delay() {
  local aig="$1"
  local tmp="/tmp/stageC_ps_$$.log"
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
  local out_list="$1"
  : > "$out_list"

  for fixed in "$WORK_DIR/c17_work/c17.aig" "$WORK_DIR/c499_work/c499.aig" "$WORK_DIR/c880_work/c880.aig"; do
    if [ -f "$fixed" ]; then
      echo "$fixed" >> "$out_list"
    fi
  done

  if [ -d "$WORK_DIR/xiaorong_aig" ]; then
    find "$WORK_DIR/xiaorong_aig" -maxdepth 1 -type f -name "*.aig" | sort >> "$out_list"
  fi

  awk '!seen[$0]++' "$out_list" > "${out_list}.dedup"
  mv "${out_list}.dedup" "$out_list"
}

run_case() {
  local bench_path="$1"
  local case_name="$2"
  local i_w="$3"
  local p_w="$4"
  local f_w="$5"
  local g_w="$6"
  local l_t="$7"
  local h_t="$8"
  local k_v="$9"

  local bench_base bench_key bench_dir out_aig out_csv out_log cmd_file
  bench_base="$(basename "$bench_path" .aig)"
  bench_key="$(sanitize "$bench_base")"
  bench_dir="$RESULT_DIR/$bench_key"
  mkdir -p "$bench_dir"

  out_aig="$bench_dir/${bench_key}_${case_name}.aig"
  out_csv="$bench_dir/${bench_key}_${case_name}.csv"
  out_log="$bench_dir/${bench_key}_${case_name}.log"
  cmd_file="/tmp/stageC_${bench_key}_${case_name}_$$.scr"

  cat > "$cmd_file" <<EOF
read_liberty $LIB_FILE
read_aiger $bench_path
map_oto
mapper_extract -o $out_csv
phyread -i $i_w -p $p_w -f $f_w -g $g_w $out_csv
phyopt -n $ROUNDS -k $k_v -L $l_t -H $h_t
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

  local before_stats after_stats
  before_stats=$(extract_area_delay "$bench_path")
  after_stats=$(extract_area_delay "$out_aig")

  local accepted rejected top_high top_low top_mid rr_rt rr_delay rr_area
  accepted=$(grep -E "phyopt: done, accepted=" "$out_log" | tail -n1 | sed -E 's/.*accepted=([0-9]+).*/\1/')
  rejected=$(grep -E "phyopt: done, accepted=" "$out_log" | tail -n1 | sed -E 's/.*rejected=([0-9]+).*/\1/')
  top_high=$(grep -E "^  high:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  top_low=$(grep -E "^  low:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  top_mid=$(grep -E "^  mid:" "$out_log" | tail -n1 | sed -E 's/.*hit=([0-9.]+)%.*/\1/')
  rr_rt=$(grep -E "runtime_or_eval_fail" "$out_log" | tail -n1 | sed -E 's/.*: *([0-9]+).*/\1/')
  rr_delay=$(grep -E "delay_worse" "$out_log" | tail -n1 | sed -E 's/.*: *([0-9]+).*/\1/')
  rr_area=$(grep -E "area_worse" "$out_log" | head -n1 | sed -E 's/.*: *([0-9]+).*/\1/')

  local phyread_args phyopt_args
  phyread_args="-i $i_w -p $p_w -f $f_w -g $g_w"
  phyopt_args="-k $k_v -L $l_t -H $h_t"

  echo "$bench_base,$case_name,$status,$before_stats,$after_stats,$accepted,$rejected,$top_high,$top_low,$top_mid,$rr_rt,$rr_delay,$rr_area,\"$phyread_args\",\"$phyopt_args\",$out_log" >> "$SUMMARY_CSV"
}

BENCH_LIST="/tmp/stageC_benches_$$.txt"
CASE_TMP="/tmp/stageC_cases_$$.txt"
collect_benches "$BENCH_LIST"
awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$CASE_LIST" > "$CASE_TMP"

if [ -n "$BENCH_ALLOW_REGEX" ]; then
  awk -v re="$BENCH_ALLOW_REGEX" '{ b=$0; sub(/^.*\//,"",b); sub(/\.aig$/,"",b); if (b ~ re) print $0 }' "$BENCH_LIST" > "${BENCH_LIST}.flt"
  mv "${BENCH_LIST}.flt" "$BENCH_LIST"
fi

if [ "$BENCH_LIMIT" -gt 0 ]; then
  head -n "$BENCH_LIMIT" "$BENCH_LIST" > "${BENCH_LIST}.lim"
  mv "${BENCH_LIST}.lim" "$BENCH_LIST"
fi

bench_cnt=$(wc -l < "$BENCH_LIST")
case_cnt=$(wc -l < "$CASE_TMP")
total_cases=$((bench_cnt * case_cnt))

echo "bench,case,status,before_area,before_delay,after_area,after_delay,accepted,rejected,topk_hit_high,topk_hit_low,topk_hit_mid,reject_runtime,reject_delay,reject_area,phyread_args,phyopt_args,log_file" > "$SUMMARY_CSV"
echo "[info] benches=$bench_cnt cases=$case_cnt total=$total_cases" >&2
echo "[info] result_dir=$RESULT_DIR" >&2

done_cases=0
bench_idx=0
while IFS= read -r bench; do
  [ -z "$bench" ] && continue
  bench_idx=$((bench_idx + 1))
  bench_name="$(basename "$bench" .aig)"

  case_idx=0
  while IFS=' ' read -r case_name i_w p_w f_w g_w l_t h_t k_v || [ -n "$case_name" ]; do
    case_idx=$((case_idx + 1))
    done_cases=$((done_cases + 1))
    echo "[progress] $done_cases/$total_cases bench=$bench_name ($bench_idx/$bench_cnt) case=$case_name ($case_idx/$case_cnt)" >&2
    run_case "$bench" "$case_name" "$i_w" "$p_w" "$f_w" "$g_w" "$l_t" "$h_t" "$k_v"
  done < "$CASE_TMP"
done < "$BENCH_LIST"

rm -f "$BENCH_LIST" "$CASE_TMP"
echo "[done] summary: $SUMMARY_CSV" >&2
