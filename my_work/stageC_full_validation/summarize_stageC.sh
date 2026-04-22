#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
STAGEC_DIR="$ROOT_DIR/my_work/stageC_full_validation"

INPUT_CSV="${1:-}"
if [ -z "$INPUT_CSV" ]; then
  latest_dir=$(ls -1dt "$STAGEC_DIR"/results/* 2>/dev/null | head -n1 || true)
  if [ -z "$latest_dir" ]; then
    echo "[error] no results folder found under $STAGEC_DIR/results" >&2
    exit 1
  fi
  INPUT_CSV="$latest_dir/summary.csv"
fi

if [ ! -f "$INPUT_CSV" ]; then
  echo "[error] input not found: $INPUT_CSV" >&2
  exit 1
fi

OUT_CSV="$(dirname "$INPUT_CSV")/case_rank.csv"

awk -F',' -v out="$OUT_CSV" '
BEGIN {
  OFS=",";
  print "case,n,pass,pass_rate_pct,avg_area_impr_pct,median_area_impr_pct,avg_delay_delta,worse_delay_cnt,accept_rate_pct,rej_runtime_pct_in_reject,rej_delay_pct_in_reject,rej_area_pct_in_reject" > out;
}
NR==1 { next }
{
  c=$2;
  status=$3;
  bA=$4+0.0; bD=$5+0.0;
  aA=$6+0.0; aD=$7+0.0;
  acc=$8+0.0; rej=$9+0.0;
  rr=$13+0.0; rd=$14+0.0; ra=$15+0.0;

  n[c]++;
  if (status == "PASS") pass[c]++;

  impr=(bA>1e-12)?((bA-aA)*100.0/bA):0.0;
  gain_sum[c]+=impr;
  gain_n[c]++;
  gain_val[c, gain_n[c]] = impr;

  dd=aD-bD;
  dd_sum[c]+=dd;
  dd_n[c]++;
  if (dd > 1e-9) worse[c]++;

  acc_sum[c]+=acc;
  rej_sum[c]+=rej;
  rr_sum[c]+=rr;
  rd_sum[c]+=rd;
  ra_sum[c]+=ra;
}
END {
  for (k in n) {
    pr = (n[k] > 0) ? (100.0*pass[k]/n[k]) : 0.0;
    avg = (gain_n[k] > 0) ? (gain_sum[k]/gain_n[k]) : 0.0;
    add = (dd_n[k] > 0) ? (dd_sum[k]/dd_n[k]) : 0.0;

    cnum = gain_n[k] + 0;
    med = 0.0;
    delete tmp;
    for (i=1; i<=cnum; i++) tmp[i]=gain_val[k,i];
    asort(tmp);
    if (cnum > 0) {
      if (cnum % 2 == 1) med = tmp[(cnum+1)/2];
      else med = (tmp[cnum/2] + tmp[cnum/2+1]) / 2.0;
    }

    at = acc_sum[k] + rej_sum[k];
    ar = (at > 1e-12) ? (100.0*acc_sum[k]/at) : 0.0;

    rrp = (rej_sum[k] > 1e-12) ? (100.0*rr_sum[k]/rej_sum[k]) : 0.0;
    rdp = (rej_sum[k] > 1e-12) ? (100.0*rd_sum[k]/rej_sum[k]) : 0.0;
    rap = (rej_sum[k] > 1e-12) ? (100.0*ra_sum[k]/rej_sum[k]) : 0.0;

    printf "%s,%d,%d,%.2f,%.4f,%.4f,%.4f,%d,%.2f,%.2f,%.2f,%.2f\n", k, n[k], pass[k], pr, avg, med, add, worse[k]+0, ar, rrp, rdp, rap >> out;
  }
}
' "$INPUT_CSV"

echo "[done] $OUT_CSV" >&2
{
  head -n 1 "$OUT_CSV"
  tail -n +2 "$OUT_CSV" | sort -t, -k5,5nr
} | sed -n '1,10p'
