#!/usr/bin/env bash
set -euo pipefail

echo "[deprecated] run_dynamic_scheduler.sh is bench-group based and does NOT match per-AIG node-dynamic requirement." >&2
echo "[deprecated] use: my_work/dynamic_scheduler_work/run_dynamic_per_aig_full.sh" >&2
exit 1

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DYN_BASE_DIR="$ROOT_DIR/my_work/dynamic_scheduler_work"
GROUPED_BASE_DIR="$ROOT_DIR/my_work/grouped_opt_stage1"

# User policy defaults
RUN_TAG="${RUN_TAG:-run_dynamic_$(date +%Y%m%d_%H%M%S)}"
RUN_GROUP_LIST="${RUN_GROUP_LIST:-L M H}"
BENCH_DIR="${BENCH_DIR:-$ROOT_DIR/my_work/xiaorong_aig}"
LIB_FILE="${LIB_FILE:-$ROOT_DIR/my_work/c17_work/NangateOpenCellLibrary_typical.lib}"
AUTO_PREPARE_GROUPS="${AUTO_PREPARE_GROUPS:-1}"
CRIT_LOW="${CRIT_LOW:-0.25}"
CRIT_HIGH="${CRIT_HIGH:-0.90}"
INIT_PCT="${INIT_PCT:-15}"
TOP_PCT="${TOP_PCT:-5}"
PROBE_PCT="${PROBE_PCT:-1}"
NO_IMPROVE_STREAK_STOP="${NO_IMPROVE_STREAK_STOP:-10}"
GLOBAL_NO_IMPROVE_ROUNDS_STOP="${GLOBAL_NO_IMPROVE_ROUNDS_STOP:-2}"
EFFECTIVE_AREA_EPS="${EFFECTIVE_AREA_EPS:-0.05}"
VERBOSE="${VERBOSE:-1}"
TRACE="${TRACE:-0}"

# Fixed-parameter policy from ablation.
FORCE_FIXED_PARAMS="${FORCE_FIXED_PARAMS:-1}"
FIXED_CASE_LIST="${FIXED_CASE_LIST:-$GROUPED_BASE_DIR/configs/cases_fixed_default.txt}"
ABLATION_OPT_L="${ABLATION_OPT_L:-0.25}"
ABLATION_OPT_H="${ABLATION_OPT_H:-0.90}"

if [ "$TRACE" = "1" ]; then
  set -x
fi

log_info() {
  if [ "$VERBOSE" = "1" ]; then
    echo "[sched] $*" >&2
  fi
}

# Keep C in single-stage for uniform incremental scheduling.
C_TWO_STAGE="${C_TWO_STAGE:-0}"

OUT_DIR="$DYN_BASE_DIR/result/$RUN_TAG"
mkdir -p "$OUT_DIR"

SCHED_LOG="$OUT_DIR/scheduler_log.csv"
SCORE_LOG="$OUT_DIR/score_log.csv"

echo "iter,step,group,bench_count,subrun_tag,group_score,global_score" > "$SCHED_LOG"
echo "iter,group,attempts,avg_area_impr,avg_delay_delta,accept_rate,group_score" > "$SCORE_LOG"

log_info "run_tag=$RUN_TAG groups=[$RUN_GROUP_LIST] init=${INIT_PCT}% top=${TOP_PCT}% probe=${PROBE_PCT}%"
log_info "stops: group_no_improve=$NO_IMPROVE_STREAK_STOP global_no_improve_rounds=$GLOBAL_NO_IMPROVE_ROUNDS_STOP eps=$EFFECTIVE_AREA_EPS"
log_info "fixed_params=$FORCE_FIXED_PARAMS case_list=$FIXED_CASE_LIST opt_L=$ABLATION_OPT_L opt_H=$ABLATION_OPT_H"
log_info "bench_dir=$BENCH_DIR auto_prepare_groups=$AUTO_PREPARE_GROUPS crit_low=$CRIT_LOW crit_high=$CRIT_HIGH"
log_info "logs: scheduler=$SCHED_LOG score=$SCORE_LOG"

