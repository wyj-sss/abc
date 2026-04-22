#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DYN_DIR="$ROOT_DIR/my_work/dynamic_scheduler_work"

RUN_TAG="${RUN_TAG:-run_iwls26_model_equiv_$(date +%Y%m%d_%H%M%S)}"
RESULT_DIR="${RESULT_DIR:-$DYN_DIR/result/$RUN_TAG}"
SUMMARY_CSV="$RESULT_DIR/summary.csv"

LIB_FILE="${LIB_FILE:-$ROOT_DIR/my_work/c17_work/NangateOpenCellLibrary_typical.lib}"
BENCH_DIR="${BENCH_DIR:-$ROOT_DIR/iwls26/results}"
BENCH_LIST="${BENCH_LIST:-$DYN_DIR/bench_ex200_209_one_each.txt}"

FIT_FILE="${FIT_FILE:-$ROOT_DIR/my_work/model/phy_fit_function_v1.txt}"

ROUNDS="${ROUNDS:-3}"
I_W="${I_W:-0.50}"
P_W="${P_W:-0.40}"
F_W="${F_W:-0.05}"
G_W="${G_W:-0.05}"
L_T="${L_T:-0.25}"
H_T="${H_T:-0.90}"
K_V="${K_V:-40}"
CASE_TIMEOUT_SEC="${CASE_TIMEOUT_SEC:-300}"

PHY_FIT_L0_SCALE="${PHY_FIT_L0_SCALE:-0.35}"
PHY_FIT_L1_SCALE="${PHY_FIT_L1_SCALE:-0.25}"

mkdir -p "$RESULT_DIR"

fail() {
  echo "[error] $*" >&2
  exit 1
}

trim_line() {
  echo "$1" | sed -E 's/#.*$//; s/[[:space:]]+$//; s/^[[:space:]]+//'
}

resolve_bench_path() {
  local item="$1"
  if [ -f "$item" ]; then
    echo "$item"
    return 0
  fi
  if [ -f "$ROOT_DIR/$item" ]; then
    echo "$ROOT_DIR/$item"
    return 0
  fi
  if [ -f "$BENCH_DIR/$item" ]; then
    echo "$BENCH_DIR/$item"
    return 0
  fi
  if [ -f "$BENCH_DIR/$item.aig" ]; then
    echo "$BENCH_DIR/$item.aig"
    return 0
  fi
  return 1
}

extract_ps_line() {
  local log_file="$1"
  grep -E "area =" "$log_file" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g'
}

metric_from_line() {
  local line="$1"
  local key="$2"
  echo "$line" | sed -nE "s/.*${key}[[:space:]]*=[[:space:]]*([0-9]+(\.[0-9]+)?).*/\1/p"
}

num_delta() {
  local before="$1"
  local after="$2"
  awk -v b="$before" -v a="$after" 'BEGIN{printf "%.2f", a-b}'
}

num_pct() {
  local before="$1"
  local after="$2"
  awk -v b="$before" -v a="$after" 'BEGIN{ if (b == 0) printf "0.00"; else printf "%.2f", (a-b)*100.0/b }'
}

count_gate_lines() {
  local blif_file="$1"
  if [ ! -f "$blif_file" ]; then
    echo 0
    return
  fi
  if grep -q '^\.gate ' "$blif_file"; then
    grep -c '^\.gate ' "$blif_file"
    return
  fi
  if grep -q '^\.names ' "$blif_file"; then
    grep -c '^\.names ' "$blif_file"
    return
  fi
  echo 0
}

write_gate_hist() {
  local blif_file="$1"
  local out_csv="$2"
  echo "gate,count" > "$out_csv"
  if [ ! -f "$blif_file" ]; then
    echo "N/A,0" >> "$out_csv"
    return
  fi
  if grep -q '^\.gate ' "$blif_file"; then
    awk '/^\.gate /{cnt[$2]++} END{for (g in cnt) printf "%s,%d\n", g, cnt[g]}' "$blif_file" | sort >> "$out_csv"
  else
    echo "N/A,0" >> "$out_csv"
  fi
}

