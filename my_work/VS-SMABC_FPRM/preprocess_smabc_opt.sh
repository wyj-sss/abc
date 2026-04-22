#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/mnt/d/My_abc_work/abc/my_work/VS-SMABC_FPRM"
SRC_DIR="$ROOT_DIR/smabc_opt"
DST_DIR="$ROOT_DIR/smabc_opt_abc"

mkdir -p "$DST_DIR"

for v in "$SRC_DIR"/*_opt.v; do
  bname="$(basename "$v")"
  yosys -q -p "read_verilog $v; write_verilog -noattr $DST_DIR/$bname"
done

echo "Preprocess done: $DST_DIR"
