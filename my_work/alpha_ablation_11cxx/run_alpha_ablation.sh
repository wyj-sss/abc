#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
AA_DIR="$ROOT_DIR/my_work/alpha_ablation_11cxx"

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
RESULT_DIR="${RESULT_DIR:-$AA_DIR/results/$RUN_TAG}"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

LIB_FILE="${LIB_FILE:-$ROOT_DIR/my_work/c17_work/NangateOpenCellLibrary_typical.lib}"
ROUNDS="${ROUNDS:-1}"
K_VAL="${K_VAL:-40}"
BUILD_JOBS="${BUILD_JOBS:-1}"

# Fixed best config (from Stage C base)
I_W="${I_W:-0.50}"
P_W="${P_W:-0.40}"
F_W="${F_W:-0.05}"
G_W="${G_W:-0.05}"
PHYOPT_L="${PHYOPT_L:-0.25}"
PHYOPT_H="${PHYOPT_H:-0.90}"

BENCH_LIST="${BENCH_LIST:-$ROOT_DIR/my_work/stageB_benches.txt}"
ALPHA_LIST="${ALPHA_LIST:-$AA_DIR/alpha_cases.txt}"

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

if [ ! -f "$ALPHA_LIST" ]; then
  echo "[error] alpha list not found: $ALPHA_LIST" >&2
  exit 1
fi

sanitize() {
  echo "$1" | sed -E 's/[^A-Za-z0-9_\-]+/_/g'
}

extract_area_delay() {
  local aig="$1"
  local tmp="/tmp/alpha_ps_$$.log"
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
  for p in \
    "$ROOT_DIR/my_work/c17_work/$name.aig" \
    "$ROOT_DIR/my_work/c499_work/$name.aig" \
    "$ROOT_DIR/my_work/c880_work/$name.aig" \
    "$ROOT_DIR/my_work/xiaorong_aig/$name.aig"; do
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
  local a_l="$3"
  local a_m="$4"
  local a_h="$5"

  local bench_base bench_key bench_dir out_aig out_csv out_log cmd_file
  bench_base="$(basename "$bench_path" .aig)"
  bench_key="$(sanitize "$bench_base")"
  bench_dir="$RESULT_DIR/$bench_key"
  mkdir -p "$bench_dir"

  out_aig="$bench_dir/${bench_key}_${case_name}.aig"
  out_csv="$bench_dir/${bench_key}_${case_name}.csv"
  out_log="$bench_dir/${bench_key}_${case_name}.log"
  cmd_file="/tmp/alpha_${bench_key}_${case_name}_$$.scr"

  cat > "$cmd_file" <<EOF
read_liberty $LIB_FILE
read_aiger $bench_path
map_oto
mapper_extract -o $out_csv
phyread -L $a_l -M $a_m -H $a_h -i $I_W -p $P_W -f $F_W -g $G_W $out_csv
phyopt -n $ROUNDS -k $K_VAL -L $PHYOPT_L -H $PHYOPT_H
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
  phyread_args="-L $a_l -M $a_m -H $a_h -i $I_W -p $P_W -f $F_W -g $G_W"
  phyopt_args="-k $K_VAL -L $PHYOPT_L -H $PHYOPT_H"

  echo "$bench_base,$case_name,$status,$before_stats,$after_stats,$accepted,$rejected,$top_high,$top_low,$top_mid,$rr_rt,$rr_delay,$rr_area,$a_l,$a_m,$a_h,\"$phyread_args\",\"$phyopt_args\",$out_log" >> "$SUMMARY_CSV"
}

BENCH_TMP="/tmp/alpha_benches_$$.txt"
ALPHA_TMP="/tmp/alpha_cases_$$.txt"

awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$BENCH_LIST" > "$BENCH_TMP"
awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$ALPHA_LIST" > "$ALPHA_TMP"

bench_cnt=$(wc -l < "$BENCH_TMP")
alpha_cnt=$(wc -l < "$ALPHA_TMP")
total_cases=$((bench_cnt * alpha_cnt))

echo "bench,case,status,before_area,before_delay,after_area,after_delay,accepted,rejected,topk_hit_high,topk_hit_low,topk_hit_mid,reject_runtime,reject_delay,reject_area,alpha_low,alpha_mid,alpha_high,phyread_args,phyopt_args,log_file" > "$SUMMARY_CSV"
echo "[info] fixed struct weights: i=$I_W p=$P_W f=$F_W g=$G_W" >&2
echo "[info] fixed phyopt args: k=$K_VAL L=$PHYOPT_L H=$PHYOPT_H" >&2
echo "[info] benches=$bench_cnt alpha_cases=$alpha_cnt total=$total_cases" >&2
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

  alpha_idx=0
  while IFS=' ' read -r case_name a_l a_m a_h || [ -n "$case_name" ]; do
    alpha_idx=$((alpha_idx + 1))
    done_cases=$((done_cases + 1))

    if ! awk -v l="$a_l" -v m="$a_m" -v h="$a_h" 'BEGIN{ok=(l>=0&&l<=1&&m>=0&&m<=1&&h>=0&&h<=1&&l<=m&&m<=h); exit(ok?0:1)}'; then
      echo "[warn] skip invalid alpha triple for case=$case_name : $a_l/$a_m/$a_h" >&2
      continue
    fi

    echo "[progress] $done_cases/$total_cases bench=$bench_name ($bench_idx/$bench_cnt) alpha=$case_name ($alpha_idx/$alpha_cnt)" >&2
    run_case "$bench_path" "$case_name" "$a_l" "$a_m" "$a_h"
  done < "$ALPHA_TMP"
done < "$BENCH_TMP"

rm -f "$BENCH_TMP" "$ALPHA_TMP"
echo "[done] summary: $SUMMARY_CSV" >&2
