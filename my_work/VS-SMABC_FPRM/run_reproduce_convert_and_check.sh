#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/d/My_abc_work/abc"
REPRO="$ROOT/my_work/VS-SMABC_FPRM/SMABC_FPRM_Reproduce"
RAW_OUT="$ROOT/my_work/VS-SMABC_FPRM/aig_output_raw"
OPT_OUT="$ROOT/my_work/VS-SMABC_FPRM/aig_output_opt"
LOG_DIR="$ROOT/my_work/VS-SMABC_FPRM/reproduce_conv_logs"
REPORT="$ROOT/my_work/VS-SMABC_FPRM/reproduce_equiv_ps_report.csv"
ABC_BIN="$ROOT/abc"

mkdir -p "$RAW_OUT" "$OPT_OUT" "$LOG_DIR"

cd "$REPRO"

gcc -O2 -Wall -Wextra -std=c11 -o smabc main.c
./smabc > "$LOG_DIR/main_generate.log" 2>&1

echo "bench,raw_ps,opt_ps,equiv_status,cec_note" > "$REPORT"

total=0
pass=0

for pla in "$REPRO"/benchmarks/*.pla; do
    bench="$(basename "$pla" .pla)"
    raw_aig="$RAW_OUT/${bench}_raw.aig"
    opt_v="$REPRO/smabc_opt/${bench}_opt.v"
    opt_aig="$OPT_OUT/${bench}_opt.aig"

    "$ABC_BIN" -c "read_pla $pla; strash; write_aiger $raw_aig; quit" \
        > "$LOG_DIR/${bench}_raw_convert.log" 2>&1

    "$ABC_BIN" -c "read_aiger $raw_aig; ps; quit" \
        > "$LOG_DIR/${bench}_raw_ps.log" 2>&1

    "$ABC_BIN" -c "read_verilog $opt_v; strash; write_aiger $opt_aig; quit" \
        > "$LOG_DIR/${bench}_opt_convert.log" 2>&1

    "$ABC_BIN" -c "read_aiger $opt_aig; ps; quit" \
        > "$LOG_DIR/${bench}_opt_ps.log" 2>&1

    "$ABC_BIN" -c "cec $raw_aig $opt_aig; quit" \
        > "$LOG_DIR/${bench}_cec.log" 2>&1

    raw_ps="$(grep -E "i/o =|and =" "$LOG_DIR/${bench}_raw_ps.log" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' | tr -s ' ')"
    opt_ps="$(grep -E "i/o =|and =" "$LOG_DIR/${bench}_opt_ps.log" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' | tr -s ' ')"
    cec_note="$(grep -E "Networks are equivalent|Networks are NOT EQUIVALENT|UNSATISFIABLE|SATISFIABLE" "$LOG_DIR/${bench}_cec.log" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' | tr -s ' ')"

    status="FAIL"
    if grep -Eq "Networks are equivalent|UNSATISFIABLE" "$LOG_DIR/${bench}_cec.log"; then
        status="PASS"
        pass=$((pass + 1))
    fi

    total=$((total + 1))

    printf '%s,"%s","%s",%s,"%s"\n' \
        "$bench" "$raw_ps" "$opt_ps" "$status" "$cec_note" >> "$REPORT"

    echo "[done] $bench -> $status"
done

echo "SUMMARY total=$total pass=$pass fail=$((total - pass))"
echo "REPORT=$REPORT"
echo "LOG_DIR=$LOG_DIR"
