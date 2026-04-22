#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BASE_DIR="$ROOT_DIR/my_work/grouped_opt_stage1"

RUN_GROUP="${RUN_GROUP:-${1:-}}"
if [ -z "$RUN_GROUP" ]; then
  case "${GROUP:-}" in
    A|B|C|D|U_mid|U_small|L|M|H) RUN_GROUP="$GROUP" ;;
  esac
fi
if [ -z "$RUN_GROUP" ]; then
  echo "[error] RUN_GROUP is required. Usage: RUN_GROUP=L bash run_group_strategy.sh" >&2
  exit 1
fi

if [ "$RUN_GROUP" = "C" ] && [ "${C_TWO_STAGE:-1}" = "1" ]; then
  RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
  RUN_TAG="$RUN_TAG" bash "$BASE_DIR/run_group_C_two_stage.sh"
  exit 0
fi

# shellcheck source=/dev/null
RUN_GROUP="$RUN_GROUP" BASE_DIR="$BASE_DIR" source "$BASE_DIR/strategy_profiles.sh"

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
RUN_GROUP="$RUN_GROUP" RUN_TAG="$RUN_TAG" bash "$BASE_DIR/run_group_experiments.sh"
