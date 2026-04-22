#!/usr/bin/env bash
set -euo pipefail

# Source this file to load strategy defaults for one group.
# Required: RUN_GROUP (A/B/C/D/U_mid/U_small)

RUN_GROUP="${RUN_GROUP:-}"
if [ -z "$RUN_GROUP" ]; then
  case "${GROUP:-}" in
    A|B|C|D|U_mid|U_small) RUN_GROUP="$GROUP" ;;
  esac
fi

if [ -z "$RUN_GROUP" ]; then
  echo "[error] RUN_GROUP is required before sourcing strategy_profiles.sh" >&2
  return 1
fi

BASE_DIR="${BASE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Common baseline
: "${DEF_I:=0.50}"
: "${DEF_P:=0.40}"
: "${DEF_F:=0.05}"
: "${DEF_G:=0.05}"
: "${DEF_OPT_L:=0.25}"
: "${DEF_OPT_H:=0.90}"
: "${DEF_K:=40}"

# Global default guards (0 means disabled)
: "${MAX_CASES:=0}"
: "${MAX_SECONDS:=0}"
: "${EARLY_STOP_FAILS:=0}"
: "${EARLY_STOP_DELAY_REJECT_CASES:=0}"

case "$RUN_GROUP" in
  L)
    STRATEGY_NAME="L_critical_low"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_fixed_default.txt}"
    USE_FEATURE_ADAPT="${USE_FEATURE_ADAPT:-0}"
    ADAPT_STRENGTH="${ADAPT_STRENGTH:-none}"
    ;;
  M)
    STRATEGY_NAME="M_critical_mid"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_fixed_default.txt}"
    USE_FEATURE_ADAPT="${USE_FEATURE_ADAPT:-0}"
    ADAPT_STRENGTH="${ADAPT_STRENGTH:-none}"
    ;;
  H)
    STRATEGY_NAME="H_critical_high"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_fixed_default.txt}"
    USE_FEATURE_ADAPT="${USE_FEATURE_ADAPT:-0}"
    ADAPT_STRENGTH="${ADAPT_STRENGTH:-none}"
    ;;
  A)
    STRATEGY_NAME="A_quality_first"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_A.txt}"
    USE_FEATURE_ADAPT="${USE_FEATURE_ADAPT:-1}"
    ADAPT_STRENGTH="${ADAPT_STRENGTH:-light}"
    MAX_SECONDS="${MAX_SECONDS:-0}"
    EARLY_STOP_FAILS="${EARLY_STOP_FAILS:-2}"
    EARLY_STOP_DELAY_REJECT_CASES="${EARLY_STOP_DELAY_REJECT_CASES:-2}"
    ;;
  B)
    STRATEGY_NAME="B_efficiency_first"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_B.txt}"
    USE_FEATURE_ADAPT="${USE_FEATURE_ADAPT:-1}"
    ADAPT_STRENGTH="${ADAPT_STRENGTH:-strong}"
    MAX_SECONDS="${MAX_SECONDS:-5400}"
    EARLY_STOP_FAILS="${EARLY_STOP_FAILS:-2}"
    EARLY_STOP_DELAY_REJECT_CASES="${EARLY_STOP_DELAY_REJECT_CASES:-2}"
    ;;
  C)
    STRATEGY_NAME="C_hybrid_two_stage"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_C.txt}"
    USE_FEATURE_ADAPT="${USE_FEATURE_ADAPT:-1}"
    ADAPT_STRENGTH="${ADAPT_STRENGTH:-strong}"
    MAX_SECONDS="${MAX_SECONDS:-0}"
    EARLY_STOP_FAILS="${EARLY_STOP_FAILS:-2}"
    EARLY_STOP_DELAY_REJECT_CASES="${EARLY_STOP_DELAY_REJECT_CASES:-2}"
    ;;
  D)
    STRATEGY_NAME="D_stable_baseline"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_D.txt}"
    USE_FEATURE_ADAPT="${USE_FEATURE_ADAPT:-1}"
    ADAPT_STRENGTH="${ADAPT_STRENGTH:-light}"
    MAX_SECONDS="${MAX_SECONDS:-0}"
    EARLY_STOP_FAILS="${EARLY_STOP_FAILS:-1}"
    EARLY_STOP_DELAY_REJECT_CASES="${EARLY_STOP_DELAY_REJECT_CASES:-1}"
    ;;
  U_mid)
    STRATEGY_NAME="U_mid_observe_light_hybrid"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_C.txt}"
    MAX_CASES="${MAX_CASES:-30}"
    ;;
  U_small)
    STRATEGY_NAME="U_small_observe_only"
    CASE_LIST="${CASE_LIST:-$BASE_DIR/configs/cases_D.txt}"
    MAX_CASES="${MAX_CASES:-10}"
    ;;
  *)
    echo "[error] unsupported RUN_GROUP=$RUN_GROUP" >&2
    return 1
    ;;
esac

  export RUN_GROUP STRATEGY_NAME CASE_LIST MAX_CASES MAX_SECONDS EARLY_STOP_FAILS EARLY_STOP_DELAY_REJECT_CASES USE_FEATURE_ADAPT ADAPT_STRENGTH
