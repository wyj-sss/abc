#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
KS_DIR="$ROOT_DIR/my_work/k_scan_winvpair_11cxx"

INPUT_CSV="${1:-}"
if [ -z "$INPUT_CSV" ]; then
  latest_dir=$(ls -1dt "$KS_DIR"/results/* 2>/dev/null | head -n1 || true)
  if [ -z "$latest_dir" ]; then
    echo "[error] no results folder found under $KS_DIR/results" >&2
    exit 1
  fi
  INPUT_CSV="$latest_dir/summary.csv"
fi

if [ ! -f "$INPUT_CSV" ]; then
  echo "[error] input not found: $INPUT_CSV" >&2
  exit 1
fi

OUT_CSV="$(dirname "$INPUT_CSV")/k_rank.csv"

awk -F',' -v out="$OUT_CSV" '
BEGIN {
  OFS=",";
  print "k_case,k_value,n,pass,pass_rate_pct,avg_area_impr_pct,median_area_impr_pct,avg_delay_delta,worse_delay_cnt,accept_rate_pct,rej_runtime_pct_in_reject,rej_delay_pct_in_reject,rej_area_pct_in_reject" > out;
}
NR==1 { next }
{
  kcase=$2; kval=$16+0;
  status=$3;
  bA=$4+0.0; bD=$5+0.0;
  aA=$6+0.0; aD=$7+0.0;
  acc=$8+0.0; rej=$9+0.0;
  rr=$13+0.0; rd=$14+0.0; ra=$15+0.0;

  n[kcase]++;
  kv[kcase]=kval;
  if (status == "PASS") pass[kcase]++;

  impr=(bA>1e-12)?((bA-aA)*100.0/bA):0.0;
  gain_sum[kcase]+=impr;
  gain_n[kcase]++;
  gain_val[kcase, gain_n[kcase]] = impr;

  dd=aD-bD;
  dd_sum[kcase]+=dd;
  dd_n[kcase]++;
  if (dd > 1e-9) worse[kcase]++;

  acc_sum[kcase]+=acc;
  rej_sum[kcase]+=rej;
  rr_sum[kcase]+=rr;
  rd_sum[kcase]+=rd;
  ra_sum[kcase]+=ra;
}
END {
  for (k in n) {
    pr = (n[k] > 0) ? (100.0*pass[k]/n[k]) : 0.0;
    avg = (gain_n[k] > 0) ? (gain_sum[k]/gain_n[k]) : 0.0;
    add = (dd_n[k] > 0) ? (dd_sum[k]/dd_n[k]) : 0.0;

    c = gain_n[k] + 0;
    m = 0.0;
    delete tmp;
    for (i=1; i<=c; i++) tmp[i]=gain_val[k,i];
    asort(tmp);
    if (c > 0) {
      if (c % 2 == 1) m = tmp[(c+1)/2];
      else m = (tmp[c/2] + tmp[c/2+1]) / 2.0;
    }

    at = acc_sum[k] + rej_sum[k];
    ar = (at > 1e-12) ? (100.0*acc_sum[k]/at) : 0.0;

    rrp = (rej_sum[k] > 1e-12) ? (100.0*rr_sum[k]/rej_sum[k]) : 0.0;
    rdp = (rej_sum[k] > 1e-12) ? (100.0*rd_sum[k]/rej_sum[k]) : 0.0;
    rap = (rej_sum[k] > 1e-12) ? (100.0*ra_sum[k]/rej_sum[k]) : 0.0;

    printf "%s,%d,%d,%d,%.2f,%.4f,%.4f,%.4f,%d,%.2f,%.2f,%.2f,%.2f\n", k, kv[k], n[k], pass[k], pr, avg, m, add, worse[k]+0, ar, rrp, rdp, rap >> out;
  }
}
' "$INPUT_CSV"

echo "[done] $OUT_CSV" >&2
{
  head -n 1 "$OUT_CSV"
  tail -n +2 "$OUT_CSV" | sort -t, -k6,6nr
} | sed -n '1,10p'
