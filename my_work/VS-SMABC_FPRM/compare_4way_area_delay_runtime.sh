#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ABC_BIN="${ABC_BIN:-$ROOT_DIR/abc}"
LIB_FILE="${LIB_FILE:-$ROOT_DIR/my_work/c17_work/NangateOpenCellLibrary_typical.lib}"
RAW_DIR="${RAW_DIR:-$ROOT_DIR/my_work/VS-SMABC_FPRM/aig_output_raw}"
OPT_DIR="${OPT_DIR:-$ROOT_DIR/my_work/VS-SMABC_FPRM/aig_output_opt}"

OUT_DIR="${OUT_DIR:-$ROOT_DIR/my_work/VS-SMABC_FPRM/compare_4way_out}"
LOG_DIR="$OUT_DIR/logs"
TMP_DIR="$OUT_DIR/tmp"
REPORT_CSV="$OUT_DIR/compare_4way_area_delay_runtime.csv"

# Keep defaults aligned with current fitted-function flow.
PHYMID_N="${PHYMID_N:-3}"
PHYMID_K="${PHYMID_K:-40}"
PHYMID_L="${PHYMID_L:-0.25}"
PHYMID_H="${PHYMID_H:-0.90}"
PHYMID_T="${PHYMID_T:-300}"
PHYMID_I="${PHYMID_I:-0.50}"
PHYMID_P="${PHYMID_P:-0.40}"
PHYMID_F="${PHYMID_F:-0.05}"
PHYMID_G="${PHYMID_G:-0.05}"
PHYMID_D="${PHYMID_D:-1}"

PHY_MICRO_ENABLE="${PHY_MICRO_ENABLE:-0}"
PHY_FIT_ENABLE="${PHY_FIT_ENABLE:-1}"
PHY_FIT_COEF_FILE="${PHY_FIT_COEF_FILE:-$ROOT_DIR/my_work/model/phy_fit_function_v1.txt}"
PHY_FIT_L0_SCALE="${PHY_FIT_L0_SCALE:-0.35}"
PHY_FIT_L1_SCALE="${PHY_FIT_L1_SCALE:-0.25}"

mkdir -p "$OUT_DIR" "$LOG_DIR" "$TMP_DIR"

if [ ! -x "$ABC_BIN" ]; then
  echo "[error] abc binary not executable: $ABC_BIN" >&2
  exit 1
fi
if [ ! -f "$LIB_FILE" ]; then
  echo "[error] liberty file not found: $LIB_FILE" >&2
  exit 1
fi
if [ ! -d "$RAW_DIR" ]; then
  echo "[error] raw aig dir not found: $RAW_DIR" >&2
  exit 1
fi
if [ ! -d "$OPT_DIR" ]; then
  echo "[error] opt aig dir not found: $OPT_DIR" >&2
  exit 1
fi
if [ "$PHY_FIT_ENABLE" = "1" ] && [ ! -f "$PHY_FIT_COEF_FILE" ]; then
  echo "[error] fit coef file not found: $PHY_FIT_COEF_FILE" >&2
  exit 1
fi

parse_metrics() {
  local log_file="$1"
  local line area delay line2

  line="$(grep -E "area =" "$log_file" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')"
  if [ -n "$line" ]; then
    area="$(echo "$line" | sed -E 's/.*area = *([0-9.]+).*/\1/')"
    delay="$(echo "$line" | sed -E 's/.*delay = *(-?[0-9.]+).*/\1/')"
    if [ -n "$area" ] && [ -n "$delay" ] && [ "$area" != "$line" ] && [ "$delay" != "$line" ]; then
      echo "$area,$delay"
      return 0
    fi
  fi

  line2="$(grep -E "Area[[:space:]]*:[[:space:]]*Delay" "$log_file" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')"
  if [ -n "$line2" ]; then
    delay="$(echo "$line2" | sed -E 's/.*Delay *= *(-?[0-9.]+).*/\1/')"
    area="$(echo "$line2" | sed -E 's/.*Area *= *([0-9.]+).*/\1/')"
    if [ -n "$area" ] && [ -n "$delay" ] && [ "$area" != "$line2" ] && [ "$delay" != "$line2" ]; then
      echo "$area,$delay"
      return 0
    fi
  fi

  echo "NA,NA"
  return 1
}

