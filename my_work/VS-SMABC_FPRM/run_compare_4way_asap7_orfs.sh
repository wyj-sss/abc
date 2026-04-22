#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/my_work/VS-SMABC_FPRM"
COMPARE_SCRIPT="$SCRIPT_DIR/compare_4way_area_delay_runtime.sh"

# ORFS ASAP7 library root
ORFS_LIB_NLDM_DIR="${ORFS_LIB_NLDM_DIR:-/mnt/d/Git_project/OpenROAD-flow-scripts/flow/platforms/asap7/lib/NLDM}"

# Corner and VT selection for the 4-way run
ASAP7_CORNER="${ASAP7_CORNER:-FF}"
ASAP7_VT="${ASAP7_VT:-RVT}"

OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/compare_4way_out_asap7_orfs_${ASAP7_VT}_${ASAP7_CORNER}}"
COMBINED_LIB="${COMBINED_LIB:-$SCRIPT_DIR/asap7_orfs_combined_${ASAP7_VT}_${ASAP7_CORNER}_nldm.lib}"

AO_LIB="$ORFS_LIB_NLDM_DIR/asap7sc7p5t_AO_${ASAP7_VT}_${ASAP7_CORNER}_nldm_211120.lib.gz"
INVBUF_LIB="$ORFS_LIB_NLDM_DIR/asap7sc7p5t_INVBUF_${ASAP7_VT}_${ASAP7_CORNER}_nldm_220122.lib.gz"
OA_LIB="$ORFS_LIB_NLDM_DIR/asap7sc7p5t_OA_${ASAP7_VT}_${ASAP7_CORNER}_nldm_211120.lib.gz"
SIMPLE_LIB="$ORFS_LIB_NLDM_DIR/asap7sc7p5t_SIMPLE_${ASAP7_VT}_${ASAP7_CORNER}_nldm_211120.lib.gz"

for f in "$AO_LIB" "$INVBUF_LIB" "$OA_LIB" "$SIMPLE_LIB"; do
  if [ ! -f "$f" ]; then
    echo "[error] missing ORFS combinational lib: $f" >&2
    exit 1
  fi
done

if [ ! -x "$ROOT_DIR/abc" ]; then
  echo "[error] abc binary not found/executable at $ROOT_DIR/abc" >&2
  exit 1
fi

tmpd="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpd"
}
trap cleanup EXIT

gzip -dc "$AO_LIB" > "$tmpd/ao.lib"
gzip -dc "$INVBUF_LIB" > "$tmpd/invbuf.lib"
gzip -dc "$OA_LIB" > "$tmpd/oa.lib"
gzip -dc "$SIMPLE_LIB" > "$tmpd/simple.lib"

# ABC's read_lib keeps one top-level library block. Merge extra cell blocks into AO library.
awk '
  {
    lines[++n] = $0
  }
  END {
    last = n
    while (last > 0 && lines[last] ~ /^[[:space:]]*$/) {
      last--
    }
    if (last > 0 && lines[last] ~ /^[[:space:]]*}[[:space:]]*$/) {
      last--
    }
    for (i = 1; i <= last; i++) {
      print lines[i]
    }
  }
' "$tmpd/ao.lib" > "$COMBINED_LIB"

extract_cells() {
  local lib_file="$1"
  awk '
    BEGIN {
      in_cell = 0
      depth = 0
    }
    /^[[:space:]]*cell[[:space:]]*\(/ {
      in_cell = 1
      depth = 0
    }
    in_cell {
      print
      opens = gsub(/\{/, "{")
      closes = gsub(/\}/, "}")
      depth += opens - closes
      if (depth == 0) {
        in_cell = 0
      }
    }
  ' "$lib_file"
}

{
  extract_cells "$tmpd/invbuf.lib"
  extract_cells "$tmpd/oa.lib"
  extract_cells "$tmpd/simple.lib"
  echo "}"
} >> "$COMBINED_LIB"

echo "[info] combined lib generated: $COMBINED_LIB"
echo "[info] output dir: $OUT_DIR"

LIB_FILE="$COMBINED_LIB" OUT_DIR="$OUT_DIR" bash "$COMPARE_SCRIPT"

echo "[done] report: $OUT_DIR/compare_4way_area_delay_runtime.csv"