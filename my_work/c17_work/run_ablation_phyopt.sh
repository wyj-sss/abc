#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

BENCH="${BENCH:-c880}"
ROUNDS="${ROUNDS:-1}"
PART_SIZE="${PART_SIZE:-30}"
OUT_CSV="${OUT_CSV:-c17_work/ablation_results.csv}"

run_case() {
  local name="$1"
  local phyread_args="$2"
  local phyopt_args="$3"

  echo "[case] ${name}"
  if ! PHYREAD_ARGS="$phyread_args" PHYOPT_ARGS="$phyopt_args" ROUNDS="$ROUNDS" PART_SIZE="$PART_SIZE" \
      bash c17_work/verify_phyopt_local.sh "$BENCH" > "c17_work/ablation_${name}.log" 2>&1; then
    echo "${name},FAIL,,," >> "$OUT_CSV"
    return 1
  fi

    local area delay line
    line=$(grep -E "${BENCH}_work/${BENCH}_phyopt_local\s+:" "c17_work/ablation_${name}.log" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')
    area=$(echo "$line" | sed -E 's/.*area = *([0-9.]+).*/\1/')
    delay=$(echo "$line" | sed -E 's/.*delay = *([0-9.]+).*/\1/')

  if [ -z "$area" ]; then
    echo "${name},PARSE_FAIL,,," >> "$OUT_CSV"
    return 1
  fi

  echo "${name},PASS,${area},${delay},${phyread_args} | ${phyopt_args}" >> "$OUT_CSV"
  return 0
}

echo "name,status,area,delay,config" > "$OUT_CSV"

# Baseline
run_case "baseline" "" ""

# Struct_raw 4-feature ablations (turn one feature off each time)
run_case "no_inv_chain" "-i 0 -p 0.3 -f 0.2 -g 0.1" ""
run_case "no_pair_collapse" "-i 0.4 -p 0 -f 0.2 -g 0.1" ""
run_case "no_fanout_ease" "-i 0.4 -p 0.3 -f 0 -g 0.1" ""
run_case "no_gate_score" "-i 0.4 -p 0.3 -f 0.2 -g 0" ""

# Criticality threshold ablations
run_case "thresh_tight" "" "-L 0.20 -H 0.90"
run_case "thresh_loose" "" "-L 0.40 -H 0.70"

# Slack-heavy vs struct-heavy alpha settings
run_case "alpha_slack_heavy" "-L 0.50 -M 0.70 -H 0.90" ""
run_case "alpha_struct_heavy" "-L 0.10 -M 0.30 -H 0.50" ""

echo "[done] wrote ${OUT_CSV}"
echo "[done] logs are in c17_work/ablation_*.log"