probe_nd() {
  local bench="$1"
  local case_tag="$2"
  local aig_file="$3"
  local cmd_file="$TMP_DIR/${bench}_${case_tag}_probe.abc"
  local log_file="$LOG_DIR/${bench}_${case_tag}_probe.log"
  local line nd

  {
    echo "read_lib $LIB_FILE"
    echo "read_aiger $aig_file"
    echo "ps"
    echo "quit"
  } > "$cmd_file"

  env \
    PHY_MICRO_ENABLE="$PHY_MICRO_ENABLE" \
    PHY_FIT_ENABLE="$PHY_FIT_ENABLE" \
    PHY_FIT_COEF_FILE="$PHY_FIT_COEF_FILE" \
    PHY_FIT_L0_SCALE="$PHY_FIT_L0_SCALE" \
    PHY_FIT_L1_SCALE="$PHY_FIT_L1_SCALE" \
    "$ABC_BIN" -f "$cmd_file" > "$log_file" 2>&1 || true

  line="$(grep -E "nd =" "$log_file" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')"
  if [ -z "$line" ]; then
    echo "-1"
    return 0
  fi

  nd="$(echo "$line" | sed -E 's/.*nd = *([0-9]+).*/\1/')"
  if [ -z "$nd" ] || [ "$nd" = "$line" ]; then
    echo "-1"
  else
    echo "$nd"
  fi
}

run_case() {
  local bench="$1"
  local case_tag="$2"
  local aig_file="$3"
  local use_phymid="$4"

  local cmd_file="$TMP_DIR/${bench}_${case_tag}.abc"
  local log_file="$LOG_DIR/${bench}_${case_tag}.log"
  local mid_csv="$TMP_DIR/${bench}_${case_tag}.phy.csv"
  local fb_cmd_file fb_log_file
  local start end runtime rc metrics area delay flow_mode nd_probe

  flow_mode="map"
  if [ "$use_phymid" = "1" ]; then
    nd_probe="$(probe_nd "$bench" "$case_tag" "$aig_file")"
    if [ "$nd_probe" -gt 1 ] 2>/dev/null; then
      flow_mode="phymid"
    else
      flow_mode="skip_trivial_map"
    fi
  fi

  {
    echo "read_lib $LIB_FILE"
    echo "read_aiger $aig_file"
    if [ "$flow_mode" = "phymid" ]; then
      if [ "$PHYMID_D" = "1" ]; then
        echo "phymid -C $mid_csv -n $PHYMID_N -k $PHYMID_K -L $PHYMID_L -H $PHYMID_H -t $PHYMID_T -i $PHYMID_I -p $PHYMID_P -f $PHYMID_F -g $PHYMID_G -d"
      else
        echo "phymid -C $mid_csv -n $PHYMID_N -k $PHYMID_K -L $PHYMID_L -H $PHYMID_H -t $PHYMID_T -i $PHYMID_I -p $PHYMID_P -f $PHYMID_F -g $PHYMID_G"
      fi
    else
      echo "map"
    fi
    echo "ps"
    echo "quit"
  } > "$cmd_file"

  start="$(date +%s.%N)"
  env \
    PHY_MICRO_ENABLE="$PHY_MICRO_ENABLE" \
    PHY_FIT_ENABLE="$PHY_FIT_ENABLE" \
    PHY_FIT_COEF_FILE="$PHY_FIT_COEF_FILE" \
    PHY_FIT_L0_SCALE="$PHY_FIT_L0_SCALE" \
    PHY_FIT_L1_SCALE="$PHY_FIT_L1_SCALE" \
    "$ABC_BIN" -f "$cmd_file" > "$log_file" 2>&1
  rc=$?
  end="$(date +%s.%N)"

  runtime="$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.3f", (e-s)}')"

  if [ "$rc" -ne 0 ]; then
    if [ "$flow_mode" = "phymid" ]; then
      fb_cmd_file="$TMP_DIR/${bench}_${case_tag}_fallback_map.abc"
      fb_log_file="$LOG_DIR/${bench}_${case_tag}_fallback_map.log"

      {
        echo "read_lib $LIB_FILE"
        echo "read_aiger $aig_file"
        echo "map"
        echo "ps"
        echo "quit"
      } > "$fb_cmd_file"

      start="$(date +%s.%N)"
      env \
        PHY_MICRO_ENABLE="$PHY_MICRO_ENABLE" \
        PHY_FIT_ENABLE="$PHY_FIT_ENABLE" \
        PHY_FIT_COEF_FILE="$PHY_FIT_COEF_FILE" \
        PHY_FIT_L0_SCALE="$PHY_FIT_L0_SCALE" \
        PHY_FIT_L1_SCALE="$PHY_FIT_L1_SCALE" \
        "$ABC_BIN" -f "$fb_cmd_file" > "$fb_log_file" 2>&1
      rc=$?
      end="$(date +%s.%N)"
      runtime="$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.3f", (e-s)}')"

      if [ "$rc" -ne 0 ]; then
        echo "NA|NA|$runtime|$fb_log_file|$rc|phymid_fallback_map_failed"
        return 0
      fi

      metrics="$(parse_metrics "$fb_log_file")"
      area="${metrics%%,*}"
      delay="${metrics##*,}"
      echo "$area|$delay|$runtime|$fb_log_file|$rc|phymid_fallback_map"
      return 0
    fi

    echo "NA|NA|$runtime|$log_file|$rc|$flow_mode"
    return 0
  fi

  metrics="$(parse_metrics "$log_file")"
  area="${metrics%%,*}"
  delay="${metrics##*,}"
  echo "$area|$delay|$runtime|$log_file|$rc|$flow_mode"
}

