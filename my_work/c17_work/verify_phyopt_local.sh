#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

usage() {
  cat <<EOF
Usage:
  $(basename "$0") [bench_name ...]

Examples:
  $(basename "$0")
  $(basename "$0") c880
  ROUNDS=1 PART_SIZE=30 $(basename "$0") c499
  BENCH_NAMES="c17 c880" $(basename "$0")
  INPUT_AIG=c880_work/c880.aig OUTPUT_AIG=c880_work/c880_custom.aig $(basename "$0")

Configuration (env vars):
  LIB_FILE            liberty file path
  ROUNDS              phyopt -n (default: 2)
  PART_SIZE           phyopt -k (default: 25)
  BUILD_JOBS          make -j (default: 1)
  SHOW_QOR            1=print mapped stats before/after (default: 1)
  CLEAN_OUTPUT        1=remove old csv/out/log before run (default: 1)

  BENCH_NAMES         space-separated bench list, used when no args given

  INPUT_AIG           explicit input aig path (single-case mode)
  OUTPUT_AIG          explicit output aig path (single-case mode)
  CSV_FILE            explicit mapper_extract csv path
  LOG_FILE            explicit log path

Notes:
  1) If INPUT_AIG is set, script runs one case using INPUT_AIG (+ optional OUTPUT_AIG/CSV_FILE/LOG_FILE).
  2) Otherwise it uses bench names and default paths like <bench>_work/<bench>.aig.
EOF
}

LIB_DEFAULT="c17_work/NangateOpenCellLibrary_typical.lib"
LIB_FILE="${LIB_FILE:-$LIB_DEFAULT}"
ROUNDS="${ROUNDS:-2}"
PART_SIZE="${PART_SIZE:-25}"
BUILD_JOBS="${BUILD_JOBS:-1}"
SHOW_QOR="${SHOW_QOR:-1}"
CLEAN_OUTPUT="${CLEAN_OUTPUT:-1}"
PHYREAD_ARGS="${PHYREAD_ARGS:-}"
PHYOPT_ARGS="${PHYOPT_ARGS:-}"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 0 ]; then
  BENCHES=("$@")
elif [ -n "${BENCH_NAMES:-}" ]; then
  # shellcheck disable=SC2206
  BENCHES=(${BENCH_NAMES})
else
  BENCHES=(c17 c499 c880)
fi

WORKDIR_FOR_BENCH() {
  local b="$1"
  echo "${b}_work"
}

ensure_build() {
  echo "[build] make -j${BUILD_JOBS}"
  if ! make -j"${BUILD_JOBS}"; then
    echo "[error] build failed"
    return 1
  fi
  if [ ! -x "./abc" ]; then
    echo "[error] ./abc not found or not executable after build"
    return 1
  fi
  return 0
}