ensure_groups_ready() {
  local missing=0
  local g gf
  for g in $RUN_GROUP_LIST; do
    gf="$(resolve_group_file "$g")"
    if [ ! -s "$gf" ]; then
      missing=1
      break
    fi
  done

  if [ "$missing" -eq 0 ]; then
    return 0
  fi

  if [ "$AUTO_PREPARE_GROUPS" != "1" ]; then
    echo "[error] group files missing and AUTO_PREPARE_GROUPS=0" >&2
    return 1
  fi

  log_info "group files missing; extracting criticality from AIGs in $BENCH_DIR"
  local crit_csv="$DYN_BASE_DIR/bench_criticality.csv"
  bash "$DYN_BASE_DIR/build_criticality_summary_from_aig.sh" "$BENCH_DIR" "$crit_csv"
  log_info "preparing LMH groups from $crit_csv"
  CRIT_LOW="$CRIT_LOW" CRIT_HIGH="$CRIT_HIGH" \
    bash "$DYN_BASE_DIR/prepare_group_inputs.sh" "$crit_csv"
}

pct_count() {
  local total="$1"
  local pct="$2"
  awk -v t="$total" -v p="$pct" 'BEGIN{ c=int((t*p+99)/100); if(c<1)c=1; if(c>t)c=t; print c }'
}

resolve_group_file() {
  local g="$1"
  if [ -f "$DYN_BASE_DIR/groups/group_${g}.txt" ]; then
    echo "$DYN_BASE_DIR/groups/group_${g}.txt"
    return 0
  fi
  echo "$GROUPED_BASE_DIR/groups/group_${g}.txt"
}

load_group_benches() {
  local g="$1"
  local gf
  gf="$(resolve_group_file "$g")"
  [ -f "$gf" ] || return 1
  awk '{ sub(/\r$/, ""); if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next; print }' "$gf"
}

bench_chunk_file() {
  local iter="$1"
  local g="$2"
  local n="$3"
  local inq="$OUT_DIR/${g}.queue"
  local out="$OUT_DIR/iter${iter}_${g}.chunk"
  if [ ! -f "$inq" ]; then
    : > "$out"
    echo "$out"
    return 0
  fi
  head -n "$n" "$inq" > "$out" || true
  tail -n +$((n+1)) "$inq" > "$inq.tmp" || true
  mv "$inq.tmp" "$inq"
  echo "$out"
}

append_group_summary() {
  local g="$1"
  local src_summary="$2"
  local dst="$OUT_DIR/${g}.summary_all.csv"
  if [ ! -f "$src_summary" ]; then
    return 1
  fi
  if [ ! -f "$dst" ]; then
    cp "$src_summary" "$dst"
  else
    tail -n +2 "$src_summary" >> "$dst"
  fi
}

calc_group_score() {
  local g="$1"
  local f="$OUT_DIR/${g}.summary_all.csv"
  if [ ! -f "$f" ]; then
    echo "0,0,0,0,0"
    return 0
  fi
  awk -F',' '
    NR==1 {next}
    {
      ba=$5+0; bd=$6+0; aa=$7+0; ad=$8+0;
      acc=$9+0; rej=$10+0;
      area=(ba>0)?((ba-aa)*100.0/ba):0;
      dly=(ad-bd);
      area_sum+=area;
      dly_sum+=dly;
      acc_sum+=acc;
      rej_sum+=rej;
      n++;
    }
    END{
      if(n==0){print "0,0,0,0,0"; exit}
      avg_area=area_sum/n;
      avg_dly=dly_sum/n;
      ar=(acc_sum+rej_sum>0)?(acc_sum*100.0/(acc_sum+rej_sum)):0;
      # Unit-budget score: area gain weighted by acceptance, penalty for delay worsening.
      delay_pen=(avg_dly>0)?(avg_dly*10.0):0;
      score=avg_area*(ar/100.0)-delay_pen;
      printf "%d,%.6f,%.6f,%.6f,%.6f", n, avg_area, avg_dly, ar, score;
    }
  ' "$f"
}

