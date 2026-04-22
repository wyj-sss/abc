#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WORK_DIR="$ROOT_DIR/my_work"
CV_DIR="$WORK_DIR/crossval_3x3_11cxx"

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
RESULT_DIR="${RESULT_DIR:-$CV_DIR/results/$RUN_TAG}"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

LIB_FILE="${LIB_FILE:-$WORK_DIR/c17_work/NangateOpenCellLibrary_typical.lib}"
ROUNDS="${ROUNDS:-1}"
PART_SIZE="${PART_SIZE:-30}"
BUILD_JOBS="${BUILD_JOBS:-1}"

BENCH_LIST="${BENCH_LIST:-$CV_DIR/cv_benches_cxx11.txt}"
THRESH_LIST="${THRESH_LIST:-$CV_DIR/cv_thresholds_3.txt}"
WEIGHT_LIST="${WEIGHT_LIST:-$CV_DIR/cv_weights_3.txt}"

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

for f in "$BENCH_LIST" "$THRESH_LIST" "$WEIGHT_LIST"; do
  if [ ! -f "$f" ]; then
    echo "[error] list not found: $f" >&2
    exit 1
  fi
done

sanitize() {
  echo "$1" | sed -E 's/[^A-Za-z0-9_\-]+/_/g'
}

extract_area_delay() {
  local aig="$1"
  local tmp="/tmp/cv3x3_ps_$$.log"
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
  local thresh_name="$2"
  local l_t="$3"
  local h_t="$4"
  local weight_name="$5"
  local i_w="$6"
  local p_w="$7"
  local f_w="$8"
  local g_w="$9"

  local combo_name="${thresh_name}__${weight_name}"
  local bench_base bench_key bench_dir out_aig out_csv out_log cmd_file
  bench_base="$(basename "$bench_path" .aig)"
  bench_key="$(sanitize "$bench_base")"
  bench_dir="$RESULT_DIR/$bench_key"
  mkdir -p "$bench_dir"

  out_aig="$bench_dir/${bench_key}_${combo_name}.aig"
  out_csv="$bench_dir/${bench_key}_${combo_name}.csv"
  out_log="$bench_dir/${bench_key}_${combo_name}.log"
  cmd_file="/tmp/cv3x3_${bench_key}_${combo_name}_$$.scr"

  cat > "$cmd_file" <<EOF
read_liberty $LIB_FILE
read_aiger $bench_path
map_oto
mapper_extract -o $out_csv
phyread -i $i_w -p $p_w -f $f_w -g $g_w $out_csv
phyopt -n $ROUNDS -k $PART_SIZE -L $l_t -H $h_t
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
  phyopt_args="-L $l_t -H $h_t"

  echo "$bench_base,$combo_name,$status,$before_stats,$after_stats,$accepted,$rejected,$top_high,$top_low,$top_mid,$rr_rt,$rr_delay,$rr_area,\"$thresh_name\",\"$weight_name\",\"$phyread_args\",\"$phyopt_args\",$out_log" >> "$SUMMARY_CSV"
}

BENCH_TMP="/tmp/cv3x3_benches_$$.txt"
THRESH_TMP="/tmp/cv3x3_thresh_$$.txt"
WEIGHT_TMP="/tmp/cv3x3_weight_$$.txt"

awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$BENCH_LIST" > "$BENCH_TMP"
awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$THRESH_LIST" > "$THRESH_TMP"
awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$WEIGHT_LIST" > "$WEIGHT_TMP"

bench_cnt=$(wc -l < "$BENCH_TMP")
thresh_cnt=$(wc -l < "$THRESH_TMP")
weight_cnt=$(wc -l < "$WEIGHT_TMP")
total_cases=$((bench_cnt * thresh_cnt * weight_cnt))

echo "bench,combo,status,before_area,before_delay,after_area,after_delay,accepted,rejected,topk_hit_high,topk_hit_low,topk_hit_mid,reject_runtime,reject_delay,reject_area,thresh_name,weight_name,phyread_args,phyopt_args,log_file" > "$SUMMARY_CSV"
echo "[info] benches=$bench_cnt thresholds=$thresh_cnt weights=$weight_cnt total=$total_cases" >&2
echo "[info] result_dir=$RESULT_DIR" >&2

done_cases=0
bench_idx=0
while IFS= read -r bench_name || [ -n "$bench_name" ]; do
  bench_idx=$((bench_idx + 1))
  bench_path=$(resolve_bench_path "$bench_name")
  if [ -z "$bench_path" ]; then
    echo "[warn] bench not found: $bench_name" >&2
    continue
  fi

  while IFS=' ' read -r thresh_name l_t h_t || [ -n "$thresh_name" ]; do
    while IFS=' ' read -r weight_name i_w p_w f_w g_w || [ -n "$weight_name" ]; do
      done_cases=$((done_cases + 1))
      echo "[progress] $done_cases/$total_cases bench=$bench_name ($bench_idx/$bench_cnt) combo=${thresh_name}__${weight_name}" >&2
      run_case "$bench_path" "$thresh_name" "$l_t" "$h_t" "$weight_name" "$i_w" "$p_w" "$f_w" "$g_w"
    done < "$WEIGHT_TMP"
  done < "$THRESH_TMP"
done < "$BENCH_TMP"

rm -f "$BENCH_TMP" "$THRESH_TMP" "$WEIGHT_TMP"

echo "[done] summary: $SUMMARY_CSV" >&2
