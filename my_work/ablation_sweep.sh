#!/bin/bash
# Ablation sweep for phymid parameter optimization
# Phase 1: Threshold + Alpha on ALL 10 benchmarks (~160 runs)
# Phase 2: Struct weights on ALL 10 benchmarks (~50 runs)
# Phase 3: Final verification with best overall params (10 runs)

ABC_EXE="./abc"
LIB="NangateOpenCellLibrary_typical.lib"
AIG_DIR="../EPFL_benchmarks/arithmetic"
LOG_DIR="my_work/phyopt_bench_logs/ablation"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_CSV="${LOG_DIR}/results_${TIMESTAMP}.csv"

mkdir -p "$LOG_DIR"

ALL_BENCH="adder bar div hyp log2 max multiplier sin sqrt square"

# Struct weights: inv=0 because map_oto -T produces zero INV cells
# Remaining 3 weights: pair-collapse, fanout-ease, gate-score
DEF_WI="0.00"
DEF_WP="0.50"
DEF_WF="0.25"
DEF_WG="0.25"

echo "=== Ablation Sweep Start: $(date) ==="
echo "Results: ${RESULT_CSV}"
echo "Benchmarks: ${ALL_BENCH}"

# CSV header
echo "phase,bench,cl,ch,al,am,ah,wi,wp,wf,wg,area,delay,acc,rej,nodes" > "$RESULT_CSV"

run_one() {
    local bench="$1" cl="$2" ch="$3" al="$4" am="$5" ah="$6"
    local wi="$7" wp="$8" wf="$9" wg="${10}" phase="${11}"

    local aig="${AIG_DIR}/${bench}.aig"
    if [ ! -f "$aig" ]; then
        echo "  [${phase}] SKIP ${bench}: AIG not found at ${aig}"
        return
    fi

    local tag="CL${cl}_CH${ch}_AL${al}_AM${am}_AH${ah}_W${wi}_${wp}_${wf}_${wg}"
    local log="${LOG_DIR}/${phase}_${bench}_${tag}.log"

    echo "  [${phase}] ${bench} CL=${cl} CH=${ch} A=(${al},${am},${ah}) W=(${wi},${wp},${wf},${wg})"

    ${ABC_EXE} -c "read_aiger ${aig}; read_lib ${LIB}; phymid -L ${cl} -H ${ch} -A ${al} -B ${am} -G ${ah} -i ${wi} -p ${wp} -f ${wf} -g ${wg}" > "${log}" 2>&1

    # Parse final mapped area/delay from last "Area" line
    local last_area=$(grep "^Area " "${log}" | tail -1)
    local area=$(echo "$last_area" | sed -n 's/.*Area = *\([0-9.]*\).*/\1/p')
    local delay=$(echo "$last_area" | sed -n 's/.*Delay = *\([0-9.]*\).*/\1/p')

    # Parse phyopt: done stats
    local done_line=$(grep "phyopt: done" "${log}" | tail -1)
    local acc=$(echo "$done_line" | sed -n 's/.*accepted=\([0-9]*\).*/\1/p')
    local rej=$(echo "$done_line" | sed -n 's/.*rejected=\([0-9]*\).*/\1/p')
    local nodes=$(echo "$done_line" | sed -n 's/.*final_nodes=\([0-9]*\).*/\1/p')

    [ -z "$area" ] && area="NA"
    [ -z "$delay" ] && delay="NA"
    [ -z "$acc" ] && acc="NA"
    [ -z "$rej" ] && rej="NA"
    [ -z "$nodes" ] && nodes="NA"

    echo "${phase},${bench},${cl},${ch},${al},${am},${ah},${wi},${wp},${wf},${wg},${area},${delay},${acc},${rej},${nodes}" >> "$RESULT_CSV"
}

# ============================================================
# Phase 1: Threshold + Alpha sweep on ALL benchmarks
#   CL in {0.15, 0.25}, CH in {0.85, 0.95} => 4 (CL,CH) pairs
#   Alpha groups: 4 strategies
#   Total per bench: 4 × 4 = 16 runs
#   Total: 10 × 16 = 160 runs
# ============================================================
PHASE="P1"
echo "=== Phase 1: Threshold + Alpha on 10 benchmarks ($(date)) ==="

