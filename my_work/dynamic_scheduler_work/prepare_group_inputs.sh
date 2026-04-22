#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_DIR="$ROOT_DIR/my_work/dynamic_scheduler_work"
INPUT_CSV="${1:-$BASE_DIR/bench_criticality.csv}"
OUT_GROUP_DIR="${OUT_GROUP_DIR:-$BASE_DIR/groups}"
CRIT_LOW="${CRIT_LOW:-0.25}"
CRIT_HIGH="${CRIT_HIGH:-0.90}"

mkdir -p "$OUT_GROUP_DIR"

if [ ! -f "$INPUT_CSV" ]; then
  echo "[error] criticality csv not found: $INPUT_CSV" >&2
  exit 1
fi

for g in L M H; do
  : > "$OUT_GROUP_DIR/group_${g}.txt"
done

PARTITION_CSV="$OUT_GROUP_DIR/bench_criticality_partition.csv"
echo "bench,total_nodes,low_nodes,mid_nodes,high_nodes,low_ratio,mid_ratio,high_ratio,group,input_csv" > "$PARTITION_CSV"

awk -F',' '
function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
NR==1 {
  for (i=1; i<=NF; i++) {
    h=trim($i)
    if (h=="bench") benchCol=i
    else if (h=="criticality") critCol=i
    else if (h=="group") groupCol=i
  }
  if (benchCol==0 || (critCol==0 && groupCol==0)) {
    printf("[error] csv header must contain bench + criticality OR bench + group\\n") > "/dev/stderr"
    exit 2
  }
  next
}
{
  b=trim($(benchCol))
  if (b=="") next

  if (groupCol>0 && critCol==0) {
    g=trim($(groupCol))
    if (g=="L" || g=="M" || g=="H") {
      forced[b]=g
      total[b]=1
      low[b]=(g=="L")?1:0
      mid[b]=(g=="M")?1:0
      high[b]=(g=="H")?1:0
    }
    next
  }

  c=trim($(critCol))+0.0
  total[b]++
  if (c>=hi) high[b]++
  else if (c<=lo) low[b]++
  else mid[b]++
}
END {
  for (b in total) {
    t=total[b]
    l=low[b]+0
    m=mid[b]+0
    h=high[b]+0

    if (b in forced) {
      g=forced[b]
    } else if (h>=m && h>=l) {
      g="H"
    } else if (l>=m && l>=h) {
      g="L"
    } else {
      g="M"
    }

    lr=(t>0)?(100.0*l/t):0.0
    mr=(t>0)?(100.0*m/t):0.0
    hr=(t>0)?(100.0*h/t):0.0

    print b >> outdir "/group_" g ".txt"
    printf "%s,%d,%d,%d,%d,%.4f,%.4f,%.4f,%s,%s\\n", b, t, l, m, h, lr, mr, hr, g, infile >> partcsv
  }
}
' lo="$CRIT_LOW" hi="$CRIT_HIGH" outdir="$OUT_GROUP_DIR" infile="$INPUT_CSV" partcsv="$PARTITION_CSV" "$INPUT_CSV"

for g in L M H; do
  f="$OUT_GROUP_DIR/group_${g}.txt"
  if [ -s "$f" ]; then
    sort -u "$f" -o "$f"
  fi
done

MANIFEST="$OUT_GROUP_DIR/group_manifest.csv"
echo "group,count,file" > "$MANIFEST"
for g in L M H; do
  f="$OUT_GROUP_DIR/group_${g}.txt"
  c=0
  [ -f "$f" ] && c=$(awk 'NF{n++} END{print n+0}' "$f")
  echo "$g,$c,$f" >> "$MANIFEST"
done

echo "[done] group files in: $OUT_GROUP_DIR" >&2
echo "[done] manifest: $MANIFEST" >&2
echo "[done] partition detail: $PARTITION_CSV" >&2
echo "[info] thresholds: low<=$CRIT_LOW high>=$CRIT_HIGH" >&2
cat "$MANIFEST"