shopt -s nullglob
raw_files=("$RAW_DIR"/*_raw.aig)
if [ "${#raw_files[@]}" -eq 0 ]; then
  echo "[error] no *_raw.aig found under $RAW_DIR" >&2
  exit 1
fi

echo "bench,raw_map_area,raw_map_delay,raw_map_runtime_sec,opt_map_area,opt_map_delay,opt_map_runtime_sec,raw_flow_area,raw_flow_delay,raw_flow_runtime_sec,opt_flow_area,opt_flow_delay,opt_flow_runtime_sec,raw_map_rc,opt_map_rc,raw_flow_rc,opt_flow_rc,raw_flow_mode,opt_flow_mode,raw_map_log,opt_map_log,raw_flow_log,opt_flow_log" > "$REPORT_CSV"

pair_count=0
for raw_path in "${raw_files[@]}"; do
  raw_name="$(basename "$raw_path")"
  bench="${raw_name%_raw.aig}"
  opt_path="$OPT_DIR/${bench}_opt.aig"

  if [ ! -f "$opt_path" ]; then
    echo "[warn] missing opt pair for $bench, skip." >&2
    continue
  fi

  pair_count=$((pair_count + 1))
  echo "[info] ($pair_count/${#raw_files[@]}) running bench=$bench" >&2

  IFS='|' read -r raw_map_area raw_map_delay raw_map_rt raw_map_log raw_map_rc raw_map_mode <<< "$(run_case "$bench" "raw_map" "$raw_path" 0)"
  IFS='|' read -r opt_map_area opt_map_delay opt_map_rt opt_map_log opt_map_rc opt_map_mode <<< "$(run_case "$bench" "opt_map" "$opt_path" 0)"
  IFS='|' read -r raw_flow_area raw_flow_delay raw_flow_rt raw_flow_log raw_flow_rc raw_flow_mode <<< "$(run_case "$bench" "raw_flow" "$raw_path" 1)"
  IFS='|' read -r opt_flow_area opt_flow_delay opt_flow_rt opt_flow_log opt_flow_rc opt_flow_mode <<< "$(run_case "$bench" "opt_flow" "$opt_path" 1)"

  echo "$bench,$raw_map_area,$raw_map_delay,$raw_map_rt,$opt_map_area,$opt_map_delay,$opt_map_rt,$raw_flow_area,$raw_flow_delay,$raw_flow_rt,$opt_flow_area,$opt_flow_delay,$opt_flow_rt,$raw_map_rc,$opt_map_rc,$raw_flow_rc,$opt_flow_rc,$raw_flow_mode,$opt_flow_mode,$raw_map_log,$opt_map_log,$raw_flow_log,$opt_flow_log" >> "$REPORT_CSV"
done

echo "[done] report: $REPORT_CSV" >&2
