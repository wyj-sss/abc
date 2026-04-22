#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_DIR="$ROOT_DIR/my_work/grouped_opt_stage1"

RUN_GROUP="${RUN_GROUP:-${1:-}}"
if [ -z "$RUN_GROUP" ]; then
  case "${GROUP:-}" in
    A|B|C|D|U_mid|U_small|L|M|H) RUN_GROUP="$GROUP" ;;
  esac
fi
if [ -z "$RUN_GROUP" ]; then
  echo "[error] RUN_GROUP is required. Usage: RUN_GROUP=L bash run_group_experiments.sh" >&2
  exit 1
fi

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
RESULT_DIR="${RESULT_DIR:-$BASE_DIR/results/$RUN_TAG/$RUN_GROUP}"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

BENCH_LIST="${BENCH_LIST:-$BASE_DIR/groups/group_${RUN_GROUP}.txt}"
CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_${RUN_GROUP}.txt}"

LIB_FILE="${LIB_FILE:-$ROOT_DIR/my_work/c17_work/NangateOpenCellLibrary_typical.lib}"
ROUNDS="${ROUNDS:-1}"
BUILD_JOBS="${BUILD_JOBS:-1}"

# Optional execution guards for strategy-driven runs.
MAX_CASES="${MAX_CASES:-0}"
MAX_SECONDS="${MAX_SECONDS:-0}"
EARLY_STOP_FAILS="${EARLY_STOP_FAILS:-0}"
EARLY_STOP_DELAY_REJECT_CASES="${EARLY_STOP_DELAY_REJECT_CASES:-0}"
STRATEGY_NAME="${STRATEGY_NAME:-manual}"

# Global default best config.
DEF_I="${DEF_I:-0.50}"
DEF_P="${DEF_P:-0.40}"
DEF_F="${DEF_F:-0.05}"
DEF_G="${DEF_G:-0.05}"
DEF_K="${DEF_K:-40}"
DEF_OPT_L="${DEF_OPT_L:-0.25}"
DEF_OPT_H="${DEF_OPT_H:-0.90}"

# Feature-adaptive tuning driven by reject profile.
USE_FEATURE_ADAPT="${USE_FEATURE_ADAPT:-0}"
FEATURE_PROFILE_CSV="${FEATURE_PROFILE_CSV:-$ROOT_DIR/my_work/reject_grouping/results/stageC_base/bench_reject_profile.csv}"
ADAPT_STRENGTH="${ADAPT_STRENGTH:-medium}" # light|medium|strong

mkdir -p "$RESULT_DIR"

if [ ! -f "$LIB_FILE" ]; then
  echo "[error] liberty not found: $LIB_FILE" >&2
  exit 1
fi
if [ ! -f "$BENCH_LIST" ]; then
  echo "[error] bench list not found: $BENCH_LIST" >&2
  exit 1
fi
if [ ! -f "$CASE_LIST" ]; then
  echo "[error] case list not found: $CASE_LIST" >&2
  exit 1
fi

if [ ! -x "$ROOT_DIR/abc" ]; then
  echo "[build] make -j${BUILD_JOBS}" >&2
  if ! (cd "$ROOT_DIR" && make -j"$BUILD_JOBS"); then
    echo "[error] build failed" >&2
    exit 1
  fi
fi

sanitize() {
  echo "$1" | sed -E 's/[^A-Za-z0-9_\-]+/_/g'
}