for bench in $ALL_BENCH; do
    for cl in 0.15 0.25; do
        for ch in 0.85 0.95; do
            if (( $(echo "${cl} >= ${ch}" | bc -l) )); then continue; fi

            # (A) Slack-heavy: all partitions mostly slack-driven
            run_one "$bench" "$cl" "$ch" 0.10 0.20 0.40 "$DEF_WI" "$DEF_WP" "$DEF_WF" "$DEF_WG" "$PHASE"
            # (B) Default: LOW struct-heavy, MID balanced, HIGH slack-heavy
            run_one "$bench" "$cl" "$ch" 0.30 0.50 0.80 "$DEF_WI" "$DEF_WP" "$DEF_WF" "$DEF_WG" "$PHASE"
            # (C) Struct-heavy: all partitions mostly struct-driven
            run_one "$bench" "$cl" "$ch" 0.50 0.70 0.90 "$DEF_WI" "$DEF_WP" "$DEF_WF" "$DEF_WG" "$PHASE"
            # (D) Gradual: smooth transition from slack to struct
            run_one "$bench" "$cl" "$ch" 0.20 0.50 0.70 "$DEF_WI" "$DEF_WP" "$DEF_WF" "$DEF_WG" "$PHASE"
        done
    done
done

echo "=== Phase 1 complete: $(date) ==="

# ============================================================
# Extract best params from Phase 1 (best = lowest avg area)
# ============================================================
echo "=== Phase 1 analysis ==="

# Find best (CL,CH,AL,AM,AH) by average area across all benches
# For each unique param combo, compute avg area and pick the best
echo "phase,bench,cl,ch,al,am,ah,wi,wp,wf,wg,area,delay,acc,rej,nodes" > /tmp/p1_header.csv
# Build a sorted list of (CL,CH,AL,AM,AH) by average area
cat /tmp/p1_header.csv <(grep "^P1," "$RESULT_CSV") | awk -F',' 'NR>1 && $12 != "NA" {
    key = $3","$4","$5","$6","$7;
    sum[key] += $12;
    cnt[key]++
}
END {
    for (k in sum) {
        avg = sum[k] / cnt[k];
        printf("%.4f %d %s\n", avg, cnt[k], k);
    }
}' | sort -n > /tmp/p1_ranking.txt

BEST_AVG=$(head -1 /tmp/p1_ranking.txt | awk '{print $1}')
BEST_CL=$(head -1 /tmp/p1_ranking.txt | cut -d',' -f1 | awk '{print $3}')
BEST_CH=$(head -1 /tmp/p1_ranking.txt | cut -d',' -f2)
BEST_AL=$(head -1 /tmp/p1_ranking.txt | cut -d',' -f3)
BEST_AM=$(head -1 /tmp/p1_ranking.txt | cut -d',' -f4)
BEST_AH=$(head -1 /tmp/p1_ranking.txt | cut -d',' -f5)

echo "  Best Phase 1 params (by avg area=${BEST_AVG}):"
echo "    CL=${BEST_CL} CH=${BEST_CH} AL=${BEST_AL} AM=${BEST_AM} AH=${BEST_AH}"
echo ""
echo "  Top 5 param combinations:"
head -5 /tmp/p1_ranking.txt

# ============================================================
# Phase 2: Struct weight sweep on ALL benchmarks
#   5 weight patterns: default, uniform, pair-dominant, fanout-dominant, gate-dominant
#   Total per bench: 5 runs
#   Total: 10 × 5 = 50 runs
# ============================================================
PHASE="P2"
echo ""
echo "=== Phase 2: Struct Weights on 10 benchmarks ($(date)) ==="

for bench in $ALL_BENCH; do
    # (A) Default: pair-heavy
    run_one "$bench" "$BEST_CL" "$BEST_CH" "$BEST_AL" "$BEST_AM" "$BEST_AH" 0.00 0.50 0.25 0.25 "$PHASE"
    # (B) Uniform: pair~=fanout~=gate
    run_one "$bench" "$BEST_CL" "$BEST_CH" "$BEST_AL" "$BEST_AM" "$BEST_AH" 0.00 0.33 0.33 0.34 "$PHASE"
    # (C) Pair dominant
    run_one "$bench" "$BEST_CL" "$BEST_CH" "$BEST_AL" "$BEST_AM" "$BEST_AH" 0.00 0.60 0.20 0.20 "$PHASE"
    # (D) Fanout dominant
    run_one "$bench" "$BEST_CL" "$BEST_CH" "$BEST_AL" "$BEST_AM" "$BEST_AH" 0.00 0.20 0.60 0.20 "$PHASE"
    # (E) Gate dominant
    run_one "$bench" "$BEST_CL" "$BEST_CH" "$BEST_AL" "$BEST_AM" "$BEST_AH" 0.00 0.20 0.20 0.60 "$PHASE"
