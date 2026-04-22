#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULT_DIR="$ROOT_DIR/my_work/ablation_results"
INPUT_CSV="${1:-$RESULT_DIR/summary.csv}"
OUT_CASE="$RESULT_DIR/summary_by_case.csv"
OUT_RECO="$RESULT_DIR/recommended_cases.csv"

if [ ! -f "$INPUT_CSV" ]; then
  echo "[error] input summary not found: $INPUT_CSV"
  exit 1
fi

awk -F',' '
function qtrim(s){ gsub(/^"|"$/, "", s); return s }
function abs(x){ return x < 0 ? -x : x }
BEGIN {
  OFS=",";
}
NR == 1 { next }
{
  caseName = $2;
  status = $3;
  beforeArea = $4 + 0.0;
  beforeDelay = $5 + 0.0;
  afterArea = $6 + 0.0;
  afterDelay = $7 + 0.0;

  total[caseName]++;
  if (status == "PASS") {
    pass[caseName]++;
    if (beforeArea > 1e-12) {
      gain = (beforeArea - afterArea) * 100.0 / beforeArea;
      nGain[caseName]++;
      gainVal[caseName, nGain[caseName]] = gain;
      sumGain[caseName] += gain;
      if (!(caseName in minGain) || gain < minGain[caseName])
        minGain[caseName] = gain;
    }
    dlt = afterDelay - beforeDelay;
    nDelay[caseName]++;
    sumDelay[caseName] += dlt;
  }

  if (!(caseName in argsRead)) argsRead[caseName] = qtrim($16);
  if (!(caseName in argsOpt)) argsOpt[caseName] = qtrim($17);
  cases[caseName] = 1;
}
END {
  bestMedian = -1e9;

  for (c in cases) {
    t = total[c] + 0;
    p = pass[c] + 0;
    passRate[c] = (t > 0) ? (100.0 * p / t) : 0.0;

    k = nGain[c] + 0;
    if (k > 0) {
      delete tmp;
      for (i = 1; i <= k; i++) tmp[i] = gainVal[c, i];
      asort(tmp);

      medIdx1 = int((k + 1) / 2);
      medIdx2 = int((k + 2) / 2);
      median[c] = (tmp[medIdx1] + tmp[medIdx2]) / 2.0;

      p25Idx = int((k - 1) * 0.25) + 1;
      if (p25Idx < 1) p25Idx = 1;
      if (p25Idx > k) p25Idx = k;
      p25[c] = tmp[p25Idx];

      meanGain[c] = sumGain[c] / k;
      worst[c] = minGain[c];
    }
    else {
      median[c] = 0.0;
      p25[c] = 0.0;
      meanGain[c] = 0.0;
      worst[c] = 0.0;
    }

    nd = nDelay[c] + 0;
    meanDelay[c] = (nd > 0) ? (sumDelay[c] / nd) : 0.0;

    # Candidate for best median benchmark among safe settings
    if (passRate[c] >= 99.999 && meanDelay[c] <= 1e-9 && median[c] > bestMedian)
      bestMedian = median[c];
  }

  print "case,benches,pass,pass_rate_pct,mean_area_gain_pct,median_area_gain_pct,p25_area_gain_pct,worst_area_gain_pct,mean_delay_delta,phyread_args,phyopt_args,recommended" > "'"$OUT_CASE"'";
  print "case,reason" > "'"$OUT_RECO"'";

  for (c in cases) {
    rec = "no";
    reason = "";

    if (passRate[c] < 99.999)
      reason = "pass_rate<100%";
    else if (meanDelay[c] > 1e-9)
      reason = "mean_delay_delta>0";
    else if (p25[c] < -1e-9)
      reason = "p25_area_gain<0";
    else if (bestMedian > -1e8 && median[c] < 0.95 * bestMedian)
      reason = "median_gain<95%_of_best";
    else {
      rec = "yes";
      reason = "stable_and_near_best";
    }

    printf "%s,%d,%d,%.2f,%.4f,%.4f,%.4f,%.4f,%.6f,\"%s\",\"%s\",%s\n",
      c, total[c], pass[c], passRate[c], meanGain[c], median[c], p25[c], worst[c], meanDelay[c], argsRead[c], argsOpt[c], rec >> "'"$OUT_CASE"'";

    if (rec == "yes")
      printf "%s,%s\n", c, reason >> "'"$OUT_RECO"'";
  }
}
' "$INPUT_CSV"

echo "[done] case summary: $OUT_CASE"
echo "[done] recommended: $OUT_RECO"
