#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPRO_DIR="$SCRIPT_DIR/SMABC_FPRM_Reproduce"
ABC_BIN="${ABC_BIN:-$ROOT_DIR/abc}"

RAW_AIG_DIR="$SCRIPT_DIR/aig_output_raw"
OPT_AIG_DIR="$SCRIPT_DIR/aig_output_opt"
OPT_V_DIR="$REPRO_DIR/smabc_opt_paper"
REPRO_OUT_DIR="$REPRO_DIR/paper_reproduce_out"
CONV_LOG_DIR="$SCRIPT_DIR/smabc_method_convert_logs"
EQUIV_REPORT="$SCRIPT_DIR/smabc_method_equiv_report.csv"

RUNS="${RUNS:-1}"
NP="${NP:-100}"
GENERATIONS="${GENERATIONS:-50}"
CONV_RUNS="${CONV_RUNS:-1}"
VERIFY_METHOD="${VERIFY_METHOD:-1}"
EXPORT_OPT_ALGO="${EXPORT_OPT_ALGO:-SMABC}"
BENCH_FILTER="${BENCH_FILTER:-}"

if [ ! -x "$ABC_BIN" ]; then
  echo "[error] abc binary not executable: $ABC_BIN" >&2
  exit 1
fi

if [ ! -d "$RAW_AIG_DIR" ]; then
  echo "[error] raw AIG dir not found: $RAW_AIG_DIR" >&2
  exit 1
fi

mkdir -p "$OPT_AIG_DIR" "$CONV_LOG_DIR"
rm -f "$OPT_AIG_DIR"/*_opt.aig
rm -f "$EQUIV_REPORT"

echo "[step1] run SMABC method reproduction and export optimized verilog"
(
  cd "$REPRO_DIR"
  rm -rf "$REPRO_OUT_DIR" "$OPT_V_DIR"
  mkdir -p "$REPRO_OUT_DIR" "$OPT_V_DIR"

  if [ -n "$BENCH_FILTER" ]; then
    VERIFY_METHOD="$VERIFY_METHOD" \
    RUNS="$RUNS" NP="$NP" GENERATIONS="$GENERATIONS" CONV_RUNS="$CONV_RUNS" \
    BENCH_FILTER="$BENCH_FILTER" \
    EXPORT_OPT_VERILOG_DIR="$OPT_V_DIR" EXPORT_OPT_ALGO="$EXPORT_OPT_ALGO" \
    ./run_paper_reproduce_full.sh
  else
    VERIFY_METHOD="$VERIFY_METHOD" \
    RUNS="$RUNS" NP="$NP" GENERATIONS="$GENERATIONS" CONV_RUNS="$CONV_RUNS" \
    EXPORT_OPT_VERILOG_DIR="$OPT_V_DIR" EXPORT_OPT_ALGO="$EXPORT_OPT_ALGO" \
    ./run_paper_reproduce_full.sh
  fi
)

echo "bench,raw_aig,opt_aig,equiv,cec_note" > "$EQUIV_REPORT"

echo "[step2] convert optimized verilog -> AIG and run cec"
shopt -s nullglob
vfiles=("$OPT_V_DIR"/*_opt.v)
if [ "${#vfiles[@]}" -eq 0 ]; then
  echo "[error] no optimized verilog generated under: $OPT_V_DIR" >&2
  exit 1
fi

for vf in "${vfiles[@]}"; do
  bench="$(basename "$vf" _opt.v)"
  raw_aig="$RAW_AIG_DIR/${bench}_raw.aig"
  opt_aig="$OPT_AIG_DIR/${bench}_opt.aig"

  "$ABC_BIN" -c "read_verilog $vf; strash; write_aiger $opt_aig; quit" \
    > "$CONV_LOG_DIR/${bench}_opt_convert.log" 2>&1

  equiv="NA"
  note="raw_aig_missing"
  if [ -f "$raw_aig" ]; then
    "$ABC_BIN" -c "cec $raw_aig $opt_aig; quit" \
      > "$CONV_LOG_DIR/${bench}_cec.log" 2>&1 || true

    if grep -Eq "Networks are equivalent|UNSATISFIABLE" "$CONV_LOG_DIR/${bench}_cec.log"; then
      equiv="PASS"
    elif grep -Eq "Networks are NOT EQUIVALENT|SATISFIABLE" "$CONV_LOG_DIR/${bench}_cec.log"; then
      equiv="FAIL"
    else
      equiv="UNKNOWN"
    fi
    note="$(grep -E "Networks are equivalent|Networks are NOT EQUIVALENT|UNSATISFIABLE|SATISFIABLE" "$CONV_LOG_DIR/${bench}_cec.log" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' | tr -s ' ')"
    if [ -z "$note" ]; then
      note="cec_no_keyline"
    fi
  fi

  printf '%s,%s,%s,%s,"%s"\n' \
    "$bench" "$raw_aig" "$opt_aig" "$equiv" "$note" >> "$EQUIV_REPORT"

  echo "  [done] $bench"
done

echo "[ok] optimized AIG generated: $OPT_AIG_DIR"
echo "[ok] equivalence report: $EQUIV_REPORT"