if [ ! -x "$ROOT_DIR/abc" ]; then
  fail "abc binary not found or not executable: $ROOT_DIR/abc"
fi
if [ ! -f "$LIB_FILE" ]; then
  fail "liberty file not found: $LIB_FILE"
fi
if [ ! -f "$BENCH_LIST" ]; then
  fail "bench list not found: $BENCH_LIST"
fi
if [ ! -f "$FIT_FILE" ]; then
  echo "[warn] fit file not found, phyopt will fall back to built-in fit defaults: $FIT_FILE" >&2
fi

bench_total=$(grep -Ev '^[[:space:]]*($|#)' "$BENCH_LIST" | wc -l | tr -d ' ')
if [ "$bench_total" -eq 0 ]; then
  fail "bench list is empty: $BENCH_LIST"
fi

echo "bench,status,equiv_pass,timeout_hit,before_area,after_area,delta_area,pct_area,before_delay,after_delay,delta_delay,pct_delay,before_nd,after_nd,delta_nd,pct_nd,before_lev,after_lev,delta_lev,pct_lev,before_gate_lines,after_gate_lines,delta_gate_lines,pct_gate_lines,baseline_blif,optimized_blif,baseline_v,optimized_v,baseline_log,optimized_log,cec_log" > "$SUMMARY_CSV"

echo "[info] run_tag=$RUN_TAG" >&2
echo "[info] bench_total=$bench_total" >&2
echo "[info] fit_file=$FIT_FILE" >&2
echo "[info] result_dir=$RESULT_DIR" >&2

idx=0
while IFS= read -r raw || [ -n "$raw" ]; do
  item="$(trim_line "$raw" | tr -d '\r')"
  [ -z "$item" ] && continue

  idx=$((idx + 1))

  bench_path=""
  if ! bench_path="$(resolve_bench_path "$item")"; then
    echo "[warn] skip missing bench entry: $item" >&2
    continue
  fi

  bench_name="$(basename "$bench_path" .aig)"
  case_dir="$RESULT_DIR/$bench_name"
  mkdir -p "$case_dir"

  base_blif="$case_dir/${bench_name}_baseline_map.blif"
  base_v="$case_dir/${bench_name}_baseline_map.v"
  base_aig="$case_dir/${bench_name}_baseline_map_strash.aig"
  base_log="$case_dir/${bench_name}_baseline.log"
  base_scr="/tmp/${bench_name}_baseline_$$.scr"

  opt_phy_csv="$case_dir/${bench_name}_phy.csv"
  opt_blif="$case_dir/${bench_name}_optimized_map.blif"
  opt_v="$case_dir/${bench_name}_optimized_map.v"
  opt_aig="$case_dir/${bench_name}_optimized_map_strash.aig"
  opt_log="$case_dir/${bench_name}_optimized.log"
  opt_scr="/tmp/${bench_name}_optimized_$$.scr"

  cec_log="$case_dir/${bench_name}_cec.log"
  gate_hist_base="$case_dir/${bench_name}_baseline_gate_hist.csv"
  gate_hist_opt="$case_dir/${bench_name}_optimized_gate_hist.csv"

  echo "[progress] $idx/$bench_total bench=$bench_name (baseline map)" >&2

  cat > "$base_scr" <<EOF
read_lib $LIB_FILE
read_aiger $bench_path
map
ps
write_blif $base_blif
write_verilog $base_v
strash
write_aiger $base_aig
quit
EOF

  base_rc=0
  "$ROOT_DIR/abc" -f "$base_scr" > "$base_log" 2>&1 || base_rc=$?
  rm -f "$base_scr"

  echo "[progress] $idx/$bench_total bench=$bench_name (model+heur optimize)" >&2

  cat > "$opt_scr" <<EOF
