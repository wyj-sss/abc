#!/usr/bin/env bash
set -euo pipefail

ABC_ROOT="${ABC_ROOT:-/mnt/d/My_abc_work/abc}"
MOCKTURTLE_ROOT="${MOCKTURTLE_ROOT:-/mnt/d/My_abc_work/mockturtle}"
BENCH_DIR="${BENCH_DIR:-/mnt/d/My_abc_work/EPFL_benchmarks/arithmetic}"
OUT_DIR="${OUT_DIR:-$MOCKTURTLE_ROOT/new_aiger}"
CSV_FILE="${CSV_FILE:-$OUT_DIR/window_rewriting_stats.csv}"

ABC_BIN="${ABC_BIN:-$ABC_ROOT/abc}"
LIB_FILE="${LIB_FILE:-$ABC_ROOT/NangateOpenCellLibrary_typical.lib}"
WINDOW_BIN="${WINDOW_BIN:-$MOCKTURTLE_ROOT/build/examples/window_rewriting}"

BENCHES_DEFAULT="adder bar div hyp log2 max multiplier sin sqrt square"
BENCHES_INPUT="${BENCHES_INPUT:-$BENCHES_DEFAULT}"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [bench ...]

Examples:
  $(basename "$0")
  $(basename "$0") adder max
  BENCHES_INPUT="adder bar" $(basename "$0")

Environment:
  ABC_ROOT         abc repo root (default: $ABC_ROOT)
  MOCKTURTLE_ROOT  mockturtle root (default: $MOCKTURTLE_ROOT)
  BENCH_DIR        arithmetic AIG directory (default: $BENCH_DIR)
  OUT_DIR          optimized AIG output directory (default: $OUT_DIR)
  CSV_FILE         summary csv path (default: $CSV_FILE)
  ABC_BIN          abc executable path (default: $ABC_BIN)
  LIB_FILE         liberty file used for ps area/delay (default: $LIB_FILE)
  WINDOW_BIN       window_rewriting executable path (default: $WINDOW_BIN)
  BENCHES_INPUT    benches list when no args are provided
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  BENCHES=("$@")
else
  # shellcheck disable=SC2206
  BENCHES=($BENCHES_INPUT)
fi

mkdir -p "$OUT_DIR"

if [[ ! -x "$ABC_BIN" ]]; then
  echo "[error] abc executable not found: $ABC_BIN"
  exit 1
fi

if [[ ! -x "$WINDOW_BIN" ]]; then
  echo "[error] window_rewriting executable not found: $WINDOW_BIN"
  exit 1
fi

if [[ ! -f "$LIB_FILE" ]]; then
  echo "[error] liberty not found: $LIB_FILE"
  exit 1
fi

extract_runtime_and_equivalent() {
  local json_file="$1"
  python3 - "$json_file" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)

runtime = ""
equivalent = ""

if isinstance(data, list) and data:
    item = data[0]
    entries = item.get("entries", []) if isinstance(item, dict) else []
    if entries:
        entry = entries[0]
        runtime = entry.get("runtime", "")
        equivalent = entry.get("equivalent", "")

print(f"{runtime},{equivalent}")
PY
}

get_area_delay() {
  local aig_file="$1"
  local tag="$2"
  local cmd_file log_file line area delay

  cmd_file="$(mktemp /tmp/window_rw_ps_${tag}.XXXXXX.abc)"
  log_file="$(mktemp /tmp/window_rw_ps_${tag}.XXXXXX.log)"

  cat > "$cmd_file" <<EOF
read_lib $LIB_FILE
read_aiger $aig_file
map
ps
quit
EOF

  if ! "$ABC_BIN" -f "$cmd_file" > "$log_file" 2>&1; then
    rm -f "$cmd_file" "$log_file"
    echo ","
    return 0
  fi

  line=$(grep -E "area =" "$log_file" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')
  if [[ -z "$line" ]]; then
    rm -f "$cmd_file" "$log_file"
    echo ","
    return 0
  fi

  area=$(echo "$line" | sed -E 's/.*area = *([0-9.]+).*/\1/')
  delay=$(echo "$line" | sed -E 's/.*delay = *([0-9.]+).*/\1/')

  rm -f "$cmd_file" "$log_file"
  echo "$area,$delay"
}

echo "bench,opt_runtime_sec,equivalent,orig_area,orig_delay,opt_area,opt_delay,orig_aig,opt_aig,run_log" > "$CSV_FILE"

for bench in "${BENCHES[@]}"; do
  orig_aig="$BENCH_DIR/$bench.aig"
  opt_aig="$OUT_DIR/$bench.aig"
  run_log="$OUT_DIR/${bench}_window_rewriting.log"
  json_copy="$OUT_DIR/${bench}_window_rewriting.json"

  if [[ ! -f "$orig_aig" ]]; then
    echo "[warn] missing input: $orig_aig"
    echo "$bench,,,,,,,,$orig_aig,$opt_aig,$run_log" >> "$CSV_FILE"
    continue
  fi

  echo "[run] $bench"

  if ! (
    cd "$MOCKTURTLE_ROOT"
    ABC_BINARY="$ABC_BIN" \
    WINDOW_REWRITING_BENCH_DIR="$BENCH_DIR" \
    WINDOW_REWRITING_OUT_DIR="$OUT_DIR" \
    WINDOW_REWRITING_BENCHES="$bench" \
    "$WINDOW_BIN" > "$run_log" 2>&1
  ); then
    echo "[warn] window_rewriting failed: $bench"
    echo "$bench,,,,,,,,$orig_aig,$opt_aig,$run_log" >> "$CSV_FILE"
    continue
  fi

  if [[ -f "$MOCKTURTLE_ROOT/window_rewriting.json" ]]; then
    cp "$MOCKTURTLE_ROOT/window_rewriting.json" "$json_copy"
  fi

  opt_runtime=""
  equivalent=""
  if [[ -f "$json_copy" ]]; then
    IFS=',' read -r opt_runtime equivalent <<< "$(extract_runtime_and_equivalent "$json_copy")"
  fi

  IFS=',' read -r orig_area orig_delay <<< "$(get_area_delay "$orig_aig" "${bench}_orig")"

  if [[ -f "$opt_aig" ]]; then
    IFS=',' read -r opt_area opt_delay <<< "$(get_area_delay "$opt_aig" "${bench}_opt")"
  else
    opt_area=""
    opt_delay=""
    echo "[warn] missing optimized output: $opt_aig"
  fi

  echo "$bench,$opt_runtime,$equivalent,$orig_area,$orig_delay,$opt_area,$opt_delay,$orig_aig,$opt_aig,$run_log" >> "$CSV_FILE"
done

echo "[done] csv: $CSV_FILE"
echo "[done] new aig dir: $OUT_DIR"
