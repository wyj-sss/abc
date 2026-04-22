#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
AIG_DIR="${1:-$ROOT_DIR/my_work/xiaorong_aig}"
OUT_CSV="${2:-$ROOT_DIR/my_work/dynamic_scheduler_work/bench_criticality.csv}"
LIB_FILE="${LIB_FILE:-$ROOT_DIR/my_work/c17_work/NangateOpenCellLibrary_typical.lib}"
TMP_DIR="${TMP_DIR:-$ROOT_DIR/my_work/dynamic_scheduler_work/tmp_criticality}"
BUILD_JOBS="${BUILD_JOBS:-1}"

mkdir -p "$(dirname "$OUT_CSV")" "$TMP_DIR"

if [ ! -d "$AIG_DIR" ]; then
  echo "[error] AIG dir not found: $AIG_DIR" >&2
  exit 1
fi
if [ ! -f "$LIB_FILE" ]; then
  echo "[error] liberty not found: $LIB_FILE" >&2
  exit 1
fi
if [ ! -x "$ROOT_DIR/abc" ]; then
  echo "[build] make -j${BUILD_JOBS}" >&2
  (cd "$ROOT_DIR" && make -j"$BUILD_JOBS")
fi

shopt -s nullglob
AIGS=("$AIG_DIR"/*.aig)
if [ "${#AIGS[@]}" -eq 0 ]; then
  echo "[error] no .aig files in: $AIG_DIR" >&2
  exit 1
fi

printf "bench,criticality\n" > "$OUT_CSV"

for aig in "${AIGS[@]}"; do
  bench="$(basename "$aig" .aig)"
  node_csv="$TMP_DIR/${bench}_nodes.csv"
  cmd_file="$TMP_DIR/${bench}.scr"
  log_file="$TMP_DIR/${bench}.log"

  cat > "$cmd_file" <<EOF
read_liberty $LIB_FILE
read_aiger $aig
map_oto
mapper_extract -o $node_csv
quit
EOF

  "$ROOT_DIR/abc" -f "$cmd_file" > "$log_file" 2>&1
  if [ ! -s "$node_csv" ]; then
    echo "[warn] mapper_extract empty: $bench" >&2
    continue
  fi

  awk -F',' -v b="$bench" '
    NR==1 {
      for (i=1; i<=NF; i++) {
        if ($i=="criticality") c=i
      }
      next
    }
    c>0 {
      v=$c+0.0
      printf "%s,%.6f\n", b, v
    }
  ' "$node_csv" >> "$OUT_CSV"

  echo "[ok] extracted bench=$bench" >&2
  rm -f "$cmd_file"
done

echo "[done] bench criticality csv: $OUT_CSV" >&2