extract_area_delay() {
  local aig="$1"
  local tmp="/tmp/gs1_ps_$$.log"
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

f_ge() {
  local x="$1"
  local y="$2"
  awk -v a="$x" -v b="$y" 'BEGIN{exit (a>=b)?0:1}'
}

get_profile_vals() {
  local bench="$1"
  [ -f "$FEATURE_PROFILE_CSV" ] || return 1
  awk -F',' -v b="$bench" 'NR>1 && $1==b {print $3","$7","$8","$9; exit}' "$FEATURE_PROFILE_CSV"
}

adapt_params_by_profile() {
  local grp="$1"
  local bench="$2"
  local case_name="$3"
  local aL="$4"
  local aM="$5"
  local aH="$6"
  local kV="$7"
  local oL="$8"
  local oH="$9"
  local iW="${10}"
  local pW="${11}"
  local fW="${12}"
  local gW="${13}"

  local vals rej_total runtime_pct area_pct delay_pct
  vals="$(get_profile_vals "$bench" || true)"
  if [ -z "$vals" ]; then
    echo "$aL $aM $aH $kV $oL $oH $iW $pW $fW $gW none"
    return 0
  fi
  IFS=',' read -r rej_total runtime_pct area_pct delay_pct <<< "$vals"

  local mode="none"
  if f_ge "$delay_pct" "5.0"; then
    mode="delay_guard"
  elif f_ge "$area_pct" "45.0"; then
    mode="area_push"
  elif f_ge "$runtime_pct" "35.0"; then
    mode="runtime_trim"
  elif f_ge "$area_pct" "35.0"; then
    mode="area_light"
  fi

  # Low-sample reject profiles are noisy: keep parameters conservative.
  if ! f_ge "$rej_total" "30"; then
    mode="small_sample"
  fi

  case "$mode" in
    area_push)
      if [ "$grp" = "B" ] || [ "$grp" = "C" ]; then
        aL="0.10"; aM="0.40"; aH="0.70"
        kV="50"; oL="0.22"; oH="0.92"
        iW="0.55"; pW="0.40"; fW="0.03"; gW="0.02"
      else
        aL="0.12"; aM="0.42"; aH="0.72"
        kV="45"; oL="0.23"; oH="0.91"
      fi
      ;;
    area_light)
      aL="0.15"; aM="0.45"; aH="0.75"
      kV="42"; oL="0.24"; oH="0.91"
      ;;
    runtime_trim)
      aL="0.22"; aM="0.52"; aH="0.82"
      kV="28"; oL="0.30"; oH="0.88"
      iW="0.48"; pW="0.40"; fW="0.06"; gW="0.06"
      ;;
    delay_guard)
      aL="0.25"; aM="0.55"; aH="0.85"
      kV="26"; oL="0.32"; oH="0.92"
      iW="0.50"; pW="0.40"; fW="0.05"; gW="0.05"
      ;;
    small_sample)
      kV="34"; oL="0.28"; oH="0.90"
      ;;
  esac

  if [ "$ADAPT_STRENGTH" = "light" ] && [ "$mode" = "area_push" ]; then
    kV="45"
    oL="0.23"
  fi
  if [ "$ADAPT_STRENGTH" = "strong" ] && [ "$mode" = "area_push" ]; then
    kV="55"
    oL="0.20"
    oH="0.93"
  fi

  echo "$aL $aM $aH $kV $oL $oH $iW $pW $fW $gW $mode"
}

run_case() {
  local bench_path="$1"
  local case_name="$2"
  local aL="$3"
  local aM="$4"
  local aH="$5"
  local kV="$6"
  local oL="$7"
  local oH="$8"
  local iW="$9"
  local pW="${10}"
  local fW="${11}"
  local gW="${12}"

  local bench_base bench_key bench_dir out_aig out_csv out_log cmd_file
  bench_base="$(basename "$bench_path" .aig)"
  bench_key="$(sanitize "$bench_base")"
  bench_dir="$RESULT_DIR/$bench_key"
  mkdir -p "$bench_dir"

  out_aig="$bench_dir/${bench_key}_${case_name}.aig"
  out_csv="$bench_dir/${bench_key}_${case_name}.csv"
  out_log="$bench_dir/${bench_key}_${case_name}.log"
  cmd_file="/tmp/gs1_${bench_key}_${case_name}_$$.scr"

  cat > "$cmd_file" <<EOF
read_liberty $LIB_FILE
read_aiger $bench_path
map_oto
mapper_extract -o $out_csv
phyread -L $aL -M $aM -H $aH -i $iW -p $pW -f $fW -g $gW $out_csv
phyopt -n $ROUNDS -k $kV -L $oL -H $oH
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
  phyread_args="-L $aL -M $aM -H $aH -i $iW -p $pW -f $fW -g $gW"
  phyopt_args="-k $kV -L $oL -H $oH"

  echo "$RUN_GROUP,$bench_base,$case_name,$status,$before_stats,$after_stats,$accepted,$rejected,$top_high,$top_low,$top_mid,$rr_rt,$rr_delay,$rr_area,$aL,$aM,$aH,$kV,$oL,$oH,$iW,$pW,$fW,$gW,\"$phyread_args\",\"$phyopt_args\",$out_log" >> "$SUMMARY_CSV"
}

BENCH_TMP="/tmp/gs1_benches_${RUN_GROUP}_$$.txt"
CASE_TMP="/tmp/gs1_cases_${RUN_GROUP}_$$.txt"
awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$BENCH_LIST" > "$BENCH_TMP"
awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$CASE_LIST" > "$CASE_TMP"

bench_cnt=$(wc -l < "$BENCH_TMP")
case_cnt=$(wc -l < "$CASE_TMP")
total=$((bench_cnt * case_cnt))

