#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CV_DIR="$ROOT_DIR/my_work/crossval_3x3_11cxx"

INPUT_CSV="${1:-}"
if [ -z "$INPUT_CSV" ]; then
  latest_dir=$(ls -1dt "$CV_DIR"/results/* 2>/dev/null | head -n1 || true)
  if [ -z "$latest_dir" ]; then
    echo "[error] no results folder found under $CV_DIR/results" >&2
    exit 1
  fi
  INPUT_CSV="$latest_dir/summary.csv"
fi

if [ ! -f "$INPUT_CSV" ]; then
  echo "[error] input not found: $INPUT_CSV" >&2
  exit 1
fi

OUT_CSV="$(dirname "$INPUT_CSV")/combo_rank.csv"

awk -F',' '
BEGIN {
  OFS=",";
  print "combo,n,pass,pass_rate_pct,avg_area_impr_pct,median_area_impr_pct,avg_delay_delta,worse_delay_cnt,thresh_name,weight_name" > out;
}
NR==1 { next }
{
  combo=$2;
  status=$3;
  bA=$4+0.0; bD=$5+0.0;
  aA=$6+0.0; aD=$7+0.0;
  th=$16; wt=$17;

  n[combo]++;
  if (status == "PASS") pass[combo]++;

  if (!(combo in thresh)) thresh[combo]=th;
  if (!(combo in weight)) weight[combo]=wt;

  impr = (bA>1e-12) ? ((bA-aA)*100.0/bA) : 0.0;
  gain_sum[combo]+=impr;
  gain_n[combo]++;
  gain_val[combo, gain_n[combo]] = impr;

  dd = aD - bD;
  dd_sum[combo]+=dd;
  dd_n[combo]++;
  if (dd > 1e-9) worse[combo]++;
}
END {
  for (k in n) {
    pr = (n[k] > 0) ? (100.0*pass[k]/n[k]) : 0.0;
    avg = (gain_n[k] > 0) ? (gain_sum[k]/gain_n[k]) : 0.0;
    add = (dd_n[k] > 0) ? (dd_sum[k]/dd_n[k]) : 0.0;

    m = 0.0;
    c = gain_n[k] + 0;
    delete tmp;
    for (i=1; i<=c; i++) tmp[i] = gain_val[k, i];
    asort(tmp);
    if (c > 0) {
      if (c % 2 == 1) m = tmp[(c+1)/2];
      else m = (tmp[c/2] + tmp[c/2+1]) / 2.0;
    }

    printf "%s,%d,%d,%.2f,%.4f,%.4f,%.4f,%d,%s,%s\n", k, n[k], pass[k], pr, avg, m, add, worse[k]+0, thresh[k], weight[k] >> out;
  }
}
' out="$OUT_CSV" "$INPUT_CSV"

echo "[done] $OUT_CSV" >&2
{
  head -n 1 "$OUT_CSV"
  tail -n +2 "$OUT_CSV" | sort -t, -k5,5nr
} | sed -n '1,15p'
