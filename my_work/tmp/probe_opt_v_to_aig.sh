#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="/mnt/d/My_abc_work/abc"
cd "$ROOT"

for f in my_work/VS-SMABC_FPRM/smabc_opt/*.v; do
  b="${f##*/}"
  {
    echo "read_verilog $f"
    echo "strash"
    echo "write_aiger /tmp/one.aig"
    echo "quit"
  } > /tmp/one_abc.scr

  ./abc -f /tmp/one_abc.scr >/tmp/one_abc.log 2>&1
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "PASS $b"
  else
    echo "FAIL $b rc=$rc"
    tail -n 3 /tmp/one_abc.log | tr '\n' ' '
    echo
  fi
done