echo "group,bench,case,status,before_area,before_delay,after_area,after_delay,accepted,rejected,topk_hit_high,topk_hit_low,topk_hit_mid,reject_runtime,reject_delay,reject_area,alpha_low,alpha_mid,alpha_high,k,opt_low,opt_high,w_i,w_p,w_f,w_g,phyread_args,phyopt_args,log_file" > "$SUMMARY_CSV"
echo "[info] group=$RUN_GROUP benches=$bench_cnt cases=$case_cnt total=$total" >&2
echo "[info] result_dir=$RESULT_DIR" >&2
echo "[info] strategy=$STRATEGY_NAME max_cases=$MAX_CASES max_seconds=$MAX_SECONDS early_stop_fails=$EARLY_STOP_FAILS early_stop_delay_reject_cases=$EARLY_STOP_DELAY_REJECT_CASES" >&2

done_cases=0
fail_cases=0
delay_reject_cases=0
start_ts=$(date +%s)
stop_now=0
while IFS= read -r bench_name || [ -n "$bench_name" ]; do
  [ "$stop_now" -eq 1 ] && break
  bench_path="$(resolve_bench_path "$bench_name" || true)"
  if [ -z "$bench_path" ]; then
    echo "[warn] bench not found: $bench_name" >&2
    continue
  fi

  while IFS=' ' read -r cname aL aM aH kV oL oH iW pW fW gW || [ -n "$cname" ]; do
    [ "$stop_now" -eq 1 ] && break
    if [ "$MAX_CASES" -gt 0 ] && [ "$done_cases" -ge "$MAX_CASES" ]; then
      echo "[stop] reached MAX_CASES=$MAX_CASES" >&2
      stop_now=1
      break
    fi
    if [ "$MAX_SECONDS" -gt 0 ]; then
      now_ts=$(date +%s)
      elapsed=$((now_ts - start_ts))
      if [ "$elapsed" -ge "$MAX_SECONDS" ]; then
        echo "[stop] reached MAX_SECONDS=$MAX_SECONDS (elapsed=$elapsed)" >&2
        stop_now=1
        break
      fi
    fi

    done_cases=$((done_cases + 1))
    aL="${aL:-0.20}"; aM="${aM:-0.50}"; aH="${aH:-0.80}"
    kV="${kV:-$DEF_K}"; oL="${oL:-$DEF_OPT_L}"; oH="${oH:-$DEF_OPT_H}"
    iW="${iW:-$DEF_I}"; pW="${pW:-$DEF_P}"; fW="${fW:-$DEF_F}"; gW="${gW:-$DEF_G}"

    adapt_mode="none"
    if [ "$USE_FEATURE_ADAPT" = "1" ] && [ -f "$FEATURE_PROFILE_CSV" ]; then
      read -r aL aM aH kV oL oH iW pW fW gW adapt_mode <<< "$(adapt_params_by_profile "$RUN_GROUP" "$bench_name" "$cname" "$aL" "$aM" "$aH" "$kV" "$oL" "$oH" "$iW" "$pW" "$fW" "$gW")"
    fi

    echo "[progress][$RUN_GROUP] $done_cases/$total bench=$bench_name case=$cname adapt=$adapt_mode" >&2
    run_case "$bench_path" "$cname" "$aL" "$aM" "$aH" "$kV" "$oL" "$oH" "$iW" "$pW" "$fW" "$gW"

    last_status=$(tail -n 1 "$SUMMARY_CSV" | awk -F',' '{print $4}')
    last_rdelay=$(tail -n 1 "$SUMMARY_CSV" | awk -F',' '{print $15+0}')
    if [ "$last_status" = "FAIL" ]; then
      fail_cases=$((fail_cases + 1))
    fi
    if [ "$last_rdelay" -gt 0 ]; then
      delay_reject_cases=$((delay_reject_cases + 1))
    fi

    if [ "$EARLY_STOP_FAILS" -gt 0 ] && [ "$fail_cases" -ge "$EARLY_STOP_FAILS" ]; then
      echo "[stop] early stop by FAIL count: $fail_cases >= $EARLY_STOP_FAILS" >&2
      stop_now=1
      break
    fi
    if [ "$EARLY_STOP_DELAY_REJECT_CASES" -gt 0 ] && [ "$delay_reject_cases" -ge "$EARLY_STOP_DELAY_REJECT_CASES" ]; then
      echo "[stop] early stop by delay-reject-case count: $delay_reject_cases >= $EARLY_STOP_DELAY_REJECT_CASES" >&2
      stop_now=1
      break
    fi
  done < "$CASE_TMP"
done < "$BENCH_TMP"

rm -f "$BENCH_TMP" "$CASE_TMP"
echo "[done] $SUMMARY_CSV" >&2
echo "[done] executed_cases=$done_cases fail_cases=$fail_cases delay_reject_cases=$delay_reject_cases" >&2