calc_global_score() {
  local sum=0
  local cnt=0
  local g
  for g in $RUN_GROUP_LIST; do
    IFS=',' read -r _ _ _ _ score <<< "$(calc_group_score "$g")"
    sum=$(awk -v a="$sum" -v b="$score" 'BEGIN{printf "%.10f", a+b}')
    cnt=$((cnt+1))
  done
  if [ "$cnt" -eq 0 ]; then
    echo "0"
  else
    awk -v s="$sum" -v c="$cnt" 'BEGIN{printf "%.6f", s/c}'
  fi
}

bench_has_effective_improve() {
  local f="$1"
  local eps="$2"
  awk -F',' -v e="$eps" '
    NR==1 {next}
    {
      ba=$5+0; bd=$6+0; aa=$7+0; ad=$8+0;
      area=(ba>0)?((ba-aa)*100.0/ba):0;
      dly=(ad-bd);
      if(area>=e && dly<=0){ ok=1; exit }
    }
    END{ exit(ok?0:1) }
  ' "$f"
}

summary_attempt_count() {
  local f="$1"
  if [ ! -f "$f" ]; then
    echo "0"
    return 0
  fi
  awk -F',' 'NR>1{n++} END{print n+0}' "$f"
}

run_group_chunk() {
  local iter="$1"
  local step="$2"
  local g="$3"
  local chunk_file="$4"

  local bench_count
  bench_count=$(wc -l < "$chunk_file" | tr -d ' ')
  if [ "$bench_count" -le 0 ]; then
    log_info "iter=$iter step=$step group=$g skip-empty-chunk"
    return 0
  fi

  local subtag="${RUN_TAG}_iter${iter}_${step}_${g}"
  log_info "iter=$iter step=$step group=$g benches=$bench_count subtag=$subtag"

  if [ "$FORCE_FIXED_PARAMS" = "1" ]; then
    local sub_result_dir="$DYN_BASE_DIR/result/$subtag/$g"
    RUN_GROUP="$g" \
    RUN_TAG="$subtag" \
    RESULT_DIR="$sub_result_dir" \
    BENCH_LIST="$chunk_file" \
    CASE_LIST="$FIXED_CASE_LIST" \
    USE_FEATURE_ADAPT=0 \
    ADAPT_STRENGTH=none \
    DEF_OPT_L="$ABLATION_OPT_L" \
    DEF_OPT_H="$ABLATION_OPT_H" \
    C_TWO_STAGE="$C_TWO_STAGE" \
    bash "$GROUPED_BASE_DIR/run_group_strategy.sh"
  else
    local sub_result_dir="$DYN_BASE_DIR/result/$subtag/$g"
    RUN_GROUP="$g" \
    RUN_TAG="$subtag" \
    RESULT_DIR="$sub_result_dir" \
    BENCH_LIST="$chunk_file" \
    C_TWO_STAGE="$C_TWO_STAGE" \
    bash "$GROUPED_BASE_DIR/run_group_strategy.sh"
  fi

  local src_summary="$DYN_BASE_DIR/result/$subtag/$g/summary.csv"
  if [ ! -f "$src_summary" ] && [ -f "$GROUPED_BASE_DIR/results/${subtag}_C_two_stage/summary_C_two_stage.csv" ]; then
    src_summary="$GROUPED_BASE_DIR/results/${subtag}_C_two_stage/summary_C_two_stage.csv"
  fi

  append_group_summary "$g" "$src_summary"

  local score
  IFS=',' read -r attempts avg_area avg_dly ar score <<< "$(calc_group_score "$g")"
  local gscore
  gscore="$(calc_global_score)"
  log_info "iter=$iter step=$step group=$g score=$score global_score=$gscore"

  echo "$iter,$step,$g,$bench_count,$subtag,$score,$gscore" >> "$SCHED_LOG"
}

