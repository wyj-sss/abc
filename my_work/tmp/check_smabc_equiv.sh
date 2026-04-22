#!/usr/bin/env bash
set -u
set -o pipefail

cd /mnt/d/My_abc_work/abc || exit 1
orig_dir="my_work/VS-SMABC_FPRM/smabc_opt"
new_dir="my_work/VS-SMABC_FPRM/smabc_opt_abc"
aig_dir="my_work/VS-SMABC_FPRM/aig_output_opt"
report="my_work/VS-SMABC_FPRM/equiv_report.csv"
tmpd="$(mktemp -d /tmp/smabc_equiv.XXXXXX)"

echo "bench,orig_v_vs_new_v,new_v_vs_aig,orig_v_vs_aig_transitive" > "$report"
overall=0

for ov in "$orig_dir"/*_opt.v; do
  b="$(basename "$ov" .v)"
  nv="$new_dir/$b.v"
  aig="$aig_dir/$b.aig"

  if [ ! -f "$nv" ] || [ ! -f "$aig" ]; then
    echo "$b,MISSING,MISSING,MISSING" >> "$report"
    overall=1
    continue
  fi

  yosys_out="$tmpd/${b}_yosys.log"
  abc_out="$tmpd/${b}_abc.log"

  yosys -q -p "read_verilog $ov; prep -top $b; rename $b gold; design -stash gold; read_verilog $nv; prep -top $b; rename $b gate; design -stash gate; design -copy-from gold gold gold; design -copy-from gate gate gate; equiv_make gold gate equiv; prep -top equiv; equiv_simple; equiv_status -assert" >"$yosys_out" 2>&1
  if [ $? -eq 0 ]; then
    r1="PASS"
  else
    r1="FAIL"
    overall=1
  fi

  cec_text="$(./abc -c "read_verilog $nv; strash; write_aiger $tmpd/${b}_new_ref.aig; cec $tmpd/${b}_new_ref.aig $aig" 2>&1)"
  printf "%s\n" "$cec_text" > "$abc_out"
  if printf "%s\n" "$cec_text" | grep -q "Networks are equivalent"; then
    r2="PASS"
  else
    r2="FAIL"
    overall=1
  fi

  if [ "$r1" = "PASS" ] && [ "$r2" = "PASS" ]; then
    r3="PASS"
  else
    r3="FAIL"
  fi

  echo "$b,$r1,$r2,$r3" >> "$report"
done

if [ "$overall" -eq 0 ]; then
  echo "overall=PASS"
else
  echo "overall=FAIL"
fi

echo "report=$report"
cat "$report"
echo "tmp_logs=$tmpd"
