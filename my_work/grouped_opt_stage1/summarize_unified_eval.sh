#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_DIR="$ROOT_DIR/my_work/grouped_opt_stage1"

INPUT_CSV="${1:-}"
if [ -z "$INPUT_CSV" ]; then
  latest=$(ls -1dt "$BASE_DIR"/results/* 2>/dev/null | head -n1 || true)
  [ -n "$latest" ] || { echo "[error] no run results found" >&2; exit 1; }
  INPUT_CSV="$latest/summary_all.csv"
fi

if [ ! -f "$INPUT_CSV" ]; then
  echo "[error] input summary not found: $INPUT_CSV" >&2
  exit 1
fi

OUT_DIR="$(dirname "$INPUT_CSV")"
OUT_CASE="$OUT_DIR/eval_by_group_case.csv"
OUT_GROUP="$OUT_DIR/eval_by_group.csv"
OUT_GLOBAL="$OUT_DIR/eval_global.csv"

awk -F',' -v out1="$OUT_CASE" -v out2="$OUT_GROUP" -v out3="$OUT_GLOBAL" '
BEGIN {
  OFS=",";
  print "group,case,n,pass,pass_rate_pct,avg_area_impr_pct,avg_delay_delta,worse_delay_cnt,accept_rate_pct" > out1;
}
NR==1 { next }
{
  g=$1; c=$3; s=$4;
  bA=$5+0.0; bD=$6+0.0; aA=$7+0.0; aD=$8+0.0;
  acc=$9+0.0; rej=$10+0.0;

  k=g "|" c;
  n[k]++;
  ng[g]++;
  if (s=="PASS") { pass[k]++; passg[g]++; passAll++; }

  impr=(bA>1e-12)?((bA-aA)*100.0/bA):0.0;
  sumImpr[k]+=impr; cntImpr[k]++;
  sumImprG[g]+=impr; cntImprG[g]++;
  sumImprAll+=impr; cntImprAll++;

  dd=aD-bD;
  sumDd[k]+=dd; cntDd[k]++;
  sumDdG[g]+=dd; cntDdG[g]++;
  sumDdAll+=dd; cntDdAll++;
  if (dd > 1e-9) { worse[k]++; worseG[g]++; worseAll++; }

  accSum[k]+=acc; rejSum[k]+=rej;
  accSumG[g]+=acc; rejSumG[g]+=rej;
  accAll+=acc; rejAll+=rej;

  nAll++;
}
END {
  for (k in n) {
    split(k, t, "|"); g=t[1]; c=t[2];
    pr=(n[k]>0)?(100.0*pass[k]/n[k]):0.0;
    ai=(cntImpr[k]>0)?(sumImpr[k]/cntImpr[k]):0.0;
    ad=(cntDd[k]>0)?(sumDd[k]/cntDd[k]):0.0;
    ar=((accSum[k]+rejSum[k])>1e-12)?(100.0*accSum[k]/(accSum[k]+rejSum[k])):0.0;
    printf "%s,%s,%d,%d,%.2f,%.4f,%.4f,%d,%.2f\n", g,c,n[k],pass[k],pr,ai,ad,worse[k]+0,ar >> out1;
  }

  print "group,n,pass,pass_rate_pct,avg_area_impr_pct,avg_delay_delta,worse_delay_cnt,accept_rate_pct" > out2;
  for (g in ng) {
    pr=(ng[g]>0)?(100.0*passg[g]/ng[g]):0.0;
    ai=(cntImprG[g]>0)?(sumImprG[g]/cntImprG[g]):0.0;
    ad=(cntDdG[g]>0)?(sumDdG[g]/cntDdG[g]):0.0;
    ar=((accSumG[g]+rejSumG[g])>1e-12)?(100.0*accSumG[g]/(accSumG[g]+rejSumG[g])):0.0;
    printf "%s,%d,%d,%.2f,%.4f,%.4f,%d,%.2f\n", g,ng[g],passg[g],pr,ai,ad,worseG[g]+0,ar >> out2;
  }

  print "n,pass,pass_rate_pct,avg_area_impr_pct,avg_delay_delta,worse_delay_cnt,accept_rate_pct" > out3;
  pr=(nAll>0)?(100.0*passAll/nAll):0.0;
  ai=(cntImprAll>0)?(sumImprAll/cntImprAll):0.0;
  ad=(cntDdAll>0)?(sumDdAll/cntDdAll):0.0;
  ar=((accAll+rejAll)>1e-12)?(100.0*accAll/(accAll+rejAll)):0.0;
  printf "%d,%d,%.2f,%.4f,%.4f,%d,%.2f\n", nAll,passAll,pr,ai,ad,worseAll+0,ar >> out3;
}
' "$INPUT_CSV"

echo "[done] $OUT_CASE" >&2
echo "[done] $OUT_GROUP" >&2
echo "[done] $OUT_GLOBAL" >&2

{
  echo "--- eval_by_group ---"
  cat "$OUT_GROUP"
  echo "--- eval_global ---"
  cat "$OUT_GLOBAL"
} | sed -n '1,30p'
