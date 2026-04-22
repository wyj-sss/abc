#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/my_work/ablation_results_stageW"
INPUT_CSV="${1:-$RESULT_DIR/summary.csv}"
OUT_CSV="$RESULT_DIR/summary_by_weight.csv"

if [ ! -f "$INPUT_CSV" ]; then
  echo "[error] input not found: $INPUT_CSV" >&2
  exit 1
fi

awk -F',' '
BEGIN {
  OFS=",";
  print "case,n,pass,pass_rate_pct,avg_area_impr_pct,avg_delay_delta,worse_delay_cnt" > out;
}
NR==1 { next }
{
  casek=$2;
  status=$3;
  bA=$4+0.0; bD=$5+0.0;
  aA=$6+0.0; aD=$7+0.0;

  n[casek]++;
  if (status == "PASS") pass[casek]++;

  if (bA > 1e-12) {
    impr = (bA-aA)*100.0/bA;
    sum_impr[casek] += impr;
    cnt_impr[casek]++;
  }

  dd = aD - bD;
  sum_dd[casek] += dd;
  cnt_dd[casek]++;
  if (dd > 1e-9) worse[casek]++;
}
END {
  for (k in n) {
    pr = (n[k] > 0) ? (100.0 * pass[k] / n[k]) : 0.0;
    ai = (cnt_impr[k] > 0) ? (sum_impr[k] / cnt_impr[k]) : 0.0;
    ad = (cnt_dd[k] > 0) ? (sum_dd[k] / cnt_dd[k]) : 0.0;
    wd = worse[k] + 0;
    printf "%s,%d,%d,%.2f,%.4f,%.4f,%d\n", k, n[k], pass[k], pr, ai, ad, wd >> out;
  }
}
' out="$OUT_CSV" "$INPUT_CSV"

echo "[done] $OUT_CSV" >&2
sort -t, -k5,5nr "$OUT_CSV" | sed -n '1,12p'