# Initialize queues and stats
ensure_groups_ready

for g in $RUN_GROUP_LIST; do
  qf="$OUT_DIR/${g}.queue"
  load_group_benches "$g" > "$qf"
  total=$(wc -l < "$qf" | tr -d ' ')
  echo "$total" > "$OUT_DIR/${g}.total"
  echo "0" > "$OUT_DIR/${g}.no_improve_streak"
  echo "0" > "$OUT_DIR/${g}.stopped"
  log_info "init-queue group=$g total_nodes=$total"
done

# Stage 1: initial probing per group (15%)
iter=1
for g in $RUN_GROUP_LIST; do
  total=$(cat "$OUT_DIR/${g}.total")
  [ "$total" -gt 0 ] || continue
  n=$(pct_count "$total" "$INIT_PCT")
  chunk="$(bench_chunk_file "$iter" "$g" "$n")"
  run_group_chunk "$iter" "init" "$g" "$chunk"

  # Update no-improve streak based on bench-level result of this chunk summary.
  last_subtag="${RUN_TAG}_iter${iter}_init_${g}"
  sf="$DYN_BASE_DIR/result/$last_subtag/$g/summary.csv"
  if [ ! -f "$sf" ] && [ -f "$GROUPED_BASE_DIR/results/${last_subtag}_C_two_stage/summary_C_two_stage.csv" ]; then
    sf="$GROUPED_BASE_DIR/results/${last_subtag}_C_two_stage/summary_C_two_stage.csv"
  fi
  if [ -f "$sf" ]; then
    attempts_this=$(summary_attempt_count "$sf")
    if bench_has_effective_improve "$sf" "$EFFECTIVE_AREA_EPS"; then
      echo "0" > "$OUT_DIR/${g}.no_improve_streak"
    else
      s=$(cat "$OUT_DIR/${g}.no_improve_streak")
      echo $((s+attempts_this)) > "$OUT_DIR/${g}.no_improve_streak"
    fi
  fi

  IFS=',' read -r attempts avg_area avg_dly ar score <<< "$(calc_group_score "$g")"
  echo "$iter,$g,$attempts,$avg_area,$avg_dly,$ar,$score" >> "$SCORE_LOG"
  log_info "init-score group=$g attempts=$attempts area=$avg_area delay=$avg_dly acc_rate=$ar score=$score"
done

best_global="$(calc_global_score)"
no_global_improve_rounds=0

