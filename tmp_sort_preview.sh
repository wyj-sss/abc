#!/usr/bin/env bash
set -e
cd /mnt/d/My_abc_work/abc

print_top() {
  file="$1"
  col="$2"
  title="$3"
  echo "== ${title} (${file}) =="
  head -n 1 "$file"
  tail -n +2 "$file" | sort -t, -k${col},${col}gr | head -n 10
  echo
}

print_top "c17_work/output.csv" 15 "c17 sort by opt_potential desc"
print_top "c17_work/output.csv" 14 "c17 sort by criticality desc"
print_top "c499_work/output.csv" 15 "c499 sort by opt_potential desc"
print_top "c499_work/output.csv" 14 "c499 sort by criticality desc"