done

echo "=== Phase 2 complete: $(date) ==="

# ============================================================
# Extract best params from Phase 2 (best = lowest avg area)
# ============================================================
echo "=== Phase 2 analysis ==="

echo "phase,bench,cl,ch,al,am,ah,wi,wp,wf,wg,area,delay,acc,rej,nodes" > /tmp/p2_header.csv
cat /tmp/p2_header.csv <(grep "^P2," "$RESULT_CSV") | awk -F',' 'NR>1 && $12 != "NA" {
    key = $3","$4","$5","$6","$7","$8","$9","$10","$11;
    sum[key] += $12;
    cnt[key]++
}
END {
    for (k in sum) {
        avg = sum[k] / cnt[k];
        printf("%.4f %d %s\n", avg, cnt[k], k);
    }
}' | sort -n > /tmp/p2_ranking.txt

BEST_P2_LINE=$(head -1 /tmp/p2_ranking.txt)
BEST_AVG_P2=$(echo "$BEST_P2_LINE" | awk '{print $1}')
BEST_CL=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f1)
BEST_CH=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f2)
BEST_AL=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f3)
BEST_AM=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f4)
BEST_AH=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f5)
BEST_WI=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f6)
BEST_WP=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f7)
BEST_WF=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f8)
BEST_WG=$(echo "$BEST_P2_LINE" | awk '{print $3}' | cut -d',' -f9)

echo "  Best Phase 2 params (by avg area=${BEST_AVG_P2}):"
echo "    CL=${BEST_CL} CH=${BEST_CH}"
echo "    Alpha: AL=${BEST_AL} AM=${BEST_AM} AH=${BEST_AH}"
echo "    StructW: WI=${BEST_WI} WP=${BEST_WP} WF=${BEST_WF} WG=${BEST_WG}"
echo ""
echo "  Top 5 param combinations:"
head -5 /tmp/p2_ranking.txt

# ============================================================
# Phase 3: All 10 benchmarks with global best params
#   Total: 10 runs
# ============================================================
PHASE="P3"
echo ""
echo "=== Phase 3: Final verification with best params ($(date)) ==="

for bench in $ALL_BENCH; do
    run_one "$bench" "$BEST_CL" "$BEST_CH" "$BEST_AL" "$BEST_AM" "$BEST_AH" "$BEST_WI" "$BEST_WP" "$BEST_WF" "$BEST_WG" "$PHASE"
done

echo "=== Phase 3 complete: $(date) ==="

# ============================================================
# Final summary
# ============================================================
echo ""
echo "============================================================"
echo "=== Ablation Sweep Complete: $(date) ==="
echo "============================================================"
echo "Results CSV: ${RESULT_CSV}"
echo ""
echo "Global best parameters:"
echo "  -L ${BEST_CL} -H ${BEST_CH} -A ${BEST_AL} -B ${BEST_AM} -G ${BEST_AH} -i ${BEST_WI} -p ${BEST_WP} -f ${BEST_WF} -g ${BEST_WG}"
echo ""

# Per-bench best in Phase 3
echo "=== Phase 3 per-bench results ==="
printf "%-12s %10s %10s %6s %6s %6s\n" "bench" "area" "delay" "acc" "rej" "nodes"
for bench in $ALL_BENCH; do
    line=$(grep "^P3,${bench}," "$RESULT_CSV" | head -1)
    if [ -n "$line" ]; then
        area=$(echo "$line" | cut -d',' -f12)
        delay=$(echo "$line" | cut -d',' -f13)
        acc=$(echo "$line" | cut -d',' -f14)
        rej=$(echo "$line" | cut -d',' -f15)
        nodes=$(echo "$line" | cut -d',' -f16)
        printf "%-12s %10s %10s %6s %6s %6s\n" "$bench" "$area" "$delay" "$acc" "$rej" "$nodes"
    else
        printf "%-12s %10s\n" "$bench" "FAIL"
    fi
done

echo ""
echo "=== Phase 1: Per-param avg area ranking (top 10) ==="
head -10 /tmp/p1_ranking.txt

echo ""
echo "=== Phase 2: Per-param avg area ranking (all) ==="
cat /tmp/p2_ranking.txt
