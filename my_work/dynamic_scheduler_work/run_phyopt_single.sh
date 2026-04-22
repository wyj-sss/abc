#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ABC_BIN="$ROOT_DIR/abc"
LIB_FILE="$ROOT_DIR/my_work/c17_work/NangateOpenCellLibrary_typical.lib"

INPUT_AIG=""
OUT_V=""
OUT_BLIF=""
OUT_AIG=""
LOG_FILE=""
PHY_CSV=""
CMD_FILE=""

# Keep defaults aligned with current fitted-function flow.
I_W="0.50"
P_W="0.40"
F_W="0.05"
G_W="0.05"
ROUNDS="3"
K_V="40"
L_T="0.25"
H_T="0.90"
CASE_TIMEOUT_SEC="300"

PHY_MICRO_ENABLE="0"
PHY_FIT_ENABLE="1"
FIT_FILE=""
PHY_FIT_L0_SCALE="0.35"
PHY_FIT_L1_SCALE="0.25"

usage() {
  cat <<'EOF'
Usage:
  run_phyopt_single.sh --input-aig <file.aig> [output options] [flow options]

Description:
  One-command phyopt flow with fitted-function scoring:
  1) read_lib
  2) read_aiger
  3) map_oto
  4) mapper_extract
  5) phyread
  6) phyopt
  7) map; ps
  8) write_verilog / write_blif / write_aiger (as requested)

Required:
  --input-aig <path>            Input AIG file.

Output options (at least one is recommended):
  --out-v <path>                Write optimized netlist as Verilog.
  --out-blif <path>             Write optimized netlist as BLIF.
  --out-aig <path>              Write optimized strashed AIG.
  --log-file <path>             Log file path (default: <out_dir>/<stem>.phyopt.log).

Flow options:
  --abc-bin <path>              ABC executable (default: <repo>/abc).
  --lib-file <path>             Liberty file (default: my_work/c17_work/NangateOpenCellLibrary_typical.lib).
  --phy-csv <path>              mapper_extract CSV path (default: <out_dir>/<stem>.phy.csv).
  --cmd-file <path>             Keep generated abc script at this path (default: temporary file).

  --i <float>                   phyread -i (default: 0.50)
  --p <float>                   phyread -p (default: 0.40)
  --f <float>                   phyread -f (default: 0.05)
  --g <float>                   phyread -g (default: 0.05)

  --rounds <int>                phyopt -n (default: 3)
  --k <int>                     phyopt -k (default: 40)
  --L <float>                   phyopt -L (default: 0.25)
  --H <float>                   phyopt -H (default: 0.90)
  --timeout-sec <int>           phyopt -t (default: 300)

Fit-function env options:
  --micro-enable <0|1>          PHY_MICRO_ENABLE (default: 0)
  --fit-enable <0|1>            PHY_FIT_ENABLE (default: 1)
  --fit-file <path>             PHY_FIT_COEF_FILE (optional)
  --fit-l0-scale <float>        PHY_FIT_L0_SCALE (default: 0.35)
  --fit-l1-scale <float>        PHY_FIT_L1_SCALE (default: 0.25)

Other:
  --help                        Show this help.

Examples:
  run_phyopt_single.sh \
    --input-aig my_work/xiaorong_aig/c17.aig \
    --out-v my_work/out/c17_opt.v \
    --out-blif my_work/out/c17_opt.blif \
    --fit-file my_work/model/phy_fit_function_v1.txt

  run_phyopt_single.sh \
    --input-aig my_work/xiaorong_aig/c17.aig \
    --out-v my_work/out/c17_opt.v \
    --rounds 5 --k 50 --L 0.20 --H 0.92 --timeout-sec 600
EOF
}

