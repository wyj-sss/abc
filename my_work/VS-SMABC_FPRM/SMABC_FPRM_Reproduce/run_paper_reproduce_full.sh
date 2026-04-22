#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

BIN="./reproduce_paper_full"
SRC="reproduce_paper_full.cpp"

if [[ ! -f "$SRC" ]]; then
  echo "[error] source not found: $SRC" >&2
  exit 1
fi

echo "[build] g++ -O3 -std=c++17 -o reproduce_paper_full reproduce_paper_full.cpp"
g++ -O3 -std=c++17 -o "$BIN" "$SRC"

echo "[run] RUNS=${RUNS:-20} NP=${NP:-100} GENERATIONS=${GENERATIONS:-50} VERIFY_METHOD=${VERIFY_METHOD:-1} BENCH_FILTER=${BENCH_FILTER:-<all>}"
"$BIN"

echo "[ok] finished. see ./paper_reproduce_out/"