read_lib $LIB_FILE
read_aiger $bench_path
map_oto
mapper_extract -o $opt_phy_csv
phyread -i $I_W -p $P_W -f $F_W -g $G_W $opt_phy_csv
phyopt -d -n $ROUNDS -k $K_V -L $L_T -H $H_T -t $CASE_TIMEOUT_SEC
map
ps
write_blif $opt_blif
write_verilog $opt_v
strash
write_aiger $opt_aig
quit
EOF

  opt_rc=0
  PHY_MICRO_ENABLE=0 \
  PHY_FIT_ENABLE=1 \
  PHY_FIT_COEF_FILE="$FIT_FILE" \
  PHY_FIT_L0_SCALE="$PHY_FIT_L0_SCALE" \
  PHY_FIT_L1_SCALE="$PHY_FIT_L1_SCALE" \
  "$ROOT_DIR/abc" -f "$opt_scr" > "$opt_log" 2>&1 || opt_rc=$?
  rm -f "$opt_scr"

  status="PASS"
  if [ "$base_rc" -ne 0 ]; then
    status="BASE_FAIL"
  elif [ "$opt_rc" -ne 0 ]; then
    status="OPT_FAIL"
  fi

  timeout_hit=0
  if grep -q "phyopt: case timeout reached" "$opt_log"; then
    timeout_hit=1
  fi

  base_line="$(extract_ps_line "$base_log")"
  opt_line="$(extract_ps_line "$opt_log")"

  base_area="$(metric_from_line "$base_line" "area")"; base_area="${base_area:-0}"
  base_delay="$(metric_from_line "$base_line" "delay")"; base_delay="${base_delay:-0}"
  base_nd="$(metric_from_line "$base_line" "nd")"; base_nd="${base_nd:-0}"
  base_lev="$(metric_from_line "$base_line" "lev")"; base_lev="${base_lev:-0}"

  opt_area="$(metric_from_line "$opt_line" "area")"; opt_area="${opt_area:-0}"
  opt_delay="$(metric_from_line "$opt_line" "delay")"; opt_delay="${opt_delay:-0}"
  opt_nd="$(metric_from_line "$opt_line" "nd")"; opt_nd="${opt_nd:-0}"
  opt_lev="$(metric_from_line "$opt_line" "lev")"; opt_lev="${opt_lev:-0}"

  base_gates="$(count_gate_lines "$base_blif")"
  opt_gates="$(count_gate_lines "$opt_blif")"

  write_gate_hist "$base_blif" "$gate_hist_base"
  write_gate_hist "$opt_blif" "$gate_hist_opt"

  delta_area="$(num_delta "$base_area" "$opt_area")"
  pct_area="$(num_pct "$base_area" "$opt_area")"

  delta_delay="$(num_delta "$base_delay" "$opt_delay")"
  pct_delay="$(num_pct "$base_delay" "$opt_delay")"

  delta_nd="$(num_delta "$base_nd" "$opt_nd")"
  pct_nd="$(num_pct "$base_nd" "$opt_nd")"

  delta_lev="$(num_delta "$base_lev" "$opt_lev")"
  pct_lev="$(num_pct "$base_lev" "$opt_lev")"

  delta_gates="$(num_delta "$base_gates" "$opt_gates")"
  pct_gates="$(num_pct "$base_gates" "$opt_gates")"

  equiv_pass=0
  if [ -f "$base_aig" ] && [ -f "$opt_aig" ]; then
    "$ROOT_DIR/abc" -q "cec $base_aig $opt_aig" > "$cec_log" 2>&1 || true
    if grep -q "Networks are equivalent" "$cec_log"; then
      equiv_pass=1
    fi
  else
    echo "missing AIG for cec" > "$cec_log"
  fi

  echo "$bench_name,$status,$equiv_pass,$timeout_hit,$base_area,$opt_area,$delta_area,$pct_area,$base_delay,$opt_delay,$delta_delay,$pct_delay,$base_nd,$opt_nd,$delta_nd,$pct_nd,$base_lev,$opt_lev,$delta_lev,$pct_lev,$base_gates,$opt_gates,$delta_gates,$pct_gates,$base_blif,$opt_blif,$base_v,$opt_v,$base_log,$opt_log,$cec_log" >> "$SUMMARY_CSV"
done < "$BENCH_LIST"

echo "[done] summary=$SUMMARY_CSV" >&2