is_abs_path() {
  case "$1" in
    /*|[A-Za-z]:/*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_path() {
  local p="$1"
  if is_abs_path "$p"; then
    echo "$p"
  else
    echo "$ROOT_DIR/$p"
  fi
}

mkdir_parent() {
  local p="$1"
  local d
  d="$(dirname "$p")"
  mkdir -p "$d"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --input-aig) INPUT_AIG="$2"; shift 2 ;;
    --out-v) OUT_V="$2"; shift 2 ;;
    --out-blif) OUT_BLIF="$2"; shift 2 ;;
    --out-aig) OUT_AIG="$2"; shift 2 ;;
    --log-file) LOG_FILE="$2"; shift 2 ;;
    --phy-csv) PHY_CSV="$2"; shift 2 ;;
    --cmd-file) CMD_FILE="$2"; shift 2 ;;

    --abc-bin) ABC_BIN="$2"; shift 2 ;;
    --lib-file) LIB_FILE="$2"; shift 2 ;;

    --i) I_W="$2"; shift 2 ;;
    --p) P_W="$2"; shift 2 ;;
    --f) F_W="$2"; shift 2 ;;
    --g) G_W="$2"; shift 2 ;;

    --rounds) ROUNDS="$2"; shift 2 ;;
    --k) K_V="$2"; shift 2 ;;
    --L) L_T="$2"; shift 2 ;;
    --H) H_T="$2"; shift 2 ;;
    --timeout-sec) CASE_TIMEOUT_SEC="$2"; shift 2 ;;

    --micro-enable) PHY_MICRO_ENABLE="$2"; shift 2 ;;
    --fit-enable) PHY_FIT_ENABLE="$2"; shift 2 ;;
    --fit-file) FIT_FILE="$2"; shift 2 ;;
    --fit-l0-scale) PHY_FIT_L0_SCALE="$2"; shift 2 ;;
    --fit-l1-scale) PHY_FIT_L1_SCALE="$2"; shift 2 ;;

    --help|-h) usage; exit 0 ;;
    *) echo "[error] unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$INPUT_AIG" ]; then
  echo "[error] --input-aig is required." >&2
  usage
  exit 1
fi
if [ -z "$OUT_V" ] && [ -z "$OUT_BLIF" ] && [ -z "$OUT_AIG" ]; then
  echo "[warn] no output file specified; flow will run and only print stats/log." >&2
fi

ABC_BIN="$(resolve_path "$ABC_BIN")"
LIB_FILE="$(resolve_path "$LIB_FILE")"
INPUT_AIG="$(resolve_path "$INPUT_AIG")"
[ -n "$OUT_V" ] && OUT_V="$(resolve_path "$OUT_V")"
[ -n "$OUT_BLIF" ] && OUT_BLIF="$(resolve_path "$OUT_BLIF")"
[ -n "$OUT_AIG" ] && OUT_AIG="$(resolve_path "$OUT_AIG")"
[ -n "$FIT_FILE" ] && FIT_FILE="$(resolve_path "$FIT_FILE")"

if [ ! -x "$ABC_BIN" ]; then
  echo "[error] abc binary not found or not executable: $ABC_BIN" >&2
  exit 1
fi
if [ ! -f "$LIB_FILE" ]; then
  echo "[error] liberty file not found: $LIB_FILE" >&2
  exit 1
fi
if [ ! -f "$INPUT_AIG" ]; then
  echo "[error] input aig not found: $INPUT_AIG" >&2
  exit 1
fi
if [ -n "$FIT_FILE" ] && [ ! -f "$FIT_FILE" ]; then
  echo "[error] fit file not found: $FIT_FILE" >&2
  exit 1
fi

if [ -n "$OUT_V" ]; then mkdir_parent "$OUT_V"; fi
if [ -n "$OUT_BLIF" ]; then mkdir_parent "$OUT_BLIF"; fi
if [ -n "$OUT_AIG" ]; then mkdir_parent "$OUT_AIG"; fi

base_stem="$(basename "$INPUT_AIG" .aig)"
out_dir="$(dirname "$INPUT_AIG")"
if [ -n "$OUT_V" ]; then
  out_dir="$(dirname "$OUT_V")"
elif [ -n "$OUT_BLIF" ]; then
  out_dir="$(dirname "$OUT_BLIF")"
elif [ -n "$OUT_AIG" ]; then
  out_dir="$(dirname "$OUT_AIG")"
fi

if [ -z "$PHY_CSV" ]; then
  PHY_CSV="$out_dir/${base_stem}.phy.csv"
else
  PHY_CSV="$(resolve_path "$PHY_CSV")"
fi
mkdir_parent "$PHY_CSV"

if [ -z "$LOG_FILE" ]; then
  LOG_FILE="$out_dir/${base_stem}.phyopt.log"
else
  LOG_FILE="$(resolve_path "$LOG_FILE")"
fi
mkdir_parent "$LOG_FILE"

if [ -z "$CMD_FILE" ]; then
  CMD_FILE="/tmp/phyopt_single_${base_stem}_$$.scr"
  CMD_IS_TEMP=1
else
  CMD_FILE="$(resolve_path "$CMD_FILE")"
  mkdir_parent "$CMD_FILE"
  CMD_IS_TEMP=0
fi

{
  echo "read_lib $LIB_FILE"
  echo "read_aiger $INPUT_AIG"
  echo "map_oto"
  echo "mapper_extract -o $PHY_CSV"
  echo "phyread -i $I_W -p $P_W -f $F_W -g $G_W $PHY_CSV"
  echo "phyopt -d -n $ROUNDS -k $K_V -L $L_T -H $H_T -t $CASE_TIMEOUT_SEC"
  echo "map"
  echo "ps"
  if [ -n "$OUT_BLIF" ]; then
    echo "write_blif $OUT_BLIF"
  fi
  if [ -n "$OUT_V" ]; then
    echo "write_verilog $OUT_V"
  fi
  if [ -n "$OUT_AIG" ]; then
    echo "strash"
    echo "write_aiger $OUT_AIG"
  fi
  echo "quit"
} > "$CMD_FILE"

echo "[info] abc_bin=$ABC_BIN" >&2
echo "[info] input_aig=$INPUT_AIG" >&2
echo "[info] lib_file=$LIB_FILE" >&2
echo "[info] phy_csv=$PHY_CSV" >&2
echo "[info] log_file=$LOG_FILE" >&2
echo "[info] cmd_file=$CMD_FILE" >&2
if [ -n "$OUT_V" ]; then echo "[info] out_v=$OUT_V" >&2; fi
if [ -n "$OUT_BLIF" ]; then echo "[info] out_blif=$OUT_BLIF" >&2; fi
if [ -n "$OUT_AIG" ]; then echo "[info] out_aig=$OUT_AIG" >&2; fi
if [ -n "$FIT_FILE" ]; then echo "[info] fit_file=$FIT_FILE" >&2; else echo "[info] fit_file=<builtin/default>" >&2; fi

env PHY_MICRO_ENABLE="$PHY_MICRO_ENABLE" \
    PHY_FIT_ENABLE="$PHY_FIT_ENABLE" \
    PHY_FIT_COEF_FILE="$FIT_FILE" \
    PHY_FIT_L0_SCALE="$PHY_FIT_L0_SCALE" \
    PHY_FIT_L1_SCALE="$PHY_FIT_L1_SCALE" \
    "$ABC_BIN" -f "$CMD_FILE" > "$LOG_FILE" 2>&1
rc=$?

if [ "$CMD_IS_TEMP" -eq 1 ]; then
  rm -f "$CMD_FILE"
fi

if [ "$rc" -ne 0 ]; then
  echo "[error] flow failed. see log: $LOG_FILE" >&2
  exit "$rc"
fi

ps_line="$(grep -E 'area =' "$LOG_FILE" | tail -n 1 | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')"
if [ -n "$ps_line" ]; then
  echo "[done] $ps_line" >&2
else
  echo "[done] flow finished. (no ps line found, check log)" >&2
fi

echo "$LOG_FILE"
