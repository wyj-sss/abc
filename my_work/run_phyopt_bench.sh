#!/bin/bash
# Run phymid optimization on all 10 EPFL arithmetic benchmarks
# Usage: in WSL, cd to abc directory, then run: bash my_work/run_phyopt_bench.sh

ABC_EXE="./abc"
LIB_PATH="NangateOpenCellLibrary_typical.lib"
AIG_DIR="../EPFL_benchmarks/arithmetic"
LOG_DIR="my_work/phyopt_bench_logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_FILE="${LOG_DIR}/summary_${TIMESTAMP}.txt"

BENCHMARKS="adder bar div hyp log2 max multiplier sin sqrt square"

echo "=== phymid benchmark run start: ${TIMESTAMP} ===" | tee -a "$SUMMARY_FILE"
echo "Benchmarks: ${BENCHMARKS}" | tee -a "$SUMMARY_FILE"
echo "" | tee -a "$SUMMARY_FILE"

for bench in $BENCHMARKS; do
    AIG_FILE="${AIG_DIR}/${bench}.aig"
    LOG_FILE="${LOG_DIR}/${bench}_${TIMESTAMP}.log"

    if [ ! -f "$AIG_FILE" ]; then
        echo "[SKIP] ${bench}: AIG file not found at ${AIG_FILE}" | tee -a "$SUMMARY_FILE"
        continue
    fi

    echo "[RUN] ${bench} ..." | tee -a "$SUMMARY_FILE"

    ${ABC_EXE} -c "read_aiger ${AIG_FILE}; read_lib ${LIB_PATH}; phymid -v" > "${LOG_FILE}" 2>&1

    # Extract key results from log
    if grep -q "phyopt: done" "${LOG_FILE}"; then
        RESULT=$(grep "phyopt: done" "${LOG_FILE}" | tail -1)
        echo "  ${RESULT}" | tee -a "$SUMMARY_FILE"
    else
        echo "  [WARN] phymid may not have completed normally for ${bench}" | tee -a "$SUMMARY_FILE"
    fi

    echo "" | tee -a "$SUMMARY_FILE"
done

echo "=== phymid benchmark run complete: $(date) ===" | tee -a "$SUMMARY_FILE"
echo "Logs saved to: ${LOG_DIR}/" | tee -a "$SUMMARY_FILE"