# Iterative scheduling
while :; do
  iter=$((iter+1))

  # Find active groups with remaining queue and not stopped.
  active=""
  for g in $RUN_GROUP_LIST; do
    stopped=$(cat "$OUT_DIR/${g}.stopped")
    rem=$(wc -l < "$OUT_DIR/${g}.queue" | tr -d ' ')
    if [ "$stopped" -eq 0 ] && [ "$rem" -gt 0 ]; then
      active="$active $g"
    fi
  done
  [ -n "${active// }" ] || break
  log_info "iter=$iter active_groups=[$active]"

  # Rank by current score (desc), top group is current leader.
  top_group=""
  top_score="-999999"
  for g in $active; do
    IFS=',' read -r _ _ _ _ score <<< "$(calc_group_score "$g")"
    better=$(awk -v a="$score" -v b="$top_score" 'BEGIN{print (a>b)?1:0}')
    if [ "$better" -eq 1 ]; then
      top_score="$score"
      top_group="$g"
    fi
  done
  log_info "iter=$iter selected_top_group=$top_group top_score=$top_score"

  # Leader runs TOP_PCT.
  t_total=$(cat "$OUT_DIR/${top_group}.total")
  t_n=$(pct_count "$t_total" "$TOP_PCT")
  t_chunk="$(bench_chunk_file "$iter" "$top_group" "$t_n")"
  run_group_chunk "$iter" "top" "$top_group" "$t_chunk"

  # Others probe PROBE_PCT.
  for g in $active; do
    [ "$g" = "$top_group" ] && continue
    total=$(cat "$OUT_DIR/${g}.total")
    n=$(pct_count "$total" "$PROBE_PCT")
    chunk="$(bench_chunk_file "$iter" "$g" "$n")"
    run_group_chunk "$iter" "probe" "$g" "$chunk"
  done

  # Update group streak/stop decisions based on this iteration's sub-runs.
  for g in $active; do
    improved=0
    tried_nodes=0
    for step in top probe; do
      subtag="${RUN_TAG}_iter${iter}_${step}_${g}"
      sf="$DYN_BASE_DIR/result/$subtag/$g/summary.csv"
      if [ ! -f "$sf" ] && [ -f "$GROUPED_BASE_DIR/results/${subtag}_C_two_stage/summary_C_two_stage.csv" ]; then
        sf="$GROUPED_BASE_DIR/results/${subtag}_C_two_stage/summary_C_two_stage.csv"
      fi
      if [ -f "$sf" ]; then
        n_this=$(summary_attempt_count "$sf")
        tried_nodes=$((tried_nodes+n_this))
        if bench_has_effective_improve "$sf" "$EFFECTIVE_AREA_EPS"; then
          improved=1
        fi
      fi
    done

    if [ "$improved" -eq 1 ]; then
      echo "0" > "$OUT_DIR/${g}.no_improve_streak"
    else
      if [ "$tried_nodes" -le 0 ]; then
        tried_nodes=1
      fi
      s=$(cat "$OUT_DIR/${g}.no_improve_streak")
      s=$((s+tried_nodes))
      echo "$s" > "$OUT_DIR/${g}.no_improve_streak"
      if [ "$s" -ge "$NO_IMPROVE_STREAK_STOP" ]; then
        echo "1" > "$OUT_DIR/${g}.stopped"
        log_info "iter=$iter stop-group group=$g reason=no_improve_streak streak=$s"
      fi
    fi

    IFS=',' read -r attempts avg_area avg_dly ar score <<< "$(calc_group_score "$g")"
    echo "$iter,$g,$attempts,$avg_area,$avg_dly,$ar,$score" >> "$SCORE_LOG"
    log_info "iter=$iter score group=$g attempts=$attempts area=$avg_area delay=$avg_dly acc_rate=$ar score=$score"
  done

  # Global stop: no overall improvement for consecutive rounds.
  global_score="$(calc_global_score)"
  improved_global=$(awk -v a="$global_score" -v b="$best_global" 'BEGIN{print (a>b+1e-9)?1:0}')
  if [ "$improved_global" -eq 1 ]; then
    best_global="$global_score"
    no_global_improve_rounds=0
    log_info "iter=$iter global_improved best_global=$best_global"
  else
    no_global_improve_rounds=$((no_global_improve_rounds+1))
    log_info "iter=$iter global_no_improve rounds=$no_global_improve_rounds best_global=$best_global current=$global_score"
  fi

  if [ "$no_global_improve_rounds" -ge "$GLOBAL_NO_IMPROVE_ROUNDS_STOP" ]; then
    log_info "iter=$iter stop-global reason=no_improve_rounds"
    break
  fi
done

# Build merged summary_all.csv
merged="$OUT_DIR/summary_all.csv"
first=1
for g in $RUN_GROUP_LIST; do
  f="$OUT_DIR/${g}.summary_all.csv"
  [ -f "$f" ] || continue
  if [ "$first" -eq 1 ]; then
    cat "$f" > "$merged"
    first=0
  else
    tail -n +2 "$f" >> "$merged"
  fi
done

echo "[done] run_tag=$RUN_TAG" >&2
echo "[done] scheduler_log=$SCHED_LOG" >&2
echo "[done] score_log=$SCORE_LOG" >&2
if [ -f "$merged" ]; then
  echo "[done] merged_summary=$merged" >&2
fi
