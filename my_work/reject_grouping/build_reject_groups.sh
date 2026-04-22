#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RG_DIR="$ROOT_DIR/my_work/reject_grouping"

INPUT_CSV="${1:-$ROOT_DIR/my_work/alpha_ablation_11cxx/results/run_20260403_alpha20/summary.csv}"
CASE_FILTER="${CASE_FILTER:-alpha_default}"
MIN_REJECT="${MIN_REJECT:-30}"
HIGH_Q="${HIGH_Q:-0.70}"
LOW_Q="${LOW_Q:-0.40}"
OUT_DIR="${OUT_DIR:-$RG_DIR/results}"

mkdir -p "$OUT_DIR"

if [ ! -f "$INPUT_CSV" ]; then
  echo "[error] input summary not found: $INPUT_CSV" >&2
  exit 1
fi

PROFILE_CSV="$OUT_DIR/bench_reject_profile.csv"
GROUP_CSV="$OUT_DIR/bench_groups.csv"
META_TXT="$OUT_DIR/group_thresholds.txt"

# 1) Build per-bench reject profile for one selected case.
awk -F',' -v casef="$CASE_FILTER" '
BEGIN {
  OFS=",";
  print "bench,n_samples,rejected_total,reject_runtime,reject_area,reject_delay,runtime_pct,area_pct,delay_pct";
}
NR==1 { next }
{
  bench=$1;
  c=$2;
  if (casef != "" && c != casef) next;

  n[bench]++;
  rej[bench] += ($9 + 0.0);
  rr[bench]  += ($13 + 0.0);
  ra[bench]  += ($15 + 0.0);
  rd[bench]  += ($14 + 0.0);
}
END {
  for (b in n) {
    rj = rej[b] + 0.0;
    rp = (rj > 1e-12) ? (100.0 * rr[b] / rj) : 0.0;
    ap = (rj > 1e-12) ? (100.0 * ra[b] / rj) : 0.0;
    dp = (rj > 1e-12) ? (100.0 * rd[b] / rj) : 0.0;
    printf "%s,%d,%.0f,%.0f,%.0f,%.0f,%.4f,%.4f,%.4f\n", b, n[b], rj, rr[b], ra[b], rd[b], rp, ap, dp;
  }
}
' "$INPUT_CSV" | {
  read -r header
  echo "$header"
  sort
} > "$PROFILE_CSV"

# 2) Compute quantile thresholds from benches with enough rejects.
read -r AREA_LOW AREA_HIGH RT_LOW RT_HIGH ELIGIBLE_CNT <<EOF
$(awk -F',' -v minr="$MIN_REJECT" -v qh="$HIGH_Q" -v ql="$LOW_Q" '
function qval(arr, n, q,   x, idx) {
  if (n <= 0) return 0.0;
  for (x = 1; x <= n; x++) tmp[x] = arr[x];
  asort(tmp);
  idx = q * n;
  if (idx != int(idx)) idx = int(idx) + 1;
  else idx = int(idx);
  if (idx < 1) idx = 1;
  if (idx > n) idx = n;
  return tmp[idx];
}
NR==1 { next }
{
  rej = $3 + 0.0;
  if (rej >= minr) {
    n++;
    area[n] = $8 + 0.0;
    rt[n]   = $7 + 0.0;
  }
}
END {
  if (n == 0) {
    printf "0 0 0 0 0\n";
    exit;
  }
  al = qval(area, n, ql);
  ah = qval(area, n, qh);
  rl = qval(rt,   n, ql);
  rh = qval(rt,   n, qh);
  printf "%.6f %.6f %.6f %.6f %d\n", al, ah, rl, rh, n;
}
' "$PROFILE_CSV")
EOF

if [ "$ELIGIBLE_CNT" -eq 0 ]; then
  echo "[error] no eligible benches for grouping (MIN_REJECT=$MIN_REJECT)." >&2
  exit 1
fi

cat > "$META_TXT" <<EOF
input_csv=$INPUT_CSV
case_filter=$CASE_FILTER
min_reject=$MIN_REJECT
high_quantile=$HIGH_Q
low_quantile=$LOW_Q
eligible_bench_cnt=$ELIGIBLE_CNT
area_low_threshold_pct=$AREA_LOW
area_high_threshold_pct=$AREA_HIGH
runtime_low_threshold_pct=$RT_LOW
runtime_high_threshold_pct=$RT_HIGH
EOF

# 3) Assign groups and strategies.
awk -F',' \
  -v minr="$MIN_REJECT" \
  -v al="$AREA_LOW" -v ah="$AREA_HIGH" \
  -v rl="$RT_LOW"   -v rh="$RT_HIGH" '
BEGIN {
  OFS=",";
  print "bench,group,strategy,n_samples,rejected_total,runtime_pct,area_pct,delay_pct,reason";
}
NR==1 { next }
{
  b=$1; ns=$2+0; rj=$3+0;
  rp=$7+0.0; ap=$8+0.0; dp=$9+0.0;

  if (rj < minr) {
    g="U_small"; s="observe_only";
    reason="reject_count_below_min";
  } else {
    areaHigh = (ap >= ah);
    areaLow  = (ap <= al);
    rtHigh   = (rp >= rh);
    rtLow    = (rp <= rl);

    if (areaHigh && rtLow) {
      g="A"; s="quality_first"; reason="area_high_runtime_low";
    } else if (rtHigh && areaLow) {
      g="B"; s="efficiency_first"; reason="runtime_high_area_low";
    } else if (areaHigh && rtHigh) {
      g="C"; s="hybrid"; reason="area_high_runtime_high";
    } else if (areaLow && rtLow) {
      g="D"; s="stable_baseline"; reason="area_low_runtime_low";
    } else {
      g="U_mid"; s="observe_or_light_hybrid"; reason="mixed_mid_zone";
    }
  }

  printf "%s,%s,%s,%d,%.0f,%.4f,%.4f,%.4f,%s\n", b, g, s, ns, rj, rp, ap, dp, reason;
}
' "$PROFILE_CSV" | {
  read -r header
  echo "$header"
  sort
} > "$GROUP_CSV"

echo "[done] profile: $PROFILE_CSV" >&2
echo "[done] groups : $GROUP_CSV" >&2
echo "[done] meta   : $META_TXT" >&2

echo "--- GROUP COUNTS ---"
awk -F',' 'NR==1{next}{cnt[$2]++} END{for(g in cnt) printf "%s,%d\n", g, cnt[g]}' "$GROUP_CSV" | sort