run_one_case() {
  local tag="$1"
  local in_aig
  local csv
  local out_aig
  local cmd_file
  local log_file
  local stat_before
  local stat_after

  in_aig="$2"
  csv="$3"
  out_aig="$4"
  log_file="$5"
  cmd_file="/tmp/phyopt_${tag}_$$.scr"

  stat_before="/tmp/phyopt_stat_before_${tag}_$$.scr"
  stat_after="/tmp/phyopt_stat_after_${tag}_$$.scr"

  if [ ! -f "$in_aig" ]; then
    echo "[skip] ${tag}: missing input ${in_aig}"
    return 2
  fi
  if [ ! -f "$LIB_FILE" ]; then
    echo "[fail] ${tag}: missing liberty ${LIB_FILE}"
    return 1
  fi

  if [ "$CLEAN_OUTPUT" = "1" ]; then
    rm -f "$csv" "$out_aig" "$log_file"
  fi

  if [ "$SHOW_QOR" = "1" ]; then
    cat > "$stat_before" <<EOF
read_liberty $LIB_FILE
read_aiger $in_aig
map
ps
quit
EOF
    echo "[qor] ${tag}: BEFORE"
    ./abc -f "$stat_before" | sed 's/^/        /'
    rm -f "$stat_before"
  fi

  cat > "$cmd_file" <<EOF
read_liberty $LIB_FILE
read_aiger $in_aig
map_oto
mapper_extract -o $csv
phyread $PHYREAD_ARGS $csv
phyopt -n $ROUNDS -k $PART_SIZE $PHYOPT_ARGS
strash
write_aiger $out_aig
cec -n $in_aig $out_aig
quit
EOF

  echo "[run] ${tag}: rounds=${ROUNDS} part_size=${PART_SIZE}"
  ./abc -f "$cmd_file" > "$log_file" 2>&1
  local rc=$?
  rm -f "$cmd_file"

  if [ $rc -ne 0 ]; then
    echo "[fail] ${tag}: abc exited with code ${rc}"
    echo "        log: ${log_file}"
    return 1
  fi

  if grep -q "Networks are equivalent" "$log_file"; then
    echo "[pass] ${tag}: equivalent"
    echo "        out: ${out_aig}"
    if [ "$SHOW_QOR" = "1" ]; then
      cat > "$stat_after" <<EOF
read_liberty $LIB_FILE
read_aiger $out_aig
map
ps
quit
EOF
      echo "[qor] ${tag}: AFTER"
      ./abc -f "$stat_after" | sed 's/^/        /'
      rm -f "$stat_after"
    fi
    return 0
  fi

  echo "[fail] ${tag}: equivalence not confirmed"
  echo "        log: ${log_file}"
  return 1
}

run_one_bench() {
  local bench="$1"
  local work
  local in_aig
  local csv
  local out_aig
  local log_file

  work="$(WORKDIR_FOR_BENCH "$bench")"
  in_aig="${work}/${bench}.aig"
  csv="${work}/output.csv"
  out_aig="${work}/${bench}_phyopt_local.aig"
  log_file="${work}/phyopt_${bench}.log"

  run_one_case "$bench" "$in_aig" "$csv" "$out_aig" "$log_file"
}

main() {
  local ok=0
  local fail=0
  local skip=0

  echo "[info] root=${ROOT_DIR}"
  echo "[info] liberty=${LIB_FILE}"
  echo "[info] rounds=${ROUNDS} part_size=${PART_SIZE}"
  echo "[info] show_qor=${SHOW_QOR} clean_output=${CLEAN_OUTPUT}"
  echo "[info] phyread_args='${PHYREAD_ARGS}' phyopt_args='${PHYOPT_ARGS}'"

  ensure_build || exit 1

  if [ -n "${INPUT_AIG:-}" ]; then
    local tag
    local in_aig
    local out_aig
    local csv
    local log_file

    in_aig="$INPUT_AIG"
    tag="$(basename "$in_aig")"
    tag="${tag%.aig}"

    out_aig="${OUTPUT_AIG:-${tag}_work/${tag}_phyopt_local.aig}"
    csv="${CSV_FILE:-${tag}_work/output.csv}"
    log_file="${LOG_FILE:-${tag}_work/phyopt_${tag}.log}"

    echo "[info] single-case INPUT_AIG=${in_aig}"
    run_one_case "$tag" "$in_aig" "$csv" "$out_aig" "$log_file"
    case $? in
      0) ok=$((ok+1)) ;;
      2) skip=$((skip+1)) ;;
      *) fail=$((fail+1)) ;;
    esac
  else
    echo "[info] benches=${BENCHES[*]}"
    for b in "${BENCHES[@]}"; do
      run_one_bench "$b"
      case $? in
        0) ok=$((ok+1)) ;;
        2) skip=$((skip+1)) ;;
        *) fail=$((fail+1)) ;;
      esac
    done
  fi

  echo "[summary] pass=${ok} fail=${fail} skip=${skip}"
  if [ $fail -ne 0 ]; then
    exit 1
  fi
  exit 0
}

main
